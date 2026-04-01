# Feature Specification: ArgoCD + Gitea GitOps

**Feature Branch**: `005-argocd-gitops`
**Created**: 2026-03-31
**Status**: Draft
**Input**: User description: "argocd+gitea gitops"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Declarative Service Deployment (Priority: P1)

The operator pushes updated Helm values or Kubernetes manifests to a Gitea repository.
ArgoCD detects the change and automatically reconciles the cluster to match the desired
state in Git — without any manual `kubectl` or `helm` commands.

**Why this priority**: This is the core GitOps loop. Everything else depends on this
working reliably. Without it, the other stories have no value.

**Independent Test**: Can be tested end-to-end by committing a trivial change (e.g.,
replica count bump) to a Gitea repo and verifying the cluster reflects it within a
reasonable time without operator intervention.

**Acceptance Scenarios**:

1. **Given** a cluster service is managed by ArgoCD, **When** the operator pushes a
   configuration change to Gitea, **Then** ArgoCD syncs the cluster to match the new
   desired state within 3 minutes without manual intervention.
2. **Given** a Gitea repo contains a valid application definition, **When** ArgoCD
   first discovers it, **Then** the application is deployed to the cluster and shown
   as Healthy + Synced in the dashboard.
3. **Given** a sync is in progress, **When** the cluster reaches the desired state,
   **Then** the application status transitions to Synced with no OutOfSync resources.

---

### User Story 2 - Sync Status Visibility (Priority: P2)

The operator can open a web dashboard to see the current sync and health status of
every GitOps-managed application in one place, without running CLI commands.

**Why this priority**: Observability of the GitOps loop is necessary for the operator
to trust automated deployments and diagnose failures quickly.

**Independent Test**: Can be fully tested by browsing the ArgoCD dashboard and
confirming all registered applications display status (Synced/OutOfSync, Healthy/
Degraded) with drill-down detail — independently of whether Story 1 is active.

**Acceptance Scenarios**:

1. **Given** ArgoCD is running, **When** the operator navigates to the dashboard URL,
   **Then** all managed applications are listed with their sync and health status.
2. **Given** an application is OutOfSync, **When** the operator views its detail page,
   **Then** the specific resources causing the drift are identified.
3. **Given** a sync fails, **When** the operator inspects the application, **Then** a
   human-readable error message is present explaining the failure.

---

### User Story 3 - Git-Driven Rollback (Priority: P3)

The operator reverts a bad deployment by reverting a commit in Gitea. ArgoCD detects
the revert and restores the cluster to the previous working state automatically.

**Why this priority**: Rollback via Git revert is the standard GitOps recovery path.
It completes the operational loop established by Story 1.

**Independent Test**: Can be tested by deploying a breaking change, reverting it in
Gitea, and confirming the cluster returns to a healthy state — without any direct
cluster intervention.

**Acceptance Scenarios**:

1. **Given** a breaking change was pushed to Gitea and synced, **When** the operator
   reverts that commit in Gitea, **Then** ArgoCD syncs the cluster back to the
   pre-change state.
2. **Given** a rollback sync completes, **When** the operator checks the dashboard,
   **Then** the application is shown as Healthy + Synced at the reverted revision.

---

### Edge Cases

- What happens when Gitea is temporarily unreachable? ArgoCD MUST continue serving
  the dashboard and display a clear "repo unreachable" status; it MUST NOT attempt
  destructive actions on the cluster while the source is unavailable.
- What happens when a pushed manifest is syntactically invalid? ArgoCD MUST surface
  a parse/validation error on the application and halt the sync rather than applying
  partial state.
- What happens when a node hosting Gitea storage fails? Gitea data MUST survive via
  replicated storage and the service MUST recover without data loss after the node
  returns or is replaced.
- What happens if ArgoCD and Gitea are both unavailable simultaneously? The cluster
  MUST continue running its last-synced state; previously deployed workloads MUST
  NOT be disrupted.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The cluster MUST host a self-contained Git service where all GitOps
  configuration (manifests, Helm values, ArgoCD Application definitions) is stored.
- **FR-002**: A continuous delivery controller MUST monitor the Git service and
  automatically reconcile the cluster to match the desired state on every commit to
  tracked branches.
- **FR-003**: The operator MUST be able to register a Git repository as a source of
  truth for a cluster application without editing live cluster resources directly.
- **FR-004**: The delivery controller MUST expose a web dashboard accessible within
  the cluster network showing application sync status, health, and recent sync history.
- **FR-005**: All persistent data for the Git service (repositories, configuration,
  user data) MUST survive single-node failures without data loss.
- **FR-006**: Both services MUST be deployed and configured via the existing Ansible
  automation workflow, with no manual cluster steps required after playbook execution.
- **FR-007**: Both services MUST be accessible via HTTPS through the existing Traefik
  ingress with valid TLS certificates.
- **FR-008**: Both services MUST be rebuildable from scratch by re-running the
  deployment playbook (idempotent).
- **FR-009**: The Git service MUST require authentication; anonymous write access MUST
  be disabled.
- **FR-010**: The delivery controller MUST be able to sync applications using Helm
  charts sourced from the self-hosted Git service.

### Key Entities

- **GitOps Repository**: A Git repository hosted on the cluster's Git service
  containing Helm values files or raw Kubernetes manifests representing desired
  cluster state for one or more applications.
- **Application Definition**: A declarative record linking a GitOps repository
  (and optionally a path/branch within it) to a target namespace in the cluster;
  created by the operator and monitored continuously by the delivery controller.
- **Sync Event**: A record of the delivery controller reconciling cluster state to
  a specific Git revision — includes timestamp, target revision, outcome
  (success/failure), and any error details.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A configuration change pushed to Gitea is reflected in the live cluster
  within 3 minutes without any manual operator action.
- **SC-002**: The operator can determine the sync and health status of any managed
  application within 30 seconds of opening the dashboard.
- **SC-003**: A rollback to a prior working state can be completed (via Git revert +
  automatic sync) in under 5 minutes.
- **SC-004**: Both services survive a single-node failure and recover to fully
  operational status without data loss once the node is restored.
- **SC-005**: A fresh cluster can have both services deployed and operational by
  running the standard deployment playbook with no additional manual steps.

## Assumptions

- The operator is the sole user of both services; multi-user access control and team
  workflows are out of scope for this feature.
- Existing Traefik ingress and TLS certificate management are already operational
  on the cluster.
- Longhorn distributed block storage is available as the `longhorn` StorageClass; all
  PVCs for this feature MUST use it (per Constitution Principle VIII).
- The Git service is internal-only; it is not exposed to the public internet directly
  (traffic routes through the existing Cloudflared tunnel if external access is needed).
- ArgoCD will initially manage only new or future services; migrating existing
  Helm-deployed services to GitOps management is out of scope for this feature.
- A single ArgoCD instance (non-HA) is sufficient given the single-operator homelab
  context.
