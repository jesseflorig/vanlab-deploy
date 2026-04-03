# Tasks: Home Automation Stack

**Input**: Design documents from `/specs/016-home-automation-stack/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, quickstart.md ✓

**Organization**: Tasks grouped by user story priority. Each story is independently deployable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no shared dependencies)
- **[Story]**: User story label (US1–US4)

---

## Phase 1: Setup

**Purpose**: Traefik MQTTS entrypoint + role skeleton directories (must exist before any role tasks)

- [x] T001 Add `mqtts` TCP entrypoint (port 8883, nodePort 30883) to `roles/traefik/files/values.yaml`
- [x] T002 [P] Create directory tree `roles/mosquitto/{defaults,tasks,templates}/`
- [x] T003 [P] Create directory tree `roles/influxdb/{defaults,tasks,templates}/`
- [x] T004 [P] Create directory tree `roles/home-assistant/{defaults,tasks,templates}/`
- [x] T005 [P] Create directory tree `roles/node-red/{defaults,tasks,templates}/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared `home-automation` namespace, internal CA infrastructure, and secrets documentation — must exist before any service role can be applied.

**⚠️ CRITICAL**: The `home-automation-ca` ClusterIssuer created here is a hard dependency for US1–US4. No service role can complete without it.

- [x] T006 Document all new secrets with inline comments in `group_vars/example.all.yml` (influxdb_admin_password, influxdb_admin_token, influxdb_org_id, mosquitto_password_entry, node_red_admin_password_bcrypt)
- [x] T007 Create `roles/mosquitto/defaults/main.yml` — set mosquitto_namespace: home-automation, mosquitto_chart_version, mosquitto_pvc_size: 1Gi, mosquitto_hostname: mqtt.fleet1.cloud, reloader_chart_version
- [x] T008 Create `roles/mosquitto/templates/ca-issuer.yaml.j2` — three-document YAML: (1) `selfsigned-issuer` ClusterIssuer (SelfSigned), (2) `home-automation-ca` Certificate (isCA: true, namespace: cert-manager, secretName: home-automation-ca-secret, issuerRef: selfsigned-issuer), (3) `home-automation-ca` ClusterIssuer (ca.secretName: home-automation-ca-secret)
- [x] T009 Add namespace + CA issuer tasks to `roles/mosquitto/tasks/main.yml` — idempotent namespace creation (`kubectl create namespace --dry-run=client`), render and apply `ca-issuer.yaml.j2` via `kubernetes.core.k8s`, wait for `home-automation-ca` ClusterIssuer to reach Ready condition

**Checkpoint**: `home-automation` namespace exists and `home-automation-ca` ClusterIssuer is Ready — all service roles can now proceed

---

## Phase 3: User Story 1 — HA accessible over HTTPS + Mosquitto MQTTS (Priority: P1) 🎯 MVP

**Goal**: Home Assistant UI is reachable at `https://hass.fleet1.cloud`. Mosquitto is running on port 8883 with a Let's Encrypt TLS server certificate. HA can connect as an MQTT client.

**Independent Test**: `curl -I https://hass.fleet1.cloud` returns 200. `mosquitto_pub --cafile /etc/ssl/certs/ca-certificates.crt -h mqtt.fleet1.cloud -p 8883 -t test -m hello` connects (mTLS not yet required in this story — cert auth added in US2).

### Mosquitto role — server TLS + Helm deployment

