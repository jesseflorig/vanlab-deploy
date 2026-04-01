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
| `servers` | node1, node3 | K3s control-plane + etcd nodes (10.1.20.11, .13) |
| `agents` | node2, node4 | K3s worker nodes (10.1.20.12, .14) |
| `cluster` | servers + agents | Full K3s cluster |
| `compute` | edge | CM5 Cloudflared device (10.1.10.x) |

OPNsense (10.1.1.1) and unmanaged switches are documented as topology comments in `hosts.ini` — managed via `network-deploy.yml` using the `oxlorg.opnsense` REST API collection.

### etcd Topology

The cluster uses K3s embedded etcd. Server count **must be odd** (1, 3, or 5) for quorum:

| Servers | Fault tolerance |
|---------|----------------|
| 1 | None — any failure = cluster down |
| 3 | 1 node |
| 5 | 2 nodes |

The first entry in `[servers]` initializes the etcd cluster (`--cluster-init`). Additional entries join the quorum automatically on the next `k3s-deploy.yml` run.

### Promoting a node from agent to server

1. Move the node from `[agents]` to `[servers]` in `hosts.ini`
2. Uninstall the agent: `ansible <node> -i hosts.ini -m shell -a "k3s-agent-uninstall.sh" --become`
3. Re-run: `ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml`
4. Verify: `kubectl get nodes` — promoted node shows `control-plane,etcd` role

## Cluster Rebuild (etcd Migration)

A full rebuild is required when migrating datastores or recovering from total cluster loss. All Longhorn PVC data is lost — ensure the Gitea repo is up to date before starting (ArgoCD restores apps automatically).

```bash
# 1. Uninstall agents
ansible agents -i hosts.ini -m shell -a "k3s-agent-uninstall.sh" --become

# 2. Uninstall server(s)
ansible servers -i hosts.ini -m shell -a "k3s-uninstall.sh" --become

# 3. Deploy etcd-backed cluster (~3 min)
ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml

# 4. Deploy all services (~10 min, includes cert issuance)
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml

# 5. Bootstrap GitOps (after creating a new Gitea PAT in group_vars/all.yml)
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap
```

Total rebuild time: ~15–20 minutes. ArgoCD syncs apps from Gitea automatically within 3 minutes of coming online.

## GitOps

The cluster runs ArgoCD backed by a self-hosted Gitea instance for fully declarative application delivery.

### Deployment workflow

1. Add Gitea and ArgoCD secret values to `group_vars/all.yml`:

   ```yaml
   gitea_admin_username: admin
   gitea_admin_password: <password>
   gitea_admin_email: <email>
   argocd_admin_password_bcrypt: <bcrypt-hash>
   gitea_argocd_token: <gitea-pat>
   ```

   Generate the ArgoCD bcrypt hash:

   ```bash
   htpasswd -nbBC 10 "" <password> | tr -d ':\n' | sed 's/$2y/$2a/'
   ```

2. Run the full services playbook:

   ```bash
   ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass
   ```

3. Access the dashboards at `https://gitea.fleet1.cloud` and `https://argocd.fleet1.cloud`.

### Registering a new application

Add an entry to `argocd_apps` in `group_vars/all.yml`:

```yaml
argocd_apps:
  - name: my-service
    repo: org/repo          # Gitea org/repo path
    path: .                 # path within the repo containing manifests or Helm chart
    namespace: my-service   # destination namespace
    revision: main          # branch, tag, or commit SHA
```

Then re-run only the bootstrap role:

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap --ask-become-pass
```

### Rollback procedure

ArgoCD continuously reconciles the cluster to match the desired state in Gitea. To roll back a bad deployment:

1. Revert the commit in Gitea (via the Gitea web UI or `git revert` + push).
2. ArgoCD detects the change and automatically re-syncs within 3 minutes.
3. Verify the application returns to `Synced/Healthy`:

   ```bash
   kubectl get applications -n argocd
   ```

No direct `kubectl` intervention is required — the Git history is the source of truth.

### Smoke test

Verify the full GitOps stack is healthy after deployment:

```bash
ansible-playbook -i hosts.ini playbooks/cluster/argocd-smoke-test.yml --ask-become-pass
```

