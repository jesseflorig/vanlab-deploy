# Phase 0 Research — MinIO Object Storage

**Feature**: 060-minio-object-store
**Date**: 2026-05-11

## Open items entering Phase 0

From spec Clarifications: one Outstanding item — **bucket naming convention for future consumers**.

From planning gaps to resolve:

1. arm64 compatibility of `minio/minio` Helm chart on K3s/CM5
2. Helm chart version pin
3. Admin console TLS termination pattern via Traefik
4. Bucket + per-bucket credential bootstrap mechanism (chart hooks vs `mc` CLI)
5. Longhorn `BackupTarget` URL/credential format for an in-cluster MinIO endpoint
6. Bucket naming convention (resolves the Outstanding item)

---

## R1 — arm64 compatibility

**Decision**: Use the official `minio/minio` Helm chart with default image (multi-arch manifest).

**Rationale**: MinIO publishes official multi-arch container images (`linux/amd64`, `linux/arm64`) under `quay.io/minio/minio`. The Helm chart uses these defaults; no value override is needed. The Raspberry Pi CM5 nodes (arm64) will pull the `linux/arm64` variant transparently.

**Alternatives considered**:
- Pin a specific arm64-tagged image — rejected: the multi-arch manifest is already the standard and changing it adds drift risk on chart upgrades.
- Build a custom arm64 image — rejected: completely unnecessary; upstream supports arm64.

**Verification step in tasks**: post-deploy, `kubectl get pod -n minio -o jsonpath='{.items[0].status.containerStatuses[0].image}'` should match an arm64 digest in the multi-arch manifest.

---

## R2 — Helm chart version pin

**Decision**: Pin chart `minio/minio` to the **latest stable 5.x** at implementation time (verify the exact patch version with `helm search repo minio/minio --versions | head` during 060 task execution). Recorded explicitly in `manifests/minio/apps/minio-app.yaml` under `targetRevision`.

**Rationale**: Constitution Principle XI requires ArgoCD multi-source Applications; pinning `targetRevision` is the GitOps norm. The 5.x line is the current stable chart family (chart was rewritten from earlier 4.x). Avoid auto-following `*` or `5.*` to prevent surprise upgrades on `helm repo update`.

**Alternatives considered**:
- Auto-track latest — rejected: violates the "pin and review" practice; major chart bumps have renamed values keys historically.
- Use an older 4.x for "stability" — rejected: the 4.x line is unmaintained for new features.

**Upgrade policy**: chart minor/patch bumps are reviewed via PR; major bumps require values-file review (mirrors the policy adopted for Authentik in spec 063).

---

## R3 — Admin console TLS termination

**Decision**: Single Traefik `IngressRoute` matching `Host(\`minio.fleet1.lan\`)`, entryPoint `websecure`, TLS from the existing fleet1.lan wildcard cert (spec 054), forwarding to the chart's `console` Service on port 9001. The chart's console Service is named `<release>-console`.

**Rationale**: Matches the pattern already in use elsewhere in the cluster (Grafana, ArgoCD, Gitea — all `*.fleet1.lan` via Traefik wildcard cert). The MinIO chart exposes the console as a separate Service from the S3 API by default, which makes routing the two endpoints cleanly trivial: only the console gets an `IngressRoute`; the S3 API Service is left in-cluster-only.

