# Implementation Plan: MQTT migrate to fleet1.lan

**Branch**: `056-mqtt-lan-migration` | **Date**: 2026-04-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/056-mqtt-lan-migration/spec.md`

## Summary

Replace the `mqtt.fleet1.cloud` MQTT ingress with `mqtt.fleet1.lan` using the same Traefik SNI + DNAT pattern used by all other fleet1.lan HTTPS services. Key changes: update the Mosquitto server cert SAN, replace the Traefik TCP IngressRoute hostname, update Frigate from a raw IP to the new hostname, and add a DNAT rule to translate port 8883 → Traefik NodePort 30883. Home Assistant and Node-RED are unaffected — they use in-cluster DNS.

## Technical Context

**Language/Version**: YAML (Ansible 2.x + Kubernetes manifests)
**Primary Dependencies**: cert-manager (Certificate), Traefik v3 (IngressRouteTCP), ArgoCD (GitOps sync), OPNsense REST API (d_nat, unbound, firewall)
**Storage**: N/A — no storage changes
**Testing**: Manual — MQTT client connect/publish/subscribe against `mqtt.fleet1.lan:8883`
**Target Platform**: K3s cluster (arm64), OPNsense router (`10.1.1.1`), NVR host (`10.1.10.11`)
**Project Type**: Infrastructure/config migration
**Performance Goals**: `mqtt.fleet1.lan` resolves and connects within 5 seconds (SC-002)
**Constraints**: Must not disrupt active MQTT sessions during migration window (SC-005). Confirm-then-retire pattern required (FR-004).
**Scale/Scope**: Three consumers (HA, Node-RED, Frigate); one broker; one cert; one TCP route.

### Key Architectural Finding — DNAT Required

`*.fleet1.lan` resolves (via OPNsense Unbound wildcard) to `10.1.20.11` (node1 host IP).
Traefik is a NodePort service: HTTPS uses `30443` (with DNAT `443 → 30443`), MQTTS uses NodePort `30883`.
There is currently **no DNAT rule for port 8883**. Without it, `mqtt.fleet1.lan:8883` hits the host IP on port 8883 but Traefik is listening on `30883`.

**Required addition**: OPNsense DNAT rule `10.1.20.11:8883 → 10.1.20.11:30883`, identical in structure to the existing `443 → 30443` HTTPS DNAT.

The existing firewall rule `10.1.10.11 (NVR) → 10.1.20.0/24:8883` (seq 200) continues to work — it allows Frigate to reach node1:8883, which the DNAT then redirects to Traefik.

### Mosquitto Service Type

Mosquitto is deployed as **raw Kubernetes manifests** (`manifests/home-automation/prereqs/mosquitto.yaml`), not a Helm chart. The Service manifest has no `type:` field, which defaults to ClusterIP. FR-007 (change to ClusterIP) is **already satisfied** in the live deployment. The `roles/mosquitto/templates/values.yaml.j2` with `service: type: LoadBalancer` is stale from the prior Helm-based approach and is no longer applied.

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I — Infrastructure as Code | ✅ Pass | All changes via Ansible tasks and Git-tracked manifests |
| II — Idempotency | ✅ Pass | DNAT rule uses description-keyed upsert pattern (already established); manifest edits are declarative |
| IV — Secrets Hygiene | ✅ Pass | Cert SAN change is via cert-manager Certificate resource; no private key material in Git |
| V — Simplicity | ✅ Pass | Hostname swap only; no new services, roles, or abstractions |
| VI — Encryption in Transit | ✅ Pass | MQTTS (port 8883 + TLS passthrough) maintained throughout |
| VII — Least Privilege | ✅ Pass | mTLS (client cert) preserved; firewall rules unchanged; Mosquitto remains ClusterIP |
| IX — Secure Service Exposure | ✅ Pass | TLS-only ingress maintained via Traefik SNI passthrough |
| X — Intra-Cluster Locality | ✅ Pass | HA and Node-RED remain on `mosquitto.home-automation.svc.cluster.local` |
| XI — GitOps Deployment | ✅ Pass | Manifest changes pushed to Gitea → ArgoCD syncs; no `kubectl apply` |

**No violations. No Complexity Tracking required.**

## Project Structure

### Documentation (this feature)

```text
specs/056-mqtt-lan-migration/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created by /speckit.plan)
```

### Source Code (affected files)

```text
manifests/home-automation/prereqs/
├── certificates.yaml          ← SAN: replace mqtt.fleet1.cloud with mqtt.fleet1.lan
└── mosquitto-tcp-route.yaml   ← HostSNI: replace mqtt.fleet1.cloud with mqtt.fleet1.lan

roles/mosquitto/
└── defaults/main.yml          ← mosquitto_hostname: mqtt.fleet1.cloud → mqtt.fleet1.lan

roles/nvr/
├── defaults/main.yml          ← rename nvr_mqtt_broker_ip → nvr_mqtt_broker_host; value → "mqtt.fleet1.lan"
└── templates/
    └── frigate-config.yml.j2  ← host: "{{ nvr_mqtt_broker_ip }}" → "{{ nvr_mqtt_broker_host }}"

playbooks/network/
└── network-deploy.yml         ← add DNAT rule: 10.1.20.11:8883 → 10.1.20.11:30883
```
