# Tasks: Longhorn Distributed Block Storage

**Input**: Design documents from `/specs/006-longhorn-storage/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

**Organization**: US1 (Longhorn installed and healthy) is foundational and must be complete before US2 (PVC provisioning) can be validated at runtime. File authoring for both stories is fully parallelizable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)

---

## Phase 1: Setup

**Purpose**: Verify existing structure and confirm role directories to create.

- [x] T001 Verify existing files: playbooks/cluster/k3s-deploy.yml, playbooks/cluster/services-deploy.yml, roles/helm/tasks/main.yml exist

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Changes to k3s-deploy.yml and services-deploy.yml that all user stories depend on at runtime. Node prereq role and Longhorn role directory scaffolding.

- [x] T002 [P] Update playbooks/cluster/k3s-deploy.yml: add `--disable local-storage` to INSTALL_K3S_EXEC on the K3s server install task (alongside existing `--disable traefik`) for fresh-install idempotency
- [x] T003 [P] Update playbooks/cluster/services-deploy.yml: add new play `- name: Install Longhorn node prerequisites` targeting `hosts: cluster` with `roles: [longhorn-prereqs]` before the existing `Install Host Tools` play; add `longhorn` to the `Install Host Tools` play roles list after `helm`
- [x] T004 [P] Create roles/longhorn-prereqs/tasks/main.yml: (1) apt install open-iscsi, nfs-common, util-linux with retries; (2) enable + start iscsid service; (3) enable + start open-iscsi service; (4) write /etc/modules-load.d/longhorn.conf with `iscsi_tcp`; (5) modprobe iscsi_tcp immediately; (6) disable + stop multipathd (ignore_errors: true); (7) stat /etc/iscsi/initiatorname.iscsi and fail_when not found
- [x] T005 [P] Create roles/longhorn/defaults/main.yml: define `longhorn_version: "v1.11.1"`, `longhorn_namespace: "longhorn-system"`, `longhorn_data_path: "/var/lib/longhorn"`

**Checkpoint**: Foundational files ready — Longhorn role implementation can begin.

---

## Phase 3: User Story 1 — Longhorn Installed and Healthy (Priority: P1) 🎯 MVP

**Goal**: Longhorn deployed across all 6 nodes, all DaemonSets and Deployments healthy, Longhorn set as default StorageClass, K3s local-path addon disabled.

**Independent Test**: `kubectl get storageclass` shows `longhorn (default)` with no other default. `kubectl get pods -n longhorn-system` shows all Running. `kubectl get nodes.longhorn.io -n longhorn-system` shows 6 nodes.

### Implementation for User Story 1

- [x] T006 [P] [US1] Create roles/longhorn/files/values.yaml: persistence.defaultClass: true, persistence.defaultClassReplicaCount: 2, persistence.reclaimPolicy: Retain; defaultSettings.defaultReplicaCount: 2, defaultSettings.defaultDataPath: /var/lib/longhorn, defaultSettings.replicaSoftAntiAffinity: true, defaultSettings.storageOverProvisioningPercentage: 200, defaultSettings.storageMinimalAvailablePercentage: 10, defaultSettings.upgradeChecker: false, defaultSettings.autoSalvage: true, defaultSettings.disableSchedulingOnCordonedNode: true; csi.attacherReplicaCount: 3, csi.provisionerReplicaCount: 3, csi.resizerReplicaCount: 3, csi.snapshotterReplicaCount: 3
- [x] T007 [P] [US1] Create roles/longhorn/handlers/main.yml: handler `Restart K3s server` using ansible.builtin.systemd (name: k3s, state: restarted) followed by ansible.builtin.uri wait for https://localhost:6443/readyz (validate_certs: false, retries: 24, delay: 5) to confirm API is back
- [x] T008 [US1] Create roles/longhorn/tasks/main.yml: (1) template /etc/rancher/k3s/config.yaml with `disable: [local-storage]` (notify: Restart K3s server); (2) wait for local-path StorageClass to be absent (kubectl get storageclass local-path, failed_when rc == 0, retries: 12, delay: 10, ignore_errors for when local-path never existed); (3) helm repo add longhorn https://charts.longhorn.io (idempotent); (4) helm repo update; (5) copy files/values.yaml to /tmp/longhorn-values.yaml; (6) helm upgrade --install longhorn longhorn/longhorn --namespace {{ longhorn_namespace }} --create-namespace --version {{ longhorn_version }} --values /tmp/longhorn-values.yaml --timeout 5m (register result, changed_when 'deployed' or 'upgraded' in stdout); (7) kubectl rollout status daemonset/longhorn-manager -n {{ longhorn_namespace }} --timeout=10m; (8) kubectl rollout status daemonset/longhorn-csi-plugin -n {{ longhorn_namespace }} --timeout=10m; (9) kubectl rollout status deployment/longhorn-ui -n {{ longhorn_namespace }} --timeout=5m; (10) kubectl rollout status deployment/longhorn-driver-deployer -n {{ longhorn_namespace }} --timeout=5m; (11) kubectl rollout status deployment/csi-attacher -n {{ longhorn_namespace }} --timeout=5m; (12) kubectl rollout status deployment/csi-provisioner -n {{ longhorn_namespace }} --timeout=5m; (13) debug msg showing longhorn_namespace and node count via kubectl get nodes.longhorn.io

**Checkpoint**: Run services-deploy.yml. Confirm `kubectl get storageclass` shows `longhorn (default)` only. Confirm all pods Running in longhorn-system. Re-run produces changed=0.

---

## Phase 4: User Story 2 — Applications Can Provision PVCs (Priority: P2)

**Goal**: A PVC with no explicit storage class is automatically provisioned by Longhorn, bound to a pod, and data persists across pod rescheduling to a different node.

**Independent Test**: Apply PVC smoke test from quickstart.md. PVC binds within 60s. Pod writes file. Pod deleted and recreated. File still present.

### Implementation for User Story 2

- [ ] T009 [US2] Run PVC smoke test per quickstart.md Step 3–4: apply test PVC + pod, wait for PVC Bound, write file, delete pod, recreate pod, verify file persists; clean up PVC and pod. Document any issues.

**Checkpoint**: PVC provisions, data persists across pod reschedule, cleanup leaves no orphaned volumes.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [ ] T010 Idempotency: re-run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass` and confirm changed=0 for all Longhorn tasks
- [ ] T011 Access Longhorn dashboard via port-forward per quickstart.md Step 6 and confirm all nodes show as schedulable with available storage capacity

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: No dependencies — T002–T005 can all be authored in parallel immediately
- **US1 (Phase 3)**: T006–T007 can be authored in parallel with Phase 2; T008 depends on T006 + T007 (tasks file references values.yaml and handler); runtime depends on T003 (services-deploy updated) and T004 (prereqs role exists)
- **US2 (Phase 4)**: Runtime requires US1 Longhorn installation to be healthy; T009 is a manual validation step
- **Polish (Phase 5)**: Requires US1 + US2 complete

