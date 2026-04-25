# Data Model: Rack Shutdown Playbook

**Feature**: 040-rack-shutdown-script  
**Date**: 2026-04-16

## Rack Components

These are the entities the playbook acts on, in shutdown order.

| Component | Inventory Group | Hosts | Service to Stop | Shutdown Command |
|-----------|----------------|-------|-----------------|-----------------|
| Agent nodes | `[agents]` | node2, node4, node6 (10.1.20.12/14/16) | `k3s-agent` | `shutdown -h now` |
| Server nodes | `[servers]` | node1, node3, node5 (10.1.20.11/13/15) | `k3s` | `shutdown -h now` |
| Edge host | `[compute]` | edge (10.1.10.10) | `cloudflared` | `shutdown -h now` |
| OPNsense | `[network]` | opnsense (10.1.1.1) | N/A (FreeBSD) | `shutdown -h now` |

## Shutdown Sequence

```
Step 1: Pre-flight
  ├── Check reachability of all hosts
  └── Check Longhorn volume health (warn only)

Step 2: Drain + shutdown agents (node2, node4, node6)
  ├── kubectl drain <node> from servers[0] (serial, one at a time)
  └── systemctl stop k3s-agent → shutdown -h now (async)

Step 3: Drain + shutdown servers (node1, node3, node5)
  ├── Drain node1 from node3 → stop k3s → shutdown node1 (async)
  ├── Drain node3 from node5 → stop k3s → shutdown node3 (async)
  └── Stop k3s on node5 → shutdown node5 (async, no drain target)

Step 4: Shutdown edge host (10.1.10.10)
  ├── systemctl stop cloudflared
  └── shutdown -h now (async)

Step 5: Shutdown OPNsense (10.1.1.1)
  └── shutdown -h now (async: 5, poll: 0, ignore_unreachable: true)
      ↑ Network path dies here — async exits before SSH drops
```

## Inventory Group Requirements

The playbook requires these groups to be defined in `hosts.ini`:

| Group | Required | Purpose |
|-------|----------|---------|
| `[agents]` | Yes | K3s worker nodes to drain and halt |
| `[servers]` | Yes | K3s control-plane nodes; also used as kubectl source |
| `[compute]` | Yes | Edge host; cloudflared must be stopped before halt |
| `[network]` | Yes (new) | OPNsense; SSH-only for shutdown; credentials in group_vars |

## Playbook Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `drain_timeout` | `600s` | Max time to wait for kubectl drain per node |
| `k3s_stop_timeout` | `120` | Seconds to wait for k3s/k3s-agent service to stop |
| `preflight_warn_only` | `true` | If false, abort on any pre-flight failure |

## Files Changed

| File | Change Type | Description |
|------|-------------|-------------|
| `playbooks/utilities/rack-shutdown.yml` | New | Full rack shutdown playbook |
| `hosts.ini` | Modified | Add `[network]` group for OPNsense; use SSH config alias (no `ansible_host`) |
| `Makefile` | New | `make shutdown` and `make shutdown-dry-run` targets |

**No new `group_vars/` files needed.** All SSH credentials are in `~/.ssh/config` (already present for all hosts). OPNsense uses `fleetadmin` via `~/.ssh/id_rsa`; key auth is forced via `ansible_ssh_private_key_file` on the `[network]` group to bypass the global `ansible_ssh_pass`.
