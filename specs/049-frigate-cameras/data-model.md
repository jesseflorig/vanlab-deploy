# Data Model: Add 4 Cameras to Frigate

**Feature**: 049-frigate-cameras  
**Date**: 2026-04-26

---

## Ansible Variable Schema: `nvr_cameras`

Each entry in `nvr_cameras` (defined in `group_vars/all.yml`) represents one camera.

### Current Schema (feature 041)

```yaml
nvr_cameras:
  - name: string          # Frigate camera identifier (e.g., cam-01)
    rtsp_url: string      # Single RTSP stream URL (used for both detect and record)
    width: integer        # Detection frame width
    height: integer       # Detection frame height
```

### Updated Schema (this feature)

```yaml
nvr_cameras:
  - name: string          # Frigate camera identifier; unique; human-readable (e.g., cam-01)
    rtsp_main_url: string # Main stream RTSP URL — used for continuous recording only
    rtsp_sub_url: string  # Sub stream RTSP URL — used for object detection only
```

**Removed fields**: `rtsp_url`, `width`, `height`  
**Added fields**: `rtsp_main_url`, `rtsp_sub_url`  
**Removed fields rationale**: Detection dimensions are fixed at 640×480 for all cameras (sub stream spec); per-camera width/height is no longer needed. The single `rtsp_url` splits into two role-specific URLs.

### Constraints

| Field | Constraint |
|-------|-----------|
| `name` | Unique across all cameras; lowercase letters, digits, hyphens only |
| `rtsp_main_url` | MUST NOT contain credentials in plaintext in Git; credentials injected via Ansible vault |
| `rtsp_sub_url` | Same constraint as `rtsp_main_url` |

---

## Frigate Config Structure (rendered output)

The Jinja2 template renders one camera block per entry:

```yaml
cameras:
  cam-01:
    ffmpeg:
      inputs:
        - path: "rtsp://user:pass@10.1.40.11:554/cam/realmonitor?channel=1&subtype=0"
          roles:
            - record
        - path: "rtsp://user:pass@10.1.40.11:554/cam/realmonitor?channel=1&subtype=1"
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
```

---

## New Firewall Rule Entry

Added to `nvr_rules` in `playbooks/network/network-deploy.yml`:

```yaml
- seq: 203
  action: pass
  interface: opt1        # VLAN10_Mgmt — NVR host
  direction: in
  ipprotocol: inet
  protocol: TCP
  source_net: "10.1.10.11"
  destination_net: "10.1.40.0/24"
  destination_port: "554"
  description: "NVR Frigate → cameras RTSP"
```

---

## Credential Variables (Ansible vault)

New variables required in `group_vars/all.yml` (gitignored) and documented in `group_vars/example.all.yml`:

| Variable | Description |
|----------|-------------|
| `nvr_camera_rtsp_user` | RTSP username shared across all 4 cameras |
| `nvr_camera_rtsp_pass` | RTSP password (Ansible vault encrypted) |

**Note**: If cameras use different credentials, the `nvr_cameras` schema should include `rtsp_user` and `rtsp_pass` per entry instead of shared variables. Confirm before implementation.
