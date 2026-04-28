# Tasks: Wireguard VPN for management laptop access to fleet1.lan

**Input**: Design documents from `/specs/058-wireguard-management-vpn/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Validation tasks follow the manual checks described in `quickstart.md`. No automated test suite requested.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 [P] Add Wireguard private/public keys and VPN subnet variables to `group_vars/all.yml`
- [X] T002 [P] Add placeholder Wireguard variables to `group_vars/example.all.yml`
- [X] T003 [P] Ensure `specs/058-wireguard-management-vpn/` directory contains all design artifacts

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Verify `os-wireguard` plugin installation on OPNsense via `oxlorg.opnsense.raw` in `playbooks/network/network-deploy.yml`
- [X] T005 Verify OPNsense API credentials in `group_vars/all.yml` have permission for `wireguard` endpoints

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Secure Remote Access (Priority: P1) 🎯 MVP

**Goal**: Establish a functional Wireguard tunnel between management laptop and OPNsense.

**Independent Test**: Management laptop successfully handshakes and pings `10.1.254.1` (VPN Gateway).

### Implementation for User Story 1

- [X] T006 [P] [US1] Define Wireguard server configuration variables in `playbooks/network/network-deploy.yml` per `contracts/wireguard-api.md`
- [X] T007 [P] [US1] Define management laptop peer configuration variables in `playbooks/network/network-deploy.yml` per `contracts/wireguard-api.md`
- [X] T008 [US1] Implement Wireguard server provisioning task using `ansible.builtin.uri` in `playbooks/network/network-deploy.yml`
- [X] T009 [US1] Implement Wireguard peer provisioning task using `ansible.builtin.uri` in `playbooks/network/network-deploy.yml`
- [X] T010 [US1] Implement Wireguard service reconfigure task in `playbooks/network/network-deploy.yml`
- [X] T011 [US1] Create local `fleet1.conf` on management laptop per `quickstart.md`
- [X] T012 [US1] Validate tunnel handshake and connectivity to `10.1.254.1`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Full LAN Resource Access (Priority: P2)

**Goal**: Allow VPN clients to reach internal management and cluster networks.

**Independent Test**: While connected via VPN, successfully resolve `opnsense.fleet1.lan` and access `https://gitea.fleet1.lan`.

### Implementation for User Story 2

- [X] T013 [US2] Add WAN-side firewall rule to allow UDP/51820 in `playbooks/network/network-deploy.yml`
- [X] T014 [US2] Add Wireguard-to-Management firewall rules in `playbooks/network/network-deploy.yml`
- [X] T015 [US2] Add Wireguard-to-Cluster firewall rules in `playbooks/network/network-deploy.yml`
- [X] T016 [US2] Add firewall apply task for Wireguard interface group in `playbooks/network/network-deploy.yml`
- [X] T017 [US2] Configure Unbound DNS to listen on and respond to the VPN subnet in `playbooks/network/network-deploy.yml`
- [X] T018 [US2] Validate internal DNS resolution and resource access per `quickstart.md`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Automated Provisioning (Priority: P3)

**Goal**: Ensure the entire VPN configuration is managed idempotently via Ansible.

**Independent Test**: Re-run the network playbook; it should report 0 changes if configuration matches.

### Implementation for User Story 3

- [X] T019 [US3] Add idempotency checks (search before add) for Wireguard server/peers in `playbooks/network/network-deploy.yml`
- [X] T020 [US3] Ensure all Wireguard tasks in `playbooks/network/network-deploy.yml` are tagged with `wireguard`
- [X] T021 [US3] Perform full playbook dry-run (`--check`) and verify reported changes

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T022 [P] Update `README.md` with Wireguard VPN connection instructions
- [X] T023 [P] Final update to `specs/058-wireguard-management-vpn/quickstart.md` with validated output
- [X] T024 Perform security audit of Wireguard firewall rules to ensure NO broad internet egress via VPN (split-tunnel only)
- [X] T025 Run final `make sync` to ensure all remotes are updated

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - Sequential priority order (US1 → US2 → US3) is recommended for network stability
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Depends on US1 (requires tunnel established to verify routing)
- **User Story 3 (P3)**: Depends on US1/US2 (requires established logic to refine idempotency)

### Within Each User Story

- Prerequisites before API calls
- Server setup before Peer setup
- Routing/Firewall before DNS configuration
- Validation after each logical group

### Parallel Opportunities

- T001, T002, T003 can run in parallel (Phase 1)
- T006, T007 can run in parallel (Phase 3)
- T022, T023 can run in parallel (Phase 6)

---

## Parallel Example: Phase 1 Setup

```bash
# Prepare all variables and workspace:
Task: "Add Wireguard private/public keys and VPN subnet variables to group_vars/all.yml"
Task: "Add placeholder Wireguard variables to group_vars/example.all.yml"
Task: "Ensure specs/058-wireguard-management-vpn/ directory contains all design artifacts"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL)
3. Complete Phase 3: User Story 1 (MVP)
4. **STOP and VALIDATE**: Verify tunnel handshake
5. Commit and continue

### Incremental Delivery

1. Complete Setup + Foundational
2. Add US1 → Verify connectivity (Gateway only)
3. Add US2 → Verify full resource access
4. Add US3 → Verify automation/idempotency
5. Polish docs and audit security

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Avoid: broad `AllowedIPs` (e.g. `0.0.0.0/0`) unless full tunnel is desired (Spec implies split-tunnel for lab access)
