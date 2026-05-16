# Quickstart — Longhorn Backup Target (MinIO)

**Feature**: 061-longhorn-backup-target

This quickstart is the operator runbook for deploying spec 061: wiring Longhorn to the MinIO `longhorn-backups` bucket, applying RecurringJob policies to critical PVCs, and validating end-to-end backup delivery.

## Prerequisites

- Spec 060 (MinIO) deployed and healthy — bucket `longhorn-backups` exists, Longhorn credentials provisioned.
- `longhorn_minio_access_key` and `longhorn_minio_secret_key` present in `group_vars/all.yml`.
- `kubectl` configured for the cluster; `kubeseal` available on management laptop.
- ArgoCD, Sealed Secrets controller, Longhorn v1.11.1 all healthy.

## Pre-flight checks

Run these before starting to confirm spec 060's outputs are reachable:

```bash
# 1. MinIO S3 API reachable in-cluster (from any pod in longhorn-system)
kubectl run -it --rm preflight --image=curlimages/curl --restart=Never -n longhorn-system -- \
  curl -s -o /dev/null -w "%{http_code}" http://minio.minio.svc.cluster.local:9000/minio/health/live
# Expected: 200

# 2. Longhorn credential can list the backup bucket
LH_AK=$(grep longhorn_minio_access_key group_vars/all.yml | awk '{print $2}')
LH_SK=$(grep longhorn_minio_secret_key group_vars/all.yml | awk '{print $2}')
kubectl port-forward -n minio svc/minio 9000:9000 &
PF_PID=$!
mc alias set preflight-check http://localhost:9000 "$LH_AK" "$LH_SK"
mc ls preflight-check/longhorn-backups   # Expected: empty listing, exit 0
mc ls preflight-check/vanlab-archive     # Expected: Access Denied (403)
kill $PF_PID
```

If check (2) fails with access granted to `vanlab-archive`, stop — the MinIO policy from spec 060 is too broad. Do not proceed until fixed.

## Step 1 — Extend seal-secrets.yml and generate the SealedSecret

The `longhorn_minio_access_key` and `longhorn_minio_secret_key` values are already in `group_vars/all.yml` from spec 060. Add the `longhorn-backup` play to `playbooks/utilities/seal-secrets.yml` and seal:

```bash
ansible-playbook playbooks/utilities/seal-secrets.yml --tags longhorn-backup
```

Inspect `manifests/longhorn-backup/prereqs/sealed-secrets.yaml` — it must:
- Contain one `SealedSecret` named `longhorn-minio-credentials`
- Have `namespace: longhorn-system`
- Contain zero plaintext values

## Step 2 — Commit and push

```bash
git add manifests/longhorn-backup/ playbooks/utilities/seal-secrets.yml \
        playbooks/utilities/label-pvcs.yml group_vars/example.all.yml
git commit -m "feat(longhorn-backup): add backup target manifests and RecurringJob policies"
git push gitea 061-longhorn-backup-target
git push origin 061-longhorn-backup-target
```

Merge via Gitea PR per CLAUDE.md workflow.

## Step 3 — Register and sync via ArgoCD

```bash
ansible-playbook playbooks/cluster/services-deploy.yml --tags argocd-bootstrap
```

Watch `https://argocd.fleet1.cloud` → `longhorn-backup` Application should reach Synced + Healthy within ~2 minutes.

Verify resources applied:

```bash
kubectl get setting backup-target -n longhorn-system -o jsonpath='{.value}'
# Expected: s3://longhorn-backups@us-east-1/

kubectl get setting backup-target-credential-secret -n longhorn-system -o jsonpath='{.value}'
# Expected: longhorn-minio-credentials

kubectl get recurringjob -n longhorn-system
# Expected: snapshot-tier-a, backup-tier-a, snapshot-tier-b, backup-tier-b

kubectl get secret longhorn-minio-credentials -n longhorn-system
# Expected: Opaque secret with 3 data keys
```

## Step 4 — Apply PVC labels (one-time Ansible bootstrap)

```bash
ansible-playbook playbooks/utilities/label-pvcs.yml
```

This applies `recurring-job-group.longhorn.io/tier-a=enabled` and `tier-b=enabled` labels to all critical PVCs using `--overwrite` (idempotent).

Verify:

```bash
kubectl get pvc gitea-shared-storage -n gitea --show-labels | grep recurring
# Expected: recurring-job-group.longhorn.io/tier-a=enabled

kubectl get pvc -n monitoring --show-labels | grep recurring
# Expected: Loki PVC has tier-a; Prometheus/Alertmanager/Grafana PVCs have tier-b
```

## Step 5 — Verify backup target in Longhorn UI

Open `https://longhorn.fleet1.lan` (or access via `kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80`).

Navigate to **Settings → General → Backup Target**:
- Backup Target: `s3://longhorn-backups@us-east-1/`
- Backup Target Credential Secret: `longhorn-minio-credentials`
- Status: Connected ✅

If the UI shows "Cannot access backup target" — verify the SealedSecret decrypted correctly and MinIO is reachable.

## Step 6 — Trigger a test backup

In the Longhorn UI, navigate to **Volumes**, select any Tier A volume (e.g., the Gitea volume), and click **Create Backup** (not snapshot — backup to S3).

Then verify the backup object landed in MinIO:

```bash
kubectl port-forward -n minio svc/minio 9000:9000 &
PF_PID=$!
mc alias set vanlab-minio http://localhost:9000 "$ROOT_USER" "$ROOT_PASS"
# (ROOT_USER/ROOT_PASS fetched from minio-root secret as in spec 060 quickstart)
mc ls vanlab-minio/longhorn-backups
# Expected: backup directory visible
kill $PF_PID
```

## Step 7 — Verify PrometheusRule loaded

```bash
kubectl get prometheusrule longhorn-backup-alerts -n longhorn-system
# Expected: resource exists

# Check it appears in Prometheus UI
# https://prometheus.fleet1.cloud/alerts → search "Longhorn"
# Expected: LonghornBackupFailed and LonghornVolumeNotBackedUp present (inactive/green)
```

## Step 8 — Idempotency check

Re-run ArgoCD sync and Ansible playbook:

```bash
# ArgoCD: trigger refresh — should remain Synced + Healthy, zero resource changes
kubectl annotate application longhorn-backup -n argocd \
  argocd.argoproj.io/refresh=normal --overwrite

# Ansible label playbook re-run — all kubectl label commands should be no-ops
ansible-playbook playbooks/utilities/label-pvcs.yml
```

## Step 9 — Hand-off to spec 063

When all checks pass, spec 063 (Authentik IdP) can begin. When spec 063 deploys its Postgres PVC, add it to Tier A by re-running `label-pvcs.yml` with the Postgres PVC included.

## Rollback

1. ArgoCD UI → `longhorn-backup` Application → Disable Auto-Sync → Delete (cascade).
2. Remove `longhorn-backup` from `argocd_apps` in `group_vars/all.yml`.
3. Remove PVC labels:
   ```bash
   # For each labeled PVC:
   kubectl label pvc <name> -n <ns> \
     recurring-job-group.longhorn.io/tier-a- \
     recurring-job-group.longhorn.io/tier-b-
   ```
4. The Setting resources will revert to default (empty backup target) once deleted.
5. No data loss — removing backup configuration does not delete existing backup objects in MinIO.
