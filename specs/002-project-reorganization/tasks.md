# Tasks: Project Reorganization

**Input**: Design documents from `/specs/002-project-reorganization/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Ansible configuration and collection dependency files required by all subsequent work

- [x] T001 Create ansible.cfg at ansible.cfg: set `inventory = hosts.ini`, `host_key_checking = False`, `interpreter_python = auto_silent`, `remote_user = fleetadmin`
- [x] T002 [P] Create requirements.yml at requirements.yml: pin `oxlorg.opnsense >= 25.0.0` from galaxy.ansible.com

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Updated inventory and split group_vars — required before any playbook can be run against the new structure

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 Update hosts.ini: rename `[masters]` → `[servers]`, `[workers]` → `[agents]`, `[k3s_cluster:children]` → `[cluster:children]`; remove `[edge]` group; add `[compute]` group with `edge ansible_host=10.1.10.x  # CM5 Cloudflared device`; add topology reference comment block for OPNsense (10.1.1.1), GS308T (10.1.1.x), and three GS308EPP switches (10.1.1.x); keep `[all:vars]` block unchanged
- [x] T004 [P] Create group_vars/cluster.yml: `k3s_master_ip: "10.1.20.11"` and `k3s_flannel_iface: "eth0"`
- [x] T005 [P] Create group_vars/network.yml: `opnsense_firewall: "10.1.1.1"` and `opnsense_api_verify_ssl: false`
- [x] T006 [P] Create group_vars/compute.yml: `cloudflared_service_name: cloudflared` and `cloudflared_token_path: /etc/cloudflared/tunnel-token`
- [x] T007 [P] Update group_vars/example.all.yml: add `cloudflare_tunnel_token: <CLOUDFLARE_TUNNEL_TOKEN>`, `opnsense_api_key: <OPNSENSE_API_KEY>`, `opnsense_api_secret: <OPNSENSE_API_SECRET>` entries alongside existing SSH credential placeholders

**Checkpoint**: Foundation ready — all device groups defined, per-category vars in place

---

## Phase 3: User Story 1 - Single Inventory (Priority: P1) 🎯 MVP

**Goal**: All managed devices reachable via single inventory; utility playbooks updated to new group names

**Independent Test**: `ansible-playbook -i hosts.ini playbooks/utilities/check_hosts.yml --ask-become-pass` — all cluster nodes and edge device respond ONLINE

### Implementation for User Story 1

- [x] T008 [US1] Move check_hosts.yml to playbooks/utilities/check_hosts.yml: update any `masters`/`workers`/`k3s_cluster` group references to `servers`/`agents`/`cluster`; verify `hosts:` targets reference new group names
- [x] T009 [P] [US1] Move utilities/read-k3s-token.yml to playbooks/utilities/read-k3s-token.yml: update any `masters`/`workers` references to `servers`/`agents`
- [x] T010 [P] [US1] Move utilities/test-join-cmd.yml to playbooks/utilities/test-join-cmd.yml: update any `masters`/`workers` references to `servers`/`agents`

**Checkpoint**: US1 complete — `check_hosts` passes against all managed devices with new group names

---

## Phase 4: User Story 2 - Edge Device Deployment (Priority: P2)

**Goal**: Cloudflared running as a native systemd service on CM5; cluster playbooks moved and updated; edge removed from cluster services

**Independent Test**: `ansible-playbook -i hosts.ini playbooks/compute/edge-deploy.yml --ask-become-pass` — Cloudflared installed and `systemctl status cloudflared` shows `active (running)` on edge device

### Implementation for User Story 2

