# Research: Rack Shutdown Playbook

**Feature**: 040-rack-shutdown-script  
**Date**: 2026-04-16

## Findings

---

### Decision 1: Ansible pattern for SSH loss on OPNsense shutdown

**Decision**: `async: 5, poll: 0` on the shutdown task, combined with `ignore_unreachable: true`

**Rationale**: `async: X, poll: 0` (fire-and-forget) causes Ansible to start the task and immediately move on without waiting for a response. The SSH connection drops when OPNsense halts, but Ansible has already exited the task and marked it as started. `ignore_unreachable: true` is defensive — if the shutdown is fast enough that Ansible's TCP teardown triggers before async completes, the error is silenced. This exact pattern (`async: 5, poll: 0`) is already established in the project at `playbooks/utilities/drain-shutdown.yml:44-48`.

**Alternatives considered**:
- `ignore_errors: true` alone — waits for the task to return; if SSH drops mid-wait, marks it unreachable/failed
- `nohup shutdown -h now &` — adds shell complexity; async handles the timing natively
- `at now` — requires atd running on the target; unnecessary on OPNsense (FreeBSD)

**FreeBSD note**: `shutdown -h now` is valid on OPNsense/FreeBSD. No changes to the async pattern needed.

---

### Decision 2: kubectl drain strategy for full rack shutdown

**Decision**: Run kubectl from `servers[0]` (a cluster node), using the established project pattern in `drain-shutdown.yml`. Do NOT delegate to localhost.

**Rationale**: The existing `drain-shutdown.yml` runs kubectl from a server node using `/etc/rancher/k3s/k3s.yaml`. This is the proven project pattern. The operator's workstation kubeconfig was cited as available during clarification, but reusing the server-side pattern avoids introducing a new assumption and is consistent with the existing utility. For agents (6 nodes), all drains run from `servers[0]`. For server drains, each is drained from a peer that is still running.

**Server drain sequencing** (3 servers: node1, node3, node5):
1. Drain node1 from node3 → shutdown node1 (etcd: 3→2 nodes, quorum maintained)
2. Drain node3 from node5 → shutdown node3 (etcd: 2→1 nodes, quorum lost — acceptable, shutdown in progress)
3. Stop k3s on node5 → shutdown node5 (no drain destination; k3s stop flushes etcd snapshot)

**Essential kubectl drain flags** (match existing project usage):
- `--ignore-daemonsets` — mandatory; DaemonSets (Longhorn, Prometheus agents) are not evicted
- `--delete-emptydir-data` — mandatory; prevents drain hanging on emptyDir pods
- `--timeout=600s` — 10 minutes; matches existing project default

**Alternatives considered**:
- Delegate to localhost — viable but diverges from established project pattern; requires workstation kubeconfig to be current
- Parallel drain — faster but risks Longhorn replica rebalancing during drain; serial is safer

---

### Decision 3: K3s graceful shutdown sequence

**Decision**: `systemctl stop k3s` (or `k3s-agent`) → then `shutdown -h now` with `async: 5, poll: 0`

**Rationale**: K3s flushes its embedded etcd state on graceful `systemctl stop`. No additional wait is needed between stopping K3s and issuing OS halt — the systemd unit stop is synchronous and blocks until the process exits. The research in `specs/008-etcd-cluster-backend/research.md` confirms K3s embedded etcd snapshots automatically (every 12 hours, last 5 retained) and that etcd can run with a single node (no quorum loss risk for the shutdown itself).

**Node service names**:
- Agent nodes: `k3s-agent`
- Server nodes: `k3s`

---

### Decision 4: Longhorn pre-flight health check

**Decision**: Query `volumes.longhorn.io` CRD via kubectl for volumes where `status.robustness != "healthy"`. Warn and continue (do not abort).

**Rationale**: The spec explicitly chose "warn and proceed" for pre-flight failures. Running a full-rack shutdown because something is wrong is a valid use case; halting the shutdown because the cluster is unhealthy would be counterproductive.

**Check command** (delegated to localhost or run from servers[0]):
```bash
kubectl get volumes.longhorn.io -n longhorn-system \
  -o jsonpath='{range .items[?(@.status.robustness!="healthy")]}{.metadata.name}{"\t"}{.status.robustness}{"\n"}{end}'
```

Returns nothing if all volumes healthy; returns name+state for any degraded volumes.

---

### Discovery: OPNsense not in hosts.ini

**Finding**: OPNsense (`10.1.1.1`) is listed in `hosts.ini` only as a topology comment — it has no inventory group. The project manages OPNsense via the `community.opnsense` REST API (see `network-deploy.yml`).

**Decision**: Add OPNsense to `hosts.ini` under a new `[network]` group for SSH-based shutdown. This is additive — the REST API plays remain unchanged for configuration management. SSH credentials for OPNsense must be in `group_vars/all.yml` (untracked) and NOT in `hosts.ini` plaintext.

**OPNsense SSH user**: OPNsense defaults to `root` for SSH. The shutdown playbook will use `ansible_user=root` scoped to the `[network]` group via `group_vars/network.yml` (untracked) rather than hardcoding in `hosts.ini`.

---

### Discovery: drain-shutdown.yml reuse

**Finding**: `playbooks/utilities/drain-shutdown.yml` already implements the drain+shutdown pattern for a single node. The new `rack-shutdown.yml` is a different concern (full rack, sequenced) and should NOT reuse it — calling a playbook from a playbook is non-standard Ansible. Write `rack-shutdown.yml` as a self-contained playbook that incorporates the same patterns directly.
