# Implementation Plan: Home Automation Stack

**Branch**: `016-home-automation-stack` | **Date**: 2026-04-02 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/016-home-automation-stack/spec.md`

## Summary

Deploy Home Assistant, Mosquitto (MQTT broker), Node-RED, and InfluxDB to the K3s cluster as four Ansible Helm roles in a shared `home-automation` namespace. All services use Longhorn-backed PVCs. Mosquitto serves MQTTS exclusively on port 8883 via a Traefik IngressRouteTCP with TLS passthrough; client certificates are issued by a new `home-automation-ca` internal ClusterIssuer. Home Assistant and Node-RED mount client certs from cert-manager Secrets to authenticate to Mosquitto. Home Assistant writes long-term metrics to InfluxDB 2.x via the built-in integration.

## Technical Context

**Language/Version**: YAML (Ansible 2.x) — follows existing project conventions
**Primary Dependencies**:
- `pajikos/home-assistant` Helm chart — `http://pajikos.github.io/home-assistant-helm-chart/`
- `helmforgedev/mosquitto` Helm chart — `https://helmforgedev.github.io/charts/`
- `schwarzit/node-red` Helm chart — `https://schwarzit.github.io/node-red-chart/`
- `influxdata/influxdb2` Helm chart — `https://helm.influxdata.com/`
- cert-manager (already installed) — `letsencrypt-prod` ClusterIssuer + new `home-automation-ca` CA issuer
- Traefik (already installed) — needs new `mqtts` TCP entrypoint on port 8883
- Stakater Reloader — watches Mosquitto TLS Secret for cert rotation

**Storage**: Longhorn `storageClass: longhorn` — Mosquitto: 1Gi, HA: 10Gi, Node-RED: 5Gi, InfluxDB: 20Gi
**Testing**: Manual smoke tests — pod health, MQTTS connection, InfluxDB write, UI access
**Target Platform**: K3s on Raspberry Pi CM5 (arm64/linux)
**Project Type**: Infrastructure automation (Ansible roles + Helm)
**Performance Goals**: Homelab scale — <10 connected devices, <100 MQTT messages/sec
**Constraints**: arm64 images required; all secrets via `group_vars/all.yml`; MQTTS only (no plaintext 1883)
**Scale/Scope**: Single homelab, 4–6 cluster nodes

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design — all gates pass.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Infrastructure as Code | PASS | All services deployed via Ansible Helm roles; no manual kubectl |
| II. Idempotency | PASS | `helm upgrade --install`, idempotent namespace creation, `kubernetes.core.k8s` for Secrets |
| III. Reproducibility | PASS | All configuration in repository; new secrets documented in `example.all.yml` |
| IV. Secrets Hygiene | PASS | InfluxDB token, Mosquitto passwordfile, Node-RED admin hash in `group_vars/all.yml` (gitignored); TLS certs via cert-manager; no secrets committed |
| V. Simplicity | PASS | Community Helm charts; single namespace; 4 roles follow identical loki/grafana pattern |
| VI. Encryption in Transit | PASS | MQTTS-only on 8883 (plaintext 1883 disabled); Traefik terminates TLS for HTTP services |
| VII. Least Privilege & Cert Auth | PASS | MQTT clients (HA, Node-RED, IoT devices) require client certs from `home-automation-ca`; narrowed per-device ACLs via `use_identity_as_username` |
| VIII. Persistent Storage | PASS | All four services use explicit Longhorn PVCs with stated sizes |
| IX. Secure Service Exposure | PASS | HTTPS for HA, Node-RED, InfluxDB via Traefik; MQTTS for Mosquitto via IngressRouteTCP passthrough |
| X. Intra-Cluster Service Locality | PASS | In-cluster traffic uses `*.home-automation.svc.cluster.local`; CoreDNS overrides needed for any public hostnames used intra-cluster (none in this feature) |
| XI. GitOps Application Deployment | JUSTIFIED DEVIATION | All four services use Helm charts — placed in "Helm-managed = Ansible-managed" category consistent with Loki/Grafana/Prometheus precedent. See Complexity Tracking. |

## Project Structure

### Documentation (this feature)

```text
specs/016-home-automation-stack/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output — chart choices, architectural decisions
├── data-model.md        # Phase 1 output — entities, secrets, network topology, role structure
├── quickstart.md        # Phase 1 output — deploy procedure, post-deploy steps
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
roles/
├── mosquitto/
│   ├── defaults/main.yml
│   ├── tasks/main.yml
│   └── templates/
│       ├── values.yaml.j2
│       ├── ca-issuer.yaml.j2          # SelfSigned issuer + home-automation-ca CA cert + CA ClusterIssuer
│       ├── server-cert.yaml.j2        # mosquitto-tls Certificate (Let's Encrypt)
│       ├── client-cert.yaml.j2        # Parameterized client cert (HA, Node-RED)
│       └── ingress-route-tcp.yaml.j2  # IngressRouteTCP for MQTTS on port 8883
├── influxdb/
│   ├── defaults/main.yml
│   ├── tasks/main.yml
│   └── templates/
│       └── values.yaml.j2
├── home-assistant/
│   ├── defaults/main.yml
│   ├── tasks/main.yml
│   └── templates/
│       ├── values.yaml.j2
│       └── config-extra.yaml.j2       # ConfigMap: http.yaml + influxdb2.yaml fragments
└── node-red/
    ├── defaults/main.yml
    ├── tasks/main.yml
    └── templates/
        └── values.yaml.j2

# Modified files
roles/traefik/files/values.yaml         # Add mqtts entrypoint (port 8883)
playbooks/cluster/services-deploy.yml   # Add 4 new roles with home-automation tags
group_vars/example.all.yml              # Document new secrets
```

**Structure Decision**: Four dedicated roles under `roles/`, one per service, following the identical structure of `roles/loki/`. All deployed from the existing `playbooks/cluster/services-deploy.yml`. No new playbooks required.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Principle XI deviation: Helm-managed HA and Node-RED instead of ArgoCD GitOps | These services require credential bootstrapping (K8s Secrets from `group_vars/all.yml`) before pod startup, which is natural in Ansible but requires extending `argocd-bootstrap` for Helm source type | Extending `argocd-bootstrap` to support external Helm repos adds ~2× implementation complexity and diverges from the monitoring stack precedent (Loki, Grafana, Prometheus are all Ansible Helm roles) |
| New `home-automation-ca` ClusterIssuer (internal PKI) | Mosquitto requires mTLS with client certs that don't need public trust; IoT devices need lightweight cert provisioning without ACME; per Principle VII | Skipping client auth would violate Principle VII; using Let's Encrypt for client certs is unsupported by ACME |
| Stakater Reloader dependency | Mosquitto does not hot-reload TLS certs; cert-manager rotation without pod restart leaves the broker running with an expired cert | Alternatives (init container polling, manual cron) add complexity without the reuse benefits of a standard Kubernetes controller |
