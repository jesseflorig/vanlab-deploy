# Feature Specification: Wireguard VPN for management laptop access to fleet1.lan

**Feature Branch**: `058-wireguard-management-vpn`  
**Created**: 2026-04-28  
**Status**: Draft  
**Input**: User description: "Add Wireguard and provision my management laptop to connect to fleet1.lan from anywhere"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Secure Remote Access (Priority: P1)

As a network administrator, I want to connect my management laptop to the `fleet1.lan` network from an external internet connection so that I can manage the lab as if I were on the local network.

**Why this priority**: This is the core requirement. Without secure remote access, the feature provides no value.

**Independent Test**: Connect the management laptop to a non-local network (e.g., a mobile hotspot), activate the Wireguard tunnel, and successfully ping `10.1.1.1` (OPNsense) and resolve `opnsense.fleet1.lan`.

**Acceptance Scenarios**:

1. **Given** the management laptop is on an external network and the Wireguard client is configured, **When** the Wireguard tunnel is activated, **Then** the laptop receives an IP address in the VPN subnet and can reach `10.1.1.1`.
2. **Given** the Wireguard tunnel is active, **When** the user attempts to access `https://opnsense.fleet1.lan`, **Then** the page loads successfully using the lab's internal DNS.

---

### User Story 2 - Full LAN Resource Access (Priority: P2)

As a network administrator, I want to access all cluster resources (K3s, Gitea, ArgoCD) while connected via VPN so that I can perform maintenance tasks remotely.

**Why this priority**: Remote management is incomplete if only the router is accessible. This allows full operational capability.

**Independent Test**: While connected via VPN, successfully access `https://gitea.fleet1.lan` and `https://argocd.fleet1.lan`.

**Acceptance Scenarios**:

1. **Given** the Wireguard tunnel is active, **When** the user accesses internal service hostnames, **Then** Traefik routes the requests correctly to the backend services.

---

### User Story 3 - Automated Provisioning (Priority: P3)

As a network administrator, I want the VPN configuration to be managed via Ansible so that the setup is idempotent and documented as code.

**Why this priority**: Ensures maintainability and consistency with the rest of the project's infrastructure-as-code approach.

**Independent Test**: Run the network playbook; it should report "ok" or "changed" correctly without manual intervention on the router.

**Acceptance Scenarios**:

1. **Given** OPNsense is running, **When** the network-deploy playbook is executed, **Then** the Wireguard server, local peer, and firewall rules are provisioned correctly.

---

### Edge Cases

- **IP Address Conflict**: What happens if the VPN client's local network (e.g., at a cafe) uses the same subnet as the `fleet1.lan` management or cluster networks?
- **WAN IP Change**: How does the system handle a change in the OPNsense router's public WAN IP if dynamic DNS is not updated or used?
- **Key Rotation**: How are rotated keys distributed to the management laptop securely?
- **MTU Issues**: How does the system handle packet fragmentation if the underlying WAN connection has a lower MTU than the Wireguard default?

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: OPNsense MUST act as the Wireguard VPN server.
- **FR-002**: The system MUST allocate a dedicated subnet for VPN clients (e.g., `10.1.254.0/24`) that does not conflict with existing VLANs.
- **FR-003**: OPNsense MUST have a firewall rule to allow incoming Wireguard traffic (UDP) from the WAN interface.
- **FR-004**: OPNsense MUST have firewall rules to allow traffic from the Wireguard interface to the internal management and cluster networks.
- **FR-005**: The management laptop MUST be configured as a Wireguard peer with a static internal VPN IP.
- **FR-006**: The VPN tunnel MUST provide DNS resolution via the OPNsense Unbound resolver for the `fleet1.lan` domain.
- **FR-007**: The system MUST generate or provide a client configuration file for the management laptop.

### Key Entities

- **Wireguard Server**: The OPNsense instance hosting the VPN endpoint.
- **VPN Peer**: The management laptop authorized to connect to the server.
- **VPN Subnet**: The private IP space used for tunnel traffic.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Handshake established between the management laptop and OPNsense in under 5 seconds.
- **SC-002**: 100% of internal `fleet1.lan` hostnames resolve correctly over the VPN tunnel.
- **SC-003**: Average latency to `10.1.1.1` over the VPN is within 20% of the base network latency (plus encryption overhead).
- **SC-004**: Ansible playbook can provision the entire VPN stack idempotently.

## Assumptions

- The OPNsense router has a publicly reachable IP address or a functional dynamic DNS hostname.
- The `os-wireguard` plugin is installed or can be installed via the API on OPNsense.
- The management laptop has the Wireguard client software already installed.
- Public/Private keys for the laptop will be provided or generated during implementation.
- WAN traffic to the Wireguard port is not blocked by an upstream ISP router.
