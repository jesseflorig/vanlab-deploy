# Data Model: fleet1.lan Infrastructure DNS Host Records

## Entities

### DNS Host Record

Represents one explicit hostname-to-address mapping in the local `fleet1.lan` namespace.

| Field | Value/Rule |
|-------|------------|
| `enabled` | Must be enabled |
| `hostname` | Host label only, without `.fleet1.lan` |
| `domain` | `fleet1.lan` |
| `record_type` | `A` |
| `address` | IPv4 management address |
| `description` | Human-readable device purpose |

### Desired Records

| Hostname | Domain | Address | Device |
|----------|--------|---------|--------|
| `opnsense` | `fleet1.lan` | `10.1.1.1` | OPNsense router/firewall |
| `sw-main` | `fleet1.lan` | `10.1.1.10` | Main management switch |
| `sw-poe-1` | `fleet1.lan` | `10.1.1.11` | PoE switch 1 |
| `sw-poe-2` | `fleet1.lan` | `10.1.1.12` | PoE switch 2 |
| `sw-poe-3` | `fleet1.lan` | `10.1.1.13` | PoE switch 3 |

### Local Resolver

The OPNsense Unbound resolver serving LAN clients for local `fleet1.lan` DNS names.

| Field | Value/Rule |
|-------|------------|
| Resolver address | `10.1.1.1` |
| Scope | LAN clients that use OPNsense DNS |
| Configuration owner | `playbooks/network/network-deploy.yml` |

## Relationships

- A Local Resolver owns many DNS Host Records.
- Each DNS Host Record maps exactly one requested network device hostname to one IPv4 address.
- The explicit host records are additive to the existing `fleet1.lan` wildcard and apex records.

## Validation Rules

- Each desired hostname must exist exactly once as an enabled `A` record in `fleet1.lan`.
- Each desired hostname must resolve to the specified IPv4 address.
- Existing records outside the desired set must not be removed or modified by this feature.
- If a desired hostname already exists with a different address, planning requires an implementation failure before final state is applied.
- If a desired address already exists for a different hostname, planning requires an implementation failure before final state is applied.
- Applying the same desired records repeatedly must not create duplicate host overrides.

## State Transitions

```text
missing desired record
  -> create enabled A record
  -> active desired record

active desired record
  -> no-op on subsequent runs

conflicting hostname or address
  -> fail with conflict details
  -> operator resolves conflict before retry
```
