# Tasks: OPNsense Metrics Collection

**Input**: Design documents from `/specs/038-opnsense-metrics/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, quickstart.md ✓

**Organization**: Tasks are grouped by user story. US1 delivers the working exporter (all metrics flow). US2 and US3 are validation phases confirming specific metric categories are reachable in Prometheus/Grafana — no additional code required.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to

---

## Phase 1: Setup

**Purpose**: Scaffold directory structure and store credentials.

- [ ] T001 Create `manifests/monitoring/prereqs/` and `manifests/monitoring/exporter/` directories by placing `.gitkeep` files
- [ ] T002 [P] Add `opnsense_api_key` and `opnsense_api_secret` vars (with real values from the downloaded key file) to `group_vars/all.yml`
- [ ] T003 [P] Add `opnsense_api_key: ""` and `opnsense_api_secret: ""` placeholder entries to `group_vars/example.all.yml`

---

## Phase 2: Foundational

**Purpose**: Namespace manifest and SealedSecret generation — must exist before ArgoCD can sync anything.

**⚠️ CRITICAL**: US1 cannot begin until T006 (SealedSecret committed) is complete.

- [ ] T004 Create `manifests/monitoring/prereqs/namespace.yaml`: `apiVersion: v1`, `kind: Namespace`, `metadata.name: monitoring`, annotated with `argocd.argoproj.io/sync-wave: "0"` so it runs first
- [ ] T005 Add an `opnsense-exporter` task block to `playbooks/utilities/seal-secrets.yml`: read `opnsense_api_key` and `opnsense_api_secret` from vars and run `kubeseal` to produce a `SealedSecret` named `opnsense-exporter-credentials` in namespace `monitoring`, writing output to `manifests/monitoring/prereqs/sealed-secrets.yaml`; tag the task `opnsense-exporter`
- [ ] T006 Run `ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml --tags opnsense-exporter` to generate `manifests/monitoring/prereqs/sealed-secrets.yaml` and commit the result

**Checkpoint**: `manifests/monitoring/prereqs/` has `namespace.yaml` and `sealed-secrets.yaml` committed — prereqs ArgoCD app can now sync.

---

## Phase 3: User Story 1 — Network Interface Metrics (Priority: P1) 🎯 MVP

**Goal**: Exporter pod running in cluster, Prometheus scraping it, interface throughput and gateway metrics visible in Grafana dashboard gnetId 21113.

**Independent Test**: `kubectl port-forward -n monitoring deploy/opnsense-exporter 8080:8080` then `curl -s http://localhost:8080/metrics | grep opnsense_interfaces_received_bytes_total` — must return labelled counter lines. Grafana dashboard 21113 must load with data.

- [ ] T007 [P] [US1] Create `manifests/monitoring/exporter/deployment.yaml`: `kind: Deployment`, name `opnsense-exporter`, namespace `monitoring`, image `ghcr.io/athennamind/opnsense-exporter:0.0.14`, 1 replica, env vars `OPNSENSE_EXPORTER_OPS_HOST=10.1.1.1`, `OPNSENSE_EXPORTER_OPS_PROTOCOL=https`, `OPNSENSE_EXPORTER_OPS_INSECURE=true`, `OPNSENSE_EXPORTER_OPS_API_KEY` and `OPNSENSE_EXPORTER_OPS_API_SECRET` sourced from `secretKeyRef` on Secret `opnsense-exporter-credentials`; container port 8080; resource requests `cpu: 50m, memory: 64Mi`; limits `cpu: 200m, memory: 128Mi`
- [ ] T008 [P] [US1] Create `manifests/monitoring/exporter/service.yaml`: `kind: Service`, name `opnsense-exporter`, namespace `monitoring`, selector matching the Deployment labels, port 8080 named `metrics`, protocol TCP, type ClusterIP
- [ ] T009 [US1] Create `manifests/monitoring/exporter/scrapeconfig.yaml`: `apiVersion: monitoring.coreos.com/v1alpha1`, `kind: ScrapeConfig`, name `opnsense-exporter`, namespace `monitoring`, `spec.staticConfigs` with target `opnsense-exporter.monitoring.svc.cluster.local:8080`, `spec.metricsPath: /metrics`, `spec.scrapeInterval: 60s`, label `job: opnsense-exporter`
- [ ] T010 [US1] Add gnetId 21113 dashboard entry to `roles/kube-prometheus-stack/templates/values.yaml.j2` under `grafana.dashboards.default`: key `opnsense-exporter`, fields `gnetId: 21113`, `revision: 1`, `datasource: Prometheus` — place alongside the existing Longhorn dashboard entry (gnetId 13032)
- [ ] T011 [US1] Add `monitoring-prereqs` and `monitoring-apps` entries to `argocd_apps` list in `group_vars/all.yml`: `monitoring-prereqs` → `path: manifests/monitoring/prereqs`, `namespace: monitoring`; `monitoring-apps` → `path: manifests/monitoring/exporter`, `namespace: monitoring`
- [ ] T012 [US1] Run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags monitoring` to apply the updated kube-prometheus-stack Helm values (provisions Grafana dashboard 21113)
- [ ] T013 [US1] Run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap` to register the two new ArgoCD Applications; verify both show `Synced / Healthy` and the exporter pod is `1/1 Running`

