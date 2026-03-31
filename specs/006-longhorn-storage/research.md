# Research: Longhorn Distributed Block Storage

**Feature**: 006-longhorn-storage
**Date**: 2026-03-31

---

## Decision 1: Longhorn Version

**Decision**: Use Longhorn v1.11.1 (latest stable as of early 2026)

**Rationale**: v1.11.1 has full arm64 multi-arch image support (arm64 images available since v1.3.0), is the current stable release, and is compatible with K3s and Kubernetes 1.29+.

**Alternatives considered**: v1.6.x LTS — stable but older; v1.11.x chosen for current feature set and arm64 image quality.

---

## Decision 2: Helm Chart and Namespace

**Decision**: Official Longhorn Helm chart from `https://charts.longhorn.io`, chart name `longhorn/longhorn`, namespace `longhorn-system`.

**Rationale**: Official chart; single namespace for all components. CRDs are bundled in the chart templates (no separate pre-apply like cert-manager) — `helm upgrade --install` handles them automatically.

**Alternatives considered**: Manifest-based install — rejected per Constitution Principle V (prefer Helm community charts).

---

## Decision 3: K3s Kubelet Root Dir

**Decision**: Use the default `/var/lib/kubelet` (no `csi.kubeletRootDir` override needed).

**Rationale**: K3s v0.10.0+ sets `--kubelet-root-dir=/var/lib/kubelet` explicitly, making it the standard path. The cluster is running a modern K3s version. If CSI plugin fails to register, add `csi.kubeletRootDir: /var/lib/kubelet` explicitly as a fallback.

**Alternatives considered**: `/var/lib/rancher/k3s/agent/kubelet` (pre-v0.10.0 path) — not applicable to this cluster.

---

## Decision 4: Displace K3s local-path Default StorageClass

**Decision**: Write `disable: [local-storage]` to `/etc/rancher/k3s/config.yaml` on server nodes and restart K3s. Also add `--disable local-storage` to `INSTALL_K3S_EXEC` in `k3s-deploy.yml` for fresh installs.

**Rationale**: K3s re-applies the `local-storage.yaml` manifest from `/var/lib/rancher/k3s/server/manifests/` on **every K3s server process restart**. A bare `kubectl patch` to remove the default annotation is not durable — the annotation is reset on next restart. The only durable approaches are:
- `disable: [local-storage]` in `/etc/rancher/k3s/config.yaml` (causes K3s to actively delete the addon and not re-apply it)
- `--disable local-storage` at K3s install time

A touch of `.yaml.skip` file suppresses re-application but does not delete the existing StorageClass — less clean.

The `local-path` provisioner does not need to be completely uninstalled; removing its default status is sufficient. Workloads can still explicitly request `storageClassName: local-path` if needed.

**Alternatives considered**: Annotation-only patch (`kubectl patch storageclass local-path`) — not durable, rejected. Leaving both defaults — causes admission controller to reject unspecified-class PVCs, rejected.

---

## Decision 5: Node Prerequisites

**Decision**: Install `open-iscsi` and `nfs-common` on all cluster nodes (servers + agents). Enable `iscsid` service. Load and persist `iscsi_tcp` kernel module. Disable `multipathd`.

**Rationale**:

- `open-iscsi`: Mandatory — Longhorn attaches block volumes to pods via iSCSI. `iscsid` must be running and `iscsi_tcp` must be loaded. On Raspberry Pi OS these are not automatic post-install.
- `nfs-common`: Required for ReadWriteMany (RWX) volumes. Also needed for Longhorn's NFS-based share-manager pod on the node side.
- `iscsi_tcp` kernel module: Present in the Raspberry Pi 5 kernel (Bookworm) but not auto-loaded. Must be explicitly loaded via `modprobe` and persisted via `/etc/modules-load.d/`.
- `multipathd`: **Critical Pi gotcha** — if running, it intercepts iSCSI block devices and prevents Longhorn volumes from mounting (well-documented Longhorn GitHub issue #1968). Must be disabled.
- `/etc/iscsi/initiatorname.iscsi`: Created automatically by `open-iscsi` package install. Longhorn preflight fails if missing — worth verifying.

**arm64 notes**: All packages have native arm64 builds in Debian Bookworm's apt repos. No special PPAs or workarounds needed.

---

## Decision 6: Replica Count

**Decision**: Default replica count of 2 (`persistence.defaultClassReplicaCount: 2` and `defaultSettings.defaultReplicaCount: 2`).

**Rationale**: With 6 nodes, a replica count of 2 provides single-node failure tolerance while keeping write amplification lower than 3. Can be increased per-volume or globally post-install.

**Alternatives considered**: 3 replicas — higher durability, higher overhead. 1 replica — no redundancy, not appropriate for primary storage.

---

## Decision 7: Longhorn Dashboard Access

**Decision**: Expose the Longhorn dashboard (`longhorn-frontend` service, port 80) via a Traefik Ingress resource within the cluster network only. No Cloudflare tunnel exposure in this feature.

**Rationale**: The spec explicitly defers external HTTPS exposure. The dashboard has no built-in authentication — official docs recommend putting auth in front before exposing externally. Internal access via `kubectl port-forward` or a cluster-internal Ingress is sufficient for this feature.

**Note**: The Longhorn UI has no built-in login. A basic-auth middleware should be added before any future external exposure.

---

## Decision 8: Prerequisites Run Scope

**Decision**: Node prerequisites (packages, services, modules) run on `cluster` group (all nodes). Helm install and StorageClass displacement run on `servers` group only.

**Rationale**: Longhorn's CSI plugin DaemonSet runs on every node — every node needs `open-iscsi` and `nfs-common` for volume mounting to work. Helm and `kubectl` only exist on server nodes.

**Implementation**: Add a new play targeting `hosts: cluster` in `services-deploy.yml` before the existing servers play, containing a `longhorn-prereqs` role.

---

## Helm Values (Final)

```yaml
# roles/longhorn/files/values.yaml
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

Note: `csi.kubeletRootDir` omitted — modern K3s uses `/var/lib/kubelet` which Longhorn auto-detects.

---

## Readiness Wait Strategy

Longhorn installs a DaemonSet (`longhorn-manager`) across all nodes and several Deployments. Helm `--wait` does not reliably track DaemonSet readiness. Explicit waits required:

```bash
# DaemonSets (run on every node — must wait for all replicas)
kubectl -n longhorn-system rollout status daemonset/longhorn-manager --timeout=10m
kubectl -n longhorn-system rollout status daemonset/longhorn-csi-plugin --timeout=10m

# Key Deployments
kubectl -n longhorn-system rollout status deployment/longhorn-ui --timeout=5m
kubectl -n longhorn-system rollout status deployment/longhorn-driver-deployer --timeout=5m
kubectl -n longhorn-system rollout status deployment/csi-attacher --timeout=5m
kubectl -n longhorn-system rollout status deployment/csi-provisioner --timeout=5m
```
