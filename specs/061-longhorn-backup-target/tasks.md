# Tasks: Longhorn Backup Target (MinIO)

**Input**: Design documents from `/specs/061-longhorn-backup-target/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, quickstart.md ✅

**Organization**: Tasks grouped by user story. GitOps flow requires all manifests committed to Gitea `main` before ArgoCD can sync — foundational phase includes commit/merge.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to
- Exact file paths in all descriptions

---

## Phase 1: Setup

**Purpose**: Scaffold directories and extend the seal-secrets utility to support the new `longhorn-system` namespace credential.

- [ ] T001 Create directory `manifests/longhorn-backup/prereqs/` (mkdir -p)
- [ ] T002 Extend `playbooks/utilities/seal-secrets.yml` with a new play tagged `longhorn-backup` that reads `longhorn_minio_access_key` and `longhorn_minio_secret_key` from `group_vars/all.yml` and seals them as `longhorn-minio-credentials` (namespace: `longhorn-system`) with keys `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and hardcoded `AWS_ENDPOINTS: http://minio.minio.svc.cluster.local:9000` — output to `manifests/longhorn-backup/prereqs/sealed-secrets.yaml`
- [ ] T003 Run `ansible-playbook playbooks/utilities/seal-secrets.yml --tags longhorn-backup` to generate `manifests/longhorn-backup/prereqs/sealed-secrets.yaml`; inspect output to confirm it contains one SealedSecret named `longhorn-minio-credentials`, namespace `longhorn-system`, and zero plaintext values

---

## Phase 2: Foundational (All Manifests + Commit)

**Purpose**: Write all Kubernetes manifests and Ansible playbook, then commit and merge to Gitea `main` so ArgoCD can sync. This phase MUST complete before any user story verification can begin.

**⚠️ CRITICAL**: ArgoCD reads from Gitea `main` — manifests must be merged before deployment verification.

- [ ] T004 [P] Write `manifests/longhorn-backup/backup-settings.yaml` containing two `longhorn.io/v1beta2` `Setting` resources: (1) `name: backup-target`, `value: "s3://longhorn-backups@us-east-1/"` with sync-wave annotation `1`; (2) `name: backup-target-credential-secret`, `value: "longhorn-minio-credentials"` with sync-wave annotation `1`
- [ ] T005 [P] Write `manifests/longhorn-backup/recurring-jobs.yaml` containing four `longhorn.io/v1beta2` `RecurringJob` resources with sync-wave annotation `2`: `snapshot-tier-a` (task: snapshot, cron: `"0 1 * * *"`, retain: 7, groups: [tier-a], concurrency: 1), `backup-tier-a` (task: backup, cron: `"0 3 * * 0"`, retain: 4, groups: [tier-a], concurrency: 1), `snapshot-tier-b` (task: snapshot, cron: `"0 1 * * *"`, retain: 3, groups: [tier-b], concurrency: 1), `backup-tier-b` (task: backup, cron: `"0 3 * * 0"`, retain: 2, groups: [tier-b], concurrency: 1) — all namespace: `longhorn-system`
- [ ] T006 [P] Write `manifests/longhorn-backup/prometheus-rules.yaml` as a `monitoring.coreos.com/v1` `PrometheusRule` named `longhorn-backup-alerts` in namespace `longhorn-system` with label `release: kube-prometheus-stack`; two alerts: `LonghornBackupFailed` (expr: `longhorn_backup_state == 3`, for: `10m`, severity: warning, message: "Longhorn backup {{ $labels.backup }} on volume {{ $labels.volume }} is in error state") and `LonghornVolumeNotBackedUp` (expr: `time() - longhorn_volume_last_backup_at > 777600`, for: `1h`, severity: warning, message: "Longhorn volume {{ $labels.volume }} has not been backed up in over 9 days") with sync-wave annotation `2`
- [ ] T007 Write `playbooks/utilities/label-pvcs.yml` — an Ansible playbook with a single play delegated to `localhost` using `ansible.builtin.command: kubectl label pvc <name> -n <ns> recurring-job-group.longhorn.io/<tier>=enabled --overwrite`; Tier A targets: `gitea-shared-storage` (ns: `gitea`), Loki PVC (ns: `monitoring`, use `-l app.kubernetes.io/name=loki` selector to get name first), Home Assistant PVC (ns: `home-automation`, selector `app.kubernetes.io/instance=home-assistant`), Node-RED PVC (ns: `home-automation`, selector `app.kubernetes.io/instance=node-red`), InfluxDB PVC (ns: `home-automation`, selector `app.kubernetes.io/instance=influxdb`), `mosquitto-data` (ns: `home-automation`), `frigate-clips` (ns: `frigate`); Tier B targets: Prometheus PVC (ns: `monitoring`, selector `app.kubernetes.io/name=prometheus`), Alertmanager PVC (ns: `monitoring`, selector `app.kubernetes.io/name=alertmanager`), Grafana PVC (ns: `monitoring`, selector `app.kubernetes.io/name=grafana`); all `kubectl label` tasks must be idempotent via `--overwrite` and use `KUBECONFIG` env var
- [ ] T008 Add `longhorn-backup` entry to `argocd_apps` in `group_vars/all.yml` (`name: longhorn-backup`, `repo: gitadmin/vanlab.git`, `path: manifests/longhorn-backup`, `namespace: longhorn-system`, `revision: main`) and add the same placeholder entry to `group_vars/example.all.yml`
- [ ] T009 Commit all new and modified files (`manifests/longhorn-backup/`, `playbooks/utilities/seal-secrets.yml`, `playbooks/utilities/label-pvcs.yml`, `group_vars/example.all.yml`) to branch `061-longhorn-backup-target`; push to Gitea and GitHub; create and merge PR via Gitea API per CLAUDE.md workflow; pull merged `main` locally; push `origin main --no-verify`; delete branch locally and on Gitea

