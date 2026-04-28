# Data Model: OPNsense 23.7 → 26.1 Upgrade

## Key Entities

This feature has no persistent data model changes — it is a procedural upgrade.
The entities below represent the artifacts and states that must be tracked through the upgrade.

### Configuration Backups

| Artifact | Format | Captured Before | Stored At |
|----------|--------|-----------------|-----------|
| `opnsense-23.7-pre.xml` | OPNsense config XML | 23.7 → 24.1 hop | Management laptop |
| `opnsense-24.1-pre.xml` | OPNsense config XML | 24.1 → 24.7 hop | Management laptop |
| `opnsense-24.7-pre.xml` | OPNsense config XML | 24.7 → 25.1 hop | Management laptop |
| `opnsense-25.1-pre.xml` | OPNsense config XML | 25.1 → 25.7 hop | Management laptop |
| `opnsense-25.7-pre.xml` | OPNsense config XML | 25.7 → 26.1 hop | Management laptop |

### Upgrade Hop States

Each hop has three states: **Pending**, **In Progress**, **Verified**.

| Hop | From | To | Key Risk | Verification Gate |
|-----|------|----|----------|-------------------|
| 1 | 23.7 | 24.1 | WireGuard migration to core | WireGuard tunnel up; all nodes reachable |
| 2 | 24.1 | 24.7 | Stability; no major breaking changes | All services respond; DHCP serving |
| 3 | 24.7 | 25.1 | DHCP migration begins (low risk — no active leases) | DHCP service running on configured VLANs |
| 4 | 25.1 | 25.7 | Unbound format change | Unbound overrides resolve correctly |
| 5 | 25.7 | 26.1 | NAT rename; Destination NAT API | API returns 200; NAT rules intact |

### Post-Upgrade Verification Checklist Items

| Item | Test | Pass Condition |
|------|------|----------------|
| Version | Check dashboard | Shows 26.1.x |
| Cluster nodes | `kubectl get nodes` | All Ready |
| DHCP — all VLANs | Check lease table | Active leases on 10.1.x subnets |
| Unbound overrides | `dig mqtt.fleet1.cloud @10.1.1.1` | Returns 10.1.20.x |
| WireGuard | Ping across tunnel | Responds |
| Existing firewall rules | `network-deploy.yml --check` | No unexpected changes |
| Destination NAT API | `POST /api/firewall/dnat/searchRule` | 200 response |
| API user credentials | Existing key/secret auth | Authenticates successfully |
| fleet1.cloud services | HTTP check per service | 200 responses |
