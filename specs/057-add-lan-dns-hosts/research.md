# Research: fleet1.lan Infrastructure DNS Host Records

## Decision 1: DNS Owner — OPNsense Unbound

**Decision**: Manage the requested names as OPNsense Unbound host overrides.

**Rationale**: The spec targets LAN clients resolving `fleet1.lan` names. OPNsense Unbound is already
the local resolver for this namespace, and `playbooks/network/network-deploy.yml` already contains
working Unbound API calls for `fleet1.lan` host overrides.

**Alternatives considered**:
- CoreDNS overrides: rejected because the requirement is for LAN clients, not in-cluster pods.
- Public DNS records: rejected because these are private `10.1.1.x` management addresses.
- Local client hosts files: rejected because they are not centralized, repeatable, or appropriate for shared LAN resolution.

## Decision 2: Implementation Location — Existing Network Playbook

**Decision**: Extend `playbooks/network/network-deploy.yml` rather than creating a new role or playbook.

**Rationale**: The existing playbook already authenticates to OPNsense, fetches Unbound overrides, creates
host overrides, and applies Unbound reconfiguration. Keeping these device records in the same location
preserves one owner for OPNsense DNS state and avoids duplicate API setup.

**Alternatives considered**:
- New `roles/dns` role: rejected as unnecessary abstraction for five static records.
- Separate utility playbook: rejected because these records are desired network state, not an ad hoc operation.

## Decision 3: Desired Records as Data

**Decision**: Represent the five host records as a small list of desired records, then loop over that list
to check, create, and apply changes.

**Rationale**: A data-driven list keeps the mapping auditable, reduces repetitive tasks, and makes idempotency
checks consistent across all five records. It also provides a natural place to add descriptions for each
network device.

**Alternatives considered**:
- Five hand-written task blocks: rejected because it invites drift between records and makes future additions harder.
- Generated hostnames from an IP range: rejected because the main switch (`sw-main`) does not follow the PoE switch sequence.

## Decision 4: Conflict Handling

**Decision**: Before creating records, detect requested hostnames or target IPs that already exist with a
conflicting value and fail with a clear message instead of silently replacing them.

**Rationale**: The spec requires conflicts to be surfaced before applying a conflicting final state. A failure is
safer than overwriting existing DNS state for infrastructure devices.

**Alternatives considered**:
- Always update existing conflicting records: rejected because replacement could mask a real addressing or naming mistake.
- Ignore duplicates by IP: rejected because duplicate IP mappings can still be intentional aliases, but this feature should not
introduce them without explicit review.

## Decision 5: Validation Method

**Decision**: Validate from a LAN client with `dig <hostname> @10.1.1.1 +short`, confirming the returned
address for each requested record.

**Rationale**: This directly verifies the user-facing resolver behavior required by the spec, independent of
how OPNsense stores the records internally.

**Alternatives considered**:
- OPNsense API response inspection only: rejected because it does not prove client-visible DNS resolution.
- Browser/admin UI checks only: rejected because service availability can fail for reasons unrelated to DNS.