- [x] T010 [US1] Create `roles/mosquitto/templates/server-cert.yaml.j2` — cert-manager Certificate resource: name: mosquitto-tls, namespace: `{{ mosquitto_namespace }}`, secretName: mosquitto-tls, issuerRef: letsencrypt-prod ClusterIssuer, dnsNames: [`{{ mosquitto_hostname }}`]
- [x] T011 [US1] Create `roles/mosquitto/templates/values.yaml.j2` — helmforgedev/mosquitto values: listener 8883 only (no 1883), cafile/certfile/keyfile paths from mounted mosquitto-tls Secret, persistence enabled with 1Gi Longhorn PVC, Reloader annotation `reloader.stakater.com/auto: "true"` on the Deployment
- [x] T012 [US1] Create `roles/mosquitto/templates/ingress-route-tcp.yaml.j2` — Traefik IngressRouteTCP: entryPoints: [mqtts], routes match `HostSNI('{{ mosquitto_hostname }}')`, service mosquitto port 8883, tls.passthrough: true
- [x] T013 [US1] Complete `roles/mosquitto/tasks/main.yml` — add Helm repo (helmforgedev), update repos, render server-cert.yaml.j2 and apply, render values.yaml.j2, `helm upgrade --install mosquitto helmforgedev/mosquitto --namespace {{ mosquitto_namespace }} --version {{ mosquitto_chart_version }} --values /tmp/mosquitto-values.yaml --wait --timeout 5m`, wait for Deployment rollout, verify PVC Bound, render and apply ingress-route-tcp.yaml.j2, add Stakater Reloader Helm repo (stakater) and `helm upgrade --install reloader stakater/reloader --namespace {{ mosquitto_namespace }} --wait`

### Home Assistant role

- [x] T014 [P] [US1] Create `roles/home-assistant/defaults/main.yml` — ha_namespace: home-automation, ha_chart_version, ha_pvc_size: 10Gi, ha_hostname: hass.fleet1.cloud, ha_image: ghcr.io/home-assistant/home-assistant
- [x] T015 [P] [US1] Create `roles/home-assistant/templates/values.yaml.j2` — pajikos/home-assistant values: image tag latest, persistence.enabled true storageClass longhorn size `{{ ha_pvc_size }}`, ingress enabled with Traefik annotations (websecure, tls: secretName fleet1-cloud-tls), env vars for HA_URL, additionalVolumes for home-assistant-config-extra ConfigMap and home-assistant-mqtt-client Secret
- [x] T016 [P] [US1] Create `roles/home-assistant/templates/config-extra.yaml.j2` — ConfigMap `home-assistant-config-extra` in `{{ ha_namespace }}`: data contains `http.yaml` with `use_x_forwarded_for: true` and `trusted_proxies: [10.42.0.0/16]`
- [x] T017 [US1] Create `roles/home-assistant/tasks/main.yml` — add Helm repo (pajikos), update repos, create ConfigMap from config-extra.yaml.j2 via `kubernetes.core.k8s`, `helm upgrade --install home-assistant pajikos/home-assistant --namespace {{ ha_namespace }} --version {{ ha_chart_version }} --values /tmp/ha-values.yaml --wait --timeout 10m`, wait for Deployment rollout, display summary with UI URL

### Playbook + services-deploy

- [x] T018 [US1] Add `mosquitto` and `home-assistant` roles to `playbooks/cluster/services-deploy.yml` under "Install Host Tools" play with tags `[home-automation, mosquitto]` and `[home-automation, hass]` respectively; mosquitto MUST appear before home-assistant

**Checkpoint**: `kubectl get pods -n home-automation` shows mosquitto and home-assistant Running. `curl -I https://hass.fleet1.cloud` returns 200. Mosquitto is serving on port 8883 with a valid LE cert.

---

## Phase 4: User Story 2 — Mosquitto mTLS client certificate enforcement (Priority: P2)

**Goal**: Mosquitto requires client certificates from all connecting clients. Plaintext and no-cert connections are refused. HA and future clients authenticate via certs from `home-automation-ca`. Mosquitto auto-restarts on cert rotation.

**Independent Test**: `mosquitto_pub -h mqtt.fleet1.cloud -p 8883 -t test -m hello` (no cert) → Connection refused. `mosquitto_pub --cafile ca.crt --cert ha-client.crt --key ha-client.key -h mqtt.fleet1.cloud -p 8883 -t test -m hello` → success.

