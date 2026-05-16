# Implementation Plan: MinIO Object Storage

**Branch**: `060-minio-object-store` | **Date**: 2026-05-11 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/060-minio-object-store/spec.md`

## Summary

Deploy a single-node MinIO instance via the official `minio/minio` Helm chart, ArgoCD-managed using the multi-source pattern, as cluster-internal S3-compatible object storage. First consumer is Longhorn's off-cluster `BackupTarget`. Admin console is exposed on `*.fleet1.lan` via Traefik + the existing wildcard cert; the S3 API is in-cluster-only via Service. MinIO admin and per-bucket credentials are stored as SealedSecrets; per-bucket scoped credentials are provisioned manually via `mc` at standup time.

This spec produces only the MinIO instance + the Longhorn backup bucket + one reserved general-purpose bucket. Wiring Longhorn's `BackupTarget` and `RecurringJob` resources is **out of scope** here and lives in spec 061.

## Technical Context

**Language/Version**: YAML (Ansible 2.x for inventory + utility playbooks; Kubernetes manifests; Helm values v3)
**Primary Dependencies**: ArgoCD (already deployed, spec 005), Sealed Secrets controller (already deployed, per Principle XI infra list), Longhorn v1.11.1 (spec 006), Traefik v3 (existing), cert-manager + fleet1.lan wildcard cert (spec 054), MinIO `minio/minio` Helm chart (community)
**Storage**: Longhorn `storageClassName: longhorn`, 200Gi initial PVC for MinIO data; online expansion via Longhorn when usage crosses ~70%
**Testing**: ArgoCD sync verification (idempotency on re-sync); `mc` CLI smoke test against the deployed Service; `aws s3` test Pod for bucket-scope verification (negative test: forbidden bucket → 403); manual restore-from-snapshot test deferred to spec 061
**Target Platform**: K3s on Raspberry Pi CM5 (arm64, Raspberry Pi OS / Debian-based); MinIO has first-class arm64 builds (research-confirmed in Phase 0)
**Project Type**: Application workload — follows `manifests/<namespace>/` pattern per Constitution Principle XI
**Performance Goals**: No latency targets (homelab). Throughput must comfortably cover the nightly Longhorn backup window for ~150Gi of source PVC data across the cluster.
**Constraints**: Single-node deployment (no MinIO erasure coding; durability via Longhorn 3× replication); S3 API not exposed via IngressRoute; admin console LAN+Tailscale only
**Scale/Scope**: One MinIO tenant, two buckets at standup (`longhorn-backups`, one reserved general-purpose bucket — name resolved in Phase 0), one root credential + one Longhorn-scoped credential at standup

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|---|---|---|
| I. IaC | All deployment artifacts in repo (manifests + values + SealedSecrets) | ✅ Pass — multi-source ArgoCD Application; no manual cluster changes |
| II. Idempotency | ArgoCD reconciliation idempotent; manual `mc` bucket-provisioning steps documented and re-runnable | ✅ Pass — `mc mb --ignore-existing`, `mc admin user add` is upsert-safe |
| III. Reproducibility | Fresh cluster rebuild produces identical deployment from repo + `group_vars/all.yml` | ✅ Pass |
| IV. Secrets Hygiene | MinIO root password + per-bucket creds as SealedSecrets only; no plaintext `Secret` manifests committed | ✅ Pass — SealedSecrets generated via `playbooks/utilities/seal-secrets.yml` |
| V. Simplicity | Single-node, community chart, no MinIO Operator, no multi-tenancy | ✅ Pass — explicit clarification 2026-05-11 |
| VI. Encryption in Transit | Console TLS via Traefik + wildcard cert; S3 API stays on cluster overlay (in-cluster Service, not crossing VLAN boundary) | ✅ Pass — no cross-VLAN plaintext |
| VII. Least Privilege | Per-bucket scoped MinIO users; Longhorn credential cannot access any bucket but `longhorn-backups` | ✅ Pass — bucket-scoped policy required by FR-005 |
| VIII. Persistent Storage | Longhorn PVC, `storageClassName: longhorn` explicit, 200Gi explicit | ✅ Pass — FR-010 |
| IX. Secure Service Exposure | Console on HTTPS via Traefik wildcard cert; S3 API not externally exposed | ✅ Pass — FR-004, FR-012 |
| X. Intra-Cluster Service Locality | Consumers (Longhorn, future Loki, future Authentik) reach MinIO via cluster DNS, not via public hostname | ✅ Pass — S3 API is Service-only; no IngressRoute for the API |
| XI. GitOps Application Deployment | Multi-source ArgoCD Application; `manifests/minio/{prereqs,apps}/` layout; ArgoCD as sole deploy mechanism | ✅ Pass — see Project Structure below |

**No violations. Constitution Check passes.**

## Project Structure

### Documentation (this feature)

```text
specs/060-minio-object-store/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── longhorn-backup-target.md
│   └── service-endpoints.md
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

This is a Kubernetes/GitOps deployment, not a software project. Layout follows Constitution Principle XI's `manifests/<namespace>/` pattern:

```text
manifests/
└── minio/
    ├── prereqs/
    │   ├── namespace.yaml                # sync wave 0
    │   ├── sealed-secrets.yaml           # sync wave 1 — generated by seal-secrets.yml
    │   └── ingress-route.yaml            # sync wave 2 — IngressRoute for admin console only
    ├── apps/
    │   └── minio-app.yaml                # multi-source ArgoCD Application
    └── minio-values.yaml                 # Helm values (no secret values)

group_vars/
└── all.yml                               # ADD (untracked): minio_root_user, minio_root_password,
                                          #   longhorn_minio_access_key, longhorn_minio_secret_key
group_vars/
└── example.all.yml                       # UPDATE: add placeholders for the four MinIO secrets above

playbooks/
└── utilities/
    └── seal-secrets.yml                  # UPDATE: extend to also generate manifests/minio/prereqs/sealed-secrets.yaml
```

**ArgoCD app registration** (per Principle XI): add `minio` to `argocd_apps` in `group_vars/all.yml`; apply via `--tags argocd-bootstrap`.

**Structure Decision**: Application workload following the constitution's multi-source ArgoCD pattern. The `prereqs/` Application creates namespace, SealedSecrets, and the console IngressRoute (sync waves 0 → 2). The `apps/` Application is the multi-source Helm install of MinIO consuming the values file from this Gitea repo. The MinIO chart itself creates the `Service`, `Deployment` (or `StatefulSet`), PVC, and admin/data ServiceAccounts.

## Complexity Tracking

> No constitution violations to justify. Section intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| _(none)_ | | |
