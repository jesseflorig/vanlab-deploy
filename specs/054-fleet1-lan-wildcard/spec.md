# Feature Specification: fleet1.lan Local DNS with Internal Wildcard TLS

**Feature Branch**: `054-fleet1-lan-wildcard`  
**Created**: 2026-04-27  
**Status**: Draft  
**Input**: User description: "Add fleet1.lan with a local wildcard cert and any provisioning playbooks. Refer to local context for additional info"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Internal Services Resolve via fleet1.lan (Priority: P1)

A homelab operator opens a browser on their management laptop and navigates to a service (e.g., `grafana.fleet1.lan`) while on the local network. The browser resolves the name to Traefik's internal IP and loads the service over HTTPS without any certificate warning.

**Why this priority**: DNS resolution and TLS trust are the foundational requirements — nothing else works without them.

**Independent Test**: Can be fully tested by navigating to any `*.fleet1.lan` service URL from the management laptop and confirming the page loads with a valid (green padlock) HTTPS connection.

**Acceptance Scenarios**:

1. **Given** the management laptop uses OPNsense Unbound as its DNS resolver, **When** a user navigates to `grafana.fleet1.lan`, **Then** the browser resolves to the Traefik internal IP and loads the Grafana UI over HTTPS with no certificate warning
2. **Given** a service is unreachable, **When** a user navigates to its `fleet1.lan` hostname, **Then** the browser shows a connection refused or timeout — not a DNS failure or cert warning
3. **Given** a client not using OPNsense as its DNS resolver, **When** a user navigates to a `fleet1.lan` hostname, **Then** the name does not resolve (correct isolation behavior)

---

### User Story 2 - Internal CA Root Trust Distributed to Managed Clients (Priority: P2)

The operator runs a provisioning playbook that installs the internal CA root certificate on the management laptop (and any other managed machines). After running the playbook, all browsers and CLI tools on those machines trust certificates issued by the internal CA.

**Why this priority**: Without CA trust distributed to clients, the wildcard cert produces browser warnings, making the setup unusable.

**Independent Test**: Can be fully tested by running the provisioning playbook on the management laptop, then navigating to a `*.fleet1.lan` service and confirming the cert is trusted without manual browser exceptions.

**Acceptance Scenarios**:

1. **Given** the provisioning playbook has run, **When** a user opens any `*.fleet1.lan` URL in a browser, **Then** the connection is trusted (no warning, valid cert shown)
2. **Given** the provisioning playbook has run, **When** a user runs `curl https://grafana.fleet1.lan`, **Then** the request succeeds without `--insecure`
3. **Given** the playbook is run a second time, **When** the CA cert is already installed, **Then** the playbook is idempotent — no duplicate entries, no errors

---

### User Story 3 - Traefik Ingresses Serve the Wildcard TLS Cert (Priority: P3)

Existing services accessible via `fleet1.cloud` are also accessible via `fleet1.lan` using Traefik, serving the internal wildcard cert for `*.fleet1.lan` connections. Internal traffic no longer routes through Cloudflare Tunnel.

**Why this priority**: This is the operational payoff — internal traffic stays on-LAN.

**Independent Test**: Can be fully tested by confirming a service responds on its `fleet1.lan` hostname via Traefik with the internal wildcard cert (not the Cloudflare cert).

**Acceptance Scenarios**:

1. **Given** an existing service has a `fleet1.cloud` IngressRoute, **When** a request arrives on its `fleet1.lan` hostname, **Then** Traefik serves it using the internal wildcard TLS certificate
2. **Given** the wildcard cert is used, **When** a new `fleet1.lan` hostname is added, **Then** no new TLS configuration is required — the wildcard covers it automatically

---

### Edge Cases

- What if OPNsense Unbound restarts — do overrides persist? Yes, they are config-file-backed and survive restarts
- What if the internal wildcard cert expires — do all internal services lose HTTPS simultaneously? Yes — cert renewal must be automated
- What if a managed client's system CA store is reset (e.g., OS reinstall)? The provisioning playbook must be re-run
- What if a `fleet1.lan` hostname is accessed from within the cluster (in-cluster DNS)? CoreDNS is not OPNsense — this scope is limited to LAN clients only

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The OPNsense Unbound resolver MUST serve a wildcard DNS override resolving `*.fleet1.lan` to Traefik's internal LAN IP
- **FR-002**: An internal Certificate Authority MUST be established within the cluster's certificate management infrastructure
- **FR-003**: A wildcard TLS certificate for `*.fleet1.lan` MUST be issued by the internal CA and stored in a cluster secret accessible to Traefik
- **FR-004**: The wildcard TLS certificate MUST be automatically renewed before expiration without manual intervention
- **FR-005**: Traefik MUST serve the internal wildcard cert for all `*.fleet1.lan` hostnames
- **FR-006**: A provisioning playbook MUST install the internal CA root certificate in the system trust store of managed machines (management laptop and any other Ansible-managed clients)
- **FR-007**: The CA root trust playbook MUST be idempotent — safe to run multiple times without side effects
- **FR-008**: The Unbound wildcard DNS override MUST be applied via Ansible, consistent with existing network provisioning conventions
- **FR-009**: All provisioning MUST follow existing Ansible project conventions (variable structure, vault usage, role layout)

### Key Entities

- **Internal CA**: A self-signed root certificate authority used to sign internal TLS certificates; stored durably within the cluster
- **Wildcard Certificate**: A TLS certificate valid for `*.fleet1.lan`, issued by the Internal CA, renewed automatically
- **Unbound Override**: A DNS host override in OPNsense Unbound mapping `*.fleet1.lan` to Traefik's LAN IP
- **CA Root Bundle**: The exported public root certificate distributed to managed clients for system-level trust

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A browser on the management laptop navigates to any `*.fleet1.lan` service with a valid HTTPS connection (no cert warning) within 30 seconds of entering the URL
- **SC-002**: The CA trust provisioning playbook completes in under 5 minutes on a managed machine
- **SC-003**: Wildcard cert renewal is fully automated — no manual steps required when the cert expires
- **SC-004**: All provisioning playbooks are idempotent — re-running produces no errors and no unintended state changes
- **SC-005**: Internal `*.fleet1.lan` traffic does not route through Cloudflare Tunnel — all requests resolve and connect on-LAN

## Assumptions

- OPNsense Unbound is the primary DNS resolver for all LAN clients in the vanlab network
- Traefik is already deployed and serving as the cluster ingress with a stable internal LAN IP
- cert-manager is already deployed in the cluster (used for existing `fleet1.cloud` certs via Cloudflare DNS challenge)
- The management laptop is Ansible-managed and is the primary (possibly only) target for the CA trust playbook
- Mobile devices and guest clients are out of scope — only Ansible-managed machines receive the CA root cert
- In-cluster pod DNS (CoreDNS) is out of scope — `fleet1.lan` resolution is for LAN clients only
- The internal CA root certificate is treated as non-secret (public key only) and safe to distribute via Ansible
- Existing `fleet1.cloud` IngressRoutes and Cloudflare Tunnel configuration remain unchanged; `fleet1.lan` hostnames are additive
