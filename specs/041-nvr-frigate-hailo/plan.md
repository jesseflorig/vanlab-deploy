# Implementation Plan: NVR Frigate + Hailo-8 Provisioning

**Branch**: `041-nvr-frigate-hailo` | **Date**: 2026-04-25 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `/specs/041-nvr-frigate-hailo/spec.md`

## Summary

Provision a dedicated NVR host at `10.1.10.11` running Frigate as a standalone Docker/systemd service with the Hailo-8 PCIe accelerator as the object detector. Event clips are stored on a Longhorn RWX PVC (50Gi, NFS-mounted on the host); continuous recordings stay on local NVMe. The cluster Traefik ingress routes `frigate.fleet1.cloud` to the host via a Service+Endpoints pair. Frigate publishes detection events to the existing MQTT broker over MQTTS with client certificates. Ansible provisions the host; ArgoCD manages all cluster-side Kubernetes resources.

## Technical Context

**Language/Version**: YAML (Ansible 2.x) for host provisioning; YAML (Kubernetes manifests) for cluster-side resources  
**Primary Dependencies**: Ansible, Docker (on NVR host), Hailo PCIe driver (`h10-hailort-pcie-driver` + `hailo-all`), Frigate (`ghcr.io/blakeblackshear/frigate:stable`), Longhorn v1.11.1 (existing), Traefik (existing), cert-manager (existing), ArgoCD (existing)  
**Storage**: Local NVMe at `/var/lib/frigate/media` (continuous recordings); Longhorn RWX PVC `frigate-clips` (50Gi) NFS-mounted at `/mnt/frigate-clips` (event clips)  
**Testing**: Ansible `--check` dry-run; manual verification (Hailo device detect, Frigate service status, NFS mountpoint, MQTT event publish, Traefik routing)  
**Target Platform**: Debian arm64 (Raspberry Pi CM5) standalone host + existing K3s cluster  
**Project Type**: Infrastructure provisioning (Ansible playbook + Kubernetes manifests)  
**Performance Goals**: Object detection on Hailo-8 PCIe (not CPU); continuous recording writes must not traverse the network  
**Constraints**: MQTTS only (port 8883); TLS on all external access; secrets in `group_vars/all.yml` only; all Kubernetes resources ArgoCD-managed  
**Scale/Scope**: Single dedicated NVR host; supports up to N cameras as Ansible variable list

## Constitution Check

*GATE: Must pass before implementation.*

| Principle | Status | Notes |
|---|---|---|
| I. Infrastructure as Code | ✅ Pass | All host config in Ansible roles; all K8s resources in `manifests/frigate/` |
| II. Idempotency | ✅ Pass | All Ansible tasks use `state:`, `creates:`, `changed_when:` guards; systemd service idempotent |
| III. Reproducibility | ✅ Pass | Quickstart documents full rebuild sequence including two-phase run order |
| IV. Secrets Hygiene | ✅ Pass | MQTT certs/keys and Frigate password in `group_vars/all.yml` only; `example.all.yml` updated with placeholders; cert files mode 0600 on host |
| V. Simplicity | ✅ Pass | Ansible role for host; raw manifests (no Helm) for cluster side — no unnecessary abstraction |
| VI. Encryption in Transit | ✅ Pass | MQTTS port 8883 with TLS; Traefik terminates HTTPS; HTTP redirected |
| VII. Least Privilege + Cert Auth | ✅ Pass | MQTT client certificates; OPNsense rules narrow-scoped (two rules, minimum required ports) |
| VIII. Persistent Storage | ✅ Pass | Longhorn RWX PVC for clips. Local NVMe for continuous recordings is a standalone-host workload — Principle VIII governs K8s PVCs, not systemd services on non-cluster hosts |
| IX. Secure Service Exposure | ✅ Pass | Traefik HTTPS via `*.fleet1.cloud` wildcard cert; HTTP → HTTPS redirect |
| X. Intra-Cluster Service Locality | ✅ Pass | Frigate connects to MQTT broker via internal IP (not public DNS); Traefik routes to internal 10.1.10.11 |
| XI. GitOps Application Deployment | ✅ Pass | All K8s resources in `manifests/frigate/`; ArgoCD Application registered in `argocd_apps`; Ansible MUST NOT `kubectl apply` these manifests |

## Project Structure

### Documentation (this feature)

```
specs/041-nvr-frigate-hailo/
├── plan.md               ← this file
├── research.md           ← Phase 0 decisions
├── data-model.md         ← variables, templates, K8s resource shapes
├── quickstart.md         ← operator runbook
├── contracts/
│   └── operator-variables.md
├── checklists/
│   └── requirements.md
└── tasks.md              ← Phase 2 output (/speckit.tasks — not yet created)
```

### Source Code Layout

