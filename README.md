# Vanlab

Ansible automation for the Vanlab homelab — K3s cluster, edge compute, and network infrastructure.

**Hardware**: 4x CM5 64GB w/ PoE HAT + M.2 2TB NVMe drives (cluster), 1x Waveshare CM5-PoE-BASE-A (edge)

## Prerequisites

Install Ansible collections once after cloning (or when `requirements.yml` changes):

```bash
ansible-galaxy collection install -r requirements.yml
```

Copy the secrets template and fill in real values:

```bash
cp group_vars/example.all.yml group_vars/all.yml
# Edit group_vars/all.yml with your credentials
```

## Quick Reference

| Category | Playbook | Command |
|----------|----------|---------|
| Cluster | Deploy K3s | `ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml --ask-become-pass` |
| Cluster | Deploy Services | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass` |
| Edge | Deploy Cloudflared | `ansible-playbook -i hosts.ini playbooks/compute/edge-deploy.yml --ask-become-pass` |
| Network | OPNsense (check) | `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml --check` |
| Utilities | Check All Hosts | `ansible-playbook -i hosts.ini playbooks/utilities/check_hosts.yml` |
| Utilities | Disk Health | `ansible-playbook -i hosts.ini playbooks/utilities/disk-health.yml --ask-become-pass` |

## Playbook Directory Structure

```
playbooks/
├── cluster/
│   ├── k3s-deploy.yml        — provision K3s server and agent nodes
│   └── services-deploy.yml   — deploy Helm, Traefik, Wireguard to cluster
├── compute/
│   └── edge-deploy.yml       — install Cloudflared systemd service on CM5 edge device
├── network/
│   └── network-deploy.yml    — manage OPNsense router via REST API
└── utilities/
    ├── check_hosts.yml        — ping all managed hosts and report online/offline
    ├── disk-health.yml        — enumerate NVMe drives and report capacity per node
    ├── read-k3s-token.yml     — read K3s join token from server node
    └── test-join-cmd.yml      — print K3s agent join command for manual use
```

## Inventory Groups

| Group | Members | Notes |
|-------|---------|-------|
| `servers` | node1, node2 | K3s server nodes (10.1.20.11–.12) |
| `agents` | node3, node4 | K3s agent nodes (10.1.20.13–.14) |
| `cluster` | servers + agents | Full K3s cluster |
| `compute` | edge | CM5 Cloudflared device (10.1.10.x) |

OPNsense (10.1.1.1) and unmanaged switches are documented as topology comments in `hosts.ini` — managed via `network-deploy.yml` using the `oxlorg.opnsense` REST API collection.

## Known Issue

Current playbook does not allow agents to join the cluster properly. Manual steps:

1. Stop the K3S agent if running: `sudo systemctl stop k3s-agent`
2. Uninstall K3S: `sudo k3s-killall.sh` then `sudo rm -rf /var/lib/rancher/k3s /var/lib/kubelet /etc/rancher/k3s`
3. Reboot: `sudo reboot now`
4. Run install and join command (replacing `[MASTER_IP]` and `[JOIN_TOKEN]`):
   `curl -sfL https://get.k3s.io | K3S_URL=https://[MASTER_IP]:6443 K3S_TOKEN=[JOIN_TOKEN] sh -`

## Todo

- [ ] Fix worker node joining in playbook
- [ ] Migrate to Pi ComputeBlades with AI expansion board
