# Feature Specification: Project Reorganization

**Feature Branch**: `002-project-reorganization`
**Created**: 2026-03-29
**Status**: Draft
**Input**: User description: "Reorganize the Ansible project structure to support managing
multiple device categories beyond the K3s cluster"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Operate the Full Infrastructure from a Single Inventory (Priority: P1)

An operator can run any playbook against any device category — cluster nodes, the OPNsense
router, or the CM5 edge device — using a single inventory file and clearly named host groups.
The inventory reflects the actual network topology, with unmanaged hardware documented as
comments for reference.

**Why this priority**: The inventory is the foundation everything else depends on. Until it
is correct, no other reorganization work can be validated.

**Independent Test**: Run `ansible-playbook -i hosts.ini check_hosts.yml` and verify all
managed devices (cluster servers, agents, router, edge device) respond. Confirm unmanaged
switches appear only as comments.

**Acceptance Scenarios**:

1. **Given** the reorganized inventory, **When** an operator targets `--limit servers`, **Then**
   only K3s server nodes respond.
2. **Given** the reorganized inventory, **When** an operator targets `--limit network`, **Then**
   only the OPNsense router responds.
3. **Given** the reorganized inventory, **When** an operator targets `--limit compute`, **Then**
   only the CM5 edge device responds.
4. **Given** the reorganized inventory, **When** an operator reviews `hosts.ini`, **Then** all
   four unmanaged switches are visible as topology comments, not active hosts.

---

### User Story 2 - Deploy and Configure the Edge Device Independently (Priority: P2)

An operator can provision the CM5 edge device — installing and configuring Cloudflared as a
standalone tunnel — using a dedicated playbook without touching the K3s cluster. The tunnel
remains operational independently of cluster health.

**Why this priority**: The primary motivation for adding the edge device is tunnel resilience.
This story delivers that value as a self-contained increment.

**Independent Test**: Run the edge playbook against the CM5 alone; verify Cloudflared is
running and the tunnel is established without the K3s cluster being involved.

**Acceptance Scenarios**:

1. **Given** the CM5 is reachable on `10.1.10.x`, **When** the edge playbook runs, **Then**
   Cloudflared is installed and active on the edge device.
2. **Given** the K3s cluster is fully stopped, **When** the Cloudflared tunnel is checked,
   **Then** the tunnel remains active on the edge device.
3. **Given** the edge playbook has run once, **When** it runs again, **Then** no changes are
   made (idempotent).

---

### User Story 3 - Manage the OPNsense Router via Automation (Priority: P3)

An operator can apply OPNsense configuration — firewall rules, VLAN definitions — through
a dedicated network playbook. The router's current state can be verified without applying
changes.

**Why this priority**: Completes the managed device surface. Builds the foundation for
enforcing Principles VI and VII (encryption in transit, least privilege) from the
constitution as code.

**Independent Test**: Run the network playbook in check mode against OPNsense; verify it
connects via the REST API and reports current state without modifying anything.

**Acceptance Scenarios**:

1. **Given** the OPNsense API is enabled, **When** the network playbook runs in check mode,
   **Then** it connects successfully and returns current firewall rule state.
2. **Given** the network playbook has run, **When** it runs again, **Then** no changes are
   made if the router is already in the desired state (idempotent).

---

### User Story 4 - Find and Run Any Playbook Without Guessing Its Location (Priority: P4)

An operator can navigate to the correct playbook for any device category without searching.
Playbooks are organized in a `playbooks/` directory by category, and the README documents
where each playbook lives and what it does.

**Why this priority**: Quality-of-life improvement that pays off on every future operation.
Depends on the prior stories establishing the device categories.

**Independent Test**: A new operator, given only the README, can locate and run the
correct playbook for any device category on their first attempt.

**Acceptance Scenarios**:

1. **Given** the reorganized `playbooks/` directory, **When** an operator needs to deploy
   cluster services, **Then** the correct playbook is findable under `playbooks/cluster/`.
