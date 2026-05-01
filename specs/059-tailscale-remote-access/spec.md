# Feature Specification: Tailscale Remote Access for fleet1.lan

**Feature Branch**: `059-tailscale-remote-access`  
**Created**: 2026-04-30  
**Status**: Implemented  
**Input**: User description: "Integrate tailscale for remote access"

## Background

WireGuard (spec 058) was removed because the OPNsense WAN sits behind CGNAT, making inbound UDP unreachable from the internet. Tailscale solves this by establishing outbound connections and relaying through its coordination network when direct NAT traversal is possible, requiring no port-forwards or public IP.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remote Access to fleet1.lan Services (Priority: P1)

As a lab administrator working from an external network (home, coffee shop, mobile hotspot), I want to reach internal services like Gitea, ArgoCD, and Grafana via their `fleet1.lan` hostnames so that I can manage the cluster without being physically present.

**Why this priority**: This is the core use case. Without it the feature delivers no value. It was previously undeliverable via WireGuard due to CGNAT.

**Independent Test**: Connect the management laptop to a mobile hotspot, activate Tailscale, and successfully open `https://gitea.fleet1.lan` in a browser.

**Acceptance Scenarios**:

1. **Given** the management laptop is on an external network with Tailscale connected, **When** the user navigates to `https://gitea.fleet1.lan`, **Then** the page loads using the lab's internal DNS and TLS certificate.
2. **Given** the management laptop is on an external network with Tailscale connected, **When** the user runs `kubectl get nodes`, **Then** the cluster API responds and all nodes are visible.
3. **Given** the management laptop is on an external network, **When** Tailscale is not active, **Then** no `fleet1.lan` resources are reachable.

---

### User Story 2 - SSH Access to All Lab Nodes (Priority: P2)

As a lab administrator, I want to SSH into any node (`node1`–`node6`, `nvr-host`, `edge`) from outside the lab using their LAN IP addresses via the Tailscale-routed subnet so that I can run Ansible playbooks and perform direct maintenance remotely.

**Why this priority**: Cluster management via Ansible requires SSH reachability. This story makes the full Ansible inventory operable from outside the lab.

**Independent Test**: From an external network with Tailscale active, run `ssh fleetadmin@10.1.20.11` and receive a shell prompt.

**Acceptance Scenarios**:

1. **Given** Tailscale is active on the management laptop, **When** SSH is initiated to any host in the `10.1.1.0/24`, `10.1.10.0/24`, `10.1.20.0/24`, `10.1.30.0/24`, `10.1.40.0/24`, or `10.1.50.0/24` subnets, **Then** the connection succeeds without manual tunneling.
2. **Given** Tailscale is active, **When** an Ansible playbook is executed targeting the full inventory, **Then** all nodes respond and tasks complete as if on the local network.

---

### User Story 3 - Automated Provisioning via Ansible (Priority: P3)

As a lab administrator, I want the Tailscale installation and configuration on all lab nodes to be managed by Ansible so that the setup is reproducible, idempotent, and consistent with the project's infrastructure-as-code approach.

**Why this priority**: Manual install on 8+ nodes is error-prone. IaC is required for maintainability.

**Independent Test**: Run the Tailscale playbook against the full inventory; all nodes should report `ok` or `changed` on first run and `ok` (no changes) on second run.

**Acceptance Scenarios**:

1. **Given** a freshly provisioned node, **When** the Tailscale playbook runs, **Then** the Tailscale daemon is installed, authenticated, and the node appears in the Tailscale admin console.
2. **Given** Tailscale is already installed and configured, **When** the playbook runs again, **Then** no changes are made (idempotent).
3. **Given** a node is removed from the cluster, **When** the decommission playbook runs, **Then** the node is removed from the Tailscale network.

---

### Edge Cases

