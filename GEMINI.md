# vanlab Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-05-03

## Traefik Conventions

- **Namespace Scoping**: Traefik `IngressRoute` resources MUST reference `TLSOption` resources within the same namespace. Cross-namespace references (e.g., `device-mtls@traefik`) are rejected by Traefik with an error like `ERR TLSOption traefik/device-mtls is not in the IngressRoute namespace`.
- **mTLS Localization**: For any service requiring mTLS via `device-mtls`, the following resources MUST be duplicated into the service's namespace:
  - `Secret`: `device-ca-public` (containing the CA public cert).
  - `TLSOption`: `device-mtls` (referencing the local secret).
- **Silent Failures**: If an `IngressRoute` is missing from the Traefik dashboard despite being synced by ArgoCD, check the Traefik logs for namespace mismatch or missing resource errors.

## Active Technologies
- YAML (Kubernetes/Ansible), Home Assistant (latest), Frigate (stable) + Frigate Custom Integration, HACS (Home Assistant Community Store), Mosquitto (MQTT) (062-frigate-ha-integration)
- Longhorn (existing HA PVC) (062-frigate-ha-integration)

- (058-wireguard-management-vpn)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for 

## Code Style

: Follow standard conventions

## Recent Changes
- 062-frigate-ha-integration: Added YAML (Kubernetes/Ansible), Home Assistant (latest), Frigate (stable) + Frigate Custom Integration, HACS (Home Assistant Community Store), Mosquitto (MQTT)

- 058-wireguard-management-vpn: Added

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