2. **Given** the README, **When** an operator looks up how to run the edge device playbook,
   **Then** the exact command is documented.

---

### Edge Cases

- What happens to existing playbook paths if they are referenced in documentation or scripts?
- How are group variables inherited when a device belongs to multiple groups (e.g., `all` and
  `cluster`)?
- What if the OPNsense API is unreachable during a run that also targets cluster nodes?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The inventory MUST define host groups: `servers`, `agents`, `cluster` (parent
  of servers + agents), `network`, and `compute`.
- **FR-002**: Unmanaged switches (GS308T, GS308EPP ×3) MUST be documented as comments in
  `hosts.ini` with their IPs and roles — not as active inventory hosts.
- **FR-003**: Group variables MUST be split by device category into separate files:
  `group_vars/cluster.yml`, `group_vars/network.yml`, `group_vars/compute.yml`, with shared
  variables remaining in `group_vars/all.yml`.
- **FR-004**: Playbooks MUST be moved into a `playbooks/` directory organized by category:
  `playbooks/cluster/`, `playbooks/network/`, `playbooks/compute/`, `playbooks/utilities/`.
- **FR-005**: A dedicated edge playbook MUST apply the Cloudflared role to the `compute`
  group only, with no dependency on the cluster group.
- **FR-006**: A dedicated network playbook MUST scaffold OPNsense management targeting the
  `network` group via the REST API.
- **FR-007**: The existing cluster playbooks (`k3s-deploy.yml`, `services-deploy.yml`) MUST
  continue to function after being moved, with all internal references updated.
- **FR-008**: The `check_hosts.yml` and `disk-health.yml` utility playbooks MUST be updated
  to work with the new inventory group names (`servers`/`agents` replacing `masters`/`workers`).
- **FR-009**: The `README.md` MUST be updated to reflect the new directory structure and
  document the command for each playbook category.
- **FR-010**: The Cloudflared role MUST be removed from cluster service deployment and
  confirmed as running exclusively on the edge device.

### Key Entities

- **Inventory**: The `hosts.ini` file defining all managed and documented-unmanaged devices,
  their addresses, and group memberships.
- **Host Group**: A named collection of devices in the inventory sharing a common role
  (`servers`, `agents`, `cluster`, `network`, `compute`).
- **Group Vars**: Per-category variable files supplying device-specific configuration to
  playbooks without hardcoding values.
- **Playbook**: An automation script targeting one or more host groups; organized under
  `playbooks/<category>/` after reorganization.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All managed devices (4 cluster nodes, 1 router, 1 edge device) are reachable
  and correctly grouped in a single `check_hosts` run with zero failures.
- **SC-002**: The Cloudflared tunnel operates on the edge device independently of cluster
  state — verified by stopping the cluster and confirming the tunnel remains active.
- **SC-003**: Every playbook in the reorganized `playbooks/` directory runs to completion
  without path or inventory errors.
- **SC-004**: An operator can locate the playbook for any device category in under 30 seconds
  using only the README.
- **SC-005**: Zero references to `masters` or `workers` group names remain anywhere in the
  repository after reorganization.

## Assumptions

- The CM5 edge device is already provisioned with Raspberry Pi OS and is reachable via SSH
  on `10.1.10.x` before the edge playbook runs.
- The OPNsense `os-api` plugin is enabled and an API key is available; the key will be
  stored in `group_vars/all.yml` (gitignored) following the existing secrets pattern.
- The Cloudflared tunnel token is already available in `group_vars/all.yml`.
- The OPNsense network playbook scaffolds the role and verifies connectivity in this
  feature; full VLAN and firewall rule automation is out of scope and will be a follow-on
  feature.
- Existing `group_vars/example.all.yml` will be updated to template the new per-category
  variable files and OPNsense API key.
- All four cluster nodes use the same SSH credentials already defined in `hosts.ini`.
