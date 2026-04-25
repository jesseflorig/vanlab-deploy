# Research: NVR Frigate + Hailo-8 Provisioning

**Feature**: 041-nvr-frigate-hailo  
**Date**: 2026-04-25

---

## Decision 1: Hailo-8 Driver Installation

**Decision**: Use the official Raspberry Pi APT repository (`h10-hailort-pcie-driver` + `hailo-all` meta-package) for driver and runtime installation.

**Rationale**: The `hailo-all` meta-package from the RPi APT repo bundles the PCIe driver, HailoRT runtime, and Python bindings in a single idempotent apt install. Manual download from Hailo's developer zone requires authentication and is not suitable for unattended automation.

**Installation sequence**:
1. Configure RPi APT repo (GPG key + sources list)
2. `apt install hailo-all linux-headers-$(uname -r)`
3. Deploy `/etc/udev/rules.d/51-hailo-udev.rules` and reload udev
4. Reboot (kernel module `hailo_pci` loads on next boot)
5. Verify: `ls -l /dev/hailo0` and `hailortcli fw-control identify`

**Kernel requirement**: Kernel ≥ 6.6.31. RPi OS ships a compatible kernel.

**Device node**: `/dev/hailo0` (created by udev after driver load). Must be accessible to the Frigate process.

**Alternatives considered**: Manual `.deb` download from Hailo developer zone — rejected (requires browser auth, not automatable).

---

## Decision 2: Frigate Deployment Model on Standalone Host

**Decision**: Deploy Frigate as a Docker container managed by a systemd unit (`frigate.service`).

**Rationale**: Frigate is distributed and documented as a container image. Running it under systemd provides automatic restart-on-failure, dependency ordering (requires docker, requires NFS mount), and the same operational model used for other long-running services in the lab.

**Container configuration essentials**:
- Image: `ghcr.io/blakeblackshear/frigate:stable`
- Device mount: `/dev/hailo0:/dev/hailo0`
- Volume mounts:
  - `/etc/localtime:/etc/localtime:ro`
  - `/var/lib/frigate/config:/config`
  - `/var/lib/frigate/media:/media/frigate` (local NVMe — continuous recordings)
  - `<longhorn-nfs-ip>:/pvc-<uuid>:/media/frigate/clips` (Longhorn NFS — event clips only)
- Privileged or `--device` flag needed for Hailo device access

**Alternatives considered**: Bare-metal install — rejected (no upstream support, complex update path). K8s workload — rejected (Hailo device plugin overhead, NVR should be availability-independent of cluster control plane).

---

## Decision 3: Frigate Hailo-8 Detector Configuration

**Decision**: Use `type: hailo8` with `device: PCIe`. Default YOLOv8 HEF model auto-downloaded to `/config/model_cache/`.

**Rationale**: Frigate natively supports Hailo-8 as a first-class detector type. The PCIe device selection is correct for the embedded Hailo-8 (not USB). The YOLOv8 model is the recommended default for Hailo-8 (non-L variant).

**Frigate detector config**:
```yaml
detectors:
  hailo8:
    type: hailo8
    device: PCIe

model:
  path: /config/model_cache/hailo/yolov8s.hef
  input_tensor: nhwc
  input_pixel_format: rgb
  model_type: yolo-generic
  width: 640
  height: 640
```

**Verification**: After startup, `docker logs frigate` should show `Loaded Hailo-8 detector` and NOT `Using CPU detector`. The Hailo device utilization should be non-zero during active inference.

---

## Decision 4: Longhorn RWX Clips Storage

**Decision**: Create a dedicated `longhorn-rwx` StorageClass and a 50Gi RWX PVC annotated with `longhorn.external.share: "true"`. The NVR host mounts the auto-generated NFS endpoint at `/mnt/frigate-clips`.

**Rationale**: Longhorn's built-in NFS provisioner for RWX volumes creates a `share-manager-<pvc>` pod per PVC and exposes it as a LoadBalancer Service. This is the only supported way to externally mount a Longhorn volume without a custom NFS server deployment.

**StorageClass**:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-rwx
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "2"
  fsType: "ext4"
  nfsOptions: "vers=4.1,noresvport"
```

**PVC**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: frigate-clips
  namespace: frigate
  annotations:
    longhorn.external.share: "true"
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: longhorn-rwx
  resources:
    requests:
      storage: 50Gi
```

**NFS endpoint discovery**: After PVC binds, a `Service` of type `LoadBalancer` is auto-created in `longhorn-system`. The Ansible playbook queries this service for its ClusterIP/LoadBalancer IP and uses it as the NFS mount target.

**Ordering dependency**: Cluster manifests must be applied (ArgoCD synced) and the Longhorn share-manager pod must be Running before the Ansible playbook configures the NFS mount on the NVR host.

**Alternatives considered**: Dedicated NFS server pod — rejected (additional component to manage, no replication). Local disk for clips — rejected (clips are the high-value footage, should survive disk failure).

---