- [x] T011 [US2] Rewrite roles/cloudflared/tasks/main.yml with these tasks in order: (1) `get_url` to download Cloudflare GPG key to `/usr/share/keyrings/cloudflare-main.gpg` mode 0644; (2) `apt_repository` adding `deb [signed-by=...] https://pkg.cloudflare.com/cloudflared bookworm main`; (3) `apt` install `cloudflared` state=present update_cache=true with `notify: Restart cloudflared`; (4) create `/etc/cloudflared/` directory mode 0755; (5) `copy` tunnel token from `{{ cloudflare_tunnel_token }}` to `{{ cloudflared_token_path }}` owner=root group=root mode=0600 with `notify: Restart cloudflared`; (6) `copy` systemd unit to `/etc/systemd/system/cloudflared.service` with ExecStart using `--token-file {{ cloudflared_token_path }}` and `notify: Restart cloudflared`; (7) `systemd_service` enable and start cloudflared with daemon_reload=true; (8) `systemd_service` register status and `failed_when` ActiveState != 'active'
- [x] T012 [P] [US2] Create roles/cloudflared/handlers/main.yml: single handler `Restart cloudflared` using `ansible.builtin.systemd_service` with `name: "{{ cloudflared_service_name }}"`, `state: restarted`, `daemon_reload: true`
- [x] T013 [P] [US2] Update roles/cloudflared/defaults/main.yml: replace all Helm/K8s vars with `cloudflared_service_name: cloudflared` and `cloudflared_token_path: /etc/cloudflared/tunnel-token` only
- [x] T014 [US2] Create playbooks/compute/edge-deploy.yml: single play targeting `hosts: compute`, `become: true`, applying `roles: [cloudflared]`; include a `pre_tasks` block that asserts `cloudflare_tunnel_token` is defined (depends on T011, T012, T013)
- [x] T015 [P] [US2] Move k3s-deploy.yml to playbooks/cluster/k3s-deploy.yml: update all `hosts: masters` → `hosts: servers`, `hosts: workers` → `hosts: agents`, `hosts: k3s_cluster` → `hosts: cluster`; update any `groups['masters']` or `groups['workers']` Jinja references to `groups['servers']`/`groups['agents']`
- [x] T016 [P] [US2] Move services-deploy.yml to playbooks/cluster/services-deploy.yml: rename `hosts: masters` → `hosts: servers` and add `traefik` to that play's roles list; rename `hosts: workers` → `hosts: agents`; delete the entire `hosts: edge` play block; remove any `cloudflared` role reference from all remaining plays
- [x] T017 [P] [US2] Move disk-health.yml to playbooks/utilities/disk-health.yml: update any `masters`/`workers`/`k3s_cluster` group references to `servers`/`agents`/`cluster`

**Checkpoint**: US2 complete — edge-deploy.yml runs idempotently; cluster playbooks work from new paths

---

## Phase 5: User Story 3 - OPNsense Scaffold (Priority: P3)

**Goal**: Network playbook connects to OPNsense via REST API and verifies connectivity in check mode

**Independent Test**: `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml --check` exits 0 and prints OPNsense connection success

### Implementation for User Story 3

- [x] T018 [US3] Create playbooks/network/network-deploy.yml: `hosts: localhost`, `connection: local`, `gather_facts: false`; add `module_defaults` block for `group/oxlorg.opnsense.all` setting `firewall: "{{ opnsense_firewall }}"`, `api_key: "{{ opnsense_api_key }}"`, `api_secret: "{{ opnsense_api_secret }}"`, `ssl_verify: "{{ opnsense_api_verify_ssl }}"`; add a single `oxlorg.opnsense.system_information` task to verify connectivity and register result; add `debug` task printing firmware version from result; include a `vars` block comment referencing group_vars/network.yml and group_vars/all.yml for credentials

**Checkpoint**: US3 complete — `--check` mode verifies OPNsense API connectivity

---

## Phase 6: User Story 4 - Playbook Discoverability (Priority: P4)

**Goal**: README updated with new directory structure and exact run commands per device category

**Independent Test**: A new operator using only the README can find and run the correct playbook for cluster, edge, network, and utilities in under 30 seconds

### Implementation for User Story 4