**Checkpoint**: `curl http://localhost:8080/metrics | grep opnsense_interfaces` returns data. Prometheus query `up{job="opnsense-exporter"}` returns 1. Grafana dashboard 21113 loads with interface traffic panels populated.

---

## Phase 4: User Story 2 — Firewall & Connection State Metrics (Priority: P2)

**Goal**: Confirm firewall packet counters and TCP connection state counts are flowing through to Prometheus — no additional manifests needed.

**Independent Test**: In Prometheus UI at `https://prometheus.fleet1.cloud`, query `opnsense_firewall_in_ipv4_pass_packets_total` — must return a non-empty result set. Query `opnsense_protocol_tcp_connection_count_by_state` — must return results labelled by state (ESTABLISHED, TIME_WAIT, etc.).

- [ ] T014 [US2] Verify firewall and protocol metrics in Prometheus: run `kubectl port-forward -n monitoring deploy/opnsense-exporter 8080:8080` and `curl -s http://localhost:8080/metrics | grep -E 'opnsense_firewall|opnsense_protocol'` — confirm both metric families are present with non-zero values; document any missing metric families

**Checkpoint**: `opnsense_firewall_*` and `opnsense_protocol_tcp_*` confirmed present in Prometheus.

---

## Phase 5: User Story 3 — System Health Metrics (Priority: P3)

**Goal**: Confirm OPNsense service status and firmware metrics are visible — no additional manifests needed.

**Independent Test**: Query `opnsense_services_running_total` and `opnsense_firmware_needs_reboot` in Prometheus — both must return values.

- [ ] T015 [US3] Verify system health metrics in Prometheus: `curl -s http://localhost:8080/metrics | grep -E 'opnsense_services|opnsense_firmware'` — confirm both metric families present; if `opnsense_unbound_dns_uptime_seconds` is absent, confirm Unbound extended statistics is enabled in OPNsense (Services → Unbound DNS → Advanced → Extended statistics)

**Checkpoint**: `opnsense_services_running_total` and `opnsense_firmware_needs_reboot` confirmed present in Prometheus.

---

## Phase 6: Polish & Validation

**Purpose**: End-to-end validation and cleanup.

- [ ] T016 Open Grafana dashboard 21113 at `https://grafana.fleet1.cloud` and confirm panels for: interface throughput (in/out bytes), gateway RTT and status, firewall blocked/passed packets, and services running count — all show data over the last 1 hour
- [ ] T017 [P] Remove `.gitkeep` files from `manifests/monitoring/prereqs/` and `manifests/monitoring/exporter/` if present (the real files replaced them)
- [ ] T018 [P] Commit all manifests, updated `group_vars/all.yml`, `group_vars/example.all.yml`, `roles/kube-prometheus-stack/templates/values.yaml.j2`, and `playbooks/utilities/seal-secrets.yml` to branch `038-opnsense-metrics` and open PR against main

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — T002 and T003 can run in parallel immediately
- **Foundational (Phase 2)**: T004 first, then T005, then T006 (sequential — same files); blocks US1
- **US1 (Phase 3)**: T007 and T008 parallel; T009 after T008; T010 and T011 parallel with T007–T009; T012 after T010; T013 after T011 and T012
- **US2 (Phase 4)**: Depends on US1 complete (exporter must be running)
- **US3 (Phase 5)**: Depends on US1 complete (exporter must be running)
- **Polish (Phase 6)**: T016 after US2+US3; T017 and T018 parallel after T016

### Parallel Opportunities

- T002 + T003: group_vars files — different files, parallel
- T007 + T008: deployment.yaml + service.yaml — different files, parallel
- T010 + T011: values.yaml.j2 + group_vars/all.yml — different files, parallel with T007–T009
- T017 + T018: cleanup and commit — parallel

---

## Implementation Strategy

### MVP (US1 only)

1. Complete Phase 1 (Setup) — store credentials
2. Complete Phase 2 (Foundational) — namespace + SealedSecret generated
3. Complete Phase 3 (US1) T007–T009 — write manifests, commit, push
4. Run T012–T013 — Ansible + ArgoCD bootstrap
5. **STOP AND VALIDATE**: port-forward → curl `/metrics` → confirm `opnsense_interfaces_*` present
6. Check Prometheus `up{job="opnsense-exporter"} == 1`
7. Check Grafana dashboard 21113 loads with data

### Incremental Delivery

1. US1 → exporter live, all metrics flowing, dashboard visible ✓
2. US2 → validate firewall metrics (no code, just verification) ✓
3. US3 → validate system health metrics (no code, just verification) ✓
4. Polish → end-to-end Grafana review, PR open ✓

---

## Notes

- All three user stories are delivered by the same single exporter Deployment — US2 and US3 are validation checkpoints, not additional code
- The SealedSecret (T006) must be committed before ArgoCD can sync the prereqs app — do not push the branch without it
- `OPNSENSE_EXPORTER_OPS_INSECURE=true` skips TLS verification for the OPNsense self-signed cert; acceptable since the call stays within the private management VLAN
- If the exporter pod fails to start, check `kubectl logs -n monitoring deploy/opnsense-exporter` for auth errors — the most common cause is incorrect ACL grants on the OPNsense API user
- Grafana dashboard 21113 is provisioned via Helm (Ansible-managed) so it survives Grafana pod restarts and Longhorn PVC rebuilds