- What happens when Tailscale's coordination servers are unavailable? (Direct connections may persist; new connections fail gracefully.)
- How are Tailscale auth keys managed and rotated securely in Ansible without committing secrets?
- What is the behavior if the management laptop and a lab node are both behind CGNAT? (Tailscale DERP relay servers handle this transparently.)
- Does subnet routing conflict with split-DNS behavior if the management laptop is on a network that also uses `10.1.x.x` addressing?
- If a node's Tailscale daemon crashes, does it break other in-cluster traffic? (No — Tailscale is only for external management access; inter-node traffic stays on LAN.)
- What happens when the management laptop's device certificate expires? (Access to all `fleet1.lan` services is rejected; a new cert must be issued from cert-manager and installed on the laptop.)
- If the management laptop is lost or stolen, how is the device certificate revoked? (cert-manager certificate revocation must be performed; Tailscale device should also be removed from the tailnet admin console.)

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Tailscale MUST be installed and running as a system service on all managed nodes (`cluster`, `compute`, `nvr`).
- **FR-002**: All three K3s server nodes (`node1`, `node3`, `node5`) MUST be configured as subnet routers, each advertising all lab subnets — `10.1.1.0/24`, `10.1.10.0/24`, `10.1.20.0/24`, `10.1.30.0/24`, `10.1.40.0/24`, and `10.1.50.0/24` — to the Tailscale network. Tailscale will automatically failover between them if any one node becomes unavailable.
- **FR-003**: The subnet router MUST have IP forwarding enabled at the OS level.
- **FR-004**: The management laptop MUST be enrolled in the same Tailscale network (tailnet) to access the advertised subnets.
- **FR-005**: The Tailscale network MUST automatically resolve `fleet1.lan` hostnames for the management laptop as soon as Tailscale connects — no manual DNS changes or host file edits on the laptop. This MUST be implemented via a custom DNS nameserver configured in the tailnet admin console, pointing to OPNsense Unbound (`10.1.1.1`), scoped to the `fleet1.lan` domain.
- **FR-006**: Tailscale auth keys MUST be stored in Ansible Vault or equivalent secrets management — never in plaintext in the repository.
- **FR-007**: The Ansible role MUST be idempotent — re-running it on already-enrolled nodes MUST NOT re-authenticate or disrupt existing connections.
- **FR-008**: The advertised subnet routes MUST be approved in the Tailscale admin console (either manually or via pre-authorized keys with route approval enabled).
- **FR-009**: Key expiry MUST be disabled on all lab nodes in the Tailscale admin console. The management laptop retains default expiry behavior.
- **FR-010**: cert-manager MUST issue a client certificate to the management laptop from a cluster-internal CA, to serve as the device identity credential for application-layer access.
- **FR-011**: Traefik MUST be configured to require the management laptop's client certificate (mTLS) for access to all internal services exposed via `fleet1.lan` hostnames. Requests without a valid client certificate MUST be rejected with a 403 response.

### Key Entities

- **Tailnet**: The private Tailscale network shared by the management laptop and all lab nodes.
- **Subnet Router**: The lab node(s) that advertise all internal LAN subnets (`10.1.1.0/24`, `10.1.10.0/24`, `10.1.20.0/24`, `10.1.30.0/24`, `10.1.40.0/24`, `10.1.50.0/24`) into the tailnet, enabling access to all non-Tailscale hosts (OPNsense, switches, and any device on any lab VLAN).
- **Device Certificate**: A client certificate issued by cert-manager's cluster-internal CA to the management laptop. Presented during the TLS handshake to authenticate the device at the application layer before Traefik grants access to internal services.
- **Auth Key**: A pre-shared secret used during node enrollment to join the tailnet without interactive browser login.
- **DERP Relay**: Tailscale's relay infrastructure used when direct peer-to-peer NAT traversal is not possible (the CGNAT scenario).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 8 managed nodes appear as active devices in the Tailscale admin console within one playbook run.
- **SC-002**: The management laptop can reach any host on any lab subnet (`10.1.1.x`, `10.1.10.x`, `10.1.20.x`, `10.1.30.x`, `10.1.40.x`, `10.1.50.x`) within 10 seconds of activating Tailscale on an external network.
- **SC-003**: All `fleet1.lan` hostnames resolve correctly immediately after activating Tailscale on the management laptop — zero manual DNS changes, host-file edits, or extra steps required.
- **SC-004**: Running the provisioning playbook twice in succession produces zero changes on the second run (idempotency verified).
- **SC-005**: No Tailscale auth keys or secrets appear in plaintext in any committed file.
- **SC-006**: Accessing any `fleet1.lan` service without a valid device client certificate (e.g., from a browser without the cert installed, or a curl request with no cert) results in a rejected connection — not a login prompt.