---

## Phase 3: User Story 1 — BackupTarget Activation (P1) 🎯 MVP

**Goal**: Longhorn is configured to use MinIO as its backup target, credentials are in place, and the backup target shows Connected in Longhorn UI.

**Independent Test**: `kubectl get setting backup-target -n longhorn-system -o jsonpath='{.value}'` returns `s3://longhorn-backups@us-east-1/` and Longhorn UI shows backup target Connected.

- [ ] T010 [US1] Register `longhorn-backup` ArgoCD Application by running `ansible-playbook playbooks/cluster/services-deploy.yml --tags argocd-bootstrap` and confirm the Application appears in ArgoCD
- [ ] T011 [US1] Wait for ArgoCD `longhorn-backup` Application to reach Synced + Healthy; check via `kubectl get application longhorn-backup -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}'` — expected: `Synced Healthy`
- [ ] T012 [US1] Verify SealedSecret decrypted: run `kubectl get secret longhorn-minio-credentials -n longhorn-system -o jsonpath='{.data}'` and confirm it has three base64 keys (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ENDPOINTS); decode AWS_ENDPOINTS and confirm it equals `http://minio.minio.svc.cluster.local:9000`
- [ ] T013 [US1] Verify Setting values applied: run `kubectl get setting backup-target -n longhorn-system -o jsonpath='{.value}'` → expected `s3://longhorn-backups@us-east-1/`; and `kubectl get setting backup-target-credential-secret -n longhorn-system -o jsonpath='{.value}'` → expected `longhorn-minio-credentials`
- [ ] T014 [US1] Verify Longhorn UI shows backup target Connected: port-forward `kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80` and open `http://localhost:8080`; navigate to Settings → General → confirm Backup Target shows Connected status and no error messages

**Checkpoint**: BackupTarget is live — Longhorn can now back up volumes to MinIO.

---

## Phase 4: User Story 2 — RecurringJob Policies (P2)

