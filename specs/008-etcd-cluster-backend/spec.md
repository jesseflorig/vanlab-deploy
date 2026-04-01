# Feature Specification: etcd Cluster Backend

**Feature Branch**: `008-etcd-cluster-backend`
**Created**: 2026-04-01
**Status**: Draft
**Input**: User description: "convert the cluster to etcd so i can add and promote nodes easier"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Add a New Worker Node Without Manual Remediation (Priority: P1)

An operator wants to add a new Raspberry Pi node to the cluster. With etcd as the datastore,
the new node joins cleanly without any manual token file workarounds or cluster restarts.

**Why this priority**: The most common day-to-day operation on a growing homelab — the current
SQLite/embedded datastore makes multi-server scenarios fragile and node joins unpredictable.

**Independent Test**: Can be fully tested by adding a new node to `hosts.ini` under `[agents]`,
running the k3s-deploy playbook, and verifying the node reaches `Ready` state with no manual steps.

**Acceptance Scenarios**:

1. **Given** a running etcd-backed cluster, **When** the deploy playbook runs against a new agent node, **Then** the node joins and reaches `Ready` state without manual remediation steps.
2. **Given** a new node has joined, **When** `kubectl get nodes` is run, **Then** all nodes appear as `Ready` with correct roles assigned.

---

### User Story 2 - Promote a Worker Node to Control Plane (Priority: P2)

An operator wants to promote an existing agent node to a server (control plane) node to
increase cluster resilience. With etcd, K3s supports multi-server HA and node promotion
is a supported operational workflow.

**Why this priority**: Core motivation for the etcd migration — SQLite only supports a single
server node, making promotion impossible without a full cluster rebuild.

**Independent Test**: Can be tested by reassigning a node from `[agents]` to `[servers]` in
`hosts.ini` and re-running the deploy playbook, verifying it joins the control plane quorum.

**Acceptance Scenarios**:

1. **Given** an etcd-backed cluster with a node in `[agents]`, **When** the node is moved to `[servers]` and the deploy playbook re-runs, **Then** the node joins the etcd quorum and is recognized as a control plane node.
2. **Given** multiple server nodes, **When** one server node is powered off, **Then** the cluster remains operational and existing workloads continue running.

---

### User Story 3 - Cluster Survives Full Rebuild with All Services Operational (Priority: P3)

An operator rebuilds the cluster from scratch. The playbook provisions etcd-backed K3s on
all nodes and the cluster reaches a healthy state with all services operational.

**Why this priority**: Reproducibility (Principle III) must hold after the datastore change.
A full rebuild must be as reliable as the current SQLite-backed flow.

**Independent Test**: Uninstall K3s on all nodes and re-run the full deploy + services playbook
sequence; verify all nodes join and core services come up cleanly.

**Acceptance Scenarios**:

1. **Given** bare nodes (K3s uninstalled), **When** the k3s-deploy playbook runs, **Then** the cluster forms with etcd as the datastore and all nodes reach `Ready`.
2. **Given** a freshly deployed cluster, **When** services-deploy runs, **Then** all services deploy without errors and ArgoCD syncs application manifests successfully.

---

### Edge Cases

- What happens when etcd quorum is lost (fewer than half of server nodes are available)?
- What is the supported migration path from the existing SQLite-backed cluster — clean rebuild or in-place upgrade?
- What happens if a second server node is added while the first server is temporarily offline?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The first K3s server node MUST be installed with `--cluster-init` to initialize the embedded etcd datastore.
- **FR-002**: Additional server nodes MUST join the existing etcd cluster via the first server's URL and node token, without `--cluster-init`.
- **FR-003**: The deploy playbook MUST distinguish the first server node (initializer) from subsequent server nodes and apply the correct install flags to each.
- **FR-004**: Agent nodes MUST continue to join using `K3S_URL` pointing at the first server node, unchanged from current behavior.
- **FR-005**: The playbook MUST be idempotent — re-running against an already-configured cluster MUST NOT reinitialize etcd or disrupt existing quorum.
- **FR-006**: `hosts.ini` MUST support multiple entries under `[servers]` and the playbook MUST handle them correctly.
- **FR-007**: The migration path (clean rebuild required) MUST be documented in `README.md` before the feature is considered complete.
- **FR-008**: `group_vars/example.all.yml` MUST be updated with any new variables introduced by this change.

### Key Entities

- **First server node**: The node that initializes the etcd cluster with `--cluster-init`; identified as `groups['servers'][0]` in the inventory.
- **Additional server nodes**: Control plane nodes that join an existing etcd quorum; require a different install command than the first server.
- **Agent nodes**: Worker-only nodes; behavior and install command unchanged from current design.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new agent node added to `hosts.ini` reaches `Ready` state within 5 minutes of running the deploy playbook, with no manual remediation steps.
- **SC-002**: A node promoted from `[agents]` to `[servers]` joins the control plane after a single playbook re-run, with no downtime for existing workloads.
- **SC-003**: A full clean rebuild (K3s uninstalled and redeployed) completes with all nodes `Ready` and all services operational within 20 minutes.
- **SC-004**: Re-running the deploy playbook against an already-healthy cluster produces zero changed tasks (fully idempotent).

## Assumptions

- The current cluster runs a single server node (node1); the initial migration will preserve this single-server topology and lay the groundwork for future HA expansion.
- A clean rebuild is the supported migration path from SQLite to etcd — no in-place datastore migration is attempted.
- An odd number of server nodes (1 or 3) will be maintained to preserve etcd quorum; the operator is responsible for ensuring this in `hosts.ini`.
- K3s version in use supports embedded etcd (requirement: v1.19+ — already satisfied by the current install).
- Longhorn, ArgoCD, and Gitea persistent data will be lost on a clean rebuild; the operator is responsible for any required backups before migrating the live cluster.
- The `k3s_flannel_iface` variable and other existing group vars remain compatible with the etcd-backed install and require no changes.
