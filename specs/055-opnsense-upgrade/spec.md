# Feature Specification: OPNsense Upgrade from 23.7 to 26.1

**Feature Branch**: `055-opnsense-upgrade`
**Created**: 2026-04-27
**Status**: Draft
**Input**: User description: "Upgrade OPNsense from 23.7 to 26.1 (current stable). Primary motivation is security (23.7 is EOL) and unlocking the Destination NAT REST API needed for fleet1.lan port forwarding automation. Network downtime expected during upgrade."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Router Upgraded with All Services Restored (Priority: P1)

The homelab operator upgrades OPNsense from 23.7 to 26.1. After the upgrade completes, all cluster nodes, edge devices, and LAN clients have full connectivity — DNS, routing, DHCP, firewall rules, and VLANs all function identically to before. The upgrade window is planned and communicated; downtime is under 30 minutes.

**Why this priority**: The router is the single point of failure for all network connectivity. A failed or misconfigured upgrade takes down every service in the lab. Getting back to a known-good state is the primary success condition.

**Independent Test**: Can be fully tested by confirming: (1) all cluster nodes are reachable via SSH from the management laptop after upgrade; (2) `kubectl get nodes` shows all nodes Ready; (3) all existing services respond on their `fleet1.cloud` hostnames; (4) DHCP is handing out addresses on all VLANs.

**Acceptance Scenarios**:

1. **Given** OPNsense 23.7 is running, **When** the operator completes the upgrade procedure, **Then** OPNsense reports version 26.1.x on the dashboard within 30 minutes of starting
2. **Given** the upgrade completes, **When** cluster nodes attempt to communicate across VLANs, **Then** all existing firewall rules are in effect and traffic flows as before
3. **Given** the upgrade completes, **When** a LAN client requests a DHCP lease on any VLAN, **Then** a lease is issued from the correct pool
4. **Given** the upgrade completes, **When** a LAN client resolves `grafana.fleet1.cloud`, **Then** DNS responds correctly (via Cloudflare or local Unbound overrides)
5. **Given** something goes wrong mid-upgrade, **When** the operator invokes the rollback procedure, **Then** OPNsense is restored to a working 23.7 state within 60 minutes

---

### User Story 2 - Destination NAT API Available and Verified (Priority: P2)

After the upgrade, the operator confirms that the new Destination NAT REST API is accessible and accepts rule creation requests. This unblocks the automated port-forwarding task (T010) in the fleet1.lan feature.

**Why this priority**: This is the secondary motivation for the upgrade. The Destination NAT API only exists in 26.1+; confirming it works closes the loop on the fleet1.lan blocker.

**Independent Test**: Can be fully tested by issuing a test API call to the Destination NAT endpoint and receiving a valid response (not a 400 "controller not found" error).

**Acceptance Scenarios**:

1. **Given** OPNsense 26.1 is running, **When** the operator queries the Destination NAT search endpoint, **Then** the response contains a valid rule list (not a 400 error)
2. **Given** the API is available, **When** a test NAT rule is created and deleted via the API, **Then** both operations return success responses

---

### User Story 3 - Upgrade Documented and Repeatable (Priority: P3)

The upgrade procedure — including pre-checks, the upgrade steps, post-upgrade verification, and rollback — is documented in a way that a future operator could repeat it or recover from a failure without prior context.

**Why this priority**: Homelab infrastructure is maintained by one person. If the upgrade causes an outage that persists past the session, documented recovery steps are essential.

**Independent Test**: Can be fully tested by reviewing the procedure documentation and confirming it covers all failure modes identified during the upgrade.

**Acceptance Scenarios**:

1. **Given** the upgrade is complete, **When** the operator reviews the documentation, **Then** the pre-upgrade backup step, upgrade commands, verification steps, and rollback procedure are all present and unambiguous
2. **Given** a future operator encounters a failed upgrade, **When** they follow the rollback procedure, **Then** they can restore OPNsense to a working state without additional research

---

### Edge Cases

- What if the upgrade process stalls mid-way (e.g., package download fails)? OPNsense upgrade can be retried from the web UI; partial upgrades are handled by the package manager
- What if a firewall rule breaks after upgrade due to syntax changes between 23.7 and 26.1? Pre-upgrade config export provides rollback; post-upgrade verification catches this before declaring success
- What if the Destination NAT API exists but requires a privilege that the existing API user doesn't have? The API user may need updated permissions in OPNsense
- What if NAT port-forward rules created in 23.7 (via web UI) are not migrated to the new "Destination NAT" format? OPNsense 26.1 release notes confirm automatic migration of existing rules
- What if the upgrade requires an intermediate version hop (23.7 → 24.x → 26.1)? OPNsense supports sequential upgrades; the upgrade path must be verified before starting

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The upgrade MUST bring OPNsense to version 26.1.x (latest patch in the 26.1 series)
- **FR-002**: A full configuration backup MUST be exported and stored before any upgrade step begins
- **FR-003**: All existing firewall filter rules MUST remain in effect after the upgrade — no rules may be silently dropped or modified
- **FR-004**: All existing Unbound DNS overrides (including the `mqtt.fleet1.cloud` entries and the `*.fleet1.lan` entry added in feature 054) MUST be preserved
- **FR-005**: DHCP server configuration for all VLANs MUST be preserved and functional after upgrade
- **FR-006**: VPN (WireGuard) configuration MUST be preserved and functional after upgrade
- **FR-007**: The Destination NAT REST API (`/api/firewall/dnat/`) MUST be accessible to the existing API user after upgrade
- **FR-008**: The upgrade procedure MUST include a pre-upgrade verification checklist and a post-upgrade verification checklist
- **FR-009**: A tested rollback procedure MUST be documented before the upgrade begins
- **FR-010**: The existing API user credentials MUST continue to work for the firewall filter and Unbound APIs after upgrade

### Key Entities

- **OPNsense Configuration Backup**: Full XML export of the router configuration; stored locally and offsite before upgrade begins
- **API User**: The OPNsense user account (`opnsense_api_key`/`opnsense_api_secret`) used by Ansible — must retain all necessary privileges post-upgrade
- **Upgrade Path**: The sequence of intermediate versions required to reach 26.1 from 23.7 — must be established before starting

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: OPNsense dashboard reports version 26.1.x within 30 minutes of starting the upgrade procedure
- **SC-002**: All cluster nodes show Ready status within 5 minutes of the router coming back online
- **SC-003**: All existing `fleet1.cloud` services respond within 5 minutes of router restoration
- **SC-004**: The Destination NAT API returns a valid response (not a 400 error) within 2 minutes of the operator testing it
- **SC-005**: Zero existing firewall rules are lost — rule count post-upgrade equals rule count pre-upgrade
- **SC-006**: Rollback procedure, if needed, restores a working router within 60 minutes

## Assumptions

- The upgrade is performed via the OPNsense web UI upgrade mechanism (not a fresh install), preserving existing configuration
- OPNsense supports a direct upgrade path from 23.7 to 26.1, either directly or via one intermediate version — the exact path must be confirmed during planning
- The management laptop retains SSH access to the OPNsense console during the upgrade (as a fallback if the web UI becomes unavailable)
- WireGuard VPN is in scope for post-upgrade verification since it provides remote access as a fallback
- The upgrade is scheduled during a low-activity window; brief network outage (expected under 30 minutes) is acceptable
- The existing OPNsense API user has sufficient privileges; if new permissions are needed for the Destination NAT API, granting them is in scope
- A fresh install is explicitly out of scope — configuration must be preserved via the in-place upgrade path
