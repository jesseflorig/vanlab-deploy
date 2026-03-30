# Data Model: Project Reorganization

**Feature**: 002-project-reorganization
**Date**: 2026-03-29

## Repository Structure (Target State)

```text
vanlab/
├── ansible.cfg                    # Ansible config (inventory path, defaults)
├── requirements.yml               # Collection dependencies (oxlorg.opnsense)
├── hosts.ini                      # Single inventory file
│
├── group_vars/
│   ├── all.yml                    # gitignored — ALL secrets live here
│   ├── example.all.yml            # committed — template for all.yml
│   ├── cluster.yml                # K3s vars (non-secret, committed)
│   ├── network.yml                # OPNsense connection vars (non-secret, committed)
│   └── compute.yml                # Edge device vars (non-secret, committed)
│
├── playbooks/
│   ├── cluster/
│   │   ├── k3s-deploy.yml         # moved from root
│   │   └── services-deploy.yml    # moved from root, cloudflared removed
│   ├── network/
│   │   └── network-deploy.yml     # new — OPNsense scaffold
│   ├── compute/
│   │   └── edge-deploy.yml        # new — CM5 Cloudflared deployment
│   └── utilities/
│       ├── check_hosts.yml        # moved from root
│       ├── disk-health.yml        # moved from root
│       ├── read-k3s-token.yml     # moved from utilities/
│       └── test-join-cmd.yml      # moved from utilities/
│
├── roles/
│   ├── cloudflared/               # rewritten — systemd service, not Helm
│   ├── helm/                      # unchanged
│   ├── traefik/                   # unchanged
│   ├── wireguard/                 # unchanged
│   └── disk-health/               # unchanged
│
└── specs/                         # feature documentation
```

---

## Inventory Groups

### Managed Groups

| Group | Members | Connection | Notes |
|-------|---------|------------|-------|
| `servers` | node1, node2 | SSH | K3s server nodes (replaces `masters`) |
| `agents` | node3, node5 | SSH | K3s agent nodes (replaces `workers`) |
| `cluster` | children: servers + agents | SSH | Full K3s cluster |
| `compute` | edge (CM5) | SSH | Standalone compute devices |

### Reference-Only Groups

| Group | Members | Notes |
|-------|---------|-------|
| `[network]` | router comment | OPNsense — REST API, not SSH |
| `[unmanaged]` | GS308T, GS308EPP ×3 | Web UI only — topology reference |

### OPNsense Connection

OPNsense is NOT an SSH-managed host. Network playbooks run on `localhost` and connect
to `10.1.1.1` via the `oxlorg.opnsense` REST API modules.

---

## hosts.ini Schema (Target)

```ini
# =============================================================================
# VANLAB INVENTORY
# =============================================================================

# --- K3s Cluster ---
[servers]
node1  ansible_host=10.1.20.11
node2  ansible_host=10.1.20.12

[agents]
node3  ansible_host=10.1.20.13
node5  ansible_host=10.1.20.15

[cluster:children]
servers
agents

# --- Edge Compute ---
[compute]
edge   ansible_host=10.1.10.x   # CM5 Cloudflared device

# =============================================================================
# TOPOLOGY REFERENCE (not managed by Ansible)
# =============================================================================
# OPNsense router:  10.1.1.1   — managed via REST API (network-deploy.yml)
# GS308T switch:    10.1.1.x   — web UI only
# GS308EPP switch1: 10.1.1.x   — web UI only
# GS308EPP switch2: 10.1.1.x   — web UI only
# GS308EPP switch3: 10.1.1.x   — web UI only

[all:vars]
ansible_user=fleetadmin
ansible_ssh_pass=...            # stored in group_vars/all.yml
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_python_interpreter=auto_silent
```

---

## group_vars Schema

### group_vars/example.all.yml (template — committed)

```yaml
# Secrets template — copy to group_vars/all.yml and fill in real values
# group_vars/all.yml is gitignored

cloudflare_tunnel_token: <CLOUDFLARE_TUNNEL_TOKEN>
opnsense_api_key: <OPNSENSE_API_KEY>
opnsense_api_secret: <OPNSENSE_API_SECRET>
ansible_ssh_pass: <SSH_PASSWORD>
ansible_become_pass: <SUDO_PASSWORD>
```

### group_vars/cluster.yml (committed)

```yaml
# K3s cluster configuration
k3s_master_ip: "10.1.20.11"
k3s_flannel_iface: "eth0"
```

### group_vars/network.yml (committed)

```yaml
# OPNsense connection — non-secret vars
opnsense_firewall: "10.1.1.1"
opnsense_api_verify_ssl: false
```

### group_vars/compute.yml (committed)

```yaml
# Edge compute device configuration
cloudflared_service_name: cloudflared
cloudflared_token_path: /etc/cloudflared/tunnel-token
```

---

## Role Changes

### roles/cloudflared (rewrite)

| Before | After |
|--------|-------|
| Helm chart deployment to K8s | systemd service on CM5 host |
| Requires `kubectl`, `helm` | Requires only `apt`, `systemd` |
| Runs in K3s namespace | Runs as OS service on `10.1.10.x` |
| Cluster-dependent | Cluster-independent |
| Token passed via Helm `--set` | Token stored in `/etc/cloudflared/tunnel-token` (mode 0600) |

### Deprecated

The `[edge]` inventory group (was `node2`) and the `edge` play in `services-deploy.yml`
are removed. `traefik` is moved to the `servers` play in `services-deploy.yml`.
