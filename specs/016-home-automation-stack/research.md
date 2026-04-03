# Research: Home Automation Stack

**Phase**: 0 — Research
**Branch**: `016-home-automation-stack`
**Date**: 2026-04-02

---

## Decision 1: Helm Charts for Each Service

### Home Assistant

- **Decision**: `pajikos/home-assistant` from `http://pajikos.github.io/home-assistant-helm-chart/`
- **Rationale**: Most actively maintained HA Helm chart (bot-updated with every HA release); native arm64 support via `ghcr.io/home-assistant/home-assistant`; StatefulSet by default for stable volume binding under Longhorn
- **Alternatives considered**: `k8s-home-lab/home-assistant` — less widely used; raw manifests — more maintenance overhead

### Mosquitto

- **Decision**: `helmforgedev/mosquitto` from `https://helmforgedev.github.io/charts/` (chart name: `mosquitto`)
- **Rationale**: Uses `eclipse-mosquitto:2.0.22` (current); supports TLS config via values; arm64 native; more recent and maintained than `t3n/mosquitto` (which pins an outdated 1.6.12 image)
- **Alternatives considered**: `t3n/mosquitto` — outdated image; raw manifests — viable but adds unnecessary maintenance since `helmforgedev/mosquitto` handles the Deployment/Service/ConfigMap plumbing

### Node-RED

- **Decision**: `schwarzit/node-red` from `https://schwarzit.github.io/node-red-chart/`
- **Rationale**: Most maintained Node-RED Helm chart (0.40.1, app 4.1.2); native arm64 via `nodered/node-red`; supports `additionalVolumes`/`additionalMounts` for client cert injection; `persistence.enabled` flag for PVC
- **Alternatives considered**: No other actively maintained chart found for Kubernetes

### InfluxDB

- **Decision**: `influxdata/influxdb2` from `https://helm.influxdata.com/`
- **Rationale**: Official InfluxDB Helm chart; arm64 native (`influxdb:2.7.4-alpine`); `adminUser.existingSecret` allows pre-provisioned credentials via K8s Secret (GitOps-safe); InfluxDB 2.x preferred over 1.x (arm64 support gap in v1 images; HA integration supports v2 natively)
- **Alternatives considered**: `bitnami/influxdb` — more opinionated secret conventions; InfluxDB 1.x — arm64 image quality inconsistent; InfluxDB 3.x — Helm chart enterprise-oriented

---

## Decision 2: InfluxDB Version — v1 vs v2

- **Decision**: InfluxDB 2.7.x
- **Rationale**:
  - InfluxDB 1.x has an open GitHub issue on incomplete arm64 multi-platform manifest support
  - InfluxDB 2.x has clean arm64 builds in the official Docker Hub image
  - HA's built-in InfluxDB integration supports v2 natively (token-based auth)
  - InfluxDB 2.x provides a v1 compatibility endpoint (`/query`) enabling InfluxQL queries from Grafana without requiring Flux
  - Token-based auth maps cleanly to K8s Secrets
- **Alternatives considered**: v1 — arm64 gaps, maintenance-mode; v3 — enterprise Helm chart only

---

## Decision 3: Mosquitto TLS Certificate — Let's Encrypt vs Internal CA

- **Decision**: Let's Encrypt DNS-01 (via existing `letsencrypt-prod` ClusterIssuer) for the **server cert** at `mqtt.fleet1.cloud`; Internal self-signed CA (`ClusterIssuer` of type `selfSigned`) for **client certs**
- **Rationale**:
  - Server cert: Let's Encrypt is already in use for all other services; Traefik SNI routing on the IngressRouteTCP requires a valid cert for TLS passthrough; browsers and external MQTT clients trust Let's Encrypt without extra CA distribution
  - Client certs: IoT devices (cameras, sensors) do not need publicly-trusted certs; an internal CA is simpler to manage and allows revocation per-device; cert-manager issues them automatically via `Certificate` resources
- **Alternatives considered**: Self-signed for both — requires CA distribution to IoT devices; Let's Encrypt for client certs — not supported (client certs are not ACME domain-validated)

---

## Decision 4: MQTT External Exposure — Traefik TCP vs LoadBalancer Service

- **Decision**: Traefik `IngressRouteTCP` with SNI on port 8883 via a new `mqtts` entrypoint added to Traefik's values
- **Rationale**:
  - Consistent with the existing Traefik-as-single-ingress pattern; all external traffic routes through Traefik
  - Traefik IngressRouteTCP with `HostSNI('mqtt.fleet1.cloud')` enables SNI-based routing on port 8883
  - The existing Traefik role's `values.yaml` needs one new entry in `ports:` for `mqtts` on 8883
  - TLS passthrough mode: Traefik forwards the TLS connection directly to Mosquitto; Mosquitto terminates TLS itself (required for mTLS client cert inspection)
- **Alternatives considered**: LoadBalancer Service — allocates a node port via K3s ServiceLB; less consistent with Traefik-first pattern; would also work but creates a separate external IP; NodePort on 8883 — inconsistent with rest of cluster ingress

