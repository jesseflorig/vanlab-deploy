---

description: "Task list for node disk health check playbook"
---

# Tasks: Node Disk Health Check

**Input**: Design documents from `/specs/001-node-disk-health/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story this task belongs to (US1, US2)
- Include exact file paths in all descriptions

## Path Conventions

- Ansible playbooks at repository root (consistent with `check_hosts.yml`, `k3s-deploy.yml`)
- Role tasks in `roles/disk-health/tasks/`

---

## Phase 1: Setup

**Purpose**: Create the playbook and role scaffolding.

- [x] T001 Create role directory structure: `roles/disk-health/tasks/` and `roles/disk-health/defaults/`
- [x] T002 [P] Create empty playbook file `disk-health.yml` at repository root with description comment

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Role defaults and smartmontools installation — required by both user stories.

**⚠️ CRITICAL**: No user story implementation can begin until this phase is complete.

- [x] T003 Define role defaults in `roles/disk-health/defaults/main.yml`: `expected_drives_min: 1`, `smart_spare_warn_threshold: 10`, `smart_used_warn_threshold: 80`
- [x] T004 Implement smartmontools installation task in `roles/disk-health/tasks/main.yml`: apt module, `state: present`, `cache_valid_time: 3600`, `retries: 5`, `delay: 10`, matching `k3s-deploy.yml` pattern

**Checkpoint**: Foundation ready — user story implementation can begin.

---

## Phase 3: User Story 1 - Run Disk Health Check Across All Nodes (Priority: P1) 🎯 MVP

**Goal**: Enumerate all NVMe drives on each node, collect S.M.A.R.T. health and capacity
data, set `node_disk_summary` fact per node, and produce a consolidated human-readable
report on stdout grouped by node.

**Independent Test**: Run `ansible-playbook -i hosts.ini disk-health.yml` against cluster;
verify stdout lists every inventory node with at least one drive entry showing capacity
(total/used/free) and a health status (HEALTHY/WARNING/CRITICAL/UNKNOWN).

### Implementation for User Story 1

- [x] T005 [P] [US1] Add block device enumeration task to `roles/disk-health/tasks/main.yml`: shell `lsblk -d -b -n -o NAME,SIZE,TYPE,MODEL`, register `lsblk_raw`, filter lines matching `nvme`, set `nvme_devices` fact
- [x] T006 [P] [US1] Add capacity collection task to `roles/disk-health/tasks/main.yml`: shell `df -B1 --output=source,size,used,avail,pcent` for each NVMe device, register `df_raw` per device
- [x] T007 [US1] Add S.M.A.R.T. health collection task to `roles/disk-health/tasks/main.yml`: shell `smartctl -j -A -H /dev/{{ item }}`, `ignore_errors: true`, register `smart_raw` per device (depends on T004)
- [x] T008 [US1] Add health status derivation task to `roles/disk-health/tasks/main.yml`: set `health_status` per drive using Jinja2 conditionals per derivation rules in `data-model.md` (CRITICAL → WARNING → HEALTHY → UNKNOWN order)
- [x] T009 [US1] Add `node_disk_summary` fact assembly task to `roles/disk-health/tasks/main.yml`: combine device name, model, size, capacity fields, health_status, and smart fields into the schema defined in `data-model.md`
- [x] T010 [US1] Wire collection play into `disk-health.yml`: `hosts: all`, `become: true`, `any_errors_fatal: false`, include role `disk-health`
- [x] T011 [US1] Add report play to `disk-health.yml`: `hosts: localhost`, `gather_facts: no`; add `debug` task with Jinja2 template looping over `groups['all']` and `hostvars` to render per-node drive table including device, model, size, use%, and health status; include report header and footer with timestamp

**Checkpoint**: User Story 1 independently functional — single command produces full report.

---

## Phase 4: User Story 2 - Detect Missing Drives (Priority: P2)

**Goal**: Explicitly flag nodes with no detected drives and exit with non-zero status code
when any CRITICAL drive or missing drive condition is present.

**Independent Test**: Temporarily set `expected_drives_min: 2` in defaults (or override via
`--extra-vars`) on a single-drive node and verify playbook flags that node MISSING and exits
with code 2.

### Implementation for User Story 2

- [x] T012 [US2] Add missing-drive detection task to `roles/disk-health/tasks/main.yml`: set `drive_status: MISSING` on `node_disk_summary.overall_status` when `nvme_devices | length < expected_drives_min`; set `drive_status: UNREACHABLE` via `ignore_unreachable: true` handler in collection play (depends on T009)
- [x] T013 [US2] Add assert play to `disk-health.yml` (after report play): loop over `groups['all']` using `hostvars`, assert `overall_status` is not CRITICAL or MISSING for each node, `ignore_errors: true` to collect all failures; follow with final `fail` task if any assertions failed — exits playbook with code 2 (depends on T011)
- [x] T014 [US2] Update report play in `disk-health.yml` to include summary footer line: counts of healthy/warning/critical/missing/unreachable nodes and overall PASS/FAIL result

**Checkpoint**: User Stories 1 and 2 both independently functional.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [x] T015 [P] Add description comment block to top of `disk-health.yml` explaining purpose, usage, and exit codes (per constitution Deployment Workflow: "all new playbooks MUST include a brief description comment")
- [x] T016 [P] Add `roles/disk-health/defaults/main.yml` variable documentation comments for `expected_drives_min`, threshold variables
- [ ] T017 Validate idempotency: run `ansible-playbook -i hosts.ini disk-health.yml` twice in succession; confirm `changed: 0` on second run (constitution Principle II)
- [x] T018 [P] Add `disk-health.yml` entry to `README.md` under a new `## Utilities` section documenting the command and what it checks

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — blocks both user stories
- **User Story 1 (Phase 3)**: Depends on Phase 2 — no dependency on US2
- **User Story 2 (Phase 4)**: Depends on Phase 3 completion (T009, T011 must exist to extend)
- **Polish (Phase 5)**: Depends on both user stories complete