## Decision 5: Traefik Routing to External Host

**Decision**: Create a Kubernetes `Service` + `Endpoints` pair in the `frigate` namespace pointing to `10.1.10.11:5000` (Frigate's default web port). The `IngressRoute` routes `frigate.fleet1.cloud` to this Service with TLS termination at Traefik using the existing `*.fleet1.cloud` wildcard cert.

**Rationale**: Traefik IngressRoute cannot reference an IP directly — it requires a Service. The Service+Endpoints pattern is the standard approach for routing to external IPs. TLS termination at Traefik is consistent with all other lab services and avoids double-TLS complexity.

**Service + Endpoints**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: frigate
  namespace: frigate
spec:
  ports:
    - name: http
      port: 5000
      targetPort: 5000
---
apiVersion: v1
kind: Endpoints
metadata:
  name: frigate
  namespace: frigate
subsets:
  - addresses:
      - ip: 10.1.10.11
    ports:
      - name: http
        port: 5000
```

**IngressRoute** (references existing `*.fleet1.cloud` wildcard cert):
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: frigate
  namespace: frigate
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`frigate.fleet1.cloud`)
      kind: Rule
      services:
        - name: frigate
          port: 5000
  tls:
    secretName: wildcard-fleet1-cloud-tls
```

**Alternatives considered**: IngressRouteTCP with passthrough — rejected (would require Frigate to handle its own TLS, adds complexity). ExternalName Service — rejected (DNS-based, less explicit for a known IP).

---

## Decision 6: MQTT Authentication

**Decision**: Frigate connects to the MQTT broker via MQTTS (port 8883) using a client certificate issued by the internal CA. Certificate material is placed on the NVR host via Ansible (templated from `group_vars/all.yml`), not committed to Git.

**Rationale**: Constitution Principles VI and VII mandate MQTTS and cert-based MQTT auth. Frigate supports `tls_ca_certs`, `tls_client_cert`, `tls_client_key` in its MQTT config block.

**Frigate MQTT config**:
```yaml
mqtt:
  enabled: true
  host: 10.1.20.x        # internal broker IP (no DNS traversal per Principle X)
  port: 8883
  tls_ca_certs: /config/certs/ca.crt
  tls_client_cert: /config/certs/frigate-client.crt
  tls_client_key: /config/certs/frigate-client.key
  topic_prefix: frigate
  client_id: frigate-nvr
```

**Cert placement**: Ansible templates cert/key files from `group_vars/all.yml` vars into `/var/lib/frigate/config/certs/` on the NVR host. The container mounts `/var/lib/frigate/config` → `/config`.

---

## Decision 7: ArgoCD Management of Cluster-Side Resources

**Decision**: All Kubernetes resources for Frigate (namespace, StorageClass, PVC, Service, Endpoints, IngressRoute, cert-manager Certificate) live under `manifests/frigate/` and are synced by an ArgoCD Application registered in `argocd_apps`.

**Rationale**: Constitution Principle XI requires all non-infrastructure cluster resources to be ArgoCD-managed. The Ansible playbook provisions the host; ArgoCD provisions the cluster side. Neither touches the other's domain.

**Manifest layout**:
```
manifests/frigate/
├── prereqs/
│   ├── namespace.yaml         (sync wave 0)
│   ├── storageclass.yaml      (sync wave 1: longhorn-rwx StorageClass)
│   ├── certificate.yaml       (sync wave 2: cert-manager Certificate for frigate.fleet1.cloud)
│   └── sealed-secrets.yaml    (sync wave 3: any sealed secrets, if needed)
├── pvc.yaml
├── service.yaml
├── endpoints.yaml
└── ingressroute.yaml
```

**ArgoCD Application** registered in `group_vars/all.yml` under `argocd_apps`.

---

## Decision 8: OPNsense Firewall Rules

**Decision**: Two new OPNsense firewall rules are required and MUST be added to the Ansible OPNsense role (Principle I — all rules as code):

1. `10.1.10.11` → `10.1.20.x:8883` — allow Frigate (edge VLAN) to reach MQTT broker (cluster VLAN) over MQTTS
2. `10.1.20.0/24` → `10.1.10.11:5000` — allow Traefik (cluster VLAN) to proxy to Frigate web UI (edge VLAN)

**Rationale**: The edge VLAN (10.1.10.x) is isolated by default. Without these rules, neither MQTT publishing nor Traefik proxying will function.

---

## Decision 9: Home Assistant Integration Output

**Decision**: Ansible outputs a rendered `ha-frigate-config.txt` task summary file (not committed to Git) containing the HA Frigate integration YAML block for the operator to apply manually.

**Rationale**: Clarification Q2 resolved this — Ansible configures the Frigate side fully; HA-side configuration is operator-applied. The output file avoids the operator having to manually construct the config from variables.

**Contents**: MQTT credentials (broker IP, topic prefix), camera entity definitions (one per configured camera), snapshot/clip URLs formatted for the HA Frigate integration component.
