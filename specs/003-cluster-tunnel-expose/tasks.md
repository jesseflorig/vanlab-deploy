# Tasks: Cluster Provisioning and Internet Exposure

**Input**: Design documents from `/specs/003-cluster-tunnel-expose/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

**Organization**: Tasks are grouped by user story. US1 (cluster) must complete before US2 (Traefik) can be tested, and US2 before US3 (whoami internet exposure). Files are distinct per story so US2 and US3 can be authored in parallel with US1 — only runtime testing is sequential.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup

**Purpose**: Confirm repository structure matches the implementation plan before changes begin.

- [x] T001 Verify existing files match plan.md structure: playbooks/cluster/k3s-deploy.yml, playbooks/cluster/services-deploy.yml, roles/traefik/tasks/main.yml exist

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No shared infrastructure changes are needed — all changes are scoped to individual files within each user story. This phase is a pass-through.

**Checkpoint**: Existing project structure confirmed — user story implementation can begin.

---

## Phase 3: User Story 1 — All Cluster Nodes Join and Are Ready (Priority: P1) 🎯 MVP

**Goal**: Fix the K3s agent join bug so all 4 nodes (2 servers, 2 agents) reach Ready state from a single playbook run with zero manual steps.

**Independent Test**: `ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml --ask-become-pass` → all 4 nodes listed as Ready in the final debug output.

### Implementation for User Story 1

- [x] T002 [US1] Update server play in playbooks/cluster/k3s-deploy.yml: add `--disable traefik` flag to INSTALL_K3S_EXEC in the K3s server install task
- [x] T003 [US1] Update server play in playbooks/cluster/k3s-deploy.yml: add two-stage API readiness sequence after server install — wait_for port 6443 (TCP), then uri /readyz probe (accept 200 or 401), then wait_for token file path, then slurp + b64decode + set_fact for k3s_node_token
- [x] T004 [US1] Update agents play in playbooks/cluster/k3s-deploy.yml: replace `creates:` idempotency guard with service_facts check; install agent only when k3s-agent.service is not defined or not running; use `groups['servers'][0]` instead of hard-coded 'node1' for token lookup
- [x] T005 [US1] Update agents play in playbooks/cluster/k3s-deploy.yml: add post-join readiness wait — `kubectl wait --for=condition=Ready node/{{ inventory_hostname }}` delegated to groups['servers'][0] with retries
- [x] T006 [US1] Add Play 4 to playbooks/cluster/k3s-deploy.yml: hosts: node1, run `kubectl get nodes -o wide`, register result, display with debug (satisfies FR-008)

**Checkpoint**: Run k3s-deploy.yml. All 4 nodes appear Ready in debug output. Re-run produces changed=0.

---

## Phase 4: User Story 2 — Traefik Ingress Controller Is Deployed (Priority: P2)

**Goal**: Deploy Traefik v3 via Helm with HTTP-only values into the `traefik` namespace. Display the assigned LoadBalancer IP so the operator can configure the Cloudflare tunnel.

**Independent Test**: After services-deploy.yml runs, `curl -H "Host: whoami.fleet1.cloud" http://<LB-IP>/` returns a response (even 404 is fine — Traefik is routing).

### Implementation for User Story 2

- [x] T007 [P] [US2] Create roles/traefik/files/values.yaml: service type LoadBalancer; web entrypoint port 80 exposed; websecure entrypoint disabled (TLS disabled); dashboard IngressRoute disabled; kubernetesIngress provider enabled with publishedService.enabled true; access logs enabled
- [x] T008 [US2] Update roles/traefik/tasks/main.yml: add copy task for files/values.yaml → /tmp/traefik-values.yaml on server; add --values /tmp/traefik-values.yaml --wait --timeout 3m to the helm upgrade --install command
- [x] T009 [US2] Update roles/traefik/tasks/main.yml: add post-deploy sequence — kubectl rollout status deployment/traefik -n traefik, then poll kubectl get svc traefik -n traefik for non-empty .status.loadBalancer.ingress[0].ip with retries, then debug display of the LB IP

**Checkpoint**: Run services-deploy.yml (Traefik only). Traefik pod Running. LB IP printed. Re-run produces changed=0.

---

## Phase 5: User Story 3 — Whoami Test App Is Reachable from the Internet (Priority: P3)