### User Story Dependencies

- **US1**: Foundational — must reach healthy state before US2 can be runtime-tested
- **US2**: Files (T009) are independent; runtime test requires US1 Longhorn running

### Within Each User Story

- T006 (values.yaml) and T007 (handlers) are independent — can run in parallel
- T008 (tasks/main.yml) depends on T006 + T007 (references both)
- T009 is a runtime validation step — requires full US1 deployment

### Parallel Opportunities

- T002, T003, T004, T005 — all different files, fully parallel (Phase 2)
- T006, T007 — different files, fully parallel (Phase 3)
- T010, T011 — different concerns, parallel (Phase 5)

---

## Parallel Example: Author all role files simultaneously

```text
Parallel A: T002 — playbooks/cluster/k3s-deploy.yml
Parallel B: T003 — playbooks/cluster/services-deploy.yml
Parallel C: T004 — roles/longhorn-prereqs/tasks/main.yml
Parallel D: T005 — roles/longhorn/defaults/main.yml

# Then in parallel:
Parallel E: T006 — roles/longhorn/files/values.yaml
Parallel F: T007 — roles/longhorn/handlers/main.yml

# After T006 + T007:
Sequential: T008 — roles/longhorn/tasks/main.yml
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (T001) + Phase 2 (T002–T005)
2. Complete Phase 3 / US1 (T006–T008)
3. **STOP and VALIDATE**: Run services-deploy.yml, confirm Longhorn healthy, StorageClass correct
4. Proceed to US2 PVC smoke test only after Longhorn is confirmed healthy

### Incremental Delivery

1. T001–T005 → scaffolding ready
2. T006–T008 → Longhorn deployed → validate US1 (StorageClass + healthy pods)
3. T009 → PVC provisioning confirmed → validate US2
4. T010–T011 → idempotency + dashboard sign-off

---

## Notes

- No tests requested in spec — no test tasks generated
- The `multipathd` disable task (T004) uses `ignore_errors: true` — it may not be installed on all nodes
- The K3s restart handler (T007) must wait for API readiness before subsequent tasks run — ensure the uri wait is in the handler itself, not a separate task
- T008 step (2) wait for local-path absence: use `failed_when: local_path_check.rc == 0` and `until: local_path_check.rc != 0` — the inverted logic ensures we wait for the StorageClass to disappear
- If `local-path` never existed (e.g., already disabled), the wait step should not fail — use `ignore_errors: true` or check stderr for "not found"
- Longhorn DaemonSet rollout (T008 steps 7–8) waits up to 10 minutes — normal for first install as images pull on all 6 nodes
