# Implementation Plan: Longhorn Backup Target (MinIO)

**Branch**: `061-longhorn-backup-target` | **Date**: 2026-05-16 | **Spec**: `specs/061-longhorn-backup-target/spec.md`
**Input**: Feature specification from `/specs/061-longhorn-backup-target/spec.md`

## Summary

Configure Longhorn to use the MinIO `longhorn-backups` bucket (deployed in spec 060) as its `BackupTarget`, apply two-tier `RecurringJob` policies to all critical cluster PVCs, and wire up explicit `PrometheusRule` alerts for backup job failures. Deployed via ArgoCD (single-source manifest Application) + one-time Ansible PVC labeling playbook.

## Technical Context

**Language/Version**: YAML (Ansible 2.x + Kubernetes manifests, Longhorn CRDs `longhorn.io/v1beta2`)
**Primary Dependencies**: Longhorn v1.11.1, ArgoCD, Sealed Secrets controller, kube-prometheus-stack (PrometheusRule CRD)
**Storage**: No new PVCs — configuring backup of existing PVCs to MinIO (`longhorn-backups` bucket)
**Testing**: Pre-flight checks via `kubectl` + port-forward; backup job trigger via Longhorn UI; PrometheusRule validation via `kubectl apply --dry-run`
**Target Platform**: K3s arm64 (Raspberry Pi CM5 cluster)
**Project Type**: Infrastructure configuration — Kubernetes CRD manifests + Ansible utility playbook
**Performance Goals**: Backup jobs must complete within the nightly/weekly window without blocking normal cluster operations; `concurrency: 1` on each RecurringJob to avoid saturating Longhorn's backup channel
**Constraints**: MinIO must be reachable at `minio.minio.svc.cluster.local:9000` from `longhorn-system` pods; credentials must be namespace-scoped SealedSecrets for `longhorn-system`

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I — Infrastructure as Code | ✅ | All CRDs in manifests/; PVC labels via Ansible playbook |
| II — Idempotency | ✅ | Setting CRDs are declarative; `kubectl label --overwrite`; RecurringJobs are CRDs (apply-safe) |
| III — Reproducibility | ✅ | quickstart.md documents every step including Ansible bootstrap |
| IV — Secrets Hygiene | ✅ | SealedSecret for `longhorn-minio-credentials`; no plaintext in Git |
| V — Simplicity | ✅ | Single-source ArgoCD App; no Helm chart; minimal new files |
| VIII — Persistent Storage | N/A | No new PVCs created |
| IX — Secure Service Exposure | N/A | No new ingress routes; MinIO access is cluster-internal |
| X — Intra-Cluster Locality | ✅ | `AWS_ENDPOINTS: http://minio.minio.svc.cluster.local:9000` routes internally |
| XI — GitOps Application Deployment | ✅ | ArgoCD manages all manifests; PVC label Ansible is metadata-only, not Helm install |

**No violations. Complexity Tracking table not required.**

## Project Structure

### Documentation (this feature)

```text
specs/061-longhorn-backup-target/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
manifests/longhorn-backup/
├── prereqs/
│   └── sealed-secrets.yaml           # wave 0 — longhorn-minio-credentials (longhorn-system)
├── backup-settings.yaml              # wave 1 — Setting CRDs: backup-target + credential-secret
├── recurring-jobs.yaml               # wave 2 — 4 RecurringJob CRDs (2 tiers × 2 task types)
└── prometheus-rules.yaml             # wave 2 — PrometheusRule: backup failures + missed backups

playbooks/utilities/
├── seal-secrets.yml                  # extended: add longhorn-backup play (longhorn-system ns)
└── label-pvcs.yml                    # new: idempotent PVC labeling for RecurringJob groups

group_vars/
├── all.yml                           # add longhorn-backup to argocd_apps (gitignored)
└── example.all.yml                   # sync placeholder
```

**Structure Decision**: Single-source ArgoCD Application (no Helm chart). All resources target the existing `longhorn-system` namespace. No `namespace.yaml` needed — `longhorn-system` already exists. PVC labels applied via Ansible to avoid ownership conflicts with Helm-managed PVCs.

