# Feature Specification: MinIO Object Storage

**Feature Branch**: `060-minio-object-store`
**Created**: 2026-05-11
**Status**: Draft
**Input**: User description: "Deploy MinIO as in-cluster S3-compatible object storage; first consumer is Longhorn off-cluster backups."

## Background

The vanlab cluster has Longhorn (spec 006) providing block storage with 3-way replication, but **no off-cluster backup target**. A Longhorn `BackupTarget` requires S3-compatible or NFS storage outside the affected PVCs' fate-sharing domain. Standing up MinIO inside the cluster (on Longhorn-backed PVCs in a *separate* namespace) gives Longhorn a backup destination *without* introducing an external dependency.

This is also a prerequisite for the SSO initiative (planned 063–065). Authentik's Postgres PVC needs real backups before it accumulates value.

MinIO is intended as a **general-purpose S3 endpoint** for the cluster — Longhorn backups are the first consumer, but Loki long-term storage, Authentik blueprint exports, and future Velero backups are anticipated consumers.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Longhorn Has an Off-Cluster Backup Target (Priority: P1)

As a lab administrator, I want Longhorn to write scheduled backups to an S3-compatible target so that PVC recovery is possible after corruption, bad upgrades, or accidental deletion — not just after disk failure (which 3-way replication already covers).

**Why this priority**: This is the actual driver. Without it, every downstream feature that holds state (Authentik, expanded Gitea use, future databases) inherits a "no real backup" gap. Longhorn replicas are *not* backups — they protect against disk failure, not against logical corruption or user error.

**Independent Test**: Configure Longhorn `BackupTarget` against the new MinIO bucket; trigger a manual backup on an existing PVC; confirm the backup appears in MinIO and can be restored to a fresh PVC.

**Acceptance Scenarios**:

1. **Given** MinIO is deployed and reachable in-cluster, **When** Longhorn is configured with the MinIO endpoint and bucket credentials, **Then** the Longhorn `BackupTarget` reports healthy and a manual backup of a test PVC completes successfully.
2. **Given** a Longhorn backup exists in MinIO, **When** the original PVC is deleted and a restore is initiated from the backup, **Then** a new PVC is created with the original data intact.
3. **Given** MinIO is unavailable, **When** Longhorn attempts a backup, **Then** the backup job fails with a clear error and existing PVCs remain unaffected.

---

### User Story 2 - Future Apps Have a Cluster-Local S3 Endpoint (Priority: P2)

As a lab administrator, I want a general-purpose S3-compatible endpoint that future apps (Loki long-term, Authentik blueprint exports, Velero cluster backups, custom apps) can consume without me deploying another object store later.

**Why this priority**: Capacity for future use is a meaningful design goal — multiple anticipated consumers (Loki S3, blueprint storage, etc.) would otherwise each justify their own MinIO/object store deployment. Building one well-organized instance up front is cheaper than retrofitting.

**Independent Test**: Create a second bucket distinct from the Longhorn backup bucket; create a scoped access credential for that bucket; verify a kubectl-run `aws s3` test pod can write/read in the second bucket but cannot access the Longhorn bucket.

**Acceptance Scenarios**:

1. **Given** MinIO is deployed with a service account model, **When** a new application bucket is provisioned with scoped credentials, **Then** those credentials can read/write only the intended bucket and cannot list or access other buckets.
2. **Given** multiple bucket-scoped credentials exist, **When** one credential is rotated or revoked, **Then** other buckets and their consumers are unaffected.

---

### User Story 3 - Deployment Is GitOps-Managed and Reproducible (Priority: P2)

As a lab administrator, I want MinIO deployment, configuration, bucket creation, and credentials to be managed via ArgoCD + Sealed Secrets so that the install is reproducible and follows the same operational pattern as the rest of the stack.

**Why this priority**: The vanlab stack is consistently GitOps-managed (spec 005). A hand-managed MinIO would be an outlier with its own restore-from-disaster story.

**Independent Test**: Tear down the MinIO namespace; run an ArgoCD sync against the MinIO `Application`; verify MinIO comes back with all buckets, policies, and consumer credentials intact (credentials regenerated from Sealed Secrets, bucket data lost — which is acceptable because backups are themselves recoverable as PVC snapshots).

**Acceptance Scenarios**:

1. **Given** the MinIO ArgoCD `Application` is defined, **When** ArgoCD performs a fresh sync, **Then** the namespace, MinIO Deployment/StatefulSet, Service, IngressRoute, and Sealed Secrets are all created without manual intervention.
2. **Given** MinIO is running, **When** a sealed secret containing a bucket credential is updated and synced, **Then** the new credential is provisioned without disrupting existing buckets.

---

### Edge Cases

