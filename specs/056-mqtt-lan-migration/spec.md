# Feature Specification: MQTT migrate to fleet1.lan

**Feature Branch**: `056-mqtt-lan-migration`
**Created**: 2026-04-28
**Status**: Draft
**Input**: User description: "I want to create mqtt.fleet1.lan and remove mqtt.fleet1.cloud once confirmed the .lan is working"

## Clarifications

### Session 2026-04-28

- Q: Frigate connects via raw IP (`10.1.20.11:8883`), not a hostname. Should it be updated to use `mqtt.fleet1.lan`, or left IP-based? → A: Update Frigate to use `mqtt.fleet1.lan` hostname (requires NVR host to resolve fleet1.lan via OPNsense Unbound).
- Q: HA and Node-RED use `mosquitto.home-automation.svc.cluster.local` — should they be migrated to `mqtt.fleet1.lan`? → A: No — leave them on cluster-internal DNS; no changes needed.
- Q: How should `mqtt.fleet1.lan` route to Mosquitto from the NVR host? → A: Via Traefik — wildcard Unbound resolves to Traefik, new `IngressRouteTCP` matches `HostSNI('mqtt.fleet1.lan')` with TLS passthrough.
- Q: The Mosquitto server cert has only `mqtt.fleet1.cloud` as a SAN. How should it be updated? → A: Replace `mqtt.fleet1.cloud` with `mqtt.fleet1.lan` (clean cutover; no dual-SAN transition needed).
- Q: With all consumers moving to Traefik, should the Mosquitto service type change from `LoadBalancer` to `ClusterIP`? → A: Yes — change to ClusterIP; all external access via Traefik only, eliminating direct LAN exposure.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — MQTT accessible via fleet1.lan (Priority: P1)

Internal MQTT clients (IoT devices, Home Assistant, Node-RED, Frigate) can reach the MQTT broker at `mqtt.fleet1.lan` using the same credentials and port as before. The hostname is consistent with all other fleet1.lan services.

**Why this priority**: Core deliverable. Until `mqtt.fleet1.lan` is reachable and stable, retirement of the old hostname cannot proceed.

**Independent Test**: An MQTT client can connect to `mqtt.fleet1.lan:8883` (MQTTS) and successfully publish and subscribe to a test topic.

**Acceptance Scenarios**:

1. **Given** the MQTT broker is running, **When** a client connects to `mqtt.fleet1.lan:8883` with valid credentials, **Then** the connection succeeds and messages can be published and received.
2. **Given** `mqtt.fleet1.lan` is configured, **When** an internal DNS lookup is performed, **Then** it resolves to the correct broker endpoint.
3. **Given** Home Assistant is reconfigured to use `mqtt.fleet1.lan`, **When** HA connects to the broker, **Then** all MQTT-based automations and device state updates continue to function without interruption.

---

### User Story 2 — mqtt.fleet1.cloud retired cleanly (Priority: P2)

After `mqtt.fleet1.lan` is confirmed working, `mqtt.fleet1.cloud` is removed from DNS and routing configuration. No dangling records or rules remain.

**Why this priority**: Reduces attack surface and simplifies network config. Must follow US1 verification — retirement before confirmation risks an outage.

**Independent Test**: `mqtt.fleet1.cloud` no longer resolves internally and all previously working clients remain connected via `mqtt.fleet1.lan`.

**Acceptance Scenarios**:

1. **Given** `mqtt.fleet1.lan` is confirmed working, **When** the fleet1.cloud MQTT DNS override is removed, **Then** `mqtt.fleet1.cloud` no longer resolves from inside the network.
2. **Given** `mqtt.fleet1.cloud` relied on internal Unbound overrides and/or DNAT rules, **When** retirement is complete, **Then** all associated rules are also removed.
3. **Given** all internal consumers have been migrated, **When** `mqtt.fleet1.cloud` is removed, **Then** zero service disruptions occur.

---

### Edge Cases