## Clarifications

### Session 2026-04-30

- Q: What is the intended connection workflow once Tailscale is set up? → A: Open Tailscale app → connect → all `fleet1.lan` hostnames and LAN IPs work automatically, nothing else needed (Option B).
- Q: How many subnet routers should be configured? → A: All three K3s server nodes (`node1`, `node3`, `node5`) — maximum redundancy with Tailscale auto-failover (Option C).
- Q: Which Tailscale account tier? → A: Free Personal plan — sufficient for single-admin homelab; no ACL policies or multi-user management needed (Option A).
- Q: Traffic routing scope on the management laptop? → A: Split tunnel — only lab subnets (`10.1.1.0/24`, `10.1.10.0/24`, `10.1.20.0/24`, `10.1.30.0/24`, `10.1.40.0/24`, `10.1.50.0/24`) route through Tailscale; all other internet traffic goes direct (Option A).
- Q: How should Tailscale key expiry be handled? → A: Disable key expiry on all lab nodes; keep default expiry on the management laptop (Option B).
- Q: Which subnets should the Tailscale subnet router advertise? → A: All six lab subnets — `10.1.1.0/24` (OPNsense/management), `10.1.10.0/24`, `10.1.20.0/24`, `10.1.30.0/24`, `10.1.40.0/24`, `10.1.50.0/24`.
- Q: What layer should the device certificate requirement operate at? → A: Application layer — cert-manager issues a client certificate to the management laptop; Traefik requires it (mTLS) to access internal services. Free Tailscale plan unchanged (Option B).

## Assumptions

- The management laptop's Tailscale client will be installed and configured manually (out of scope for Ansible automation).
- A Tailscale Free Personal account exists (or will be created). No paid tier features (ACLs, audit logs, multi-user management) are required.
- All three K3s server nodes (`node1`, `node3`, `node5`) serve as subnet routers for maximum redundancy; Tailscale handles automatic failover between them.
- The OPNsense router does not need Tailscale installed — it is reachable via the advertised subnet route through the subnet router node.
- Inter-node cluster traffic continues to flow over the existing LAN; Tailscale is used only for external management access. The management laptop uses split-tunnel mode — all six lab subnets (`10.1.1.0/24`, `10.1.10.0/24`, `10.1.20.0/24`, `10.1.30.0/24`, `10.1.40.0/24`, `10.1.50.0/24`) route through Tailscale; no exit node is configured.
- Tailscale key expiry is disabled on all lab nodes (`cluster`, `compute`, `nvr`) to prevent unexpected remote-access outages. The management laptop retains the default 180-day expiry since re-authentication is a manual interactive step.
- The `fleet1.lan` DNS resolution uses a custom nameserver configured in the tailnet admin console pointing to OPNsense Unbound (`10.1.1.1`), scoped to the `fleet1.lan` domain — not MagicDNS global override.
- cert-manager is already deployed in the cluster and will serve as the CA for issuing device client certificates. The management laptop client cert will be installed manually into the browser/OS keychain (out of scope for Ansible automation).
- The Free Tailscale Personal plan remains sufficient; device certificate enforcement is handled at the application layer (Traefik mTLS), not at the Tailscale coordination layer.