- What happens if MinIO's own PVC is corrupted? (Longhorn backups stored there are unrecoverable from that path; however, since this is Longhorn's *backup* target, losing it means losing the off-cluster copy — local Longhorn snapshots remain. A second-tier remote target is out of scope but worth noting.)
- What happens during a cluster-wide outage? (MinIO is unreachable; Longhorn backups fail until cluster recovers. Existing on-cluster PVC data is unaffected.)
- How are bucket-scoped credentials rotated without disrupting consumers?
- How are MinIO admin credentials recovered if the bootstrap Sealed Secret is lost?
- What is the disk usage growth model — does Longhorn backup retention need to be tuned to prevent the MinIO PVC from filling?
- What happens if a consumer (e.g., a misbehaving app) generates excessive PUT traffic — is there any rate limiting or quota?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MinIO MUST be deployed via the official **`minio/minio` community Helm chart**, managed by ArgoCD as a Kubernetes `Application` in the same GitOps pattern as the rest of vanlab. The MinIO Operator and Bitnami's chart are explicitly not used.
- **FR-002**: MinIO MUST run on Longhorn-backed PVC storage in a namespace **separate** from any namespace whose PVCs it will back up (to avoid Longhorn-issue fate-sharing).
- **FR-003**: MinIO MUST expose its S3 API on a cluster-internal `Service` reachable by Longhorn and future S3-consuming workloads.
- **FR-004**: MinIO MUST expose its admin console on `*.fleet1.lan` via Traefik + existing wildcard TLS (spec 054), accessible only from LAN/Tailscale.
- **FR-005**: MinIO MUST support multiple buckets with **per-bucket scoped credentials** — a credential for one bucket MUST NOT be able to read, write, or list any other bucket.
- **FR-006**: MinIO admin (root) credentials and per-bucket credentials MUST be stored as Sealed Secrets in Git — never plaintext.
- **FR-007**: At minimum two buckets MUST be provisioned at standup: one for Longhorn backups, one reserved for future general-purpose use (naming TBD).
- **FR-008**: The MinIO PVC MUST be included in any cluster-wide backup story *only after* spec 061 (Longhorn backup target) is in place — and MinIO must not be configured to back up to *itself*.
- **FR-009**: Retention of Longhorn backup objects MUST be owned by Longhorn via `RecurringJob.retain` (per-PVC, per-job count). The MinIO bucket MUST NOT have a competing lifecycle policy. Longhorn is the single source of truth for "how many backups exist."
- **FR-010**: MinIO MUST be provisioned with an **initial PVC size of 200 Gi** on Longhorn. PVC usage MUST be monitored (alert at ~70% used) and expanded via Longhorn's online volume expansion when growth warrants. Estimated based on ~150 Gi source data across critical PVCs + headroom for the second-bucket future use case.
- **FR-011**: MinIO MUST be deployed in **single-node mode** (one Pod, one PVC). Durability is provided by Longhorn's 3-way replication of the underlying PVC; MinIO-level erasure coding is explicitly not used.
- **FR-012**: The MinIO S3 API endpoint MUST be reachable **in-cluster only** via its `Service`. The admin console MUST be exposed on `*.fleet1.lan` via Traefik + the existing wildcard cert. The S3 API MUST NOT be exposed via `IngressRoute` to LAN/Tailscale; off-cluster S3 access is explicitly out of scope for v1.

### Key Entities

- **MinIO Tenant**: The deployed MinIO instance providing the S3 API endpoint. Holds buckets, policies, and access credentials.
- **Bucket**: A logical container for objects, named per-consumer (e.g., `longhorn-backups`, `loki-chunks`, `vanlab-archive`).
- **Service Account / Access Credential**: A scoped MinIO user with an access key + secret key, granted explicit policy permissions to specific buckets only.
- **Bucket Policy**: The ACL/policy defining which credentials can perform which operations (get/put/list/delete) on a given bucket.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A fresh ArgoCD sync of the MinIO `Application` produces a working MinIO instance with all configured buckets and credentials, zero manual post-sync steps.
- **SC-002**: Longhorn `BackupTarget` health check returns healthy within 60 seconds of the MinIO endpoint coming online.
- **SC-003**: A bucket-scoped credential cannot list or access any bucket outside its scope (verified via test pod running `aws s3 ls` against a forbidden bucket — must fail with 403).
- **SC-004**: Re-running the ArgoCD sync produces zero changes (idempotency).
- **SC-005**: No MinIO credentials appear in plaintext in any committed file.
- **SC-006**: The MinIO admin console is reachable at its `*.fleet1.lan` hostname from LAN or Tailscale, and is **not** reachable from the public internet.

## Clarifications

### Session 2026-05-11

- Q: Single-node MinIO vs distributed mode? → A: Single-node — durability comes from Longhorn 3× replication; MinIO erasure coding skipped.
- Q: Which Helm chart? → A: Official `minio/minio` community chart (not Operator, not Bitnami).
- Q: S3 API endpoint exposure scope? → A: In-cluster Service only; admin console alone on `*.fleet1.lan`. Off-cluster S3 access out of scope for v1.
- Q: Who owns backup retention? → A: Longhorn `RecurringJob.retain` is sole source of truth; no MinIO lifecycle policy.
- Q: Initial MinIO PVC size? → A: 200 Gi, with online expansion via Longhorn when usage exceeds ~70%.

### Pending — to be resolved during `/clarify` or planning

- Bucket naming convention for future consumers.

## Assumptions

- Longhorn (spec 006) is already deployed and healthy.
- ArgoCD (spec 005) is the deployment mechanism.
- Sealed Secrets is the secrets-handling pattern (existing convention in `manifests/*/prereqs/sealed-secrets.yaml`).
- Traefik + cert-manager + fleet1.lan wildcard cert (spec 054) provide ingress and TLS.
- MinIO will be deployed in **single-tenant single-node** mode for homelab simplicity; distributed mode and multi-tenancy are explicitly out of scope for v1.
- The bootstrap MinIO admin password lives in a Sealed Secret; bucket-scoped credentials are managed as additional Sealed Secrets, one per consumer.
- Per-bucket credentials are created **manually via MinIO CLI/console at standup time**, not via a Helm chart's bucket-provisioning hooks (which exist but have inconsistent behavior across MinIO chart versions).
- This spec is the prerequisite for spec 061 (Longhorn backup target configuration) and indirectly for specs 063–065 (Authentik SSO) which depend on a real backup story.
