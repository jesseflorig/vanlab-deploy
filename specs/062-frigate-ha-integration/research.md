# Research: Frigate Home Assistant Integration

## Decision: Use HACS for Custom Component Installation

**Decision**: Install HACS (Home Assistant Community Store) in the HA pod and use it to install the Frigate Custom Integration.

**Rationale**: 
- HACS is the standard way to manage custom components in Home Assistant.
- It provides automated updates and dependency management.
- While it requires a manual one-time installation step (shell script in pod), it simplifies long-term maintenance compared to manual file copying.

**Alternatives considered**:
- **Manual File Copy**: Copying `custom_components/frigate` manually. Rejected because it's harder to keep updated and prone to errors during manual extraction in a containerized environment.
- **Git Submodule/Manifest Integration**: Automating the download via init-containers. Rejected as overly complex for a homelab setup where HACS is the community-standard tool.

## Decision: Configure via YAML Packages

**Decision**: Use the HA `packages` feature to inject the `frigate:` configuration block via the `home-assistant-config-extra` ConfigMap.

**Rationale**:
- Keeps the main `configuration.yaml` (stored on the PVC) untouched and clean.
- Allows configuration-as-code managed by ArgoCD.
- Facilitates easy disabling/enabling by updating the ConfigMap.

**Alternatives considered**:
- **UI-only Configuration**: Configuring the integration solely via the HA Integrations UI. Rejected because it doesn't align with the project's IaC principles (Principle I).

## Decision: Direct IP for NVR Connection

**Decision**: Connect Home Assistant to Frigate using the direct IP and port: `http://10.1.10.11:5000`.

**Rationale**:
- Bypasses the cluster's external ingress (Traefik), reducing latency and dependency on external DNS/TLS.
- Ensures connectivity even if the external ingress or Cloudflare tunnel is down.
- HA and the NVR are both on the local network.

**Alternatives considered**:
- **Public URL**: `https://frigate.fleet1.cloud`. Rejected for internal traffic due to extra hops and dependency on external certificate validation.

## Research Findings

- **HACS Installation**: Requires a one-liner `wget -O - https://get.hacs.xyz | bash -` run inside the HA pod.
- **Frigate Requirements**: The custom integration requires the `frigate:` key in `configuration.yaml` (or a package) and a shared MQTT broker.
- **MQTT Broker**: HA already has access to the cluster's Mosquitto broker with mTLS certs. Frigate is also configured to use the same broker. No additional MQTT work is needed.
