# Quickstart: OPNsense 23.7 → 26.1 Upgrade

**Total time**: ~3 hours. Plan a maintenance window with no other changes in flight.
**Downtime**: ~5 minutes per hop (reboot). Other services remain up between hops.

## Before You Start

- [ ] Cluster is healthy: `kubectl get nodes` — all Ready
- [ ] No pending Gitea PRs or ArgoCD syncs in progress
- [ ] Management laptop has SSH access to `10.1.1.1` as backup console
- [ ] Current OPNsense version confirmed: `23.7.12_5` (or latest 23.7.x patch)

## Per-Hop Procedure (repeat 5 times)

### Step 1 — Export config backup

System → Configuration → Backups → Download → save as `opnsense-<CURRENT_VERSION>-pre.xml`

### Step 2 — Trigger major upgrade

System → Firmware → Status → click "Check for Updates" to get the latest patch in the current series first, apply it. Then trigger the major version upgrade:

**Console method (SSH to 10.1.1.1, or physical console):**
```
# At the OPNsense console menu
12   ← Major Upgrade
# Enter target version number when prompted (e.g., "24.1")
```

**Web UI method (if available in current version):**
System → Firmware → Settings → change release type to next major → Update

### Step 3 — Wait for reboot and log back in

Router is unavailable for ~5 minutes. Verify new version in dashboard header.

### Step 4 — Run per-hop verification

```bash
# From management laptop
dig mqtt.fleet1.cloud @10.1.1.1        # Unbound overrides working
ping 10.1.20.11                         # Cluster node reachable
kubectl get nodes                       # All Ready
# Check OPNsense DHCP lease table for each VLAN in Services → DHCPv4
```

✅ All pass → proceed to next hop
❌ Any fail → stop, diagnose, restore backup if needed before continuing

---

## Hop Sequence

| # | From | To | Key check after |
|---|------|----|-----------------|
| 1 | 23.7 | 24.1 | WireGuard tunnel up |
| 2 | 24.1 | 24.7 | All services respond |
| 3 | 24.7 | 25.1 | DHCP service running on configured VLANs |
| 4 | 25.1 | 25.7 | Unbound overrides resolve |
| 5 | 25.7 | 26.1 | Destination NAT API + all services |

---

## Final Verification (after hop 5 to 26.1)

> **Deviation from plan**: The Destination NAT API path is `/api/firewall/d_nat/` (underscore),
> not `/api/firewall/dnat/`. `DNatController` maps to `d_nat` in OPNsense's URL routing.
> Also: the API user requires an explicit "Destination NAT" privilege grant
> (System → Access → Users → API user → Privileges) — it is not covered by the general
> Firewall: Rules privilege.

```bash
# Verify Destination NAT API (correct path: d_nat with underscore)
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  "https://10.1.1.1/api/firewall/d_nat/searchRule" \
  -X POST -H "Content-Type: application/json" -d '{}' | python3 -m json.tool

# Expected: {"rows": [...], "rowCount": N, ...}
# 403 Forbidden = endpoint found but API user needs Destination NAT privilege added

# Run network-deploy in check mode — verify no unexpected drift
ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml --check
```

---

## Rollback Procedure

If a hop leaves OPNsense in an unbootable state:

1. Boot from OPNsense USB installer for the **previous** version
2. During install, select "Restore Configuration" and import the pre-hop XML backup
3. System will boot into the working previous version with full config restored
4. Investigate the failure before retrying the hop

If OPNsense boots but config is broken (services not working):

1. System → Configuration → Backups → restore the pre-hop XML
2. Reboot
3. Verify services before retrying
