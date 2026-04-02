# vanlab Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-02

## Active Technologies
- YAML (Ansible 2.x) — existing project conventions (002-project-reorganization)
- N/A — no persistent storage required (004-static-site-tls)
- YAML (Ansible 2.x) — existing project conventions + Longhorn Helm chart v1.11.1 (`https://charts.longhorn.io`), open-iscsi, nfs-common (006-longhorn-storage)
- Longhorn itself — uses `/var/lib/longhorn` on each node's local NVMe disk (006-longhorn-storage)
- YAML (Ansible 2.x) — existing project conventions + K3s (already installed), embedded etcd (bundled with K3s — no separate install) (008-etcd-cluster-backend)
- N/A — etcd state stored at `/var/lib/rancher/k3s/server/db/` on server nodes (008-etcd-cluster-backend)
- YAML (Ansible 2.x) — existing project conventions + `prometheus-community/kube-prometheus-stack` Helm chart; Longhorn (already deployed) (009-prometheus-longhorn-monitoring)
- Longhorn `storageClassName: longhorn` — Prometheus 20Gi, Grafana 5Gi, Alertmanager 5Gi (009-prometheus-longhorn-monitoring)
- Longhorn `storageClass: longhorn` — Loki 20Gi PVC (014-loki-log-shipping)

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
- 014-loki-log-shipping: Added YAML (Ansible 2.x) — follows existing project conventions
- 009-prometheus-longhorn-monitoring: Added YAML (Ansible 2.x) — existing project conventions + `prometheus-community/kube-prometheus-stack` Helm chart; Longhorn (already deployed)
- 008-etcd-cluster-backend: Added YAML (Ansible 2.x) — existing project conventions + K3s (already installed), embedded etcd (bundled with K3s — no separate install)


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
