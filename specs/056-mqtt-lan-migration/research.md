# Research: MQTT migrate to fleet1.lan

**Feature**: `056-mqtt-lan-migration` | **Date**: 2026-04-28

## Findings

### 1. Routing Architecture — DNAT Required

**Decision**: Add an OPNsense DNAT rule translating `10.1.20.11:8883 → 10.1.20.11:30883`.

**Rationale**: The `*.fleet1.lan` Unbound wildcard resolves to `10.1.20.11` (node1). Traefik is a NodePort service — its `mqtts` entrypoint listens on NodePort `30883`, not `8883`. The existing HTTPS ingress already uses an identical DNAT (`443 → 30443`). Port 8883 has no DNAT rule today. Without it, clients connecting to `mqtt.fleet1.lan:8883` hit the node host on port 8883, which is not Traefik's NodePort.

**Alternatives considered**:
- Switch Traefik to LoadBalancer service — rejected; would change all existing ingress IPs and NodePort assignments.
- Add a specific Unbound override for `mqtt.fleet1.lan` pointing to a different IP — rejected; unnecessarily diverges from the wildcard pattern.
- Use NodePort `30883` directly in Frigate config — rejected; exposes the NodePort detail to application config, bypasses consistent hostname design.

### 2. Mosquitto Service Type — Already ClusterIP

**Decision**: No service type change required.

**Rationale**: Mosquitto was migrated from a Helm chart (which had `service: type: LoadBalancer`) to raw Kubernetes manifests at `manifests/home-automation/prereqs/mosquitto.yaml`. The raw manifest Service has no `type:` field (= ClusterIP). The `roles/mosquitto/templates/values.yaml.j2` with `LoadBalancer` is a stale Ansible template from the prior Helm approach and is no longer applied to the cluster.

**Alternatives considered**: None — the desired state (ClusterIP) already exists.

### 3. Frigate MQTT Connection Path

**Decision**: Change Frigate from raw IP (`10.1.20.11`) to hostname `mqtt.fleet1.lan`. Rename variable `nvr_mqtt_broker_ip` → `nvr_mqtt_broker_host`.

**Rationale**: Frigate connects to `10.1.20.11:8883` (node1 host IP). With Mosquitto now ClusterIP and no DNAT for port 8883, this path is unreliable or broken. Switching Frigate to `mqtt.fleet1.lan` provides: (1) a stable hostname independent of node IP assignment, (2) proper TLS SNI for Traefik routing, (3) consistency with all other fleet1.lan services. The NVR host (VLAN10) can resolve `fleet1.lan` names via OPNsense Unbound (same resolver all hosts use).

**Alternatives considered**:
- Leave Frigate on IP — rejected; IP-based connections don't send SNI, so Traefik cannot route them. Also fragile if node IP changes.
- Use NodePort directly (`10.1.20.11:30883`) — rejected; bypasses hostname design and leaks infrastructure port detail into application config.

### 4. TLS Certificate SAN

**Decision**: Replace `mqtt.fleet1.cloud` with `mqtt.fleet1.lan` in the `mosquitto-tls` Certificate SAN list. The cluster-internal SAN `mosquitto.home-automation.svc.cluster.local` is retained (used by in-cluster clients).

**Rationale**: Frigate (and any other external client) validates the server cert against the hostname it connects to. With `mqtt.fleet1.lan` as the connection hostname, the cert must include it as a SAN. The `mqtt.fleet1.cloud` SAN is unused (no consumer connects via that hostname). cert-manager automatically reissues the cert when the Certificate resource changes.

**Alternatives considered**:
- Keep both SANs during a transition period — rejected; no consumer uses `mqtt.fleet1.cloud` today, so a dual-SAN cert serves no purpose and adds confusion.

### 5. Traefik IngressRouteTCP

**Decision**: Update `mosquitto-tcp-route.yaml` to match `HostSNI('mqtt.fleet1.lan')`. This is the live deployed manifest — it is not rendered from the Ansible template (`roles/mosquitto/templates/ingress-route-tcp.yaml.j2`). Also update `mosquitto_hostname` in `roles/mosquitto/defaults/main.yml` so the role template stays consistent with the deployed state.

**Rationale**: The deployed manifest `manifests/home-automation/prereqs/mosquitto-tcp-route.yaml` has a hardcoded `HostSNI('mqtt.fleet1.cloud')`. This is the actual ArgoCD-managed resource. The Ansible role template `ingress-route-tcp.yaml.j2` uses `{{ mosquitto_hostname }}` — this template exists for initial bootstrap but the manifest in `manifests/` is authoritative for the live cluster.

### 6. HA and Node-RED — No Changes

**Decision**: Home Assistant and Node-RED remain on `mosquitto.home-automation.svc.cluster.local`.

**Rationale**: Both services are in-cluster and connect via cluster DNS directly to the Mosquitto Service (bypassing Traefik entirely). Migrating them to `mqtt.fleet1.lan` would add an unnecessary Traefik hop and break the intra-cluster locality principle (X).

### 7. OPNsense Firewall Rule — No Changes

**Decision**: The existing NVR firewall rule (seq 200, `10.1.10.11 → 10.1.20.0/24:8883`) requires no modification.

**Rationale**: Frigate will continue to connect to `10.1.20.11:8883` (via `mqtt.fleet1.lan` DNS resolution). The DNAT rule then forwards this to Traefik on port `30883`. The firewall rule permits the initial connection — it doesn't need to know about the DNAT redirect.
