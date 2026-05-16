# Research — Longhorn Backup Target (MinIO)

**Feature**: 061-longhorn-backup-target
**Phase**: 0 — Technical Decisions

---

## Decision 1: BackupTarget Configuration Method

**Decision**: Use Longhorn `Setting` CRDs (kind: `Setting`, API `longhorn.io/v1beta2`) to configure the backup target and credential secret name declaratively via ArgoCD.

**Rationale**: Longhorn represents all cluster settings as `Setting` resources in the `longhorn-system` namespace. ArgoCD can apply patches to these resources idempotently. This keeps the configuration in Git (Principle I, XI) without requiring a Helm install or UI interaction. The two settings of interest (`backup-target`, `backup-target-credential-secret`) are user-configurable and are not overwritten by the Longhorn reconciler once set.

**Alternatives considered**:
- *Helm chart defaultSettings*: Only applies on initial install; cannot be used since Longhorn is already deployed via Ansible.
- *ConfigMap override*: The agent initially suggested a ConfigMap approach; this is incorrect for a running cluster — it applies only during initial Helm install, not as a day-2 change.
- *ArgoCD post-sync hook with `kubectl patch`*: More complex, no advantage over direct Setting CRD management.

**YAML pattern**:
```yaml
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: backup-target
  namespace: longhorn-system
value: "s3://longhorn-backups@us-east-1/"
```

---

## Decision 2: Credential Secret Key Format

**Decision**: Secret in `longhorn-system` namespace uses three keys: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINTS`.

**Rationale**: Longhorn's backup subsystem uses the AWS SDK internally. For MinIO (S3-compatible), the SDK requires these three env-var keys. The endpoint override (`AWS_ENDPOINTS`) points to the in-cluster MinIO service. No `VIRTUAL_HOSTED_STYLE` key is needed — MinIO defaults to path-style addressing, which is compatible.

**Values (from spec 060 contract)**:
```
AWS_ACCESS_KEY_ID:     <longhorn_minio_access_key from group_vars/all.yml>
AWS_SECRET_ACCESS_KEY: <longhorn_minio_secret_key from group_vars/all.yml>
AWS_ENDPOINTS:         http://minio.minio.svc.cluster.local:9000
```

---

## Decision 3: RecurringJob CRD Design

**Decision**: Define 4 `RecurringJob` resources using `longhorn.io/v1beta2`, split into two groups/tiers:

| Job Name | Task | Cron | Retain | Group |
|---|---|---|---|---|
| `snapshot-tier-a` | snapshot | `0 1 * * *` | 7 | `tier-a` |
| `backup-tier-a` | backup | `0 3 * * 0` | 4 | `tier-a` |
| `snapshot-tier-b` | snapshot | `0 1 * * *` | 3 | `tier-b` |
| `backup-tier-b` | backup | `0 3 * * 0` | 2 | `tier-b` |

**Rationale**: Two groups maps directly to the two-tier retention policy from clarifications. Weekly backups run on Sunday at 03:00; nightly snapshots run at 01:00. Tier A retain=7 (days) / 4 (weeks). Tier B retain=3 / 2.

**PVC assignment labels** (applied via Ansible `playbooks/utilities/label-pvcs.yml`):
```bash
kubectl label pvc <name> -n <ns> recurring-job-group.longhorn.io/tier-a=enabled --overwrite
kubectl label pvc <name> -n <ns> recurring-job-group.longhorn.io/tier-b=enabled --overwrite
```

**Tier A PVCs** (data — source of truth):
- `gitea-shared-storage` / `gitea`
- Loki PVC (selector `app.kubernetes.io/name=loki`) / `monitoring`
- `mosquitto-data` / `home-automation`
- Home Assistant PVC (selector `app.kubernetes.io/instance=home-assistant`) / `home-automation`
- Node-RED PVC (selector `app.kubernetes.io/instance=node-red`) / `home-automation`
- InfluxDB PVC (selector `app.kubernetes.io/instance=influxdb`) / `home-automation`
- `frigate-clips` / `frigate`

**Tier B PVCs** (monitoring — reconstructible):
- Prometheus PVC (selector `app.kubernetes.io/name=prometheus`) / `monitoring`
- Alertmanager PVC (selector `app.kubernetes.io/name=alertmanager`) / `monitoring`
- Grafana PVC (selector `app.kubernetes.io/name=grafana`) / `monitoring`

---

## Decision 4: Prometheus Alerting

**Decision**: Explicit `PrometheusRule` with two alerts:
1. `LonghornBackupFailed` — fires when `longhorn_backup_state` reaches state 4 (Error) for any backup in the last 24h.
2. `LonghornVolumeNotBackedUp` — fires when `longhorn_volume_last_backup_at` is older than 9 days (Tier A cadence + 2-day grace) for any labeled volume.

**Rationale**: kube-prometheus-stack does not ship Longhorn backup failure alerts by default. The two metrics confirmed available in Longhorn v1.11:
- `longhorn_backup_state{backup,volume,backupTarget}` — 0=Unknown, 1=InProgress, 2=Completed, 3=Error, 4=Deleted
- `longhorn_volume_last_backup_at{volume}` — Unix timestamp of most recent successful backup (0 if never backed up)

Missed schedule detection uses `longhorn_volume_last_backup_at` rather than CronJob metrics, since Longhorn manages its own scheduler. The 9-day threshold (7-day Tier A cadence + 2-day grace) prevents false positives during maintenance windows.

---

## Decision 5: ArgoCD Application Pattern

**Decision**: Single-source ArgoCD Application pointing at `manifests/longhorn-backup/` in Gitea. No Helm chart involved — pure Kubernetes manifests (Setting, RecurringJob, SealedSecret, PrometheusRule).

**Rationale**: There is no upstream Helm chart for Longhorn's configuration CRDs. The multi-source pattern (from spec 060's MinIO) is only required when a Helm chart + values file need to be co-located. A single-source Application is simpler and Constitution XI-compliant.

**Application registered in `argocd_apps`** (`group_vars/all.yml`) — no exception needed; not a multi-source Application.

---

## Decision 6: PVC Label Application via Ansible

**Decision**: A new playbook `playbooks/utilities/label-pvcs.yml` applies RecurringJob group labels to existing PVCs using `kubectl label --overwrite`. This is run once after ArgoCD syncs the RecurringJob CRDs.

**Rationale**: PVCs are owned by their respective Helm releases/StatefulSets and managed by ArgoCD through those applications. Adding a standalone ArgoCD-managed resource that patches another ArgoCD application's PVC would create ownership conflicts. An Ansible playbook applying metadata labels is a clean boundary — labels are idempotent, metadata-only, and survive pod restarts. This mirrors the `mc` bootstrap pattern from spec 060.

**Constitution note**: `kubectl label` is metadata mutation, not `kubectl apply` of application manifests — it does not violate Principle XI's prohibition on direct manifest application.