**Goal**: All critical cluster PVCs are labeled for their tier, RecurringJob CRDs are active, and Longhorn schedules show the expected nightly snapshots and weekly backups.

**Independent Test**: `kubectl get pvc gitea-shared-storage -n gitea --show-labels` shows `recurring-job-group.longhorn.io/tier-a=enabled` and Longhorn UI Volume detail for that volume shows two scheduled jobs.

- [ ] T015 [US2] Run `ansible-playbook playbooks/utilities/label-pvcs.yml` against the cluster using the correct `KUBECONFIG`; confirm all `kubectl label` tasks report success with no errors
- [ ] T016 [US2] Verify Tier A PVC labels across all namespaces: `kubectl get pvc gitea-shared-storage -n gitea --show-labels | grep tier-a`, check Loki PVC in `monitoring`, check Mosquitto/HA/Node-RED/InfluxDB PVCs in `home-automation`, check `frigate-clips` in `frigate` — all must show `recurring-job-group.longhorn.io/tier-a=enabled`
- [ ] T017 [US2] Verify Tier B PVC labels: `kubectl get pvc -n monitoring --show-labels | grep tier-b` — Prometheus, Alertmanager, Grafana PVCs must show `recurring-job-group.longhorn.io/tier-b=enabled` (and must NOT show tier-a)
- [ ] T018 [US2] Verify RecurringJobs in Longhorn UI: navigate to `http://localhost:8080` (port-forwarded) → Recurring Jobs tab — confirm `snapshot-tier-a`, `backup-tier-a`, `snapshot-tier-b`, `backup-tier-b` all present with correct cron schedules and retain counts; click into any Tier A volume and verify it shows the snapshot-tier-a and backup-tier-a jobs scheduled

**Checkpoint**: All critical PVCs have active RecurringJob schedules.

---

## Phase 5: User Story 3 — Observability (P3)

**Goal**: PrometheusRule alerts for backup failures and missed backups are active in the monitoring stack and visible in the Prometheus alert UI.

**Independent Test**: `kubectl get prometheusrule longhorn-backup-alerts -n longhorn-system` returns the resource, and Prometheus UI at `https://prometheus.fleet1.cloud/alerts` lists both `LonghornBackupFailed` and `LonghornVolumeNotBackedUp`.

- [ ] T019 [US3] Verify PrometheusRule resource exists and is valid: `kubectl get prometheusrule longhorn-backup-alerts -n longhorn-system -o yaml` — confirm two alerts present with correct names, expressions, and labels (`release: kube-prometheus-stack`)
- [ ] T020 [US3] Verify alerts loaded in Prometheus UI: open `https://prometheus.fleet1.cloud/alerts` → search "Longhorn" → confirm `LonghornBackupFailed` and `LonghornVolumeNotBackedUp` both present in state Inactive (green — no active failures expected); if alerts are not visible after 2 minutes, check `kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus | grep longhorn-backup-alerts` for discovery errors

**Checkpoint**: Backup failures will now page the operator via Prometheus alerting.

---

## Phase 6: Polish & Acceptance

**Purpose**: End-to-end validation, idempotency confirmation, and cross-spec hygiene.

