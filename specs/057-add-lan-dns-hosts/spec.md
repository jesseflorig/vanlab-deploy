# Feature Specification: fleet1.lan Infrastructure DNS Host Records

**Feature Branch**: `057-add-lan-dns-hosts`  
**Created**: 2026-04-28  
**Status**: Draft  
**Input**: User description: "Add opnsense.fleet1.lan for 10.1.1.1, sw-main.fleet1.lan for 10.1.1.10, sw-poe-1.fleet1.lan through sw-poe-3 for 10.1.1.11-13"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Resolve Core Network Devices by Name (Priority: P1)

A homelab operator uses a LAN-connected management machine to reach core network devices by stable `fleet1.lan` hostnames instead of memorizing IP addresses.

**Why this priority**: The requested value is direct name resolution for known infrastructure devices; this must work before any operational workflow benefits from the new names.

**Independent Test**: Can be fully tested by resolving each requested hostname from a LAN client that uses the local resolver and confirming the returned address matches the requested mapping.

**Acceptance Scenarios**:

1. **Given** a LAN client uses the local resolver, **When** the operator resolves `opnsense.fleet1.lan`, **Then** the result is `10.1.1.1`
2. **Given** a LAN client uses the local resolver, **When** the operator resolves `sw-main.fleet1.lan`, **Then** the result is `10.1.1.10`
3. **Given** a LAN client uses the local resolver, **When** the operator resolves `sw-poe-1.fleet1.lan`, `sw-poe-2.fleet1.lan`, and `sw-poe-3.fleet1.lan`, **Then** the results are `10.1.1.11`, `10.1.1.12`, and `10.1.1.13` respectively

---

### User Story 2 - Use Hostnames in Routine Administration (Priority: P2)

A homelab operator opens device admin pages or runs operational checks using the new hostnames, keeping documentation and commands readable as the network grows.

**Why this priority**: Once resolution is correct, the practical outcome is improved day-to-day administration through memorable device names.

**Independent Test**: Can be fully tested by using the hostnames from a LAN client for an administrative connection attempt and confirming the connection targets the expected device address.

**Acceptance Scenarios**:

1. **Given** the DNS records are active, **When** the operator connects to `opnsense.fleet1.lan`, **Then** the connection targets `10.1.1.1`
2. **Given** the DNS records are active, **When** the operator connects to any switch hostname in scope, **Then** the connection targets that switch's assigned management IP

### Edge Cases

- If a queried name is outside the requested set, it must not be created as part of this feature.
- If a LAN client is not using the local resolver, the requested hostnames may not resolve; this feature only covers local `fleet1.lan` resolution.
- If an existing DNS record already uses one of the requested hostnames with a different address, that conflict must be surfaced before replacement.
- If a requested IP address is already assigned to a different hostname, that conflict must be surfaced before adding a duplicate mapping.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The local resolver MUST provide an address record for `opnsense.fleet1.lan` resolving to `10.1.1.1`.
- **FR-002**: The local resolver MUST provide an address record for `sw-main.fleet1.lan` resolving to `10.1.1.10`.
- **FR-003**: The local resolver MUST provide an address record for `sw-poe-1.fleet1.lan` resolving to `10.1.1.11`.
- **FR-004**: The local resolver MUST provide an address record for `sw-poe-2.fleet1.lan` resolving to `10.1.1.12`.
- **FR-005**: The local resolver MUST provide an address record for `sw-poe-3.fleet1.lan` resolving to `10.1.1.13`.
- **FR-006**: The records MUST be persistent across local resolver restarts and normal configuration refreshes.
- **FR-007**: The records MUST be additive and MUST NOT remove or alter unrelated `fleet1.lan` records.
- **FR-008**: The resulting configuration MUST be repeatable so applying the same desired records more than once does not create duplicates or unintended changes.
- **FR-009**: Any hostname or address conflict involving the requested records MUST be reported before applying a conflicting final state.

### Key Entities

- **DNS Host Record**: A single hostname-to-address mapping within the `fleet1.lan` local namespace.
- **Network Device**: A managed infrastructure device represented by a stable hostname and LAN management address.
- **Local Resolver**: The DNS service used by LAN clients for local `fleet1.lan` name resolution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All five requested hostnames resolve to their specified IP addresses from a LAN client using the local resolver.
- **SC-002**: Each requested hostname returns the expected address within 2 seconds during validation from a LAN client.
- **SC-003**: Reapplying the desired records results in zero duplicate DNS entries and no changes to unrelated records.
- **SC-004**: The records remain available after a local resolver restart or configuration refresh.
- **SC-005**: Routine device administration can reference the five requested hostnames without requiring the operator to look up or type their numeric addresses.

## Assumptions

- OPNsense Unbound remains the local resolver for `fleet1.lan` clients.
- The requested addresses are current management IPs for the listed devices.
- This feature is limited to explicit infrastructure host records and does not change wildcard `fleet1.lan` behavior.
- This feature does not introduce TLS certificates, redirects, aliases, or remote/public DNS records.
