# Data Model: MQTT migrate to fleet1.lan

**Feature**: `056-mqtt-lan-migration` | **Date**: 2026-04-28

This migration has no new persistent entities or schema changes. The model documents the before/after state of each infrastructure resource being modified.

---

## Resource: Mosquitto TLS Certificate (`mosquitto-tls`)

**Kind**: `cert-manager.io/v1 Certificate`
**Namespace**: `home-automation`
**File**: `manifests/home-automation/prereqs/certificates.yaml`

| Field | Before | After |
|-------|--------|-------|
| `spec.dnsNames[0]` | `mqtt.fleet1.cloud` | `mqtt.fleet1.lan` |
| `spec.dnsNames[1]` | `mosquitto.home-automation.svc.cluster.local` | `mosquitto.home-automation.svc.cluster.local` (unchanged) |
| `spec.dnsNames[2]` | `mosquitto.home-automation` | `mosquitto.home-automation` (unchanged) |

cert-manager reissues the certificate automatically when the resource changes.

---

## Resource: Mosquitto Traefik TCP Route (`mosquitto-mqtts`)

**Kind**: `traefik.io/v1alpha1 IngressRouteTCP`
**Namespace**: `home-automation`
**File**: `manifests/home-automation/prereqs/mosquitto-tcp-route.yaml`

| Field | Before | After |
|-------|--------|-------|
| `spec.routes[0].match` | `HostSNI('mqtt.fleet1.cloud')` | `HostSNI('mqtt.fleet1.lan')` |
| `spec.tls.passthrough` | `true` | `true` (unchanged) |

---

## Resource: Mosquitto Hostname (Ansible default)

**File**: `roles/mosquitto/defaults/main.yml`

| Variable | Before | After |
|----------|--------|-------|
| `mosquitto_hostname` | `mqtt.fleet1.cloud` | `mqtt.fleet1.lan` |

Used by: `roles/mosquitto/templates/ingress-route-tcp.yaml.j2` (initial bootstrap template — not the live ArgoCD-managed manifest).

---

## Resource: Frigate NVR Config — MQTT Broker

**File**: `roles/nvr/defaults/main.yml` + `roles/nvr/templates/frigate-config.yml.j2`

| Variable | Before | After |
|----------|--------|-------|
| `nvr_mqtt_broker_ip` (removed) | `"10.1.20.11"` | — |
| `nvr_mqtt_broker_host` (added) | — | `"mqtt.fleet1.lan"` |

Template change in `frigate-config.yml.j2`:

```yaml
# Before
host: "{{ nvr_mqtt_broker_ip }}"

# After
host: "{{ nvr_mqtt_broker_host }}"
```

Frigate's `port`, `tls_ca_certs`, `tls_client_cert`, `tls_client_key` fields are unchanged.

---

## Resource: OPNsense DNAT Rule (new)

**Managed by**: `playbooks/network/network-deploy.yml`
**API endpoint**: `/api/firewall/d_nat/addRule`

| Field | Value |
|-------|-------|
| `interface` | `lan` |
| `protocol` | `tcp` |
| `destination.address` | `10.1.20.11` |
| `destination.port` | `8883` |
| `target` | `10.1.20.11` |
| `local-port` | `30883` |
| `descr` | `fleet1.lan MQTTS → Traefik NodePort` |

Mirrors the existing HTTPS DNAT (`443 → 30443`) in structure and idempotency key (`descr` field).

---

## Unchanged Resources

| Resource | Why unchanged |
|----------|--------------|
| Mosquitto Kubernetes Service | Already ClusterIP (raw manifest); no `type:` field to change |
| HA `home-assistant-values.yaml` | Uses `mosquitto.home-automation.svc.cluster.local` |
| Node-RED `node-red-values.yaml` | Uses `mosquitto.home-automation.svc.cluster.local` |
| Frigate client cert (`mqtt-client-cert.yaml`) | Client cert SAN is independent of server hostname |
| OPNsense firewall rule seq 200 | `10.1.10.11 → 10.1.20.0/24:8883` still valid post-DNAT |
| Mosquitto broker config | Broker itself unchanged; only routing and cert change |
