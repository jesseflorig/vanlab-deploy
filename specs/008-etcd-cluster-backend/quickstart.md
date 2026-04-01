# Quickstart: etcd Cluster Backend Migration

**Branch**: `008-etcd-cluster-backend` | **Date**: 2026-04-01

## Prerequisites

- All nodes reachable via Ansible (`ansible all -i hosts.ini -m ping`)
- `group_vars/all.yml` present with `ansible_ssh_pass` and `ansible_become_pass`
- Gitea repo is up to date (all manifests pushed) — GitOps will restore apps after rebuild
- Longhorn data acknowledged as lost — take manual backups of any PVC data if needed

## Migration Steps

### Step 1: Uninstall K3s on all nodes

```bash
# Uninstall agents first
ansible agents -i hosts.ini -m shell -a "k3s-agent-uninstall.sh" --become

# Then uninstall server
ansible servers -i hosts.ini -m shell -a "k3s-uninstall.sh" --become
```

### Step 2: Deploy etcd-backed K3s

```bash
ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml
```

node1 will initialize the etcd cluster with `--cluster-init`. Any additional entries
under `[servers]` in `hosts.ini` will join the etcd quorum automatically.

### Step 3: Deploy services

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml
```

### Step 4: Verify cluster

```bash
# Check all nodes Ready
ansible node1 -i hosts.ini -m shell -a "kubectl get nodes -o wide" --become

# Check etcd member list (confirms etcd is in use)
ansible node1 -i hosts.ini -m shell -a "kubectl -n kube-system exec etcd-node1 -- etcdctl member list --endpoints=https://127.0.0.1:2379 --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt --cert=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt --key=/var/lib/rancher/k3s/server/tls/etcd/server-client.key" --become
```

### Step 5: Monitor ArgoCD sync

ArgoCD will automatically sync all apps from Gitea within ~3 minutes of coming online.
Monitor at `https://argocd.fleet1.cloud`.

## Adding a New Node (Post-Migration)

1. Add node to `hosts.ini` under `[agents]` (or `[servers]` for control plane)
2. Re-run `k3s-deploy.yml` — existing nodes are no-op, new node joins automatically
3. Verify with `kubectl get nodes`

## Promoting a Node to Control Plane (Future)

1. SSH to the node and run `k3s-agent-uninstall.sh`
2. Move node from `[agents]` to `[servers]` in `hosts.ini`
3. Re-run `k3s-deploy.yml` — node installs as server and joins etcd quorum
4. Verify with `kubectl get nodes` — node should show `control-plane` role