## Technical Detail

### RecurringJob Definitions

```yaml
# Tier A — data PVCs (source of truth)
- name: snapshot-tier-a  task: snapshot  cron: "0 1 * * *"  retain: 7  group: tier-a
- name: backup-tier-a    task: backup    cron: "0 3 * * 0"  retain: 4  group: tier-a

# Tier B — monitoring PVCs (reconstructible)
- name: snapshot-tier-b  task: snapshot  cron: "0 1 * * *"  retain: 3  group: tier-b
- name: backup-tier-b    task: backup    cron: "0 3 * * 0"  retain: 2  group: tier-b
```

### PVC Assignment

| PVC | Namespace | Tier |
|-----|-----------|------|
| `gitea-shared-storage` | `gitea` | A |
| Loki PVC (`app.kubernetes.io/name=loki`) | `monitoring` | A |
| `mosquitto-data` | `home-automation` | A |
| HA PVC (`app.kubernetes.io/instance=home-assistant`) | `home-automation` | A |
| Node-RED PVC (`app.kubernetes.io/instance=node-red`) | `home-automation` | A |
| InfluxDB PVC (`app.kubernetes.io/instance=influxdb`) | `home-automation` | A |
| `frigate-clips` | `frigate` | A |
| Prometheus PVC (`app.kubernetes.io/name=prometheus`) | `monitoring` | B |
| Alertmanager PVC (`app.kubernetes.io/name=alertmanager`) | `monitoring` | B |
| Grafana PVC (`app.kubernetes.io/name=grafana`) | `monitoring` | B |

### PrometheusRule Alerts

| Alert | Expression | For | Severity |
|-------|-----------|-----|----------|
| `LonghornBackupFailed` | `longhorn_backup_state == 3` | 10m | warning |
| `LonghornVolumeNotBackedUp` | `time() - longhorn_volume_last_backup_at > 777600` | 1h | warning |

> `777600` = 9 days in seconds (7-day Tier A cadence + 2-day grace).

### ArgoCD Application Entry

```yaml
# group_vars/all.yml — argocd_apps addition
- name: longhorn-backup
  repo: gitadmin/vanlab.git
  path: manifests/longhorn-backup
  namespace: longhorn-system
  revision: main
```

### seal-secrets.yml Extension

New play (tag: `longhorn-backup`) seals `longhorn-minio-credentials` into `manifests/longhorn-backup/prereqs/sealed-secrets.yaml` with namespace `longhorn-system`.

Source values from `group_vars/all.yml`:
- `longhorn_minio_access_key` → `AWS_ACCESS_KEY_ID`
- `longhorn_minio_secret_key` → `AWS_SECRET_ACCESS_KEY`
- Endpoint hardcoded: `http://minio.minio.svc.cluster.local:9000` → `AWS_ENDPOINTS`

## Implementation Phases

### Phase 1 — Sealed Secret + ArgoCD bootstrap
1. Extend `seal-secrets.yml` with `longhorn-backup` play
2. Add credentials to `group_vars/all.yml` (already present from spec 060)
3. Generate `prereqs/sealed-secrets.yaml`
4. Add `longhorn-backup` to `argocd_apps`; run `argocd-bootstrap` tag

### Phase 2 — Core manifests
5. Write `backup-settings.yaml` (2 Setting CRDs)
6. Write `recurring-jobs.yaml` (4 RecurringJob CRDs)
7. Write `prometheus-rules.yaml` (1 PrometheusRule, 2 alerts)

### Phase 3 — PVC labeling
8. Write `playbooks/utilities/label-pvcs.yml`
9. Run playbook against cluster
10. Verify labels applied; verify Longhorn UI shows jobs scheduled

### Phase 4 — Verification
11. Run quickstart.md pre-flight checks
12. Trigger test backup via Longhorn UI; confirm object appears in MinIO
13. Verify PrometheusRule loaded in Prometheus
14. Verify ArgoCD sync Synced + Healthy