### Within Each User Story

- T005, T006 can run in parallel (different output vars, no dependency)
- T007 depends on T004 (smartmontools must be installed before smartctl runs)
- T008 depends on T007 (needs smart_raw to derive health_status)
- T009 depends on T005, T006, T008 (assembles all facts)
- T010 depends on T009 (wires role into playbook)
- T011 depends on T010 (report play reads hostvars set by collection play)

### Parallel Opportunities

- T001, T002 can run in parallel (different paths)
- T005, T006 can run in parallel within US1
- T015, T016, T018 can run in parallel in Polish phase

---

## Parallel Example: User Story 1 Setup

```bash
# Launch simultaneously (different files, no shared state):
Task: "Add block device enumeration task to roles/disk-health/tasks/main.yml"   # T005
Task: "Add capacity collection task to roles/disk-health/tasks/main.yml"         # T006
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (install smartmontools)
3. Complete Phase 3: User Story 1 (enumeration + S.M.A.R.T. + report)
4. **STOP and VALIDATE**: `ansible-playbook -i hosts.ini disk-health.yml` — verify report output
5. Proceed to User Story 2 once report is confirmed

### Incremental Delivery

1. Setup + Foundational → scaffolding ready
2. User Story 1 → working report on stdout (MVP)
3. User Story 2 → adds missing-drive detection + exit code signal
4. Polish → idempotency validated, README updated

---

## Notes

- [P] tasks operate on different files or independent variables — safe to run in parallel
- [US1]/[US2] labels map directly to user stories in spec.md
- Constitution Principle II (Idempotency): T017 explicitly validates this
- Constitution Principle V (Simplicity): no custom modules; standard `lsblk`, `df`, `smartctl`
- `any_errors_fatal: false` on collection play is required — do not change this
- `become: true` required on collection play (smartctl needs root to read S.M.A.R.T. data)
