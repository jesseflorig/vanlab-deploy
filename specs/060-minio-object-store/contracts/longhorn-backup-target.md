# Contract — Longhorn BackupTarget Inputs (consumed by spec 061)

**Feature**: 060-minio-object-store
**Consumer**: 061-longhorn-backup-target

This contract enumerates exactly what spec 061 will need from spec 060 to configure Longhorn's `BackupTarget`.

## Required inputs for spec 061

### BackupTarget URL

```text
s3://longhorn-backups@us-east-1/
```

- `longhorn-backups` is the bucket name (provisioned by 060 standup).
- `us-east-1` is a placeholder region — MinIO ignores it but the AWS SDK that Longhorn embeds requires *some* region.
- A trailing slash is required.

### Credentials Secret (lives in `longhorn-system` namespace)

Spec 061 will create a separate SealedSecret in `manifests/longhorn-backup/prereqs/sealed-secrets.yaml` that decrypts into:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: longhorn-minio-credentials
  namespace: longhorn-system
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: <longhorn_minio_access_key from group_vars/all.yml>
  AWS_SECRET_ACCESS_KEY: <longhorn_minio_secret_key from group_vars/all.yml>
  AWS_ENDPOINTS: http://minio.minio.svc.cluster.local:9000
```

- The plaintext access key and secret are the same values that 060's bootstrap step provisioned in MinIO via `mc admin user add`.
- The `AWS_ENDPOINTS` value points at the in-cluster S3 API Service (per the service-endpoints contract).
- Sealed Secrets are namespace-scoped, so spec 061 MUST re-seal these values for the `longhorn-system` namespace independently — they cannot be reused from 060's `minio`-namespace SealedSecret.

### Longhorn settings to populate (in spec 061's playbook or manifest)

| Setting | Value |
|---|---|
| `backup-target` | `s3://longhorn-backups@us-east-1/` |
| `backup-target-credential-secret` | `longhorn-minio-credentials` |

## What spec 061 MUST NOT do

- MUST NOT create a new bucket — 060 already created `longhorn-backups`.
- MUST NOT use the MinIO root credentials — only the scoped Longhorn credential.
- MUST NOT add bucket lifecycle policies in MinIO — Longhorn `RecurringJob.retain` is the sole retention authority per spec 060 clarification.
- MUST NOT expose MinIO's S3 API via `IngressRoute`.

## Pre-flight checks 061 should run

1. Resolve `minio.minio.svc.cluster.local` from a `longhorn-system` Pod — should return a ClusterIP.
2. `curl -s http://minio.minio.svc.cluster.local:9000/minio/health/live` should return HTTP 200.
3. With the Longhorn credentials, `aws s3 ls s3://longhorn-backups --endpoint-url http://minio.minio.svc.cluster.local:9000` should succeed.
4. With the Longhorn credentials, `aws s3 ls s3://vanlab-archive --endpoint-url …` should **fail with 403** — verifies bucket-scope enforcement.

A failure of (4) is a critical regression — it indicates the MinIO policy was scoped too broadly during the 060 standup `mc` steps, granting Longhorn credentials access beyond their intended bucket.
