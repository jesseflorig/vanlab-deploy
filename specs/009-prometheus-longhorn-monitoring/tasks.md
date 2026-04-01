# Tasks: Prometheus Longhorn Monitoring

**Input**: Design documents from `/specs/009-prometheus-longhorn-monitoring/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup

**Purpose**: Create the role scaffold and verify prerequisites before any code is written.

- [X] T001 Create role directory structure: `mkdir -p roles/kube-prometheus-stack/{defaults,tasks,templates}`
- [X] T002 [P] Verify Longhorn is healthy before proceeding: `ansible node1 -i hosts.ini -m shell -a "kubectl get pods -n longhorn-system --field-selector=status.phase!=Running" --become`
- [X] T003 [P] Verify wildcard TLS secret exists: `ansible node1 -i hosts.ini -m shell -a "kubectl get secret fleet1-cloud-tls -n traefik" --become`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create all role files and update supporting config before deploying anything.

**⚠️ CRITICAL**: All user story work depends on this phase being complete.

- [X] T004 Create `roles/kube-prometheus-stack/defaults/main.yml` with `monitoring_namespace`, `prometheus_stack_chart_version`, `prometheus_storage_size`, `grafana_hostname`, `prometheus_hostname`, `grafana_admin_password` defaults
- [X] T005 Create `roles/kube-prometheus-stack/tasks/main.yml` with tasks: add prometheus-community Helm repo, update repos, create monitoring namespace (idempotent), render values template, helm upgrade --install --atomic --timeout 10m
- [X] T006 Create `roles/kube-prometheus-stack/templates/values.yaml.j2` with full kube-prometheus-stack values: disable kubeControllerManager/kubeScheduler/kubeEtcd/kubeProxy, Longhorn PVCs (Prometheus 20Gi, Grafana 5Gi, Alertmanager 5Gi), Grafana ingress at `{{ grafana_hostname }}`, Prometheus ingress at `{{ prometheus_hostname }}`, serviceMonitorSelectorNilUsesHelmValues: false, Longhorn dashboard via gnetId 13032
- [X] T007 Add `monitoring.enabled: true` to `roles/longhorn/files/values.yaml` so the Longhorn ServiceMonitor is created
- [X] T008 Add monitoring role to `playbooks/cluster/services-deploy.yml` between longhorn and traefik with tag `[monitoring]`
- [X] T009 [P] Add `grafana_admin_password`, `grafana_hostname`, `prometheus_hostname` placeholders to `group_vars/example.all.yml`

**Checkpoint**: All files authored. Ready to deploy and validate user stories.

---

## Phase 3: User Story 1 - Cluster and Node Metrics in Grafana (Priority: P1) 🎯 MVP

**Goal**: kube-prometheus-stack deployed, Grafana accessible, node metrics visible.

**Independent Test**: Open `https://grafana.fleet1.cloud`, log in, query `node_cpu_seconds_total` in Explore — data returns for all 4 nodes.

- [X] T010 [US1] Add `grafana_admin_password`, `grafana_hostname: grafana.fleet1.cloud`, `prometheus_hostname: prometheus.fleet1.cloud` to `group_vars/all.yml` (local secret file, not committed)
- [X] T011 [US1] Deploy monitoring stack: `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags monitoring`
- [X] T012 [US1] Verify all monitoring pods reach Running state: `ansible node1 -i hosts.ini -m shell -a "kubectl get pods -n monitoring" --become`
- [X] T013 [US1] Verify Grafana ingress is reachable and returns HTTP 200: open `https://grafana.fleet1.cloud` in browser and log in with admin password
- [X] T014 [US1] Verify node metrics: navigate to Grafana → Explore → query `node_cpu_seconds_total` → confirm data for all cluster nodes

**Checkpoint**: Grafana is live with node metrics. US1 complete.

---

## Phase 4: User Story 2 - Longhorn Storage Metrics in Grafana (Priority: P2)

**Goal**: Longhorn ServiceMonitor scraped by Prometheus, Longhorn dashboard showing volume/disk data.

