# Feature Specification: Home Automation Stack

**Feature Branch**: `016-home-automation-stack`
**Created**: 2026-04-02
**Status**: Draft
**Input**: User description: "Add Home Assistant, Mosquitto, NodeRed, and InfluxDB to the cluster and configure secure integration between them"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Home Assistant accessible over HTTPS with MQTT device integration (Priority: P1)

An operator opens `https://hass.fleet1.cloud` and completes Home Assistant onboarding. IoT sensors on the `10.1.40.x` VLAN publish to the Mosquitto MQTT broker (MQTTS on port 8883) and are discovered automatically by Home Assistant's MQTT integration.

**Why this priority**: Core value — the cluster hosts a functional home automation controller with secure device connectivity. Everything else builds on this.

**Independent Test**: Open `https://hass.fleet1.cloud` → onboarding wizard completes → add MQTT integration pointing to `mosquitto.home-automation.svc.cluster.local:8883` → a test device publishing to `homeassistant/sensor/test/state` appears as an entity.

**Acceptance Scenarios**:

1. **Given** the stack is deployed, **When** an operator visits `https://hass.fleet1.cloud`, **Then** the Home Assistant UI loads over HTTPS with a valid TLS certificate.
2. **Given** a sensor publishes to MQTTS on port 8883, **When** Home Assistant's MQTT integration is configured, **Then** the sensor entity appears in HA within 30 seconds.
3. **Given** HA is behind Traefik, **When** HA receives a request, **Then** it trusts the `X-Forwarded-For` header from the pod CIDR and correctly identifies the client IP.

---

### User Story 2 - Mosquitto MQTT broker enforces MQTTS with client certificates (Priority: P2)

Mosquitto is reachable on port 8883 from all VLANs. Plaintext port 1883 is disabled. All clients (Home Assistant, Node-RED, IoT devices) authenticate using client certificates issued by the cluster's internal CA. Password-only auth is rejected.

**Why this priority**: Principle VI and VII compliance — without this the MQTT broker violates the cluster security constitution.

**Independent Test**: `mosquitto_pub --cafile ca.crt --cert client.crt --key client.key -h mqtt.fleet1.cloud -p 8883 -t test -m hello` succeeds. `mosquitto_pub -h mqtt.fleet1.cloud -p 8883 -t test -m hello` (no cert) is rejected.

**Acceptance Scenarios**:

1. **Given** Mosquitto is deployed, **When** a client connects without a certificate, **Then** the connection is refused.
2. **Given** a valid client cert from the internal CA, **When** a client connects on port 8883, **Then** the connection succeeds and the client can publish/subscribe.
3. **Given** the server TLS cert is rotated by cert-manager, **When** the cert Secret is updated, **Then** Mosquitto restarts automatically and reconnects all clients.

---

### User Story 3 - InfluxDB stores Home Assistant long-term metrics (Priority: P3)

Home Assistant's built-in InfluxDB integration writes all entity state changes to InfluxDB 2.x. An operator can query the data via the InfluxDB UI at `https://influxdb.fleet1.cloud` or via Grafana.

**Why this priority**: Long-term storage for home automation metrics — the HA SQLite database only retains a rolling window; InfluxDB provides indefinite retention.

**Independent Test**: Open `https://influxdb.fleet1.cloud` → Data Explorer → query `homeassistant` bucket → entity state points appear.

**Acceptance Scenarios**:

1. **Given** HA and InfluxDB are running, **When** a sensor changes state, **Then** the new state is written to InfluxDB within 30 seconds.
2. **Given** Influx data exists, **When** Grafana queries the InfluxDB datasource (InfluxQL v1 compatibility), **Then** dashboards render entity history.
3. **Given** InfluxDB is redeployed, **When** the Longhorn PVC is retained, **Then** historical data survives the redeployment.

---

### User Story 4 - Node-RED provides flow automation accessible over HTTPS (Priority: P4)

An operator opens `https://node-red.fleet1.cloud`, creates flows that subscribe to Mosquitto MQTT topics, and writes processed results back to MQTT and/or InfluxDB.

