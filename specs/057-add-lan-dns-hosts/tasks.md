# Tasks: fleet1.lan Infrastructure DNS Host Records

**Input**: Design documents from `/specs/057-add-lan-dns-hosts/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/unbound-host-overrides.md, quickstart.md

**Tests**: No separate automated test suite was requested. Validation tasks use Ansible syntax/check-mode where useful and the quickstart DNS checks.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the existing network playbook and feature docs are ready for implementation.

- [X] T001 Review the existing Unbound host override block and variable scope in `playbooks/network/network-deploy.yml`
- [X] T002 [P] Review the desired record list and validation rules in `specs/057-add-lan-dns-hosts/data-model.md`
- [X] T003 [P] Review the OPNsense API interaction contract in `specs/057-add-lan-dns-hosts/contracts/unbound-host-overrides.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add shared data and conflict detection needed before any user story can be implemented safely.

**CRITICAL**: No user story work can begin until this phase is complete.

- [X] T004 Add `fleet1_lan_infra_dns_records` to the `vars` block in `playbooks/network/network-deploy.yml` with entries for `opnsense`, `sw-main`, `sw-poe-1`, `sw-poe-2`, and `sw-poe-3`
- [X] T005 Build an existing Unbound override lookup structure from `existing_unbound_overrides.json.rows` in `playbooks/network/network-deploy.yml` for desired hostname/domain/address comparisons
- [X] T006 Add hostname conflict detection to `playbooks/network/network-deploy.yml` that fails when a desired `fleet1.lan` hostname exists with a different `server` value
- [X] T007 Add address conflict detection to `playbooks/network/network-deploy.yml` that fails when a desired `10.1.1.x` address exists on an unrelated `fleet1.lan` hostname

**Checkpoint**: The playbook can identify the desired records and fail before applying conflicting DNS state.

---

## Phase 3: User Story 1 - Resolve Core Network Devices by Name (Priority: P1) MVP

**Goal**: LAN clients using OPNsense DNS resolve all five requested infrastructure hostnames to their specified IP addresses.

**Independent Test**: Resolve `opnsense.fleet1.lan`, `sw-main.fleet1.lan`, `sw-poe-1.fleet1.lan`, `sw-poe-2.fleet1.lan`, and `sw-poe-3.fleet1.lan` against `10.1.1.1`; each must return the expected address.

### Implementation for User Story 1

- [X] T008 [US1] Add an idempotent loop in `playbooks/network/network-deploy.yml` that creates missing entries from `fleet1_lan_infra_dns_records` via `/unbound/settings/addHostOverride`
- [X] T009 [US1] Update the Unbound reconfigure condition in `playbooks/network/network-deploy.yml` so `/unbound/service/reconfigure` runs when any infrastructure DNS record is created
- [X] T010 [US1] Ensure infrastructure DNS record creation in `playbooks/network/network-deploy.yml` uses enabled `A` records with hostname, domain, server, and description values from `fleet1_lan_infra_dns_records`
- [X] T011 [US1] Run an Ansible syntax validation for `playbooks/network/network-deploy.yml` and record any required fixes in `specs/057-add-lan-dns-hosts/tasks.md`
- [X] T012 [US1] Apply `playbooks/network/network-deploy.yml` from the repository root to create the missing OPNsense Unbound records
- [X] T013 [US1] Validate the five expected DNS answers using the commands in `specs/057-add-lan-dns-hosts/quickstart.md`

**Checkpoint**: User Story 1 is complete when all five hostnames resolve to `10.1.1.1`, `10.1.1.10`, `10.1.1.11`, `10.1.1.12`, and `10.1.1.13` respectively.

---

## Phase 4: User Story 2 - Use Hostnames in Routine Administration (Priority: P2)

**Goal**: The operator can use the new hostnames for routine device administration instead of typing numeric addresses.

**Independent Test**: From a LAN client, connection attempts to the new hostnames target the expected management IPs.

### Implementation for User Story 2

- [X] T014 [US2] Validate that `opnsense.fleet1.lan` targets `10.1.1.1` for an administrative connection attempt and document the command/result in `specs/057-add-lan-dns-hosts/quickstart.md`
- [X] T015 [US2] Validate that `sw-main.fleet1.lan`, `sw-poe-1.fleet1.lan`, `sw-poe-2.fleet1.lan`, and `sw-poe-3.fleet1.lan` target their expected management IPs and document the command/result in `specs/057-add-lan-dns-hosts/quickstart.md`

**Checkpoint**: User Story 2 is complete when routine connection attempts can reference all five new names and land on the expected device addresses.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Verify idempotency, persistence, and documentation after both user stories are complete.

- [X] T016 Re-run `playbooks/network/network-deploy.yml` and confirm the infrastructure DNS records are idempotent with no duplicate Unbound host overrides
- [X] T017 Validate persistence after an OPNsense Unbound reconfigure or restart using `specs/057-add-lan-dns-hosts/quickstart.md`
- [X] T018 Update `specs/057-add-lan-dns-hosts/quickstart.md` with the final apply, idempotency, DNS validation, and persistence validation results

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies; can start immediately.
- **Foundational (Phase 2)**: Depends on Setup completion; blocks all user stories.
- **User Story 1 (Phase 3)**: Depends on Foundational completion; MVP.
- **User Story 2 (Phase 4)**: Depends on User Story 1 DNS records being active.
- **Polish (Phase 5)**: Depends on desired user stories being complete.

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational; no dependency on User Story 2.
- **User Story 2 (P2)**: Depends on User Story 1 because administrative hostname use requires DNS resolution first.

### Within Each User Story

- Data and conflict checks before create/apply tasks.
- Create missing host records before Unbound reconfigure.
- Apply playbook before DNS validation.
- DNS validation before administrative connection validation.

### Parallel Opportunities

- T002 and T003 can run in parallel during setup.
- After T004, T006 and T007 can be developed together if edits are coordinated in `playbooks/network/network-deploy.yml`.
- US2 validation tasks T014 and T015 can run in parallel after US1 is complete.

---

## Parallel Example: User Story 2

```text
Task: "Validate that opnsense.fleet1.lan targets 10.1.1.1 for an administrative connection attempt and document the command/result in specs/057-add-lan-dns-hosts/quickstart.md"
Task: "Validate that sw-main.fleet1.lan, sw-poe-1.fleet1.lan, sw-poe-2.fleet1.lan, and sw-poe-3.fleet1.lan target their expected management IPs and document the command/result in specs/057-add-lan-dns-hosts/quickstart.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 setup review.
2. Complete Phase 2 desired-record data and conflict detection.
3. Complete Phase 3 DNS record creation and DNS validation.
4. Stop and validate all five DNS answers before moving to administrative connection checks.

### Incremental Delivery

1. Add the desired-record list and safety checks.
2. Add idempotent record creation for User Story 1.
3. Validate DNS resolution and idempotency.
4. Validate routine administration via the new names for User Story 2.
5. Run polish checks for re-run behavior and persistence.

### Notes

- Keep this feature limited to explicit host overrides for the five requested infrastructure devices.
- Do not modify the existing `*.fleet1.lan` wildcard, apex override, DNAT rules, TLS configuration, or unrelated `fleet1.lan` records.
- Commit after the playbook change and validation notes are complete.