- [x] T019 [US2] Update `roles/mosquitto/templates/values.yaml.j2` — add to mosquitto.conf: `require_certificate true`, `use_identity_as_username true`, mount mosquitto-passwords Secret as `/mosquitto/passwd/passwordfile`, mount home-automation-ca ConfigMap (CA cert) as `/certs/ca.crt` for client verification
- [x] T020 [US2] Create `roles/mosquitto/templates/client-cert.yaml.j2` — parameterized cert-manager Certificate template: variables `cert_name`, `cert_namespace`, `cert_cn`, `cert_secret_name`; issuerRef: home-automation-ca ClusterIssuer; usages: [client auth]
- [x] T021 [US2] Add password file Secret task to `roles/mosquitto/tasks/main.yml` — create K8s Secret `mosquitto-passwords` in `{{ mosquitto_namespace }}` with key `passwordfile` sourced from `{{ mosquitto_password_entry }}` variable using `kubernetes.core.k8s`
- [x] T022 [US2] Add HA client cert task to `roles/home-assistant/tasks/main.yml` — render client-cert.yaml.j2 with cert_name=home-assistant-mqtt-client, cert_cn=home-assistant, cert_secret_name=home-assistant-mqtt-client and apply via `kubernetes.core.k8s`; wait for Certificate Ready condition
- [x] T023 [US2] Update `roles/home-assistant/templates/values.yaml.j2` — add additionalVolume for `home-assistant-mqtt-client` Secret mounted at `/certs/mqtt-client/`; add MQTT_CLIENT_CERT_DIR env var pointing to mount path

**Checkpoint**: Re-run `services-deploy.yml --tags mosquitto,hass`. Verify no-cert connections rejected and cert-authenticated connections succeed.

---

## Phase 5: User Story 3 — InfluxDB + Home Assistant long-term metrics (Priority: P3)

**Goal**: InfluxDB 2.7 is accessible at `https://influxdb.fleet1.cloud`. Home Assistant's built-in InfluxDB integration writes entity states to the `homeassistant` bucket.

**Independent Test**: Open `https://influxdb.fleet1.cloud` → admin login succeeds. After HA connects: `kubectl exec -n home-automation deploy/influxdb -- influx query 'from(bucket:"homeassistant") |> range(start:-5m) |> limit(n:5)'` returns rows.

- [x] T024 [P] [US3] Create `roles/influxdb/defaults/main.yml` — influxdb_namespace: home-automation, influxdb_chart_version (2.x), influxdb_pvc_size: 20Gi, influxdb_hostname: influxdb.fleet1.cloud, influxdb_org: vanlab, influxdb_bucket: homeassistant, influxdb_secret_name: influxdb-auth
- [x] T025 [P] [US3] Create `roles/influxdb/templates/values.yaml.j2` — influxdata/influxdb2 values: adminUser.existingSecret: `{{ influxdb_secret_name }}`, adminUser.organization: `{{ influxdb_org }}`, adminUser.bucket: `{{ influxdb_bucket }}`, persistence.storageClass: longhorn, persistence.size: `{{ influxdb_pvc_size }}`, ingress.enabled true with Traefik annotations (websecure, tls fleet1-cloud-tls), service.type: ClusterIP
- [x] T026 [US3] Create `roles/influxdb/tasks/main.yml` — add Helm repo (influxdata), update repos, create K8s Secret `{{ influxdb_secret_name }}` with keys admin-password and admin-token from `group_vars/all.yml` using `kubernetes.core.k8s`, render values.yaml.j2, `helm upgrade --install influxdb influxdata/influxdb2 --namespace {{ influxdb_namespace }} --version {{ influxdb_chart_version }} --values /tmp/influxdb-values.yaml --wait --timeout 5m`, wait for StatefulSet rollout, verify PVC Bound, display summary with UI URL
- [x] T027 [US3] Update `roles/home-assistant/templates/config-extra.yaml.j2` — add `influxdb2.yaml` key to ConfigMap data: `influxdb2:` block with host `influxdb.home-automation.svc.cluster.local`, port 8086, token `!secret influxdb_token`, organization `!secret influxdb_org_id`, bucket homeassistant
- [x] T028 [US3] Add InfluxDB secrets.yaml write task to `roles/home-assistant/tasks/main.yml` — after Helm install, use `kubernetes.core.k8s_exec` to write `secrets.yaml` content (influxdb_token + influxdb_org_id from `group_vars/all.yml`) into the HA config PVC at `/config/secrets.yaml`; use `--dry-run` guard to skip if file already contains the token (idempotency)
- [x] T029 [US3] Add `influxdb` role to `playbooks/cluster/services-deploy.yml` with tags `[home-automation, influxdb]`; place before `home-assistant` in execution order (InfluxDB must be reachable when HA starts)

