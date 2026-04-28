# Contract: OPNsense Unbound Host Overrides

## Desired Outcome

After applying the network playbook, the local resolver at `10.1.1.1` must answer these LAN DNS
queries:

| Query | Expected A Record |
|-------|-------------------|
| `opnsense.fleet1.lan` | `10.1.1.1` |
| `sw-main.fleet1.lan` | `10.1.1.10` |
| `sw-poe-1.fleet1.lan` | `10.1.1.11` |
| `sw-poe-2.fleet1.lan` | `10.1.1.12` |
| `sw-poe-3.fleet1.lan` | `10.1.1.13` |

## OPNsense API Interaction Contract

The implementation should follow the existing API pattern in `playbooks/network/network-deploy.yml`:

1. Search existing host overrides with `POST /api/unbound/settings/searchHostOverride`.
2. Compare existing rows by `hostname`, `domain`, and `server`.
3. Create missing desired records with `POST /api/unbound/settings/addHostOverride`.
4. Reconfigure Unbound with `POST /api/unbound/service/reconfigure` only when records changed.

## Idempotency Contract

- A record that already exists with the expected hostname, domain, type, and address is a no-op.
- Missing desired records are created once.
- The playbook must not create duplicate records on repeated runs.
- The playbook must fail before applying final state when a requested hostname or address conflicts with an existing override.

## Client Validation Contract

From a LAN client using OPNsense DNS, each validation command must return exactly the expected address:

```bash
dig opnsense.fleet1.lan @10.1.1.1 +short
dig sw-main.fleet1.lan @10.1.1.1 +short
dig sw-poe-1.fleet1.lan @10.1.1.1 +short
dig sw-poe-2.fleet1.lan @10.1.1.1 +short
dig sw-poe-3.fleet1.lan @10.1.1.1 +short
```
