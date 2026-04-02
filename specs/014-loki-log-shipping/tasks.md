# Tasks: Add Grafana Loki Log Aggregation

**Input**: Design documents from `specs/014-loki-log-shipping/`
**Prerequisites**: plan.md, spec.md, research.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create role scaffolding and update Helm values template for Grafana datasource

- [X] T001 Create `roles/loki/defaults/main.yml` with chart version (6.55.0), namespace (monitoring), storage size (20Gi), retention (168h)
- [X] T002 [P] Create `roles/loki/tasks/main.yml` with run_once Helm tasks (add grafana repo, update repos, install loki chart, wait for rollout)
- [X] T003 [P] Create `roles/alloy/defaults/main.yml` with chart version, namespace, loki endpoint URL
- [X] T004 [P] Create `roles/alloy/tasks/main.yml` with run_once Helm tasks (add grafana repo, update repos, render config, install alloy chart, wait for DaemonSet)
- [X] T005 Add `loki_storage_size` and `loki_retention_period` placeholder vars to `group_vars/example.all.yml`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core Helm values templates that all user stories depend on — Loki must be deployed before Alloy, and Grafana datasource update must happen in the same run as kube-prometheus-stack

**⚠️ CRITICAL**: User story work cannot be independently tested until this phase is complete

- [X] T006 Create `roles/loki/templates/values.yaml.j2` — SingleBinary mode, auth_enabled false, filesystem storage at /var/loki/chunks, Longhorn PVC (size from `loki_storage_size`), retention from `loki_retention_period`, compactor enabled, distributor/ingester/querier/queryFrontend replicas all set to 0, gateway disabled
- [X] T007 Create `roles/alloy/templates/config.alloy.j2` — River config with `discovery.kubernetes` for pods, `loki.source.kubernetes` for pod logs, `loki.source.journal` for journald with job label, `loki.write` targeting `http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push`
- [X] T008 Create `roles/alloy/templates/values.yaml.j2` — controller type daemonset, configMap from rendered config.alloy.j2, tolerations for control-plane nodes, hostPath mounts for /var/log/pods and /run/log/journal and /etc/machine-id (read-only), alloy.mounts.varlog true
- [X] T009 Add `additionalDataSources` entry for Loki to `roles/kube-prometheus-stack/templates/values.yaml.j2` — type loki, url http://loki.monitoring.svc.cluster.local:3100, access proxy, isDefault false, jsonData.maxLines 1000
- [X] T010 Add `loki` and `alloy` roles to `playbooks/cluster/services-deploy.yml` after kube-prometheus-stack, each with appropriate tags

**Checkpoint**: All role files exist and services-deploy.yml is updated — ready to deploy

---

## Phase 3: User Story 1 — View cluster logs in Grafana (Priority: P1) 🎯 MVP

**Goal**: Operator can query pod logs from any namespace in Grafana Explore using the Loki datasource within 60 seconds of log generation.

**Independent Test**: Open Grafana → Explore → select Loki → query `{namespace="argocd"}` → ArgoCD pod logs appear.