**Goal**: Deploy the whoami test app to the cluster with a Traefik Ingress for `whoami.fleet1.cloud`, then verify end-to-end reachability from the internet through the Cloudflare tunnel.

**Independent Test**: From a cellular device, `curl https://whoami.fleet1.cloud` returns request headers from the whoami app. (Requires manual Cloudflare dashboard step per quickstart.md Step 4.)

### Implementation for User Story 3

- [x] T010 [P] [US3] Create roles/whoami/files/whoami.yaml: Kubernetes Deployment (traefik/whoami:latest, 1 replica, namespace traefik) + Service (ClusterIP port 80) + Ingress (ingressClassName: traefik, annotation traefik.io/router.entrypoints: web, host whoami.fleet1.cloud, pathType Prefix /)
- [x] T011 [P] [US3] Create roles/whoami/tasks/main.yml: copy files/whoami.yaml to /tmp/whoami.yaml on server; kubectl apply -f /tmp/whoami.yaml; kubectl rollout status deployment/whoami -n traefik --timeout=60s
- [x] T012 [US3] Update playbooks/cluster/services-deploy.yml: remove wireguard from servers play roles list; add whoami role after traefik role

**Checkpoint**: Run services-deploy.yml. Whoami pod Running. `curl -H "Host: whoami.fleet1.cloud" http://<LB-IP>/` returns headers. Re-run produces changed=0.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all stories.

- [x] T013 Idempotency validation: re-run `ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml --ask-become-pass` and confirm changed=0
- [x] T014 Idempotency validation: re-run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass` and confirm changed=0
- [x] T015 End-to-end validation: from a cellular device, curl https://whoami.fleet1.cloud and confirm whoami response headers received (per quickstart.md Step 5)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: Pass-through — no blocking work
- **US1 (Phase 3)**: No dependencies — start immediately after setup
- **US2 (Phase 4)**: Files can be authored in parallel with US1; runtime test requires US1 cluster
- **US3 (Phase 5)**: Files can be authored in parallel with US1/US2; runtime test requires US2 Traefik
- **Polish (Phase 6)**: Requires all stories complete

### User Story Dependencies

- **US1**: Independent — start immediately
- **US2**: File authoring independent; integration test requires US1 complete
- **US3**: File authoring independent; integration test requires US2 complete

### Within Each User Story

- T002 → T003 → T004 → T005 → T006 are sequential (same file: k3s-deploy.yml)
- T007 [P] and T008/T009 are partially parallelizable (T007 is a new file; T008/T009 modify main.yml)
- T010 [P] and T011 [P] are parallelizable (different new files); T012 depends on both existing

### Parallel Opportunities

- T007 (values.yaml) can run in parallel with any US1 task
- T010 (whoami.yaml) and T011 (whoami/tasks/main.yml) can run in parallel with each other and with US1/US2 file tasks
- T013 and T014 can run in parallel (different playbooks)

---

## Parallel Example: Author US2 and US3 files while implementing US1

```text
# While implementing T002–T006 (k3s-deploy.yml):
Parallel task A: T007 — Create roles/traefik/files/values.yaml
Parallel task B: T010 — Create roles/whoami/files/whoami.yaml
Parallel task C: T011 — Create roles/whoami/tasks/main.yml

# After T007 exists:
Sequential: T008, T009 — Update roles/traefik/tasks/main.yml

# After T010 + T011 exist:
Sequential: T012 — Update playbooks/cluster/services-deploy.yml
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 3: US1 (T002–T006) — fix k3s-deploy.yml
3. **STOP and VALIDATE**: `ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml --ask-become-pass` → all 4 nodes Ready
4. Proceed to US2 only after cluster is confirmed healthy

### Incremental Delivery

1. T001 → T002–T006 → validate cluster (US1 MVP)
2. T007–T009 + T012 partial → validate Traefik (US2)
3. T010–T012 → validate whoami + Cloudflare dashboard config → validate internet reachability (US3)
4. T013–T015 → idempotency + end-to-end sign-off

---

## Notes

- No tests requested in spec — no test tasks generated
- The Cloudflare tunnel public hostname configuration (quickstart.md Step 4) is a manual dashboard step — no Ansible task
- `groups['servers'][0]` is used throughout instead of hard-coded 'node1'
- The `creates:` guard in the agent play is replaced by `service_facts` — this handles the partial-install case where the service file exists but the agent never joined
- Principle VI exception (HTTP cross-VLAN) is accepted and documented in plan.md