---

## Decision 5: Mosquitto Cert Rotation Handling

- **Decision**: Deploy `stakater/Reloader` alongside Mosquitto to watch the TLS Secret and trigger a rolling restart on cert update
- **Rationale**: Mosquitto does not hot-reload TLS certs on SIGHUP or signal — a pod restart is required. Stakater Reloader (a lightweight Kubernetes controller) watches Secrets and triggers Deployment restarts when their content changes. This ensures cert rotation is automatic with zero operator intervention.
- **Alternatives considered**: cert-manager post-issuance webhook — more complex to configure; manual `kubectl rollout restart` — not automated; Init container polling — adds complexity; Reloader is the standard K8s community solution for this exact problem

---

## Decision 6: Namespace Strategy — Shared vs Isolated

- **Decision**: Single `home-automation` namespace for all four services
- **Rationale**:
  - Services communicate via Kubernetes DNS (`mosquitto.home-automation.svc.cluster.local`) — single namespace eliminates cross-namespace Service access complexity
  - Longhorn PVCs are namespace-scoped; a shared namespace groups all home automation storage together
  - Consistent with how the monitoring stack uses a single `monitoring` namespace for Prometheus, Grafana, Loki, and Alloy
  - RBAC can be scoped to the namespace if needed later
- **Alternatives considered**: Separate namespace per service — cleaner isolation but adds DNS cross-namespace routing; no practical security benefit for internal services

---

## Decision 7: Deployment Method — Ansible Helm Roles vs GitOps Manifests

- **Decision**: All four services deployed via Ansible Helm roles (same pattern as Loki, Prometheus, Grafana)
- **Rationale**:
  - All four services use community Helm charts, which places them in the "Helm-managed = Ansible-managed" category per the constitution's precedent
  - Ansible roles enable credential bootstrapping (creating K8s Secrets from `group_vars/all.yml` values) before Helm deployment — this is the standard pattern for InfluxDB, Mosquitto passwordfile, and Node-RED admin auth
  - The monitoring stack (Loki, Prometheus, Grafana) follows identical deployment pattern as Ansible Helm roles, establishing the precedent
- **Constitution Principle XI note**: HA and Node-RED could be considered application workloads subject to GitOps. However, their Helm chart dependency and credential-injection bootstrapping requirement makes Ansible the pragmatic choice. Documented in plan.md Complexity Tracking.
- **Alternatives considered**: ArgoCD Helm source — supported by ArgoCD but would require extending the `argocd-bootstrap` role to support Helm chart sources and external repos; adding complexity without benefit; raw manifests via GitOps — would require writing ~300 lines of Kubernetes YAML per service instead of 30-line Helm values files

---

## Decision 8: InfluxDB Credential Management

- **Decision**: Pre-create a K8s Secret (via Ansible `kubernetes.core.k8s` task) before Helm deployment; reference via `adminUser.existingSecret` in chart values
- **Rationale**:
  - `existingSecret` is the GitOps-safe pattern — the password and API token don't change on re-deploy
  - The InfluxDB chart reads `admin-password` and `admin-token` keys from the Secret
  - Home Assistant reads the token from `secrets.yaml` in the HA config volume (not directly from K8s Secrets) — the token is provisioned once during setup
- **Alternatives considered**: Auto-generated credentials — chart creates a random password that changes on first install, making the HA integration configuration fragile

---

## Decision 9: Home Assistant Configuration Management

- **Decision**: Mount a `ConfigMap` containing `configuration.yaml` additions (InfluxDB integration, HTTP proxy config) alongside the Helm-managed persistent volume
- **Rationale**:
  - The HA Helm chart supports `additionalVolumes` and `additionalMounts` for injecting extra config
  - `configuration.yaml` includes `influxdb2:` integration block (referencing `!secret influxdb_token`) and `http:` trusted_proxies block — these must be present before HA starts
  - The actual `secrets.yaml` with the real token is managed on the PVC (written by an Ansible task on first deploy)
- **Note**: HA's `!secret` macro reads from the `secrets.yaml` file in the config directory (not K8s Secrets) — this is HA-native secret management, appropriate for the config directory pattern

---

## Key arm64 / K3s Gotchas Resolved

1. **Home Assistant image**: Use `ghcr.io/home-assistant/home-assistant` only — Pi-specific images stopped updating mid-2023
2. **InfluxDB org field**: HA integration requires the org **ID** (hex UUID from URL) not the display name — document in `example.all.yml`
3. **Node-RED persistence**: Must set `persistence.enabled: true` — off by default in schwarzit chart; flows are lost on pod restart otherwise
4. **Traefik 8883 entrypoint**: The existing `roles/traefik/files/values.yaml` has no port 8883 entry — this role must be updated to add the `mqtts` entrypoint before Mosquitto ingress routing works
5. **Mosquitto TLS passthrough**: IngressRouteTCP must use `tls.passthrough: true` so Mosquitto handles TLS termination itself (required for mTLS client cert inspection — Traefik cannot inspect client certs in termination mode for TCP routes)
