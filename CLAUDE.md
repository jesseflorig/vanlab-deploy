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
- Longhorn `storageClass: longhorn` — Mosquitto: 1Gi, HA: 10Gi, Node-RED: 5Gi, InfluxDB: 20Gi (016-home-automation-stack)

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
- 016-home-automation-stack: Added YAML (Ansible 2.x) — follows existing project conventions
- 014-loki-log-shipping: Added YAML (Ansible 2.x) — follows existing project conventions
- 009-prometheus-longhorn-monitoring: Added YAML (Ansible 2.x) — existing project conventions + `prometheus-community/kube-prometheus-stack` Helm chart; Longhorn (already deployed)


<!-- MANUAL ADDITIONS START -->

## File Editing

- Always use the `Edit` tool to modify existing files. NEVER use `sed`, `awk`, or shell
  redirection to patch file content — not even as a fallback after a failed `Edit` attempt.
- If an `Edit` fails because the `old_string` is not found, the correct response is to re-read
  the file, find the exact text (mind whitespace, indentation, and line endings), and retry
  the `Edit` with corrected context. Do not switch to a Bash-based workaround.
- Before editing any file, read the section you plan to change. Never edit from memory.

## Git Workflow

- NEVER commit or push directly to `main`.
- ALL work MUST happen on a feature branch named `NNN-short-description`
  (e.g., `017-argocd-gitops`), branched from current `main`.
- Commit work on the branch, then merge to `main` only when the work is complete.
- After merging to `main`, push both `gitea` and `origin` remotes:
  ```bash
  git push gitea main && git push origin main
  ```
- Delete the feature branch locally after a successful merge.

<!-- MANUAL ADDITIONS END -->