```
playbooks/
└── nvr/
    └── nvr-provision.yml           ← main playbook; tags: host-setup, hailo, frigate-config, nfs-mount, frigate-service

roles/
└── nvr/
    ├── defaults/
    │   └── main.yml                ← nvr_* variable defaults
    ├── tasks/
    │   ├── main.yml                ← tag routing
    │   ├── host-setup.yml          ← Docker install, OS hardening, SSH config, firewall
    │   ├── hailo.yml               ← driver install, udev rules, device verification
    │   ├── frigate-config.yml      ← config dir, cert files, config.yml template
    │   ├── nfs-mount.yml           ← /mnt/frigate-clips systemd mount unit + fstab
    │   └── frigate-service.yml     ← systemd unit template, service enable + start
    ├── templates/
    │   ├── frigate-config.yml.j2   ← Frigate config.yml (MQTT, detector, cameras, storage)
    │   ├── frigate.service.j2      ← systemd unit (docker run with all mounts/devices)
    │   ├── frigate-clips.mount.j2  ← systemd NFS mount unit
    │   └── ha-frigate-config.txt.j2 ← HA integration output (written to repo root, gitignored)
    └── handlers/
        └── main.yml                ← reload udev, restart frigate, daemon-reload

manifests/
└── frigate/
    ├── prereqs/
    │   ├── namespace.yaml          ← sync wave 0
    │   ├── storageclass.yaml       ← sync wave 1: longhorn-rwx StorageClass
    │   ├── certificate.yaml        ← sync wave 2: cert-manager Certificate
    │   └── sealed-secrets.yaml     ← sync wave 3: placeholder (no cluster secrets needed currently)
    ├── pvc.yaml                    ← frigate-clips RWX PVC (50Gi, longhorn-rwx)
    ├── service.yaml                ← ClusterIP Service pointing to 10.1.10.11:5000
    ├── endpoints.yaml              ← Endpoints pointing to 10.1.10.11
    └── ingressroute.yaml           ← Traefik IngressRoute: frigate.fleet1.cloud → frigate svc

group_vars/
└── example.all.yml                 ← add nvr_* placeholder entries
```

**Structure Decision**: Single Ansible role with tagged task files for the host side; flat raw-manifest layout in `manifests/frigate/` for the cluster side (no Helm — this is a set of ~6 resources, not a parameterized chart). ArgoCD Application registered in `argocd_apps` in `group_vars/all.yml`.

## Complexity Tracking

No constitution violations requiring justification.

---

## Implementation Notes (for task generation)

### Two-Phase Playbook Execution

The provisioning has a mandatory ordering dependency that operators must follow (documented in quickstart.md and contracts/):

1. **Phase A** (`--tags host-setup,hailo,frigate-config`): Provisions the host, installs drivers, renders config. Does NOT start Frigate. Does NOT configure NFS mount.
2. **ArgoCD sync**: Operator pushes branch, merges PR, ArgoCD syncs `manifests/frigate/`. Longhorn creates the share-manager pod and NFS endpoint.
3. **Operator step**: Queries Longhorn NFS IP + path, sets `nvr_longhorn_nfs_ip` and `nvr_longhorn_nfs_path` in `group_vars/all.yml`.
4. **Phase B** (`--tags nfs-mount,frigate-service`): Configures NFS mount, starts Frigate service.

The playbook must assert that `nvr_longhorn_nfs_ip != ""` before Phase B tasks execute.

### OPNsense Firewall Rules

Two rules must be added to the OPNsense Ansible role (or a dedicated nvr-firewall playbook):
- Source: `10.1.10.11`, Destination: `10.1.20.x/24`, Port: `8883` (MQTTS — Frigate → MQTT broker)
- Source: `10.1.20.0/24`, Destination: `10.1.10.11`, Port: `5000` (Traefik → Frigate web UI)

### Hailo Device Verification

The `hailo.yml` task file must include a verification step after driver install:
```yaml
- name: Verify Hailo-8 device node exists
  ansible.builtin.stat:
    path: /dev/hailo0
  register: hailo_device
  failed_when: not hailo_device.stat.exists
```

If the device node does not exist after reboot, the playbook fails with a descriptive error — no silent CPU fallback.

### NFS Mount via systemd

Use a systemd `.mount` unit (not `/etc/fstab`) for the Longhorn NFS mount. This integrates with systemd dependency ordering: the `frigate.service` unit declares `Requires=mnt-frigate-clips.mount`, ensuring Frigate never starts without the NFS volume available.

### Longhorn RWX StorageClass

A dedicated `longhorn-rwx` StorageClass is needed (separate from the default `longhorn` class) because RWX volumes require different Longhorn parameters (`nfsOptions`, NFS provisioner). The existing `longhorn` StorageClass should not be modified.

### ArgoCD Application Registration

Add to `argocd_apps` in `group_vars/all.yml`:
```yaml
- name: frigate
  namespace: frigate
  path: manifests/frigate
  repoURL: https://gitea.fleet1.cloud/gitadmin/vanlab
  prune: true
  selfHeal: true
  retry_limit: 5
```

### HA Integration Output

The `ha-frigate-config.txt.j2` template is rendered to the repo root as `ha-frigate-config.txt`. This file must be added to `.gitignore`. It contains the Home Assistant Frigate integration YAML block built from `nvr_cameras`, `nvr_mqtt_broker_ip`, and the configured topic prefix.