- [x] T019 [US4] Update README.md: add or replace the playbook directory section to show the `playbooks/` tree organized by category (cluster/, network/, compute/, utilities/); add a "Quick Reference" table or section with the exact `ansible-playbook` command for each playbook matching quickstart.md; update any stale paths (root-level playbook references) to their new `playbooks/<category>/` locations

**Checkpoint**: US4 complete — README documents all playbook locations with exact commands

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Verify zero drift from old group names; confirm all paths functional

- [x] T020 [P] Grep repository for remaining references to group names `masters`, `workers`, `k3s_cluster`, `[edge]` (excluding specs/ and .git/); fix any found in playbooks, roles, or documentation
- [x] T021 Run ansible-playbook --syntax-check on all moved/new playbooks: playbooks/utilities/check_hosts.yml, playbooks/cluster/k3s-deploy.yml, playbooks/cluster/services-deploy.yml, playbooks/compute/edge-deploy.yml, playbooks/network/network-deploy.yml, playbooks/utilities/disk-health.yml

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on T003 (hosts.ini) — can start as soon as T003 completes
- **US2 (Phase 4)**: Depends on Foundational completion — T011/T012/T013 parallelizable
- **US3 (Phase 5)**: Depends on T003 + T005 (hosts.ini + network.yml) — independent of US2
- **US4 (Phase 6)**: Depends on all prior phases completing — documentation reflects final state
- **Polish (Phase 7)**: Depends on all user stories complete

### User Story Dependencies

- **US1 (P1)**: Unblocked after T003 — foundational inventory change
- **US2 (P2)**: Unblocked after Phase 2 — role rewrite + playbook moves are independent of US1
- **US3 (P3)**: Unblocked after T003 + T005 — new playbook, no file conflicts with US1/US2
- **US4 (P4)**: Must follow US1–US3 — documents the final state of all playbook paths

### Parallel Opportunities

- T001 + T002: parallel (different files)
- T004 + T005 + T006 + T007: parallel (different files)
- T008 + T009 + T010: parallel within US1 (different files)
- T011 + T012 + T013: parallel within US2 role rewrite (different files)
- T015 + T016 + T017: parallel within US2 playbook moves (different files)
- T020: parallel with T021

---

## Parallel Example: User Story 2 (Role Rewrite)

```bash
# Launch role rewrite tasks together (all different files):
Task T011: "Rewrite roles/cloudflared/tasks/main.yml for systemd"
Task T012: "Create roles/cloudflared/handlers/main.yml"
Task T013: "Update roles/cloudflared/defaults/main.yml"

# After T011/T012/T013 complete, launch playbook moves together:
Task T014: "Create playbooks/compute/edge-deploy.yml"
Task T015: "Move k3s-deploy.yml to playbooks/cluster/k3s-deploy.yml"
Task T016: "Move services-deploy.yml to playbooks/cluster/services-deploy.yml"
Task T017: "Move disk-health.yml to playbooks/utilities/disk-health.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T002)
2. Complete Phase 2: Foundational (T003–T007)
3. Complete Phase 3: US1 (T008–T010)
4. **STOP and VALIDATE**: `ansible-playbook -i hosts.ini playbooks/utilities/check_hosts.yml --ask-become-pass`
5. All managed devices respond with new group names → US1 shipped

### Incremental Delivery

1. Setup + Foundational → inventory correct, vars split
2. US1 → utility playbooks moved, check_hosts passes (MVP)
3. US2 → edge device operational, cluster playbooks at new paths
4. US3 → OPNsense connectivity verified in check mode
5. US4 + Polish → README complete, zero legacy group references

---

## Notes

- [P] tasks = different files, no dependencies — safe to run in parallel
- [Story] label maps each task to its user story for traceability
- No test tasks generated — spec does not request TDD approach; validation is via smoke tests per quickstart.md
- After T003 (hosts.ini), run `ansible-playbook --syntax-check` before continuing to catch group reference errors early
- `group_vars/all.yml` is gitignored; never modify it in tasks — only `example.all.yml`
- The `utilities/` root directory is retired after T009 and T010 move its contents
