# Data Model — MinIO Object Storage

**Feature**: 060-minio-object-store
**Date**: 2026-05-11

This feature's "data model" is the set of Kubernetes and MinIO resources the implementation produces. Listed here with attributes and relationships.

## Kubernetes Resources

### `Namespace` — `minio`

| Field | Value |
|---|---|
| `metadata.name` | `minio` |
| Labels | `app.kubernetes.io/name=minio`, `argocd.argoproj.io/instance=minio-prereqs` |
| Annotations | `argocd.argoproj.io/sync-wave: "0"` |

### `SealedSecret` — `minio-root` (in `minio` namespace)

Source: `group_vars/all.yml` → `minio_root_user`, `minio_root_password` → sealed via `playbooks/utilities/seal-secrets.yml`.

| Decrypted Key | Source variable |
|---|---|
| `rootUser` | `minio_root_user` |
| `rootPassword` | `minio_root_password` |

Consumed by: MinIO chart via `auth.existingSecret: minio-root` (chart values key may differ per chart version — verify in Phase 2 tasks).

### `SealedSecret` — `longhorn-minio-credentials-source` (in `minio` namespace)

Source: `group_vars/all.yml` → `longhorn_minio_access_key`, `longhorn_minio_secret_key`.

| Decrypted Key | Source variable |
|---|---|
| `accessKey` | `longhorn_minio_access_key` |
| `secretKey` | `longhorn_minio_secret_key` |

**Note**: This is the *source-of-truth* copy in the MinIO namespace; it exists only so the manual bootstrap step (R4) can fetch the same values that spec 061 will also use. Spec 061 produces a *separate* SealedSecret for `longhorn-system` namespace with the same plaintext values (SealedSecrets are namespace-scoped).

### `IngressRoute` — `minio-console` (in `minio` namespace)

| Field | Value |
|---|---|
| `spec.entryPoints` | `["websecure"]` |
| `spec.routes[0].match` | `` Host(`minio.fleet1.lan`) `` |
| `spec.routes[0].services[0].name` | `<release>-console` (resolved at chart-deploy time; release name `minio`) |
| `spec.routes[0].services[0].port` | `9001` |
| `spec.tls.secretName` | fleet1.lan wildcard cert (existing, per spec 054) |

Annotations: `argocd.argoproj.io/sync-wave: "2"`.

### `Application` — `minio-prereqs` (ArgoCD)

| Field | Value |
|---|---|
| `spec.source.repoURL` | `https://gitea.fleet1.cloud/<org>/vanlab` |
| `spec.source.path` | `manifests/minio/prereqs` |
| `spec.destination.namespace` | `minio` |
| `spec.syncPolicy.automated.prune` | `true` |
| `spec.syncPolicy.automated.selfHeal` | `true` |
| `spec.syncPolicy.retry.limit` | `5` |

### `Application` — `minio` (ArgoCD, multi-source)

| Field | Value |
|---|---|
| `spec.sources[0].repoURL` | `https://charts.min.io/` |
| `spec.sources[0].chart` | `minio` |
| `spec.sources[0].targetRevision` | (pinned 5.x version, resolved at task time) |
| `spec.sources[0].helm.valueFiles` | `["$values/manifests/minio/minio-values.yaml"]` |
| `spec.sources[1].repoURL` | `https://gitea.fleet1.cloud/<org>/vanlab` |
| `spec.sources[1].ref` | `values` |
| `spec.destination.namespace` | `minio` |
| `spec.syncPolicy.automated.prune` | `true` |
| `spec.syncPolicy.automated.selfHeal` | `true` |
| `spec.syncPolicy.retry.limit` | `5` |

### Chart-produced resources (created by the Helm chart, not by us)

| Resource | Notes |
|---|---|
| `Deployment` or `StatefulSet` — `minio` | Single replica; arm64 image from multi-arch manifest |
| `PersistentVolumeClaim` | `storageClassName: longhorn`, `resources.requests.storage: 200Gi` (set via values) |
| `Service` — `minio` | ClusterIP, port 9000 (S3 API) — in-cluster only |
| `Service` — `minio-console` | ClusterIP, port 9001 (admin console) — target of the `IngressRoute` |