**Checkpoint**: `kubectl get pods -n home-automation` shows influxdb Running. InfluxDB UI loads at `https://influxdb.fleet1.cloud`. After re-running `--tags hass`, HA starts writing to InfluxDB.

---

## Phase 6: User Story 4 — Node-RED with MQTTS client cert (Priority: P4)

**Goal**: Node-RED is accessible at `https://node-red.fleet1.cloud` with admin authentication. It can connect to Mosquitto over MQTTS using a client certificate and persist flows across pod restarts.

**Independent Test**: Open `https://node-red.fleet1.cloud` → admin login prompt appears. Add MQTT broker node pointing to `mosquitto.home-automation.svc.cluster.local:8883` with client cert → flow deploys and connects.

- [x] T030 [P] [US4] Create `roles/node-red/defaults/main.yml` — nodered_namespace: home-automation, nodered_chart_version (0.40.x), nodered_pvc_size: 5Gi, nodered_hostname: node-red.fleet1.cloud, nodered_image: nodered/node-red, nodered_image_tag: 4.1.2
- [x] T031 [P] [US4] Create `roles/node-red/templates/values.yaml.j2` — schwarzit/node-red values: image.repository and tag, persistence.enabled true storageClass longhorn size `{{ nodered_pvc_size }}`, ingress.enabled true with Traefik annotations (websecure, tls fleet1-cloud-tls) host `{{ nodered_hostname }}`, settings.credentialSecret from env var, additionalVolumes for `node-red-mqtt-client` Secret mounted at `/certs/mqtt-client/`, env var NODE_RED_CREDENTIAL_SECRET from K8s Secret
- [x] T032 [US4] Add Node-RED client cert task to `roles/node-red/tasks/main.yml` using `roles/mosquitto/templates/client-cert.yaml.j2` — render with cert_name=node-red-mqtt-client, cert_cn=node-red, cert_secret_name=node-red-mqtt-client and apply; wait for Certificate Ready
- [x] T033 [US4] Create `roles/node-red/tasks/main.yml` — add Helm repo (schwarzit), update repos, create K8s Secret `node-red-admin` with node_red_admin_password_bcrypt from `group_vars/all.yml`, issue Node-RED MQTT client cert (T032), render values.yaml.j2, `helm upgrade --install node-red schwarzit/node-red --namespace {{ nodered_namespace }} --version {{ nodered_chart_version }} --values /tmp/node-red-values.yaml --wait --timeout 5m`, wait for Deployment rollout, verify PVC Bound, display summary with UI URL
- [x] T034 [US4] Add `node-red` role to `playbooks/cluster/services-deploy.yml` with tags `[home-automation, node-red]`; place after `mosquitto` (client cert issuer must exist)

