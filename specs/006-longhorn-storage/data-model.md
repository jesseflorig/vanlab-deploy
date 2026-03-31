# Data Model: Longhorn Distributed Block Storage

**Feature**: 006-longhorn-storage
**Date**: 2026-03-31

This feature does not introduce application-level data entities. The entities below describe Longhorn's configuration model as expressed via Helm values and Kubernetes resources.

---

## StorageClass (longhorn)

The cluster-wide default storage provisioner entry point.

| Field | Value | Notes |
|---|---|---|
| `name` | `longhorn` | Created by Helm chart |
| `provisioner` | `driver.longhorn.io` | Longhorn CSI driver |
| `is-default-class` | `true` | Displaces K3s `local-path` default |
| `reclaimPolicy` | `Retain` | Volumes not deleted when PVC deleted |
| `volumeBindingMode` | `Immediate` | PVC bound on creation |
| `numberOfReplicas` | `2` | Per-volume replica count |
| `dataLocality` | unset | Replicas distributed across nodes |

---

## Longhorn Settings (global defaults)

Managed via Longhorn's `settings.longhorn.io` CRD and seeded by Helm values.

| Setting | Value | Notes |
|---|---|---|
| `defaultReplicaCount` | `2` | Applies to all volumes not using StorageClass param |
| `defaultDataPath` | `/var/lib/longhorn` | Storage directory on each node |
| `storageOverProvisioningPercentage` | `200` | Allow 2× over-provisioning |
| `storageMinimalAvailablePercentage` | `10` | Reserve 10% per node — below this, no new replicas scheduled |
| `autoSalvage` | `true` | Auto-recover volumes after node failure |
| `upgradeChecker` | `false` | Disable call-home |
| `disableSchedulingOnCordonedNode` | `true` | No new replicas on cordoned nodes |
| `replicaSoftAntiAffinity` | `true` | Allow same-zone placement if needed |

---

## Node Prerequisite State

Required state on every cluster node before Longhorn DaemonSet can function.

| Component | Required State |
|---|---|
| `open-iscsi` package | Installed |
| `nfs-common` package | Installed |
| `iscsid` service | Enabled + running |
| `open-iscsi` service | Enabled + running |
| `iscsi_tcp` kernel module | Loaded (immediate + persisted via modules-load.d) |
| `/etc/iscsi/initiatorname.iscsi` | Exists |
| `multipathd` service | Disabled + stopped |

---

## K3s Server Configuration

Required addition to `/etc/rancher/k3s/config.yaml` on server nodes.

```yaml
disable:
  - local-storage
```

This causes K3s to remove the `local-path` StorageClass and provisioner Deployment, and prevents re-applying them on server restart.

---

## K3s Install Args (fresh installs)

`INSTALL_K3S_EXEC` in `playbooks/cluster/k3s-deploy.yml` must include `--disable local-storage` alongside the existing `--disable traefik`.

---

## File Layout (this feature)

```text
roles/longhorn/
├── defaults/main.yml       # version, namespace, data path
├── files/values.yaml       # Helm values
├── tasks/main.yml          # prereqs + StorageClass displacement + Helm install + waits
└── handlers/main.yml       # Restart K3s server

roles/longhorn-prereqs/
└── tasks/main.yml          # packages, services, modules, multipathd — runs on all nodes

playbooks/cluster/
├── k3s-deploy.yml          # modified: add --disable local-storage to INSTALL_K3S_EXEC
└── services-deploy.yml     # modified: add longhorn-prereqs play (all nodes) + longhorn role (servers)
```
