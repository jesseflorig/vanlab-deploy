# Data Model: Frigate Home Assistant Integration

## Entities

### Frigate Integration (Custom Component)
- **Type**: HA Component
- **Identifier**: `frigate`
- **Scope**: Namespace `home-automation`
- **Configuration**:
  - `host`: `http://10.1.10.11:5000` (Direct NVR IP)

### Camera (Home Assistant Entity)
- **Type**: `camera`
- **Naming**: Derived from Frigate camera names (e.g., `camera.front_door`)
- **Attributes**:
  - `access_token`: Managed by HA
  - `stream_url`: `http://10.1.10.11:5000/api/<name>/stream.m3u8`
  - `snapshot_url`: `http://10.1.10.11:5000/api/<name>/latest.jpg`

### Object Detection Sensor (Home Assistant Entity)
- **Type**: `binary_sensor`
- **Naming**: `binary_sensor.<camera>_<object>_motion` (e.g., `binary_sensor.front_door_person_motion`)
- **State**: `on` (Detected), `off` (Clear)
- **Source**: MQTT topic `frigate/<camera>/<object>`

## Relationships

- **Home Assistant** (Pod) connects to **Frigate** (NVR Host) via HTTP (Port 5000).
- **Home Assistant** (Pod) subscribes to **Mosquitto** (Broker Pod) for real-time events from Frigate.
- **ArgoCD** (Controller) manages the **ConfigMap** `home-assistant-config-extra` which contains the integration settings.
