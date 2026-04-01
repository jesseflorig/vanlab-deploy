# Research: etcd Cluster Backend

**Branch**: `008-etcd-cluster-backend` | **Date**: 2026-04-01

## Current Cluster State

- **Server nodes**: 1 (node1 — `10.1.20.11`)
- **Agent nodes**: 3 (node2–4 — `10.1.20.12–14`)
- **Commented-out**: node5, node6 (available for future expansion)
- **K3s install flags today**: `--disable traefik --disable local-storage --write-kubeconfig-mode 600 --flannel-iface=eth0`
- **No multi-server logic** in the current playbook — all servers get the same install command, and no `--cluster-init` is passed.

---

## Decision 1: First Server vs Additional Server Install Flags

**Decision**: Use `--cluster-init` on the first server only; additional servers join via `K3S_URL` + `K3S_TOKEN`.

**Rationale**: K3s embedded etcd is initialized with `--cluster-init` on exactly one node. Subsequent server nodes join the existing cluster using the same environment variables as agent nodes (`K3S_URL`, `K3S_TOKEN`) but without the agent install path — the installer detects server role from the presence of server-specific flags. Passing `--cluster-init` on a second server would create a split-brain cluster.

**First server command**:
```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="--cluster-init --disable traefik --disable local-storage \
    --write-kubeconfig-mode 600 --flannel-iface={{ k3s_flannel_iface }}" sh -
```

**Additional server command**:
```bash
curl -sfL https://get.k3s.io | \
  K3S_URL="https://{{ k3s_master_ip }}:6443" \
  K3S_TOKEN="{{ k3s_node_token }}" \
  INSTALL_K3S_EXEC="--disable traefik --disable local-storage \
    --write-kubeconfig-mode 600 --flannel-iface={{ k3s_flannel_iface }}" sh -
```

Note: `--datastore-endpoint` is NOT used for embedded etcd — that flag is for external etcd clusters. Embedded etcd is managed entirely by K3s.

**Alternatives considered**: External etcd cluster (separate etcd processes on each node) — rejected as unnecessary complexity for a homelab (Principle V).

---

## Decision 2: Migration Path — Clean Rebuild Required

**Decision**: No in-place SQLite → etcd migration; a clean rebuild is the only supported path.

**Rationale**: K3s has no native tool to convert an embedded SQLite datastore to embedded etcd. The data formats and cluster identity are incompatible. Attempting an in-place conversion risks data corruption.

**Migration procedure**:
1. Back up Gitea and Longhorn data (PVC snapshots) before starting.
2. Export ArgoCD application definitions from Gitea — they are already in the Git repo, so no extra step needed.
3. Uninstall K3s on all nodes (`k3s-uninstall.sh` on servers, `k3s-agent-uninstall.sh` on agents).
4. Re-run `k3s-deploy.yml` — node1 gets `--cluster-init`, agents rejoin.
5. Re-run `services-deploy.yml` to reinstall Helm services.
6. ArgoCD syncs application manifests from Gitea automatically.

Since all application state lives in Gitea (GitOps) and all infrastructure is Ansible-managed, the rebuild is largely automated. Longhorn data (PVCs) will be lost — this is documented in the spec assumptions.

**Alternatives considered**: Parallel cluster with DNS cutover — rejected as unnecessary for a homelab without uptime SLAs.

---

## Decision 3: Single Server Node with Embedded etcd

**Decision**: A single server node with `--cluster-init` is a valid starting point; it provides no fault tolerance but is fully supported and upgradeable to 3 nodes later.

**Rationale**: etcd can run as a cluster of 1. The node always has quorum with itself. There is no meaningful difference in day-to-day operation compared to SQLite from the workload perspective. The key benefit over SQLite is that K3s supports adding additional server nodes to an etcd cluster — you can go from 1 → 3 servers without a rebuild.

**Quorum reference**:
- 1 server: 0 fault tolerance (any failure = cluster down)
- 3 servers: 1 fault tolerance (can lose 1 node)
- 5 servers: 2 fault tolerance

**Recommendation**: Start with 1 server (current topology), expand to 3 when nodes are available by promoting agents via `hosts.ini` reassignment + playbook re-run.

---

## Decision 4: Idempotency Guard

**Decision**: Wrap the `--cluster-init` install in a `creates:` guard on `/etc/systemd/system/k3s.service` (same as today). Additional server installs also get a `creates:` guard. Promote-in-place (agent → server) is out of scope for this feature; it requires K3s uninstall first.

**Rationale**: The current agent install already uses a `when:` guard on service state. The server install uses `creates:`. Both patterns are idempotent — re-running the playbook against an already-installed node is a no-op.

---

## Decision 5: etcd Snapshot Backup

**Decision**: Out of scope for this feature. K3s automatically creates etcd snapshots at `/var/lib/rancher/k3s/server/db/snapshots/` every 12 hours (default), retaining the last 5. This is sufficient for a homelab and requires no additional configuration.

**Rationale**: Adding a backup automation feature adds scope beyond "convert to etcd." The snapshot directory can be addressed in a future feature if off-cluster storage is needed.

---

## Playbook Change Summary

| Area | Current | Required Change |
|------|---------|-----------------|
| First server install | No `--cluster-init` | Add `--cluster-init` flag |
| Additional server install | Not handled | New task block for `groups['servers'][1:]` |
| Agent install | Uses `when:` service guard | No change |
| Idempotency guard | `creates:` on service file | No change |
| `hosts.ini` | Supports multiple `[servers]` entries already | No change — Ansible handles it |
| `group_vars` | `k3s_master_ip`, `k3s_flannel_iface` | No new variables required |