**S3 API endpoint name**: `<release>` Service (the chart's primary Service), port 9000 — reachable in-cluster as `minio.minio.svc.cluster.local:9000`.

**Alternatives considered**:
- Single `IngressRoute` with path-based routing for both API and console — rejected: harder to apply per-endpoint security (FR-012 wants the S3 API explicitly off ingress).
- Expose console via the chart's built-in Ingress value — rejected: the chart's built-in Ingress doesn't drive `traefik.io/v1alpha1.IngressRoute` CRDs cleanly; using a separate `IngressRoute` resource is the consistent pattern in vanlab.

---

## R4 — Bucket and per-bucket credential bootstrap

**Decision**: Manual bootstrap via the `mc` (MinIO CLI) tool, executed once at standup time from a developer's kubectl-port-forward session or a one-shot `kubectl run` Pod. Documented step in `quickstart.md`.

**Rationale**: The `minio/minio` chart does have `users[]` and `buckets[]` values that *can* drive a post-install Job for provisioning. However:

- Chart-driven user creation does not produce predictable, named access-key/secret-key pairs you can write into a SealedSecret in advance. The chart generates random secrets at install time which then have to be extracted from the cluster — that's a chicken-and-egg violation of Principle IV (secrets should originate from `group_vars/all.yml` and be sealed before commit, not be cluster-generated).
- The manual `mc` approach lets us *pre-generate* access keys, seal them via `seal-secrets.yml`, commit the SealedSecret, and then `mc admin user add` with the same access key the Longhorn consumer will later look up from the SealedSecret. Both ends agree by design.
- `mc mb --ignore-existing`, `mc admin user add`, and `mc admin policy attach` are upsert-safe — re-running them does no harm, preserving Principle II.

**Alternatives considered**:
- Chart's `buckets[]` and `users[]` values — rejected per Principle IV reasoning above.
- A custom Kubernetes Job in `prereqs/` that runs `mc` against MinIO during sync — rejected for v1: adds order-of-operations complexity (Job has to wait for MinIO to be Ready), and the manual one-time step is acceptable for a single-tenant homelab. Can be revisited if multi-tenant bucket provisioning ever becomes routine.

**Bootstrap steps to be captured in `quickstart.md`**:
1. After ArgoCD reports `minio` Application Synced & Healthy, `kubectl port-forward svc/minio 9000:9000 -n minio` on a workstation with `mc` installed.
2. `mc alias set vanlab-minio https://localhost:9000 <root-user> <root-password>` (root creds from the sealed secret, retrievable via `kubectl get secret`).
3. `mc mb --ignore-existing vanlab-minio/longhorn-backups`
4. `mc mb --ignore-existing vanlab-minio/vanlab-archive` (the reserved general-purpose bucket — see R6)
5. `mc admin user add vanlab-minio <longhorn-access-key> <longhorn-secret-key>` (values from sealed secret)
6. Create a custom policy `longhorn-backups-rw` scoped to `arn:aws:s3:::longhorn-backups/*` with `s3:GetObject, PutObject, DeleteObject, ListBucket`; attach to the Longhorn user.
7. Verify with `mc ls vanlab-minio` as the Longhorn user — should see only `longhorn-backups`.

---

## R5 — Longhorn `BackupTarget` URL format

**Decision**: Longhorn `BackupTarget` URL is `s3://longhorn-backups@us-east-1/` with credentials supplied via a Kubernetes Secret in the `longhorn-system` namespace named `longhorn-minio-credentials`.

**Rationale**: Longhorn's S3 backend uses the AWS S3 SDK and expects a URL of the form `s3://<bucket>@<region>/`. MinIO requires *some* region string in the URL even though MinIO itself is region-agnostic; `us-east-1` is the canonical default. The endpoint URL (cluster DNS `minio.minio.svc.cluster.local:9000`) is supplied via the `AWS_ENDPOINTS` key inside the credentials Secret, not in the URL.

**Credentials Secret format** (consumed by Longhorn in spec 061, but the source values originate from this spec's SealedSecret):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: longhorn-minio-credentials
  namespace: longhorn-system
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: <longhorn-access-key>
  AWS_SECRET_ACCESS_KEY: <longhorn-secret-key>
  AWS_ENDPOINTS: http://minio.minio.svc.cluster.local:9000
```

This spec produces the **source-of-truth SealedSecret** for these credentials in `manifests/minio/prereqs/sealed-secrets.yaml`. Spec 061 will produce a *second* SealedSecret in `manifests/longhorn-backup/prereqs/` containing the same access/secret pair (sealed for the `longhorn-system` namespace this time, since SealedSecrets are namespace-scoped). Both come from the same source values in `group_vars/all.yml`.

**Alternatives considered**:
- HTTPS endpoint for MinIO inside the cluster — rejected: requires additional cert wiring for in-cluster mTLS; constitution VI exempts intra-cluster traffic from the encryption-in-transit requirement (`SHOULD use mTLS where the workload supports it`, not MUST). HTTP within the cluster overlay is acceptable for v1; revisit if/when MinIO is exposed beyond the cluster.

---

## R6 — Bucket naming convention (resolves spec Outstanding)

**Decision**:
- **Per-consumer dedicated buckets**: named for the consumer (`longhorn-backups`, future `loki-chunks`, future `authentik-blueprints`).
- **General-purpose buckets**: prefixed `vanlab-` (`vanlab-archive`).
- All lowercase, hyphen-separated, no underscores (MinIO bucket name rules + S3 path compatibility).

At standup time this spec provisions exactly two buckets: `longhorn-backups` and `vanlab-archive`. Additional buckets are provisioned on-demand by their consumer's spec (e.g., 061 only consumes `longhorn-backups` — does not create new buckets).

**Rationale**: Naming a bucket per consumer makes ACL/policy scoping unambiguous; the `vanlab-` prefix distinguishes "default fallback" buckets from "this belongs to consumer X" buckets at a glance. Hyphenated lowercase satisfies all MinIO and AWS S3 naming rules and avoids ambiguity in S3 path-style URLs.

**Alternatives considered**:
- Single shared bucket with prefix-based separation — rejected: per-prefix ACLs are clumsier than per-bucket; complicates retention policies and quota observation.
- Random-suffixed bucket names for collision avoidance — rejected: single-tenant homelab has no collision risk; readability wins.

This resolves the Outstanding clarification item from the spec.

---

## Summary of resolved unknowns

| Item | Resolution |
|---|---|
| arm64 chart support | Confirmed via upstream multi-arch image (R1) |
| Chart version | Pin latest stable 5.x at task-execution time; record in `targetRevision` (R2) |
| Console TLS termination | Single Traefik `IngressRoute` to `<release>-console` Service:9001 with wildcard cert (R3) |
| Bucket + credential bootstrap | Manual `mc` bootstrap; pre-generated keys via SealedSecret (R4) |
| Longhorn BackupTarget URL | `s3://longhorn-backups@us-east-1/` + Secret with endpoint `http://minio.minio.svc.cluster.local:9000` (R5) |
| Bucket naming | Lowercase-hyphenated; per-consumer = consumer-named; general-purpose = `vanlab-*` (R6) |

All NEEDS CLARIFICATION resolved. Ready for Phase 1.
