# Feature Specification: Node Disk Health Check

**Feature Branch**: `001-node-disk-health`
**Created**: 2026-03-27
**Status**: Draft
**Input**: User description: "Add ansible playbook that checks node hard drives are present and report capacity and health"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run Disk Health Check Across All Nodes (Priority: P1)

An operator runs a single command against the cluster inventory and receives a consolidated
report showing, for every node: which drives were found, their total and available capacity,
and their health status. The report makes it immediately obvious if any node is missing a
drive or has a degraded or failing drive.

**Why this priority**: This is the core value of the feature. Without it nothing else matters.

**Independent Test**: Run the playbook against the cluster; verify output lists every node
in `hosts.ini` and reports at least one drive per node with capacity figures and a health
status.

**Acceptance Scenarios**:

1. **Given** all nodes are reachable and drives are healthy, **When** the playbook runs,
   **Then** each node reports all expected drives with capacity (total/used/free) and a
   HEALTHY status.
2. **Given** a node has a degraded or failing drive, **When** the playbook runs, **Then**
   that drive is flagged with a WARNING or CRITICAL status and the node is visually
   distinguished in the report.
3. **Given** a node is unreachable, **When** the playbook runs, **Then** the playbook
   reports that node as UNREACHABLE without aborting the entire run.

---

### User Story 2 - Detect Missing Drives (Priority: P2)

The operator is alerted when a node has fewer drives detected than expected, indicating a
drive has been removed, failed to mount, or is not recognized by the OS.

**Why this priority**: Silent drive absence is a data-loss risk. Detection must be explicit.

**Independent Test**: Remove or mask a drive from a test node; verify the playbook flags the
node as having fewer drives than expected.

**Acceptance Scenarios**:

1. **Given** a node is expected to have at least one NVMe drive and none are detected,
   **When** the playbook runs, **Then** the playbook reports MISSING drive(s) for that node.
2. **Given** any drive is CRITICAL or any expected drive is missing, **When** the playbook
   completes, **Then** it exits with a non-zero status code.

---

### Edge Cases

- What happens when a node is powered off or SSH is unavailable?
- What if drive health assessment tools are not installed on a node?
- What if a node has no NVMe drive but is a valid cluster member (e.g., a future
  compute-only node with no local storage)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The playbook MUST run against all nodes defined in the cluster inventory.
- **FR-002**: The playbook MUST detect and list all block storage devices on each node.
- **FR-003**: For each detected drive, the playbook MUST report total capacity, used space,
  and free space.
- **FR-004**: For each detected drive, the playbook MUST report a health status:
  HEALTHY, WARNING, CRITICAL, or UNKNOWN.
- **FR-005**: The playbook MUST produce a human-readable summary report grouped by node at
  the end of the run.
- **FR-006**: The playbook MUST NOT abort the entire run if one or more nodes are
  unreachable; unreachable nodes MUST be reported in the summary.
- **FR-007**: If no drives are detected on a node where at least one is expected, the
  playbook MUST flag that node as having missing drives.
- **FR-008**: The playbook MUST exit with a non-zero status code when any drive is CRITICAL
  or any expected drive is missing.
- **FR-009**: The playbook MUST be idempotent — repeated runs MUST NOT modify node state.

### Key Entities

- **Node**: A cluster member (master or worker) identified by hostname/IP in the inventory.
- **Drive**: A block storage device attached to a node; characterized by device identifier,
  capacity (total/used/free), and health status.
- **Health Status**: A categorical assessment — HEALTHY / WARNING / CRITICAL / UNKNOWN.
- **Run Report**: The consolidated human-readable output produced at the end of execution,
  listing all nodes and their drive findings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A single command produces a complete disk health report for all reachable
  cluster nodes in under 2 minutes for a 6-node cluster.
- **SC-002**: 100% of drives attached to reachable nodes appear in the report — no drives
  are silently omitted.
- **SC-003**: An operator with no prior context can determine the overall health of all
  cluster drives by reading the report summary alone, without parsing raw logs.
- **SC-004**: A node with a missing or failing drive is identifiable within the report
  without referencing any other file or output.
- **SC-005**: The playbook exit code reliably reflects cluster drive health, enabling use
  in automated monitoring or alerting pipelines.

## Assumptions

- Each node is expected to have at least one NVMe M.2 drive (current hardware: 2TB M.2
  NVMe per Pi5 node).
- Nodes run a Debian-based OS (Raspberry Pi OS arm64); standard disk inspection tools are
  available or can be installed by the playbook as a prerequisite step.
- Drive health assessment uses S.M.A.R.T. data where the drive supports it; drives that do
  not support S.M.A.R.T. report UNKNOWN health status rather than failing.
- The playbook targets all nodes in `hosts.ini` (masters and workers) unless scoped at
  invocation time with `--limit`.
- No persistent storage of historical run data is in scope for v1; each run is independent.
- Report output is written to stdout only; file-based or structured (JSON/CSV) output is
  out of scope for v1.