- [ ] T011 [US1] Run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags monitoring` to deploy kube-prometheus-stack with Loki datasource update
- [ ] T012 [US1] Run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags loki` to deploy Loki and verify pod is Running and PVC is Bound (quickstart.md steps 1 and 8)
- [ ] T013 [US1] Run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags alloy` to deploy Alloy DaemonSet and verify 6 pods are Running (quickstart.md step 2)
- [ ] T014 [US1] Verify Loki is receiving logs via port-forward curl to `/loki/api/v1/labels` and confirm labels include namespace and pod (quickstart.md step 3)
- [ ] T015 [US1] Verify Grafana Loki datasource appears and queries return results for each critical namespace per quickstart.md step 5

**Checkpoint**: Grafana Explore shows live pod logs from all namespaces — US1 complete

---

## Phase 4: User Story 2 — Logs persist across restarts (Priority: P2)

**Goal**: Logs survive pod evictions and node reboots; pre-restart logs remain queryable.

**Independent Test**: Restart a pod, query its logs in Grafana — logs before and after restart both present with no gap.

- [ ] T016 [US2] Verify Longhorn PVC for Loki is using `storageClass: longhorn` and is Bound by running `kubectl get pvc -n monitoring -l app.kubernetes.io/name=loki` (quickstart.md step 8)
- [ ] T017 [US2] Perform persistence test: record a timestamp, restart `argocd-server` deployment, then query Grafana for logs from before the restart and confirm they are present (quickstart.md step 7)

**Checkpoint**: Pre-restart logs confirmed present in Grafana — US2 complete

---

## Phase 5: User Story 3 — Node-level system logs captured (Priority: P3)

**Goal**: K3s system service logs from journald are visible in Grafana alongside pod logs, queryable by node.

**Independent Test**: Query `{job="systemd-journal"} |= "k3s"` in Grafana — K3s service log entries appear from all nodes.

- [ ] T018 [US3] Verify journald logs appear in Grafana by querying `{job="systemd-journal"}` in Explore and confirming entries from multiple nodes are present (quickstart.md step 6)
- [ ] T019 [US3] Confirm all 6 nodes are represented in journald logs by checking `node_name` or `hostname` label values in the query results

**Checkpoint**: System logs from all 6 nodes visible in Grafana — US3 complete

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T020 [P] Add `drain-shutdown` playbook timeout increase — update `roles/drain-shutdown` drain timeout from 120s to 600s to handle slow Longhorn pod termination
- [X] T021 [P] Update `README.md` Quick Reference table to add Loki/Alloy deploy command
- [X] T022 [P] Update `README.md` playbook directory structure to include `roles/loki/` and `roles/alloy/`
- [ ] T023 Run full `services-deploy.yml` (no tags) and confirm idempotent — no errors, no data loss, Loki PVC intact

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately; T002/T003/T004 can run in parallel
- **Foundational (Phase 2)**: Depends on Setup — T006/T007/T008 can run in parallel; T009 and T010 can run in parallel; all must complete before user stories
- **US1 (Phase 3)**: Depends on Foundational — tasks run sequentially (each deploy step gates the next)
- **US2 (Phase 4)**: Depends on US1 (Loki must be running to test persistence)
- **US3 (Phase 5)**: Depends on US1 (Alloy must be running to ship journald logs)
- **Polish (Phase 6)**: Depends on all user stories; T020/T021/T022 can run in parallel

### Parallel Opportunities

```bash
# Phase 1 — run in parallel:
Task T002: Create roles/loki/tasks/main.yml
Task T003: Create roles/alloy/defaults/main.yml
Task T004: Create roles/alloy/tasks/main.yml

# Phase 2 — run in parallel first batch:
Task T006: Create roles/loki/templates/values.yaml.j2
Task T007: Create roles/alloy/templates/config.alloy.j2
Task T008: Create roles/alloy/templates/values.yaml.j2

# Phase 2 — run in parallel second batch:
Task T009: Update kube-prometheus-stack values.yaml.j2
Task T010: Update services-deploy.yml

# Phase 6 — run in parallel:
Task T020: Fix drain-shutdown timeout
Task T021: Update README Quick Reference
Task T022: Update README directory structure
```

---

## Implementation Strategy

### MVP (User Story 1 Only)

1. Complete Phase 1: Setup (role scaffolding)
2. Complete Phase 2: Foundational (Helm values, services-deploy.yml)
3. Complete Phase 3: US1 — deploy and verify logs appear in Grafana
4. **STOP and VALIDATE**: Query logs in Grafana — if it works, US1 is done

### Incremental Delivery

1. Setup + Foundational → all role files ready
2. US1 → Loki + Alloy running, logs visible in Grafana (MVP)
3. US2 → Confirm persistence (no code changes, just validation)
4. US3 → Confirm journald logs (no code changes, just validation)
5. Polish → README updates, idempotency check

---

## Notes

- All `tasks/main.yml` files MUST use `run_once: true` on every task (matches existing role pattern)
- Loki MUST deploy before Alloy in services-deploy.yml (Alloy needs the push endpoint)
- kube-prometheus-stack MUST run before Loki in services-deploy.yml (Grafana datasource update)
- The `grafana` Helm repo (`https://grafana.github.io/helm-charts`) is shared between loki and alloy roles — both roles add it idempotently
- Alloy config uses River/HCL syntax in `config.alloy.j2`, NOT YAML
- T020 (drain-shutdown timeout fix) is unrelated to Loki but addresses the operational issue observed during node maintenance this session
