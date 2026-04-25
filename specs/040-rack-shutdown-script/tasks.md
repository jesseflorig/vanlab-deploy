# Tasks: Rack Shutdown Script

**Input**: Design documents from `/specs/040-rack-shutdown-script/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cli.md

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on each other)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Inventory and entry point changes needed before any playbook work begins.

- [x] T001 [P] Add `[network]` group to `hosts.ini` with entry `opnsense  ansible_ssh_private_key_file=~/.ssh/id_rsa` (no `ansible_host` — SSH config resolves `opnsense` → `10.1.1.1` with `User fleetadmin`)
- [x] T002 [P] Create `Makefile` at repo root with two targets: `shutdown` running `ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml` and `shutdown-dry-run` running the same with `--check`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Playbook file scaffold that all subsequent tasks build on.

**⚠️ CRITICAL**: All user story tasks edit `playbooks/utilities/rack-shutdown.yml` — this file must exist first.

- [x] T003 Create `playbooks/utilities/rack-shutdown.yml` with a file-header comment block (description, usage, author) and five empty named plays: `Pre-flight checks`, `Drain and shut down agent nodes`, `Drain and shut down server nodes`, `Shut down edge host`, `Shut down OPNsense` — each with correct `hosts:` target (`localhost`, `agents`, `servers`, `compute`, `network`), `become: true` where applicable, and `gather_facts: false`

**Checkpoint**: `rack-shutdown.yml` exists and passes `ansible-playbook --syntax-check` before any play content is added.

---

## Phase 3: User Story 1 — Graceful Full Rack Shutdown (Priority: P1) 🎯 MVP

**Goal**: Full rack halts in dependency order — agents → servers → edge → OPNsense — with graceful drain at each step.

**Independent Test**: Run `make shutdown` against the live rack and confirm: all 6 cluster nodes reach `NotReady`, cloudflared stops on edge, OPNsense halts, Longhorn reports no degraded volumes after power-on.

### Implementation

- [x] T004 [US1] Implement the pre-flight host reachability check in Play 1 of `playbooks/utilities/rack-shutdown.yml`: use `ansible.builtin.wait_for_connection` (timeout 10s) across all inventory groups with `ignore_unreachable: true`; register results and emit a `debug` warning message for any unreachable host; do NOT fail
- [x] T005 [US1] Implement the pre-flight Longhorn volume health check in Play 1 of `playbooks/utilities/rack-shutdown.yml`: delegate a `kubectl get volumes.longhorn.io -n longhorn-system` command to localhost, parse output for volumes where `status.robustness` is not `healthy`, emit a `debug` warning listing degraded volumes; do NOT fail
- [x] T006 [US1] Implement agent drain + shutdown in Play 2 of `playbooks/utilities/rack-shutdown.yml`: set `serial: 1`; for each agent, run `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=600s` from `servers[0]` (using `delegate_to: "{{ groups['servers'][0] }}"` and `KUBECONFIG: /etc/rancher/k3s/k3s.yaml`); then stop `k3s-agent` via `ansible.builtin.systemd`; then issue `shutdown -h now` with `async: 5, poll: 0`
- [x] T007 [US1] Implement server drain + shutdown in Play 3 of `playbooks/utilities/rack-shutdown.yml`: set `serial: 1`; for each server, determine the drain source (the next surviving server peer — `servers[1]` when draining `servers[0]`, `servers[2]` when draining `servers[1]`, skip drain when draining the last server); drain using same kubectl flags as T006; stop `k3s` via `ansible.builtin.systemd`; issue `shutdown -h now` with `async: 5, poll: 0`
- [x] T008 [US1] Implement edge host shutdown in Play 4 of `playbooks/utilities/rack-shutdown.yml`: stop `cloudflared` via `ansible.builtin.systemd` (state: stopped); then issue `shutdown -h now` with `async: 5, poll: 0`
- [x] T009 [US1] Implement OPNsense shutdown in Play 5 of `playbooks/utilities/rack-shutdown.yml`: run `ansible.builtin.command: shutdown -h now` with `async: 5`, `poll: 0`, and `ignore_unreachable: true`; set `changed_when: true`; add a `debug` task immediately before it printing "OPNsense shutdown command sent — network connectivity will drop"

**Checkpoint**: `make shutdown` halts the full rack without manual intervention on a healthy cluster.

---

## Phase 4: User Story 2 — Dry-Run Preview (Priority: P2)

**Goal**: `make shutdown-dry-run` prints the full planned sequence without executing any remote actions.

**Independent Test**: Run `make shutdown-dry-run` and verify: no SSH connections are made to cluster nodes or OPNsense (confirm via Ansible `-v` output), all cluster and node states are unchanged, printed sequence matches the documented order in `contracts/cli.md`.

### Implementation

- [x] T010 [US2] Add a dry-run header task at the top of Play 1 in `playbooks/utilities/rack-shutdown.yml`: a `ansible.builtin.debug` task with `msg: "DRY RUN — no changes will be made"` conditional on `ansible_check_mode`; set `check_mode: false` so it runs even during `--check`
- [x] T011 [US2] Set `check_mode: false` on the pre-flight read-only tasks in Play 1 of `playbooks/utilities/rack-shutdown.yml` (the `wait_for_connection` reachability check and the kubectl Longhorn check from T004/T005), so they execute and display current state during `--check` runs rather than being skipped

**Checkpoint**: `make shutdown-dry-run` completes with no destructive actions taken; output shows each planned step in the correct sequence.

---

## Phase 5: User Story 3 — Progress Feedback (Priority: P3)

**Goal**: Every step prints a clear status line so the operator can follow along or identify where a failure occurred.

**Independent Test**: Run `make shutdown` and confirm: each play transition prints a visible banner, each critical step (drain, service stop, halt) prints before and after status, the OPNsense play prints a notice before the final command.

### Implementation

- [x] T012 [US3] Add play-opening banner `ansible.builtin.debug` tasks at the start of each play in `playbooks/utilities/rack-shutdown.yml` — one per play, e.g., `"=== Phase 2: Draining and shutting down agent nodes ==="` — using `check_mode: false` so banners display in dry-run too
- [x] T013 [US3] Ensure all tasks in `playbooks/utilities/rack-shutdown.yml` have descriptive `name:` values that read as a progress log (e.g., `"Drain node {{ inventory_hostname }} from {{ groups['servers'][0] }}"`, `"Stop k3s-agent on {{ inventory_hostname }}"`, `"Halt {{ inventory_hostname }}"`)
- [x] T014 [US3] Add a 5-second pause task in Play 1 of `playbooks/utilities/rack-shutdown.yml` immediately after the pre-flight summary — triggered only when any warning was emitted — using `ansible.builtin.pause` with `seconds: 5` and a prompt message `"Pre-flight warnings detected above — press Ctrl+C to abort, or wait 5 seconds to continue"`; set `check_mode: false`

**Checkpoint**: An operator watching the output can trace exactly where a failure occurred and why, without consulting source code.

---

## Phase 6: Polish & Validation

**Purpose**: Syntax validation, end-to-end dry-run verification, and documentation tidy-up.

- [x] T015 [P] Run `ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml --syntax-check` and fix any syntax errors
- [ ] T016 Run `make shutdown-dry-run` against the live rack and confirm output sequence matches `specs/040-rack-shutdown-script/contracts/cli.md` exactly; update `quickstart.md` with any corrections
- [ ] T017 [P] Verify `make shutdown` and `make shutdown-dry-run` targets in `Makefile` work correctly from repo root with a clean shell (no Ansible env vars pre-set)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — T001 and T002 can start immediately in parallel
- **Foundational (Phase 2)**: Depends on T001 (hosts.ini must have `[network]`) before T003 can be fully validated
- **US1 (Phase 3)**: Depends on T003 — all US1 tasks edit the same file sequentially
- **US2 (Phase 4)**: Depends on T004/T005 existing in the playbook (T010/T011 modify those tasks)
- **US3 (Phase 5)**: Depends on all US1 plays being implemented (T004–T009)
- **Polish (Phase 6)**: Depends on all implementation phases complete

### User Story Dependencies

- **US1 (P1)**: After Foundational — no cross-story dependencies
- **US2 (P2)**: After US1 T004/T005 (modifies pre-flight tasks); can partially overlap US1
- **US3 (P3)**: After US1 complete (modifies all plays); completes the playbook

### Within US1

T004 and T005 both live in Play 1 and can be implemented together. T006 → T007 → T008 → T009 are strictly sequential — each is a separate play in order.

### Parallel Opportunities

- T001 and T002 are fully parallel (different files)
- T015 and T017 are parallel (read-only checks)

---

## Parallel Example: Phase 1

```bash
# Both can start immediately:
Task T001: Add [network] group to hosts.ini
Task T002: Create Makefile with shutdown targets
```

---

## Implementation Strategy

### MVP (User Story 1 only)

1. Complete Phase 1: T001, T002
2. Complete Phase 2: T003
3. Complete Phase 3: T004 → T005 → T006 → T007 → T008 → T009
4. **STOP and VALIDATE**: Run `make shutdown` against live rack
5. Full rack shuts down gracefully — core value delivered

### Incremental Delivery

1. Phase 1 + Phase 2 → Scaffold ready
2. Phase 3 (US1) → Full rack shutdown works
3. Phase 4 (US2) → Dry-run preview works
4. Phase 5 (US3) → Progress feedback polished
5. Phase 6 → Validated and documented

---

## Notes

- All tasks T004–T014 edit `playbooks/utilities/rack-shutdown.yml` — implement sequentially; no parallel edits to the same file
- `ansible_check_mode` variable is `true` when `--check` is passed; use it for conditional dry-run tasks
- `check_mode: false` on a task = "run this task even in check mode" (for read-only pre-flight and banners)
- The peer-drain logic in T007 is the most complex task — the last server (servers[2]) skips drain entirely since there's no surviving API server to drain to
- OPNsense `ansible_ssh_pass` from `[all:vars]` is bypassed by `ansible_ssh_private_key_file` on the `[network]` group (T001)