## MinIO-internal Resources (provisioned via `mc` at standup, not by Helm)

### Bucket — `longhorn-backups`

| Property | Value |
|---|---|
| Name | `longhorn-backups` |
| Versioning | Disabled (Longhorn manages incremental backups itself) |
| Lifecycle policy | **None** — retention is owned by Longhorn `RecurringJob.retain` (per spec clarification 2026-05-11) |
| Quota | None (PVC capacity is the only quota) |

### Bucket — `vanlab-archive`

| Property | Value |
|---|---|
| Name | `vanlab-archive` |
| Versioning | Disabled |
| Lifecycle policy | None |
| Quota | None |
| Purpose | Reserved general-purpose bucket for future consumers (Loki, Authentik blueprint exports, etc.) — no specific consumer at 060 standup |

### MinIO User — Longhorn

| Property | Value |
|---|---|
| Access Key | from `longhorn-minio-credentials-source` SealedSecret |
| Secret Key | from `longhorn-minio-credentials-source` SealedSecret |
| Policy | `longhorn-backups-rw` (custom, scoped) |
| Permissions | `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` on `arn:aws:s3:::longhorn-backups/*` and `arn:aws:s3:::longhorn-backups` only |
| Negative test | Cannot `ListBucket` on `vanlab-archive`; cannot `GetObject` from any bucket other than `longhorn-backups` |

### MinIO Policy — `longhorn-backups-rw`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::longhorn-backups/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": ["arn:aws:s3:::longhorn-backups"]
    }
  ]
}
```

## Relationships

```text
group_vars/all.yml
     │
     │ (seal-secrets.yml)
     ▼
manifests/minio/prereqs/sealed-secrets.yaml
     │
     │ (ArgoCD sync — minio-prereqs Application)
     ▼
SealedSecret (k8s)  ──┬──▶  Secret minio-root          ──▶  MinIO chart (auth.existingSecret)
                     └──▶  Secret longhorn-minio-       ──▶  (read manually at bootstrap;
                            credentials-source                also referenced by spec 061
                                                              for the longhorn-system copy)

manifests/minio/apps/minio-app.yaml + manifests/minio/minio-values.yaml
     │
     │ (ArgoCD multi-source sync — minio Application)
     ▼
MinIO chart resources (Deployment, PVC, Services)

                                                  ┌── (in-cluster Service, port 9000) ──▶ S3 API consumers
MinIO instance ──┬── Service: minio:9000           │   (Longhorn via 061, future Loki/Authentik, etc.)
                 │
                 └── Service: minio-console:9001 ──▶ IngressRoute minio.fleet1.lan (TLS via wildcard)

MinIO instance ──(manual mc bootstrap)──▶ Buckets {longhorn-backups, vanlab-archive}
                                          + User: longhorn (with scoped policy)
```

## Lifecycle / State Transitions

| Transition | Trigger | Resulting state |
|---|---|---|
| Initial deployment | `argocd-bootstrap` tag run after manifests committed | `minio-prereqs` Synced → `minio` Synced → Pod Healthy |
| Bucket bootstrap | Manual `mc` commands per quickstart | Both buckets exist; Longhorn user exists; policy attached |
| Root password rotation | Update `minio_root_password` in `group_vars/all.yml` → re-run `seal-secrets.yml` → commit → push → MinIO Pod restart | New password active; existing Longhorn user credentials unaffected |
| Longhorn credential rotation | Update `longhorn_minio_access_key`/`_secret_key` → re-seal → commit → manually `mc admin user rm` old + `mc admin user add` new + re-attach policy | Old credential rejected; spec 061's Secret must be re-sealed in parallel |
| PVC growth | Edit values file `persistence.size: <new>Gi` → commit → push → ArgoCD applies → Longhorn online-expands | New PVC capacity; no downtime |
| Chart upgrade | Update `targetRevision` in `minio-app.yaml` → commit → push → ArgoCD applies | New chart version live; review release notes for values-key renames |
| Disaster recovery | MinIO PVC corrupted → restore from Longhorn snapshot (once spec 061 is live; until then, snapshots are local-only) | Buckets restored to last snapshot; in-flight backups since snapshot are lost |
