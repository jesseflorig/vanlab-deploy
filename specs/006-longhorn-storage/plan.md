# Implementation Plan: Longhorn Distributed Block Storage

**Branch**: `006-longhorn-storage` | **Date**: 2026-03-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/006-longhorn-storage/spec.md`

## Summary

Deploy Longhorn v1.11.1 as the default StorageClass on the vanlab K3s cluster. Install node prerequisites (open-iscsi, nfs-common, iscsi_tcp module) on all nodes, disable the K3s built-in `local-path` addon durably via `/etc/rancher/k3s/config.yaml`, and install Longhorn via the official Helm chart with 2-replica default and `Retain` reclaim policy.

## Technical Context

**Language/Version**: YAML (Ansible 2.x) — existing project conventions
**Primary Dependencies**: Longhorn Helm chart v1.11.1 (`https://charts.longhorn.io`), open-iscsi, nfs-common
**Storage**: Longhorn itself — uses `/var/lib/longhorn` on each node's local NVMe disk
**Testing**: kubectl PVC smoke test (PVC bind + pod write + pod reschedule + data verify)
**Target Platform**: K3s on Raspberry Pi CM5, arm64 Debian Bookworm
**Project Type**: Infrastructure role/playbook
**Performance Goals**: PVC bind within 60s; pod reschedule + volume reattach within 120s
**Constraints**: All 6 nodes must run Longhorn DaemonSet; replica count ≥ 2 for durability
**Scale/Scope**: 6-node cluster; NVMe 2TB storage per node; ~12TB raw capacity

## Constitution Check

| Principle | Status | Notes |
|---|---|---|
| I. Infrastructure as Code | ✅ PASS | All changes via Ansible roles + Helm chart |
| II. Idempotency | ✅ PASS | Helm `upgrade --install`; K3s config write is idempotent; `state: present` for packages/services |
| III. Reproducibility | ✅ PASS | Full install reproducible from `services-deploy.yml` |
| IV. Secrets Hygiene | ✅ PASS | No secrets involved in Longhorn installation |
| V. Simplicity | ✅ PASS | Official Helm chart; two focused roles; no custom operators |
| VI. Encryption in Transit | ✅ PASS | Longhorn is cluster-internal; crosses no VLAN boundary |
| VII. Least Privilege | ✅ N/A | No MQTT/client-cert concerns |

## Project Structure

### Documentation (this feature)

```text
specs/006-longhorn-storage/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
roles/
├── longhorn-prereqs/
│   └── tasks/main.yml          # packages, services, iscsi_tcp module, multipathd — runs on ALL nodes
└── longhorn/
    ├── defaults/main.yml        # longhorn_version, longhorn_namespace, longhorn_data_path
    ├── files/values.yaml        # Helm values (replica count, defaultClass, CSI settings)
    ├── handlers/main.yml        # Restart K3s server
    └── tasks/main.yml           # K3s config disable, Helm install, waits

playbooks/cluster/
├── k3s-deploy.yml               # MODIFIED: add --disable local-storage to INSTALL_K3S_EXEC
└── services-deploy.yml          # MODIFIED: add longhorn-prereqs play + longhorn role
```

**Structure Decision**: Two-role pattern: `longhorn-prereqs` (runs on all cluster nodes) and `longhorn` (runs on servers only). This mirrors the existing separation between cluster-wide node prep and server-only Helm installs. `services-deploy.yml` gains a new pre-play targeting `hosts: cluster`.

## Implementation Notes

### Role: longhorn-prereqs (hosts: cluster — all nodes)

Tasks:
1. Install `open-iscsi`, `nfs-common`, `util-linux` via apt
2. Enable + start `iscsid` service
3. Enable + start `open-iscsi` service
4. Write `/etc/modules-load.d/longhorn.conf` with `iscsi_tcp`
5. Load `iscsi_tcp` module immediately via modprobe
6. Disable + stop `multipathd` (ignore_errors: true — may not be installed)
7. Verify `/etc/iscsi/initiatorname.iscsi` exists (fail if missing)

### Role: longhorn (hosts: servers)

Tasks:
1. Write `/etc/rancher/k3s/config.yaml` with `disable: [local-storage]` — notify handler
2. Handler: Restart K3s server + wait for API readiness
3. Wait for `local-path` StorageClass to be absent (retries with kubectl get)
4. Helm repo add `longhorn https://charts.longhorn.io` (idempotent)
5. Helm repo update
6. Copy `files/values.yaml` to `/tmp/longhorn-values.yaml`
7. `helm upgrade --install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace --values /tmp/longhorn-values.yaml --version {{ longhorn_version }} --timeout 5m`
8. `kubectl rollout status daemonset/longhorn-manager -n longhorn-system --timeout=10m`
9. `kubectl rollout status daemonset/longhorn-csi-plugin -n longhorn-system --timeout=10m`
10. `kubectl rollout status deployment/longhorn-ui -n longhorn-system --timeout=5m`
11. `kubectl rollout status deployment/longhorn-driver-deployer -n longhorn-system --timeout=5m`
12. `kubectl rollout status deployment/csi-attacher -n longhorn-system --timeout=5m`
13. `kubectl rollout status deployment/csi-provisioner -n longhorn-system --timeout=5m`
14. Display storage node count

### Helm values.yaml

```yaml
persistence:
  defaultClass: true
  defaultClassReplicaCount: 2
  reclaimPolicy: Retain

defaultSettings:
  defaultReplicaCount: 2
  defaultDataPath: /var/lib/longhorn
  replicaSoftAntiAffinity: true
  storageOverProvisioningPercentage: 200
  storageMinimalAvailablePercentage: 10
  upgradeChecker: false
  autoSalvage: true
  disableSchedulingOnCordonedNode: true
  replicaZoneSoftAntiAffinity: true

csi:
  attacherReplicaCount: 3
  provisionerReplicaCount: 3
  resizerReplicaCount: 3
  snapshotterReplicaCount: 3
```

Note: `csi.kubeletRootDir` omitted — modern K3s uses `/var/lib/kubelet` which Longhorn auto-detects. Add explicitly if CSI plugin fails to register.

### Modification: k3s-deploy.yml

Add `--disable local-storage` to `INSTALL_K3S_EXEC` on the K3s server install task (line 89) alongside `--disable traefik`. This ensures fresh installs never have `local-path` as default.

### Modification: services-deploy.yml

Add a new play before the existing `Install Host Tools` play:

```yaml
- name: Install Longhorn node prerequisites
  hosts: cluster
  become: true
  roles:
    - longhorn-prereqs
```

Add `longhorn` to the existing `Install Host Tools` play's roles list (after `helm`, before or after `traefik`).

## Complexity Tracking

No Constitution violations. No complexity justification required.
