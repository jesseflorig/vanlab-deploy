# Data Model: etcd Cluster Backend

**Branch**: `008-etcd-cluster-backend` | **Date**: 2026-04-01

This feature is infrastructure automation — there is no application data model. The relevant
"entities" are Ansible inventory groups and K3s node roles.

## Cluster Topology Entities

### Server Node (Control Plane)

Defined under `[servers]` in `hosts.ini`.

| Attribute | Value |
|-----------|-------|
| Role | K3s server (control plane + etcd member) |
| First node | Installs with `--cluster-init`; initializes etcd |
| Additional nodes | Join via `K3S_URL` + `K3S_TOKEN`; extend etcd quorum |
| Minimum count | 1 (no HA); 3 for fault tolerance |
| Must be odd | Yes — etcd quorum requires majority vote |

### Agent Node (Worker)

Defined under `[agents]` in `hosts.ini`.

| Attribute | Value |
|-----------|-------|
| Role | K3s agent (workload scheduling only) |
| Joins via | `K3S_URL` + `K3S_TOKEN` pointing at first server |
| etcd participation | None — agents do not join the etcd cluster |
| Behavior change | None from current implementation |

## State Transitions

```
bare node
    │
    ▼ (k3s-deploy.yml — first server)
etcd initializer (--cluster-init)
    │
    ▼ (k3s-deploy.yml — additional servers, when groups['servers'] > 1)
etcd quorum member (joins existing cluster)

bare node
    │
    ▼ (k3s-deploy.yml — agents, unchanged)
agent worker
```

## Promote Agent → Server (Future / Out of Scope)

Requires: uninstall K3s agent, move node from `[agents]` to `[servers]` in `hosts.ini`,
re-run k3s-deploy.yml. Not automated in this feature.
