# vanlab Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-01

## Active Technologies
- YAML (Ansible 2.x) — existing project conventions (002-project-reorganization)
- N/A — no persistent storage required (004-static-site-tls)
- YAML (Ansible 2.x) — existing project conventions + Longhorn Helm chart v1.11.1 (`https://charts.longhorn.io`), open-iscsi, nfs-common (006-longhorn-storage)
- Longhorn itself — uses `/var/lib/longhorn` on each node's local NVMe disk (006-longhorn-storage)
- YAML (Ansible 2.x) — existing project conventions + K3s (already installed), embedded etcd (bundled with K3s — no separate install) (008-etcd-cluster-backend)
- N/A — etcd state stored at `/var/lib/rancher/k3s/server/db/` on server nodes (008-etcd-cluster-backend)

- YAML (Ansible 2.x) — follows existing project conventions + `smartmontools` (apt) — installed idempotently by the playbook as a (001-node-disk-health)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for YAML (Ansible 2.x) — follows existing project conventions

## Code Style

YAML (Ansible 2.x) — follows existing project conventions: Follow standard conventions

## Recent Changes
- 008-etcd-cluster-backend: Added YAML (Ansible 2.x) — existing project conventions + K3s (already installed), embedded etcd (bundled with K3s — no separate install)
- 005-argocd-gitops: Added [if applicable, e.g., PostgreSQL, CoreData, files or N/A]
- 006-longhorn-storage: Added YAML (Ansible 2.x) — existing project conventions + Longhorn Helm chart v1.11.1 (`https://charts.longhorn.io`), open-iscsi, nfs-common


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
