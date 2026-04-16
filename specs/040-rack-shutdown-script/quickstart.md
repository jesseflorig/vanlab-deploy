# Quickstart: Rack Shutdown

**Feature**: 040-rack-shutdown-script  
**Date**: 2026-04-16

## Prerequisites

1. You are at the repo root on the `040-rack-shutdown-script` branch (or `main` after merge).
2. SSH access to all hosts is working — cluster nodes and edge host via `fleetadmin`, OPNsense via `fleetadmin`, all using `~/.ssh/id_rsa` (per `~/.ssh/config`).
3. Your SSH agent has `~/.ssh/id_rsa` loaded, or the key has no passphrase.

## Verify first

```bash
# Confirm all hosts are reachable
ansible -i hosts.ini all -m ping

# Dry run — see what will happen without executing anything
make shutdown-dry-run
```

## Shut down the rack

```bash
make shutdown
```

Watch the output. The playbook will:
1. Run pre-flight checks and display any warnings.
2. Drain and halt agent nodes (node2, node4, node6).
3. Drain and halt server nodes (node1, node3, node5) one at a time.
4. Stop cloudflared and halt the edge host (10.1.10.10).
5. Halt OPNsense (10.1.1.1) — your terminal will lose connectivity here.

The final OPNsense step will not print a confirmation (the network is gone). This is expected — the playbook will report the command as sent and exit.

## One-off node shutdown (existing utility)

For shutting down a single cluster node for maintenance (not a full rack shutdown):

```bash
ansible-playbook -i hosts.ini playbooks/utilities/drain-shutdown.yml -e target=node4
```

## After power-on

Manual startup steps (not automated by this feature):

1. Power on OPNsense first (networking required for everything else).
2. Power on the edge host (cloudflared will start automatically via systemd).
3. Power on cluster nodes — K3s will start automatically via systemd.
4. Verify cluster: `kubectl get nodes`
5. Verify Longhorn: `kubectl get volumes.longhorn.io -n longhorn-system`