**Checkpoint**: `kubectl get pods -n home-automation` shows node-red Running. `https://node-red.fleet1.cloud` requires admin login. MQTT broker node in Node-RED connects to Mosquitto successfully.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T035 Update `README.md` — add "Home Automation Stack" section listing service URLs (hass, node-red, influxdb, mqtt), namespace, and reference to `quickstart.md` for IoT device cert provisioning
- [x] T036 Verify `requirements.yml` includes `community.general` and `kubernetes.core` collections; add any missing entries
- [x] T037 [P] Add `ha_namespace: home-automation` variable to `roles/home-assistant/defaults/main.yml` (consolidate any hardcoded namespace references into defaults)
- [x] T038 Smoke-test full idempotency: re-run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags home-automation` twice and confirm no errors, no data loss, no duplicate resources

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately; T002–T005 fully parallel
- **Foundational (Phase 2)**: Depends on Phase 1 — **blocks all user stories**
- **US1 (Phase 3)**: Depends on Foundational; T014–T016 parallel once T009 complete
- **US2 (Phase 4)**: Depends on US1 completion (mosquitto and HA roles must exist)
- **US3 (Phase 5)**: Depends on Foundational; T024–T025 parallel; independent of US2
- **US4 (Phase 6)**: Depends on Foundational + `home-automation-ca` existing (T009); independent of US2/US3
- **Polish (Phase 7)**: Depends on all desired user stories complete

### User Story Dependencies

- **US1 (P1)**: Requires Foundational complete; no dependency on other stories
- **US2 (P2)**: Requires US1 (modifies Mosquitto role that US1 creates)
- **US3 (P3)**: Requires Foundational only; independent of US1/US2; HA role shared but additive
- **US4 (P4)**: Requires Foundational only; independent of US1/US2/US3

### Within Each Story

- Mosquitto role tasks are strictly sequential: defaults → templates → tasks/main.yml completion
- HA role: defaults + templates can be written in parallel; tasks/main.yml must come after
- InfluxDB role: defaults + templates parallel; tasks/main.yml after
- Node-RED role: defaults + templates parallel; tasks/main.yml after

### Parallel Opportunities

#### Phase 1

```bash
# All in parallel after T001:
T002 Create roles/mosquitto/ tree
T003 Create roles/influxdb/ tree
T004 Create roles/home-assistant/ tree
T005 Create roles/node-red/ tree
```

#### Phase 3 (once T009 complete)

```bash
# Mosquitto templates in parallel:
T010 server-cert.yaml.j2
T011 values.yaml.j2
T012 ingress-route-tcp.yaml.j2

# HA role in parallel with mosquitto templates:
T014 ha defaults/main.yml
T015 ha values.yaml.j2
T016 ha config-extra.yaml.j2
```

#### Phase 5 (independent of Phase 4)

```bash
# InfluxDB role in parallel:
T024 influxdb defaults/main.yml
T025 influxdb values.yaml.j2
```

#### Phase 6 (independent of Phases 4 and 5)

```bash
# Node-RED role in parallel:
T030 node-red defaults/main.yml
T031 node-red values.yaml.j2
```

---

## Implementation Strategy

### MVP First (US1 Only — Phases 1–3)

1. Complete Phase 1: Setup (T001–T005)
2. Complete Phase 2: Foundational (T006–T009)
3. Complete Phase 3: US1 (T010–T018)
4. **STOP and VALIDATE**: HA loads at `https://hass.fleet1.cloud`; Mosquitto on port 8883 with LE cert
5. Run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags home-automation`

### Incremental Delivery

1. Setup + Foundational → infrastructure ready
2. US1 → HA + Mosquitto (MQTT TLS) — functional MVP
3. US2 → Mosquitto mTLS hardening — constitution compliance
4. US3 → InfluxDB + HA long-term metrics
5. US4 → Node-RED flow automation
6. Polish → idempotency verification, docs

### Parallel Team Strategy

With two developers after Foundational is complete:
- Developer A: US1 (Mosquitto + HA roles, T010–T018) → then US2 (mTLS, T019–T023)
- Developer B: US3 (InfluxDB, T024–T029) → then US4 (Node-RED, T030–T034)

---

## Notes

- [P] tasks operate on different files with no shared state — safe to run concurrently
- `kubernetes.core.k8s` must be used for applying manifests (not `command: kubectl apply`) to satisfy Ansible idempotency requirements
- Mosquitto role tasks/main.yml grows across US1 and US2 — add US2 tasks as additional blocks at the end of the existing file, not as rewrites
- The `home-automation-ca` ClusterIssuer and `selfsigned-issuer` ClusterIssuer are cluster-scoped; create them once in the mosquitto role — other roles reference but do not create them
- InfluxDB org ID cannot be known until after first login — `quickstart.md` documents the two-phase setup
- All `helm upgrade --install` commands use `--wait --timeout` flags per the Loki/Gitea precedent
- Re-running any individual role tag must be safe (idempotent) at any point in delivery
