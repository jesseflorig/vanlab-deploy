# Tasks: etcd Cluster Backend

**Input**: Design documents from `/specs/008-etcd-cluster-backend/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup

**Purpose**: Validate prerequisites and prepare the working environment before making changes.

- [x] T001 Verify all cluster nodes are reachable: `ansible all -i hosts.ini -m ping`
- [x] T002 Confirm current K3s version supports embedded etcd: `ansible node1 -i hosts.ini -m shell -a "k3s --version" --become`
- [x] T003 [P] Verify `hosts.ini` has correct `[servers]` and `[agents]` groupings for intended topology

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Update the playbook to support both first-server and additional-server etcd install paths. This is the core code change that enables all three user stories.

**⚠️ CRITICAL**: All user story work depends on this phase being complete and merged.

- [x] T004 Update first-server install block in `playbooks/cluster/k3s-deploy.yml` to add `--cluster-init` flag to `INSTALL_K3S_EXEC`
- [x] T005 Add new task block in `playbooks/cluster/k3s-deploy.yml` for additional server nodes (`groups['servers'][1:]`) that joins the existing etcd cluster via `K3S_URL` + `K3S_TOKEN` without `--cluster-init`
- [x] T006 Verify idempotency guard on additional server task uses `creates: /etc/systemd/system/k3s.service` (same as first server) so re-runs are no-ops
- [x] T007 Restrict kubeconfig permissions on additional server nodes in `playbooks/cluster/k3s-deploy.yml` (mirror existing T004 chmod task for `node1`)
- [x] T008 [P] Update `group_vars/example.all.yml` with a comment explaining the `[servers]` multi-node convention and etcd quorum requirement

**Checkpoint**: Playbook changes are complete. Ready to proceed with live cluster migration (US1) and validation (US2, US3).

---

## Phase 3: User Story 1 - Add a New Agent Node Without Manual Remediation (Priority: P1) 🎯 MVP

**Goal**: Prove the updated playbook lets a new node join the etcd-backed cluster with zero manual steps.

**Independent Test**: Add a node to `[agents]` in `hosts.ini`, run `k3s-deploy.yml`, verify `kubectl get nodes` shows it `Ready` within 5 minutes.

- [x] T009 [US1] Execute live cluster migration: uninstall K3s on all nodes and re-run `playbooks/cluster/k3s-deploy.yml` against the updated playbook
- [x] T010 [US1] Verify etcd is the active datastore: `ansible node1 -i hosts.ini -m shell -a "k3s etcd-snapshot ls" --become` — should succeed without error
- [x] T011 [US1] Verify all current nodes reach `Ready` state: `ansible node1 -i hosts.ini -m shell -a "kubectl get nodes -o wide" --become`
- [x] T012 [US1] Run `playbooks/cluster/services-deploy.yml` to restore Helm-managed services post-rebuild
- [x] T013 [US1] Confirm ArgoCD syncs `static-site` and `redirects` apps from Gitea without manual intervention
- [x] T014 [US1] Re-run `playbooks/cluster/k3s-deploy.yml` against the already-running cluster and confirm zero changed tasks (idempotency validation)

**Checkpoint**: etcd-backed cluster is live, services restored, idempotency confirmed. US1 complete.

---

## Phase 4: User Story 2 - Promote a Worker Node to Control Plane (Priority: P2)

**Goal**: Prove a node can be reassigned from `[agents]` to `[servers]` in `hosts.ini` and join the etcd quorum via a single playbook run.

**Independent Test**: Move one agent node to `[servers]`, re-run `k3s-deploy.yml`, verify the node appears as `control-plane` in `kubectl get nodes`.

- [x] T015 [US2] Move one agent node (e.g., `node2`) from `[agents]` to `[servers]` in `hosts.ini`
- [x] T016 [US2] Uninstall K3s agent on the node being promoted: `ansible node3 -i hosts.ini -m shell -a "k3s-agent-uninstall.sh" --become`
- [x] T017 [US2] Re-run `playbooks/cluster/k3s-deploy.yml` — the promoted node should install as a server and join the etcd quorum
- [x] T018 [US2] Verify promoted node appears with `control-plane` role: `ansible node1 -i hosts.ini -m shell -a "kubectl get nodes -o wide" --become`
- [x] T019 [US2] Verify etcd quorum has expanded (node1 and node3 both carry `etcd=true` label)
- [x] T020 [US2] Revert `hosts.ini` to original topology and document the promotion procedure in `README.md`

**Checkpoint**: Node promotion via `hosts.ini` + playbook re-run is validated. US2 complete.

---

## Phase 5: User Story 3 - Full Rebuild with All Services Operational (Priority: P3)

**Goal**: Prove a complete from-scratch rebuild produces a healthy cluster with all services running within 20 minutes.

**Independent Test**: Uninstall K3s on all nodes, run the full playbook sequence, time the result, verify all services operational.

- [x] T021 [US3] Document migration procedure in `README.md` — uninstall steps, playbook sequence, rebuild time (~15–20 min), Longhorn data loss caveat, etcd quorum table, node promotion procedure
- [x] T022 [US3] Perform a timed full rebuild — completed during US1 live migration
- [x] T023 [US3] Verify all Helm services healthy post-rebuild — confirmed during US1
- [x] T024 [US3] Verify ArgoCD syncs both apps (`static-site`, `redirects`) without manual intervention — confirmed during US1

**Checkpoint**: Full rebuild validated end-to-end. US3 complete.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T025 [P] Commit all playbook changes with a descriptive commit message referencing this feature
- [ ] T026 [P] Push to both GitHub (`origin`) and Gitea (`gitea`) remotes
- [ ] T027 Merge `008-etcd-cluster-backend` into `main`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — blocks all user stories
- **US1 (Phase 3)**: Depends on Phase 2 — live cluster migration
- **US2 (Phase 4)**: Depends on Phase 3 (cluster must be running etcd)
- **US3 (Phase 5)**: Can run after Phase 2; does not depend on US2
- **Polish (Phase 6)**: Depends on all desired stories complete

### User Story Dependencies

- **US1 (P1)**: Requires Foundational complete; is the live migration
- **US2 (P2)**: Requires US1 (needs a live etcd cluster to promote into)
- **US3 (P3)**: Requires Foundational; independent of US2

### Parallel Opportunities

- T003, T008 can run in parallel during their respective phases
- T010, T011 can run in parallel during US1
- T025, T026 can run in parallel during Polish

---

## Implementation Strategy

### MVP (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational — update `k3s-deploy.yml`
3. Complete Phase 3: US1 — live cluster migration + idempotency check
4. **STOP and VALIDATE**: cluster is healthy, services restored, ArgoCD synced
5. Merge if stable

### Incremental Delivery

1. Setup + Foundational → playbook ready
2. US1 → etcd cluster live (MVP)
3. US2 → node promotion validated
4. US3 → full rebuild documented and timed
5. Polish → merge

---

## Notes

- [P] tasks = different files or independent commands, no blocking dependencies
- Longhorn PVC data is lost on rebuild — ensure Gitea is up to date before starting US1
- etcd auto-snapshots at `/var/lib/rancher/k3s/server/db/snapshots/` every 12h (K3s default)
- Quorum note: 1 server = 0 fault tolerance; 3 servers = 1 fault tolerance
- Commit after each phase or logical group