**Why this priority**: Extends automation beyond HA's native capabilities — provides a visual programming environment for complex multi-step flows.

**Independent Test**: Open `https://node-red.fleet1.cloud` → deploy a flow that subscribes to an MQTT topic via MQTTS → verify message receipt in the Debug sidebar.

**Acceptance Scenarios**:

1. **Given** Node-RED is deployed, **When** an operator opens `https://node-red.fleet1.cloud`, **Then** the UI loads over HTTPS with a valid cert.
2. **Given** an MQTT broker node configured with the Mosquitto service DNS name and client cert, **When** a flow is deployed, **Then** Node-RED connects to Mosquitto successfully.
3. **Given** the Node-RED PVC contains saved flows, **When** the Node-RED pod restarts, **Then** all flows are restored automatically.

---

### Edge Cases

- What happens if Mosquitto's TLS cert rotates while HA and Node-RED are connected — are they automatically reconnected?
- What if InfluxDB storage fills up — does it evict old data or reject new writes?
- What if the `home-automation` namespace is deleted — are Longhorn PVCs preserved?
- What if a cert-manager Certificate renewal fails — does Mosquitto continue serving with the expired cert?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Mosquitto MUST serve MQTTS exclusively on port 8883; plaintext port 1883 MUST be disabled.
- **FR-002**: MQTT clients MUST authenticate using client certificates issued by the cluster's internal CA.
- **FR-003**: Mosquitto's server TLS certificate MUST be issued by cert-manager (Let's Encrypt DNS-01 for external access; internal CA for in-cluster clients).
- **FR-004**: Home Assistant MUST be accessible at `https://hass.fleet1.cloud` via Traefik.
- **FR-005**: Home Assistant MUST be configured to trust the K3s pod CIDR as a reverse proxy.
- **FR-006**: InfluxDB 2.x MUST be deployed with a Longhorn-backed PVC and credentials stored as a K8s Secret.
- **FR-007**: Home Assistant's built-in InfluxDB integration MUST write entity states to the `homeassistant` bucket.
- **FR-008**: Node-RED MUST be accessible at `https://node-red.fleet1.cloud` via Traefik with admin authentication enabled.
- **FR-009**: Node-RED MUST connect to Mosquitto via MQTTS using a client certificate mounted as a K8s Secret.
- **FR-010**: All services MUST use Longhorn PVCs with explicit storage sizes (HA: 10Gi, Mosquitto: 1Gi, Node-RED: 5Gi, InfluxDB: 20Gi).
- **FR-011**: All Ansible roles MUST be idempotent — re-running services-deploy.yml MUST NOT cause data loss or duplicate resources.
- **FR-012**: Mosquitto MUST restart automatically when cert-manager rotates its TLS Secret.

### Key Entities

- **Mosquitto**: Eclipse Mosquitto 2.x MQTT broker; serves MQTTS on 8883; uses cert-manager-issued TLS; enforces client cert auth
- **Home Assistant**: HA Core 2026.x; connects to Mosquitto as MQTT client; writes to InfluxDB; exposed via Traefik HTTPS
- **Node-RED**: Node-RED 4.x; connects to Mosquitto as MQTT client using a client cert; exposed via Traefik HTTPS
- **InfluxDB**: InfluxDB 2.7.x; receives writes from HA; admin credentials in K8s Secret; exposed via Traefik HTTPS
- **Internal CA**: cert-manager ClusterIssuer backed by a self-signed CA; issues client certs for Mosquitto mTLS
- **Mosquitto TLS Certificate**: Let's Encrypt cert for `mqtt.fleet1.cloud` via DNS-01; mounted into Mosquitto pod

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All four services start successfully on the first `services-deploy.yml` run.
- **SC-002**: Mosquitto rejects all plaintext (port 1883) and no-certificate connections.
- **SC-003**: Home Assistant discovers MQTT devices automatically within 30 seconds of publish.
- **SC-004**: InfluxDB contains Home Assistant entity states within 60 seconds of HA startup.
- **SC-005**: Node-RED UI loads at `https://node-red.fleet1.cloud` with admin login.
- **SC-006**: Re-running `services-deploy.yml` produces no errors and causes no data loss.
