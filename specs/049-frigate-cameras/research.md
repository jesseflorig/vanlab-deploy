# Research: Add 4 Cameras to Frigate

**Feature**: 049-frigate-cameras  
**Date**: 2026-04-26

---

## Frigate Dual-Stream Camera Configuration

**Decision**: Use two separate RTSP inputs per camera — main stream with `record` role, sub stream with `detect` role.

**Rationale**: Frigate supports multiple `ffmpeg.inputs` per camera with explicit role assignment. Using the high-resolution main stream (2688x1520@20fps) for recording and the low-resolution sub stream (640x480@5fps) for detection follows Frigate's recommended pattern — inference runs only on the small stream, keeping CPU/accelerator load proportional to the number of cameras.

**Alternatives considered**:
- Single stream with both roles: simpler config but forces Frigate to decode a 4K stream for detection, wasting Hailo capacity and network bandwidth. Rejected.
- Hardware transcoding to downscale: adds complexity and Docker capability requirements. Rejected.

**Impact**: The `nvr_cameras` Ansible variable schema must be extended. Each entry currently has `name`, `rtsp_url`, `width`, `height`. The new schema adds `rtsp_sub_url`; the detect dimensions are fixed at 640×480 (sub stream spec) and no longer need to be per-camera variables. The existing `rtsp_url` field becomes the main/record stream. The Jinja2 template `frigate-config.yml.j2` must be updated to render two inputs per camera.

---

## Hailo Detector Type and Model

**Decision**: Keep `type: hailo8l` and omit a custom model path (continue using Frigate's bundled default Hailo model). Do not override with an explicit `yolov8s.hef` path unless runtime verification shows the bundled model is insufficient.

**Rationale**: The existing config (`roles/nvr/templates/frigate-config.yml.j2`) already uses `hailo8l` with no model path, meaning Frigate uses its bundled default model. The detector is already functional from feature 041. Frigate's bundled Hailo model for Hailo-8L is a variant of yolov8 at 640×640 — functionally equivalent to what the spec requires. Introducing a custom model path without confirmed need adds a file-management dependency.

**Note**: If runtime inspection shows the bundled model is significantly less accurate than `yolov8s`, the `model.path` can be added to the Frigate config template pointing to `/config/model_cache/hailo/yolov8s.hef` after copying the `.hef` into the role's `files/hailo/` directory.

**Alternatives considered**:
- Explicit `yolov8s.hef` path: requires sourcing and bundling a compiled Hailo `.hef` file. Deferred — address if needed post-deployment.

---

## Retention Configuration

**Decision**: Event clips 30-day time-based retention (`record.events.retain.default: 30`); continuous recordings storage-based via existing `nvr_recording_retain_days: 7` default.

**Rationale**: The existing defaults already match both clarified answers. `nvr_clips_retain_days: 30` is the role default (aligns with Q1). Continuous recordings use `record.retain.days: 7` — Frigate automatically purges the oldest recordings when NVMe storage is under pressure, making this effectively storage-managed with a 7-day ceiling (aligns with Q4). No template changes needed for retention.

---

## Firewall Gap: NVR → Camera VLAN RTSP

**Decision**: Add a new OPNsense firewall rule allowing NVR host (10.1.10.11) to reach cameras on the IoT VLAN (10.1.40.0/24) over TCP port 554 (RTSP).

**Rationale**: The existing NVR firewall rules in `playbooks/network/network-deploy.yml` cover:
- NVR → cluster VLAN:8883 (MQTT)
- NVR → cluster VLAN:2049 (NFS)
- Cluster → NVR:5000 (Traefik)

There is no rule permitting NVR to pull RTSP streams from 10.1.40.x. Without this rule, Frigate cannot connect to any camera. The network playbook must be extended with a new rule before camera config is applied.

**Alternatives considered**:
- Routing NVR through the cluster VLAN: the NVR is on VLAN10; this would require re-addressing. Rejected.
- Broad IoT VLAN access: rejected per Principle VII (least privilege) — scope to port 554 only.

---

## RTSP Stream Path Pattern

**Decision**: Use Dahua standard RTSP paths — cameras are EmpireTech IPC-T54IR-AS-2.8mm-S3, a Dahua OEM product.

**Confirmed paths**:
- Main stream (2688x1520@20fps): `/cam/realmonitor?channel=1&subtype=0`
- Sub stream (640x480@5fps): `/cam/realmonitor?channel=1&subtype=1`
- Port: 554 (standard RTSP)

**Full URL pattern**:
```
rtsp://<user>:<pass>@10.1.40.{11-14}:554/cam/realmonitor?channel=1&subtype=0
rtsp://<user>:<pass>@10.1.40.{11-14}:554/cam/realmonitor?channel=1&subtype=1
```

**Rationale**: EmpireTech is an Australian Dahua OEM distributor. The IPC-T54IR-AS uses standard Dahua firmware with standard Dahua RTSP path conventions. The `subtype=0` / `subtype=1` pattern is consistent across all Dahua IPC models. This was previously a hard blocker; it is now resolved.
