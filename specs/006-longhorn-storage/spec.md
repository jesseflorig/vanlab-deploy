# Feature Specification: Longhorn Distributed Block Storage

**Feature Branch**: `006-longhorn-storage`
**Created**: 2026-03-31
**Status**: Draft
**Input**: User description: "Deploy Longhorn distributed block storage on the vanlab Kubernetes cluster so that applications can provision PersistentVolumeClaims backed by replicated storage across cluster nodes. Longhorn should be installed, healthy, and set as the default StorageClass."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Longhorn Installed and Healthy (Priority: P1)

The operator deploys Longhorn on the cluster. All Longhorn components are running and healthy across every node. The Longhorn dashboard is accessible and shows the cluster storage topology.

**Why this priority**: Longhorn must be fully operational before any application can provision persistent volumes. This is the prerequisite for all storage use cases.

**Independent Test**: The Longhorn dashboard is reachable and shows all nodes as schedulable with available storage capacity. No components report errors.

**Acceptance Scenarios**:

1. **Given** Longhorn is deployed, **When** the operator checks the Longhorn dashboard, **Then** all cluster nodes appear as storage nodes with healthy status and available capacity.
2. **Given** Longhorn is running, **When** the operator inspects storage components, **Then** all manager, driver, and UI components are in a running state with no restarts.
3. **Given** Longhorn is installed, **When** the operator lists storage classes, **Then** a Longhorn storage class is present and marked as the cluster default.

---

### User Story 2 - Applications Can Provision PVCs (Priority: P2)

A workload on the cluster requests persistent storage via a PersistentVolumeClaim. Longhorn automatically provisions a replicated volume, binds it to the workload, and the workload can read and write data that persists across pod restarts.

**Why this priority**: This is the primary deliverable — applications need to be able to actually use the storage. Depends on US1.

**Independent Test**: Deploy a test pod with a PVC, write a file, delete and recreate the pod, and confirm the file persists.

**Acceptance Scenarios**:

1. **Given** a PVC is created with no explicit storage class, **When** Longhorn is the default storage class, **Then** the PVC is automatically bound and a replicated volume is provisioned.
2. **Given** a pod is bound to a Longhorn volume with data written to it, **When** the pod is deleted and recreated on any node, **Then** the previously written data is accessible.
3. **Given** a PVC is deleted, **When** the reclaim policy is applied, **Then** the underlying volume is cleaned up according to policy without orphaned storage.

---

### Edge Cases

- What happens if a node goes offline while hosting a Longhorn replica? Longhorn re-replicates to remaining healthy nodes to maintain the configured replica count.
- What happens if disk space runs out on a node? Longhorn marks that node as unschedulable for new volumes and existing volumes degrade gracefully.
- What happens if Longhorn is installed on nodes with insufficient disk space? Installation succeeds but no volumes can be scheduled; the dashboard reports the capacity constraint.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Longhorn MUST be deployed across all cluster nodes and all components MUST be healthy after installation.
- **FR-002**: Longhorn MUST be configured as the default storage class so PVCs with no explicit class are automatically provisioned by Longhorn.
- **FR-003**: Volumes MUST be replicated across multiple nodes to survive a single node failure.
- **FR-004**: The Longhorn management dashboard MUST be accessible to the operator.
- **FR-005**: Longhorn installation MUST be reproducible and idempotent via the existing Ansible playbook workflow.
- **FR-006**: Existing cluster services MUST continue to function without interruption during and after Longhorn installation.
- **FR-007**: Node prerequisites (required system packages) MUST be installed automatically as part of the provisioning workflow.

### Key Entities

- **StorageClass**: Cluster-wide default storage class backed by Longhorn. Used when PVCs omit an explicit class.
- **Volume**: A Longhorn-managed block device replicated across nodes. Bound to a PVC and mounted by a pod.
- **Replica**: One copy of a volume's data on a specific node's disk. Longhorn maintains the configured replica count for durability.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All cluster nodes appear as healthy storage nodes in the Longhorn dashboard immediately after installation.
- **SC-002**: A PVC is provisioned and bound within 60 seconds of being created with no explicit storage class.
- **SC-003**: Data written to a Longhorn-backed volume persists and is accessible after the workload pod is rescheduled to a different node.
- **SC-004**: Re-running the Ansible provisioning playbook after initial installation results in zero changes (idempotent).

## Assumptions

- All cluster nodes have sufficient local disk space to participate as Longhorn storage nodes (minimum 10 GB free per node assumed).
- The Longhorn dashboard will be accessible within the cluster network; external HTTPS exposure via Cloudflare tunnel is out of scope for this feature.
- The default replica count will be 2 (replication across 2 nodes) given the cluster size; this can be adjusted post-install.
- Node prerequisite packages (open-iscsi, nfs-common) will be installed by Ansible as part of this feature.
- Longhorn will be installed via Helm using the official Longhorn chart.
