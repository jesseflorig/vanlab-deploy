# Feature Specification: Rack Shutdown Script

**Feature Branch**: `040-rack-shutdown-script`  
**Created**: 2026-04-16  
**Status**: Draft  
**Input**: User description: "Create a utility script to safely shut down the vanlab rack: cluster, edge, and opnsense"

## Clarifications

### Session 2026-04-16

- Q: What is the edge host? → A: Ubuntu Bookworm server at 10.1.10.10 running cloudflared; reachable via SSH.
- Q: What form should the shutdown script take? → A: Ansible playbook (consistent with project conventions). Planning should research Ansible patterns for handling SSH session loss when a remote host shuts down the network gateway (OPNsense-last problem).
- Q: How does OPNsense accept the shutdown command? → A: SSH (`shutdown -h now` or `halt`).
- Q: Where does `kubectl drain` run? → A: Operator's workstation; kubectl is configured locally and Ansible delegates drain tasks there.
- Q: Should the playbook perform a pre-flight check? → A: Warn and proceed — report unhealthy state (unreachable nodes, degraded Longhorn volumes) at the start but continue unless the operator manually intervenes.
- Q: What is the operator-facing entry point? → A: `make shutdown` (Makefile target wrapping `ansible-playbook shutdown.yml`); direct ansible-playbook invocation remains available for flags like `--check` and `--verbose`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Graceful Full Rack Shutdown (Priority: P1)

An operator preparing for planned maintenance runs the shutdown script from their workstation. The script drains and shuts down the Kubernetes cluster, then the edge host, and finally OPNsense — in the correct dependency order — so that all workloads terminate cleanly and no storage or network state is corrupted.

**Why this priority**: This is the core use case. Without a sequenced, graceful shutdown, cluster workloads may be interrupted mid-write, Longhorn volumes may not flush, and nodes may lose connectivity before they finish shutting down.

**Independent Test**: Can be tested by running the script against the live rack and confirming all nodes reach a stopped state in order, with Longhorn reporting no degraded volumes afterward.

**Acceptance Scenarios**:

1. **Given** the cluster is healthy and all nodes are online, **When** the operator runs the shutdown script, **Then** the script drains Kubernetes workloads, shuts down worker nodes, then control-plane nodes, then the edge host, then OPNsense — in that order — and exits with a success status.
2. **Given** one cluster node is already offline, **When** the operator runs the shutdown script, **Then** the script logs a warning for the unavailable node, skips it, and continues with the remaining shutdown sequence without failing.
3. **Given** a workload drain times out on a node, **When** the timeout is reached, **Then** the script reports the failure, halts, and does not proceed to shut down networking components — leaving the rack in a state where the operator can intervene.

---

### User Story 2 - Dry-Run Preview (Priority: P2)

An operator wants to confirm exactly what the script will do before committing to a shutdown. They run the script in dry-run mode and see a sequenced list of every action that would be taken — without anything being executed.

**Why this priority**: Rack shutdowns are irreversible in the moment; a preview step reduces the risk of unintended consequences and builds operator confidence.

**Independent Test**: Can be tested by running with the dry-run flag and verifying that no SSH connections are made and all cluster/node states remain unchanged.

**Acceptance Scenarios**:

1. **Given** dry-run mode is enabled, **When** the operator runs the script, **Then** it outputs each planned action in order (e.g., "Would drain node X", "Would shut down OPNsense") without executing any of them.
2. **Given** dry-run mode is enabled, **When** the operator reviews the output, **Then** the sequence matches the documented shutdown order (workers → control plane → edge host → OPNsense).

---

### User Story 3 - Progress Feedback During Shutdown (Priority: P3)

As the shutdown progresses, the operator sees real-time status for each step — which component is being acted on, whether it succeeded, and what comes next — so they know the script is making forward progress and can identify where it stopped if something goes wrong.

**Why this priority**: A silent script that takes several minutes gives no signal that it's working; progress output lets the operator know when to walk away vs. when to intervene.

**Independent Test**: Can be tested by running the script and confirming each step prints a status line (start, success/failure) before moving to the next.

**Acceptance Scenarios**:

1. **Given** the script is running, **When** a step begins, **Then** the operator sees a message indicating which component is being acted on and what action is in progress.
2. **Given** a step completes successfully, **When** control moves to the next step, **Then** the previous step is marked as complete in the output.
3. **Given** a step fails, **When** the script halts, **Then** the failed step and the reason are clearly identified in the output.

---

### Edge Cases

- What happens if the script is run when the cluster is already partially shut down (some nodes already offline)?
- What happens if OPNsense becomes unreachable before the cluster finishes shutting down?
- If a Longhorn volume is degraded before shutdown begins, the playbook warns the operator and continues — it does not abort.
- What happens if the operator interrupts the script mid-run (Ctrl+C)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The script MUST shut down components in dependency order: Kubernetes workers → Kubernetes control-plane nodes → edge host → OPNsense.
- **FR-002**: The script MUST drain Kubernetes node workloads gracefully before issuing a node shutdown, waiting for pods to terminate before proceeding.
- **FR-003**: The playbook MUST support a dry-run mode (via `ansible-playbook --check` or `make shutdown-dry-run`) that prints all planned actions without executing any of them.
- **FR-004**: The script MUST print a status line for each step (starting, succeeded, failed) so the operator can track progress in real time.
- **FR-005**: The script MUST halt and report an error if a critical step fails (e.g., drain timeout, node unreachable mid-sequence), rather than continuing and leaving the rack in an inconsistent state.
- **FR-006**: The script MUST warn the operator (but not halt) when a node is already offline at the start of the run, skip that node, and continue.
- **FR-007**: The script MUST be runnable from the operator's workstation without requiring manual SSH steps — all remote actions are automated.
- **FR-008**: The script MUST use existing SSH/Ansible credentials already configured in the project; no new credential setup is required.
- **FR-009**: The playbook MUST handle the loss of SSH connectivity when OPNsense is shut down as the final step — the OPNsense shutdown task must not cause the overall playbook to report a false failure.

### Key Entities

- **Worker Node**: A Kubernetes worker node running application workloads; must be drained before shutdown.
- **Control-Plane Node**: A Kubernetes control-plane node; shut down after all workers are stopped.
- **Edge Host**: An Ubuntu Bookworm server at 10.1.10.10 running the cloudflared tunnel daemon; shut down after the cluster is fully stopped.
- **OPNsense**: The network gateway and firewall; shut down last since all other components depend on it for connectivity.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A full rack shutdown completes without manual operator intervention on the happy path (all nodes online, healthy cluster).
- **SC-002**: No Longhorn volumes are left in a degraded or error state after a successful shutdown run.
- **SC-003**: The shutdown sequence from script invocation to OPNsense halt completes in under 10 minutes for a healthy rack.
- **SC-004**: Dry-run output fully matches the sequence of actions taken in a real run when compared side-by-side.
- **SC-005**: An operator unfamiliar with the internals can identify which step failed and why from script output alone, without reading source code.

## Assumptions

- The operator runs the script from their admin workstation, which has network access to all rack components at the time the script is invoked.
- SSH and Ansible credentials for cluster nodes are already configured, consistent with existing project conventions. kubectl is configured on the operator's workstation and used for drain commands (delegated locally by the playbook).
- OPNsense is shut down via SSH (`shutdown -h now`), consistent with how all other hosts are managed.
- The edge host (Ubuntu Bookworm, 10.1.10.10, running cloudflared) is reachable via SSH from the operator's workstation and supports standard Linux shutdown commands; cloudflared must be stopped before the host is halted.
- The playbook performs a pre-flight check (node reachability, Longhorn volume health) and reports any issues before starting the shutdown sequence. It warns but does not abort — the operator can interrupt manually if the warnings are severe enough.
- The playbook is a utility for intentional, operator-initiated shutdowns only — not intended for automated or unattended use.
- The shutdown is implemented as an Ansible playbook invoked via `make shutdown`; direct `ansible-playbook` invocation is also supported for flags like `--check` and `--verbose`.
- The OPNsense shutdown will terminate the operator's network path; the playbook must treat loss of SSH connectivity on the final step as an expected success condition, not a failure. Planning should evaluate the best Ansible pattern for this (async fire-and-forget, `ignore_errors`, or equivalent).
