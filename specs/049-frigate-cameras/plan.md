# Implementation Plan: Add 4 Cameras to Frigate

**Branch**: `049-frigate-cameras` | **Date**: 2026-04-26 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `/specs/049-frigate-cameras/spec.md`

## Summary

Add 4 IP cameras (10.1.40.11–14) to the existing Frigate NVR deployment. Each camera uses a dual-stream RTSP setup: main stream (2688x1520@20fps) for continuous recording, sub stream (640x480@5fps) for Hailo accelerated object detection. Changes span three areas: OPNsense firewall (new RTSP rule), the Ansible `nvr_cameras` variable schema (dual-stream), and the Frigate config Jinja2 template (two inputs per camera). Clip retention is 30 days (matches existing default). Detection uses the existing bundled Hailo model via the already-configured `hailo8l` detector.

## Technical Context

**Language/Version**: YAML (Ansible 2.x)  
**Primary Dependencies**: Ansible, OPNsense REST API (`oxlorg.opnsense`), Docker (Frigate on NVR host), Jinja2  
**Storage**: Local NVMe at `/var/lib/frigate/media` (continuous recordings, storage-managed); Longhorn RWX NFS PVC `frigate-clips` 50Gi (event clips, 30-day retention)  
**Testing**: Manual — Frigate UI live view, detection event trigger, recording segment check  
**Target Platform**: NVR host (10.1.10.11, arm64 Ubuntu 24.04); OPNsense router (10.1.1.1)  
**Project Type**: Infrastructure configuration (Ansible role extension)  
**Performance Goals**: Detection latency ≤ existing baseline; 4 simultaneous RTSP streams without Frigate restart  
**Constraints**: RTSP stream paths unknown until confirmed from camera documentation — hard pre-implementation dependency  
**Scale/Scope**: 4 cameras, single NVR host, single Hailo-8L accelerator

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I — Infrastructure as Code | ✅ Pass | All changes via Ansible playbooks; no manual host edits |
| II — Idempotency | ✅ Pass | Template rendering and firewall rule upserts are idempotent |
| III — Reproducibility | ✅ Pass | `group_vars/example.all.yml` documents new variables |
| IV — Secrets Hygiene | ✅ Pass | RTSP credentials injected via Ansible vault; not committed in plaintext |
| V — Simplicity | ✅ Pass | Extending existing role and template; no new abstractions |
| VI — Encryption in Transit | ✅ Pass | RTSP on isolated IoT VLAN; no cross-VLAN plaintext (cameras → NVR only, not internet-exposed) |
| VII — Least Privilege | ✅ Pass | New firewall rule scoped to TCP/554 NVR→cameras only |
| VIII — Persistent Storage | ✅ Pass | Existing Longhorn PVC and NVMe paths unchanged |
| IX — Secure Service Exposure | ✅ Pass | Frigate UI not newly exposed; existing Traefik/TLS ingress unchanged |
| X — Intra-Cluster Service Locality | ✅ Pass | No cluster service routing changes |
| XI — GitOps Application Deployment | ✅ Pass | Frigate is a Docker workload on NVR host (not a cluster application); Ansible management is correct here |

## Project Structure

### Documentation (this feature)

```text
specs/049-frigate-cameras/
├── plan.md                        # This file
├── research.md                    # Phase 0: decisions and rationale
├── data-model.md                  # Phase 1: variable schema + rendered config shape
├── quickstart.md                  # Phase 1: deployment runbook
├── contracts/
│   └── nvr-cameras-schema.md      # nvr_cameras Ansible variable contract
└── tasks.md                       # Phase 2 output (created by /speckit.tasks)
```

### Source Code Changes

```text
# Modified files
roles/nvr/
├── defaults/main.yml              # No change (nvr_clips_retain_days: 30 already correct)
└── templates/
    └── frigate-config.yml.j2      # Update camera loop: two inputs per camera (main + sub)

playbooks/network/
└── network-deploy.yml             # Add seq 203: NVR → IoT VLAN:554 RTSP rule

group_vars/
├── example.all.yml                # Update nvr_cameras example: dual-stream schema
└── all.yml                        # Operator fills: nvr_cameras entries + RTSP credentials
                                   # (gitignored — not committed)
```

## Implementation Phases

### Phase A — RTSP Stream Paths (Resolved)

Cameras are EmpireTech IPC-T54IR-AS-2.8mm-S3 (Dahua OEM). Paths are confirmed:
- Main stream: `rtsp://<user>:<pass>@10.1.40.{11-14}:554/cam/realmonitor?channel=1&subtype=0`
- Sub stream:  `rtsp://<user>:<pass>@10.1.40.{11-14}:554/cam/realmonitor?channel=1&subtype=1`

No discovery step required. Populate `group_vars/all.yml` directly (see quickstart.md Step 3).

---

### Phase B — Firewall Rule

Add a new rule to `playbooks/network/network-deploy.yml` `nvr_rules` list:

```yaml
- seq: 203
  action: pass
  interface: opt1
  direction: in
  ipprotocol: inet
  protocol: TCP
  source_net: "10.1.10.11"
  destination_net: "10.1.40.0/24"
  destination_port: "554"
  description: "NVR Frigate → cameras RTSP"
```

Apply:
```bash
ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml
```

---

### Phase C — Template Update

Update `roles/nvr/templates/frigate-config.yml.j2` camera loop to render two inputs per camera:

```jinja2
{% for cam in nvr_cameras %}
  {{ cam.name }}:
    ffmpeg:
      inputs:
        - path: "{{ cam.rtsp_main_url }}"
          roles:
            - record
        - path: "{{ cam.rtsp_sub_url }}"
          roles:
            - detect
    detect:
      enabled: true
      width: 640
      height: 480
      fps: 5
    objects:
      track:
        - person
        - car
        - truck
        - bicycle
        - dog
        - cat
    record:
      enabled: true
    snapshots:
      enabled: true
{% endfor %}
```

Remove the old `cam.width` and `cam.height` references.

---

### Phase D — Variable Schema Migration

Update `group_vars/example.all.yml`: replace the single `rtsp_url` example with the dual-stream `rtsp_main_url` / `rtsp_sub_url` schema. Add `nvr_camera_rtsp_user` and `nvr_camera_rtsp_pass` variable documentation.

In `group_vars/all.yml` (operator-managed, gitignored): populate `nvr_cameras` with all 4 camera entries once RTSP paths are confirmed. Vault-encrypt `nvr_camera_rtsp_pass`.

---

### Phase E — Apply Frigate Config

Once Phase A (stream paths) is resolved and Phase B (firewall) is applied:

```bash
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml \
  --tags frigate-config,frigate-service
```

---

### Phase F — Validation

1. Open Frigate UI — confirm all 4 cameras appear with live feeds
2. Verify detection is using sub streams: check Frigate logs for `640x480` detect resolution
3. Walk in front of a camera — confirm person detection event appears
4. Confirm `hailo8l` detector shown in Frigate stats (not CPU fallback)
5. Wait 5 minutes — confirm recording segments appear for each camera under `/var/lib/frigate/media`
6. Confirm clips volume remains mounted: `df -h /mnt/frigate-clips` on NVR host

## Complexity Tracking

No constitution violations.