- A device still hardcoded to `mqtt.fleet1.cloud` after retirement will fail to connect — all consumers must be migrated before removal.
- If `mqtt.fleet1.cloud` is also a public Cloudflare DNS record (external), it must be removed there separately from the internal Unbound override.
- Home Assistant and Node-RED may hold cached connections; a service restart after config update ensures clean re-connection to the new hostname.
- Frigate runs on the NVR host (VLAN10, `10.1.10.11`) outside the cluster. Updating it to use `mqtt.fleet1.lan` requires that OPNsense Unbound resolves `fleet1.lan` names from VLAN10.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `mqtt.fleet1.lan` MUST resolve via the existing wildcard `*.fleet1.lan` Unbound override to Traefik. A new `IngressRouteTCP` matching `HostSNI('mqtt.fleet1.lan')` with TLS passthrough MUST be added to route MQTTS traffic to the Mosquitto service.
- **FR-002**: MQTT clients MUST be able to connect to `mqtt.fleet1.lan` on port 8883 (MQTTS) using existing credentials without any credential changes. The Mosquitto server cert MUST include `mqtt.fleet1.lan` as a SAN (replacing `mqtt.fleet1.cloud`).
- **FR-002a**: The existing `mosquitto-tcp-route.yaml` manifest matching `HostSNI('mqtt.fleet1.cloud')` MUST be replaced with a route matching `HostSNI('mqtt.fleet1.lan')`.
- **FR-003**: Frigate MUST be updated from raw IP (`10.1.20.11`) to the `mqtt.fleet1.lan` hostname. Home Assistant and Node-RED remain on `mosquitto.home-automation.svc.cluster.local` (in-cluster DNS) — no changes required for them.
- **FR-004**: The `mqtt.fleet1.cloud` DNS override MUST NOT be removed until `mqtt.fleet1.lan` is verified working end-to-end.
- **FR-005**: Any DNAT or firewall rules specific to `mqtt.fleet1.cloud` MUST be removed as part of retirement.
- **FR-006**: All provisioning changes MUST be idempotent — re-running must not create duplicate DNS entries or routing rules.
- **FR-007**: The Mosquitto Kubernetes service type MUST be changed from `LoadBalancer` to `ClusterIP`. All external MQTT access MUST route exclusively through Traefik after migration.

### Key Entities

- **Traefik IngressRouteTCP**: New TCP route matching `HostSNI('mqtt.fleet1.lan')` with TLS passthrough → Mosquitto service port 8883. `mqtt.fleet1.lan` resolves via the wildcard `*.fleet1.lan` Unbound override (no specific override needed).
- **MQTT broker (Mosquitto)**: Unchanged — only the hostname routing changes, not the broker itself.
- **Internal consumers**: Home Assistant and Node-RED (in-cluster, currently use `mosquitto.home-automation.svc.cluster.local`); Frigate (NVR host on VLAN10, currently uses raw IP `10.1.20.11`). All three must be updated to use `mqtt.fleet1.lan`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `mqtt.fleet1.lan` resolves correctly on first internal DNS query with no retries.
- **SC-002**: An MQTT client connects, publishes, and receives a test message via `mqtt.fleet1.lan:8883` within 5 seconds. TLS cert validation against `mqtt.fleet1.lan` SAN succeeds.
- **SC-002a**: After migration, direct connection to the former Mosquitto LoadBalancer IP on port 8883 from VLAN10 fails (service is ClusterIP only).
- **SC-003**: All MQTT-dependent automations and device states in Home Assistant remain functional after migration with zero manual intervention required.
- **SC-004**: After retirement, `mqtt.fleet1.cloud` returns NXDOMAIN on an internal DNS lookup.
- **SC-005**: Zero MQTT service disruptions during the migration window.

## Assumptions

- The Mosquitto broker port 8883 is unchanged. The service type changes from LoadBalancer to ClusterIP — the broker IP is no longer directly accessible from the LAN after migration.
- `mqtt.fleet1.cloud` is currently served only via an internal Unbound override, not as a public Cloudflare DNS record pointing to an external IP. This will be verified before retirement.
- Home Assistant and Node-RED currently use the in-cluster DNS name `mosquitto.home-automation.svc.cluster.local`, not `mqtt.fleet1.cloud`. Frigate currently uses the Mosquitto LoadBalancer IP (`10.1.20.11`) directly, not a hostname. Neither path uses `mqtt.fleet1.cloud` — the Traefik TCP route for that hostname may be unused.
- The migration follows a confirm-then-retire pattern: `.lan` verified working before `.cloud` is removed.
- MQTTS (port 8883 with TLS) is the only protocol in scope; plain MQTT (port 1883) is not used.
- The wildcard `*.fleet1.lan` Unbound override already routes `mqtt.fleet1.lan` to the correct node — a specific override may not be needed, but routing verification is required.