**Independent Test**: Open Grafana → Dashboards → Default → Longhorn — volume and disk metrics populated.

- [X] T015 [US2] Re-deploy Longhorn with monitoring enabled: `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags longhorn` (updates Helm values to add `monitoring.enabled: true`)
- [X] T016 [US2] Verify Longhorn ServiceMonitor exists: `ansible node1 -i hosts.ini -m shell -a "kubectl get servicemonitor -n longhorn-system" --become`
- [X] T017 [US2] Verify Prometheus is scraping Longhorn targets: open `https://prometheus.fleet1.cloud/targets` and confirm `longhorn` targets show `UP`
- [X] T018 [US2] Open Grafana → Dashboards → Default → Longhorn (ID 13032) and verify volume count, replica status, and disk usage metrics are populated

**Checkpoint**: Longhorn metrics visible in Grafana dashboard. US2 complete.

---

## Phase 5: User Story 3 - Prometheus UI for Ad-Hoc Queries (Priority: P3)

**Goal**: Prometheus UI accessible at `https://prometheus.fleet1.cloud` with healthy targets.

**Independent Test**: Open Prometheus UI → Status → Targets — all enabled scrapers show UP.

- [X] T019 [US3] Open `https://prometheus.fleet1.cloud/targets` and verify all enabled scrape targets show `UP` (kubeControllerManager/kubeScheduler/kubeEtcd/kubeProxy should not appear)
- [X] T020 [US3] Run a PromQL query in the Prometheus UI (`up`) and confirm results are returned for all expected jobs

**Checkpoint**: Prometheus UI confirmed healthy. US3 complete.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T021 Run idempotency check: `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags monitoring` — verify no failures and no unintended changes to running stack
- [ ] T022 [P] Commit all new and modified files to `009-prometheus-longhorn-monitoring` branch
- [ ] T023 [P] Push to both GitHub (`origin`) and Gitea (`gitea`) remotes
- [ ] T024 Merge `009-prometheus-longhorn-monitoring` into `main`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1
- **US1 (Phase 3)**: Depends on Phase 2 — deploys the stack
- **US2 (Phase 4)**: Depends on US1 (needs running Prometheus to scrape Longhorn)
- **US3 (Phase 5)**: Depends on US1 (needs Prometheus deployed); independent of US2
- **Polish (Phase 6)**: Depends on all stories complete

### User Story Dependencies

- **US1 (P1)**: Requires Foundational — deploys the full stack (MVP)
- **US2 (P2)**: Requires US1 — Longhorn targets must be scraped by a running Prometheus
- **US3 (P3)**: Requires US1 — Prometheus UI must be deployed

### Parallel Opportunities

- T002, T003 can run in parallel (both read-only cluster checks)
- T008, T009 can run in parallel (different files)
- T022, T023 can run in parallel (git operations)

---

## Implementation Strategy

### MVP (User Story 1 Only)

1. Phase 1: Setup — create role scaffold
2. Phase 2: Foundational — author all files
3. Phase 3: US1 — deploy and verify Grafana + node metrics
4. **STOP and VALIDATE**: Grafana loads, node metrics visible
5. Proceed to US2 (Longhorn dashboard) and US3 (Prometheus UI) if desired

### Incremental Delivery

1. Setup + Foundational → all files ready
2. US1 → monitoring stack live with node metrics (MVP)
3. US2 → Longhorn storage metrics visible
4. US3 → Prometheus UI validated
5. Polish → idempotency check + merge

---

## Notes

- [P] tasks = different files or independent commands, no blocking dependencies
- `grafana_admin_password` must be set in `group_vars/all.yml` before T011
- Helm deploy (T011) takes ~3–5 minutes on first run (image pulls + PVC provisioning)
- Longhorn dashboard (gnetId 13032) requires internet access from the cluster at deploy time
- K3s control-plane scrapers (kubeControllerManager, kubeScheduler, kubeEtcd, kubeProxy) are intentionally disabled — their absence from Prometheus targets is expected and correct
