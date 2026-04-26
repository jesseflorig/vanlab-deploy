# Contract: nvr_cameras Variable Schema

**Feature**: 049-frigate-cameras  
**Type**: Ansible variable schema  
**Defined in**: `group_vars/all.yml`  
**Consumed by**: `roles/nvr/templates/frigate-config.yml.j2`

---

## Schema

```yaml
nvr_cameras:
  - name: <string>           # Required. Unique camera ID used in Frigate UI and MQTT topics.
    rtsp_main_url: <string>  # Required. Full RTSP URL for the main (high-res) stream.
    rtsp_sub_url: <string>   # Required. Full RTSP URL for the sub (low-res) stream.
```

## Validation Rules

- `name`: unique across all entries; matches `[a-z0-9-]+`
- `rtsp_main_url`: valid RTSP URL; credentials MUST be Ansible vault variables (never literal)
- `rtsp_sub_url`: valid RTSP URL; same credential constraint

## Example (4-camera setup)

Cameras are EmpireTech IPC-T54IR-AS (Dahua OEM). Paths confirmed:

```yaml
nvr_cameras:
  - name: cam-01
    rtsp_main_url: "rtsp://{{ nvr_camera_rtsp_user }}:{{ nvr_camera_rtsp_pass }}@10.1.40.11:554/cam/realmonitor?channel=1&subtype=0"
    rtsp_sub_url:  "rtsp://{{ nvr_camera_rtsp_user }}:{{ nvr_camera_rtsp_pass }}@10.1.40.11:554/cam/realmonitor?channel=1&subtype=1"
  - name: cam-02
    rtsp_main_url: "rtsp://{{ nvr_camera_rtsp_user }}:{{ nvr_camera_rtsp_pass }}@10.1.40.12:554/cam/realmonitor?channel=1&subtype=0"
    rtsp_sub_url:  "rtsp://{{ nvr_camera_rtsp_user }}:{{ nvr_camera_rtsp_pass }}@10.1.40.12:554/cam/realmonitor?channel=1&subtype=1"
  - name: cam-03
    rtsp_main_url: "rtsp://{{ nvr_camera_rtsp_user }}:{{ nvr_camera_rtsp_pass }}@10.1.40.13:554/cam/realmonitor?channel=1&subtype=0"
    rtsp_sub_url:  "rtsp://{{ nvr_camera_rtsp_user }}:{{ nvr_camera_rtsp_pass }}@10.1.40.13:554/cam/realmonitor?channel=1&subtype=1"
  - name: cam-04
    rtsp_main_url: "rtsp://{{ nvr_camera_rtsp_user }}:{{ nvr_camera_rtsp_pass }}@10.1.40.14:554/cam/realmonitor?channel=1&subtype=0"
    rtsp_sub_url:  "rtsp://{{ nvr_camera_rtsp_user }}:{{ nvr_camera_rtsp_pass }}@10.1.40.14:554/cam/realmonitor?channel=1&subtype=1"
```

## Breaking Change from Feature 041

The `rtsp_url`, `width`, and `height` fields are removed. Any existing `nvr_cameras` entries in `group_vars/all.yml` must be migrated to the new schema before running `--tags frigate-config`.
