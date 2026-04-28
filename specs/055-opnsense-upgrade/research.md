# Research: OPNsense 23.7 → 26.1 Upgrade

## Decision 1: Upgrade Path — Five Sequential Major Hops Required

**Decision**: No direct jump from 23.7 to 26.1. The upgrade must proceed through every
intermediate major release in sequence:

```
23.7 → 24.1 → 24.7 → 25.1 → 25.7 → 26.1
```

Each hop must complete and be verified before starting the next.

**Rationale**: OPNsense enforces sequential major version upgrades; the package manager cannot
resolve dependencies across more than one major series boundary. Attempting to skip a version
is not supported and risks an unbootable system.

**Procedure per hop**: At the OPNsense console menu, press `12` (Major Upgrade), enter the
target version number. The system downloads packages, applies them, and reboots. Alternatively
via SSH: `opnsense-update -bkp` to back up, then the firmware upgrade mechanism in the web UI
under System → Firmware → Status.

**Time estimate**: ~15–25 minutes per hop (download + apply + reboot). Total window for all
5 hops: ~2–2.5 hours. Plan for a 3-hour maintenance window.

---

## Decision 2: Backup Strategy — Manual Export Before Each Hop

**Decision**: Export a full configuration XML backup before each major hop via
System → Configuration → Backups → Download. Five backups total (one per pre-upgrade state):
`opnsense-23.7-pre.xml`, `opnsense-24.1-pre.xml`, etc. Store on the management laptop.

**Rationale**: OPNsense retains automatic config history (System → Configuration → Backups)
but the depth is limited by the Backup Count setting. A manual export guarantees a clean
restore point for each version. If the system becomes unbootable after a hop, a USB-boot
recovery can restore the XML via the installer's config import step.

**ZFS snapshot note**: OPNsense only supports pre-upgrade snapshots on ZFS filesystems.
The default OPNsense install uses UFS — snapshots are not available. Manual XML export
is the only reliable rollback path.

**Rollback procedure**: System → Configuration → Backups → restore the pre-upgrade XML →
reboot. This restores the config but does NOT downgrade the OPNsense version. A version
rollback requires re-installing OPNsense from a 23.7 image and importing the backup XML.

---

## Decision 3: Breaking Changes Requiring Post-Hop Verification

The following changes between 23.7 and 26.1 directly affect the vanlab configuration and
must each be verified after the relevant hop:

| Change | Introduced | Impact | Verification |
|--------|-----------|--------|-------------|
| WireGuard moved to core | 24.1 | WireGuard VPN migrated from plugin to built-in; must verify tunnel is up post-24.1 upgrade | `ping` across WireGuard tunnel |
| ISC-DHCP deprecated → plugin | 25.x | DHCP server auto-migrated; Dnsmasq becomes default. Verify all VLANs still get leases | Check DHCP leases table for each VLAN |
| Port Forward renamed to Destination NAT | 26.1 | Existing port-forward rules persist but rule associations dropped; config migrates automatically | Verify any existing manual NAT rules survive |
| Unbound settings format change | 25.7 | Blocklist/settings format changed; host overrides should survive but must be verified | Check that `mqtt.fleet1.cloud` and `*.fleet1.lan` overrides resolve correctly |
| `mwexec()` removed | 26.1 | Only affects custom plugins/scripts; vanlab has none | N/A |

---

## Decision 4: Destination NAT API — No Extra Plugin Required

**Decision**: The `/api/firewall/dnat/` endpoint is part of OPNsense core in 26.1. No
additional plugin installation is needed. The existing API user (using the same key/secret
pair in `group_vars/all.yml`) will have access, provided the API user has the
`Firewall: Aliases: Rules` privilege (or equivalent for the new dnat controller).

**Rationale**: The research confirms the Destination NAT API is core (not plugin-dependent)
in 26.1. The API uses the same basic HTTP auth as the existing firewall filter and Unbound
endpoints already used by `network-deploy.yml`. Privilege may need to be expanded for the
API user if `dnat` is under a new ACL group — verify immediately after the 26.1 hop.

**Post-upgrade verification call**:
```
POST /api/firewall/dnat/searchRule  body: {}
```
Expected: `{"rows": [...], "rowCount": N, ...}` (not a 400 error).

---

## Decision 5: DHCP Migration Risk — Reduced (No Active Leases)

**Decision**: The ISC-DHCP → plugin migration (occurring somewhere in the 24.x–25.x series)
is a known breaking change, but its practical risk is reduced for this environment. All
cluster nodes and fixed infrastructure devices use static IPs (confirmed in hosts.ini:
10.1.20.11–16 for cluster, 10.1.10.10–11 for edge/NVR). DHCP is configured on some VLANs
but no active leases are currently held — there are no clients that will lose connectivity
mid-upgrade due to a lease renewal failure.

**Mitigation**: After each hop in the 24.x–25.x range, verify the DHCP service is running
(not just that leases exist). Check System → Services → DHCPv4 (or Dnsmasq, whichever the
migrated version uses) shows the service as active. If the service fails to start:
1. Check System → Services → ISC DHCPv4 / Dnsmasq for error state
2. Restart the DHCP service from the web UI
3. If still broken, restore the pre-hop config backup

**Risk level**: Low — no active leases means no lease-renewal deadline pressure. DHCP
correctness is still verified post-upgrade, but it is no longer a blocking urgency item.

---

## Decision 6: Upgrade Execution — Web UI Preferred Over Console

**Decision**: Use the OPNsense web UI (System → Firmware → Status → Update) for minor
version updates within a series, and the console menu option `12` (or web UI equivalent
if available in newer versions) for major version hops. SSH access is maintained throughout
as a fallback.

**Rationale**: The web UI provides progress feedback and is less error-prone than CLI for
this operation. The console option `12` is the documented path for major upgrades when
the web UI's "Check for Updates" only shows within-series updates.
