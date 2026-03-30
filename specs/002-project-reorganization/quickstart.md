# Quickstart: Project Reorganization

## Prerequisites

- `group_vars/all.yml` exists with all secrets (see `group_vars/example.all.yml`)
- OPNsense `os-api` plugin enabled and API key generated
- CM5 edge device provisioned with Raspberry Pi OS, reachable at `10.1.10.x`
- Ansible collections installed: `ansible-galaxy collection install -r requirements.yml`

## Verify All Devices Are Reachable

```bash
ansible-playbook -i hosts.ini playbooks/utilities/check_hosts.yml --ask-become-pass
```

Expected: all cluster nodes, edge device respond ONLINE. OPNsense and switches
appear in topology comments — not checked here.

## Deploy K3s Cluster

```bash
ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml --ask-become-pass
```

## Deploy Cluster Services

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass
```

## Deploy Edge Device (Cloudflared)

```bash
ansible-playbook -i hosts.ini playbooks/compute/edge-deploy.yml --ask-become-pass
```

Verify tunnel is active after deployment:
```bash
# SSH to edge device and check service
ssh fleetadmin@10.1.10.x "sudo systemctl status cloudflared"
```

## Verify OPNsense Connectivity

```bash
ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml --check
```

Running in `--check` mode verifies API connectivity without making any changes.

## Run Disk Health Check

```bash
ansible-playbook -i hosts.ini playbooks/utilities/disk-health.yml --ask-become-pass
```

## Install Collections

Run once after cloning the repository (or when `requirements.yml` changes):

```bash
ansible-galaxy collection install -r requirements.yml
```
