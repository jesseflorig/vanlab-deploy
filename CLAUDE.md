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

- NEVER commit directly to `main` or merge feature branches into local `main`.
- ALL work MUST happen on a feature branch named `NNN-short-description`
  (e.g., `017-argocd-gitops`), branched from current `main`.
- Local `main` is a read-only mirror — only ever updated via `git pull` after a
  remote merge completes.

**Branch lifecycle:**

1. Branch from `main`: `git checkout -b NNN-short-description`
2. Commit work on the branch.
3. Push branch to both remotes:
   ```bash
   git push gitea NNN-short-description
   git push origin NNN-short-description
   ```
4. Merge into Gitea `main` via API (Gitea enforces server-side branch protection):
   ```bash
   # Create PR
   curl -sk -X POST "https://10.1.20.11:30443/api/v1/repos/gitadmin/vanlab/pulls" \
     -H "Host: gitea.fleet1.cloud" -u "gitadmin:$GITEA_PASS" \
     -H "Content-Type: application/json" \
     -d '{"title":"...","head":"NNN-short-description","base":"main"}'
   # Merge PR (use PR number from response)
   curl -sk -X POST "https://10.1.20.11:30443/api/v1/repos/gitadmin/vanlab/pulls/N/merge" \
     -H "Host: gitea.fleet1.cloud" -u "gitadmin:$GITEA_PASS" \
     -H "Content-Type: application/json" \
     -d '{"Do":"merge"}'
   ```
5. Pull the merged `main` locally and update GitHub mirror:
   ```bash
   git checkout main && git pull gitea main
   git push origin main
   ```
6. Delete the feature branch locally and on Gitea:
   ```bash
   git branch -d NNN-short-description
   curl -sk -X DELETE "https://10.1.20.11:30443/api/v1/repos/gitadmin/vanlab/branches/NNN-short-description" \
     -H "Host: gitea.fleet1.cloud" -u "gitadmin:$GITEA_PASS"
   ```

<!-- MANUAL ADDITIONS END -->