- [ ] T021 Trigger a manual test backup to confirm the full pipeline works: in Longhorn UI port-forward, select the Gitea volume → Create Backup (not snapshot) → wait for status Complete; then verify the backup object landed in MinIO: `kubectl port-forward -n minio svc/minio 9000:9000 &` then `mc ls vanlab-minio/longhorn-backups` (using root credentials per spec 060 quickstart) — expected: backup directory with Gitea volume data visible
- [ ] T022 Idempotency check: re-run `ansible-playbook playbooks/cluster/services-deploy.yml --tags argocd-bootstrap`, trigger ArgoCD refresh on `longhorn-backup` Application (expect Synced + Healthy, zero resource changes), and re-run `ansible-playbook playbooks/utilities/label-pvcs.yml` (expect all `kubectl label` commands are no-ops / `already labeled`)
- [ ] T023 Run `quickstart.md` end-to-end against the deployed cluster as a final acceptance check; record any drift between the runbook and reality and fix `specs/061-longhorn-backup-target/quickstart.md` before marking spec 061 done; commit any fixes via branch → PR → merge
- [ ] T024 Update `specs/063-authentik-idp/spec.md` to note that spec 061 is deployed and that the Authentik Postgres PVC must be added to Tier A RecurringJobs by re-running `playbooks/utilities/label-pvcs.yml` with the Postgres PVC included once spec 063 is live

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately. T003 depends on T002 (seal-secrets extension must exist before running it).
- **Foundational (Phase 2)**: T004, T005, T006, T007 can start after T001 (directory exists). T008 can start any time. T009 BLOCKS all deployment verification — must merge before Phase 3.
- **US1 (Phase 3)**: Requires T009 merged to Gitea main. T010–T014 sequential.
- **US2 (Phase 4)**: Requires Phase 3 complete (ArgoCD must have synced RecurringJob CRDs before labels are useful). T015–T018 sequential.
- **US3 (Phase 5)**: Can start after T011 (ArgoCD synced, PrometheusRule applied). T019–T020 sequential.
- **Polish (Phase 6)**: T021 requires Phase 3 + 4 complete. T022 requires Phase 3 complete. T023–T024 require all phases complete.

### Parallel Opportunities Within Phase 2

```
After T001 (directory created):
  T004  backup-settings.yaml
  T005  recurring-jobs.yaml      ← all three in parallel
  T006  prometheus-rules.yaml
  T007  label-pvcs.yml
  T008  argocd_apps update       ← independent, no file conflicts
```

### User Story Dependencies

- **US1 (P1)**: No dependency on US2 or US3. Can stop here for MVP.
- **US2 (P2)**: Depends on US1 (RecurringJob CRDs must exist in cluster before labels take effect).
- **US3 (P3)**: Depends only on ArgoCD sync (T011) — can proceed in parallel with US2.

---

## Parallel Example: Phase 2 Manifests

```bash
# All four manifest/playbook files can be written simultaneously:
Task: "Write manifests/longhorn-backup/backup-settings.yaml (2 Setting CRDs)"
Task: "Write manifests/longhorn-backup/recurring-jobs.yaml (4 RecurringJob CRDs)"
Task: "Write manifests/longhorn-backup/prometheus-rules.yaml (PrometheusRule)"
Task: "Write playbooks/utilities/label-pvcs.yml (PVC labeling playbook)"
Task: "Update argocd_apps in group_vars/all.yml and example.all.yml"
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1: Setup (T001–T003)
2. Complete Phase 2 Foundational: write backup-settings.yaml + SealedSecret + commit (T004, T008, T009)
3. Complete Phase 3: US1 BackupTarget activation (T010–T014)
4. **STOP and VALIDATE**: Longhorn shows backup target Connected, test manual backup works
5. US2 and US3 can follow in subsequent sessions

### Full Delivery

1. Phase 1 + 2 complete → all manifests committed and merged
2. Phase 3 → BackupTarget live ✅
3. Phase 4 → RecurringJob schedules active ✅
4. Phase 5 → Alerting wired ✅
5. Phase 6 → Acceptance + idempotency ✅

---

## Notes

- All ArgoCD operations require being on `main` after PR merge — do not run argocd-bootstrap from the feature branch
- `label-pvcs.yml` must use `--overwrite` on all `kubectl label` calls for idempotency
- PVC names for Helm-deployed StatefulSets (Prometheus, Alertmanager, Grafana, Loki, HA, Node-RED, InfluxDB) are discovered dynamically via label selectors in the playbook — do NOT hardcode them
- The `longhorn-backup` ArgoCD Application targets namespace `longhorn-system`; no `namespace.yaml` needed (namespace already exists)
- sync-wave ordering: SealedSecret (wave 0) → Settings (wave 1) → RecurringJobs + PrometheusRule (wave 2)
