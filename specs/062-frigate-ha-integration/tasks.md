---
description: "Task list for Frigate Home Assistant integration implementation"
---

# Tasks: Frigate Home Assistant Integration

**Input**: Design documents from `/specs/062-frigate-ha-integration/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Verify Home Assistant pod is running and accessible in namespace `home-automation`
- [x] T002 Verify Frigate NVR is accessible from the cluster network at `http://10.1.10.11:5000`
- [x] T003 [P] Verify MQTT broker is healthy and accessible in `home-automation` namespace

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

- [x] T004 Install HACS (Home Assistant Community Store) in the HA pod via `kubectl exec` and `wget`
- [x] T005 Restart Home Assistant statefulset to activate HACS
- [x] T006 Install the Frigate Custom Integration via the HACS UI and restart HA
- [x] T007 [P] Ensure the `packages` directory inclusion is present in `configuration.yaml` (handled by role but needs verification)

**Checkpoint**: HACS and Frigate component installed - user story implementation can now begin.

---

## Phase 3: User Story 1 - View Frigate Cameras in Home Assistant (Priority: P1) 🎯 MVP

**Goal**: View live Frigate camera feeds in the HA dashboard.

**Independent Test**: Add a camera entity to an HA dashboard card and verify the live stream from the NVR host.

### Implementation for User Story 1

- [x] T008 [US1] Add `frigate.yaml` package to `manifests/home-automation/prereqs/config-extra.yaml` with `frigate: host: http://10.1.10.11:5000`
- [x] T009 [US1] Commit and push updated `config-extra.yaml` to Gitea for ArgoCD sync
- [ ] T010 [US1] Finalize integration setup in HA UI (**Settings** → **Devices & Services** → **Add Integration** → **Frigate**)
- [ ] T011 [US1] Verify camera entities (e.g., `camera.front_door`) are created and showing live streams

**Checkpoint**: At this point, camera feeds should be viewable in Home Assistant.

---

## Phase 4: User Story 2 - Receive Person/Object Detection Events (Priority: P2)

**Goal**: Trigger HA binary sensors based on Frigate detection events via MQTT.

**Independent Test**: Trigger a detection in Frigate and verify the corresponding binary sensor in HA switches to "Detected".

### Implementation for User Story 2

- [ ] T012 [US2] Verify MQTT connectivity within the Frigate integration settings in HA
- [ ] T013 [US2] Verify binary sensors (e.g., `binary_sensor.front_door_person_motion`) are created in HA
- [ ] T014 [US2] Test event flow by simulating or triggering a detection and monitoring HA entity state

**Checkpoint**: Detection events should be flowing from Frigate to Home Assistant sensors.

---

## Phase 5: User Story 3 - Access Frigate Media (Clips/Snapshots) (Priority: P3)

**Goal**: Review past event clips and snapshots within Home Assistant.

**Independent Test**: Navigate to the Frigate Media Browser in HA and play a recorded clip.

### Implementation for User Story 3

- [ ] T015 [US3] Verify "Frigate" entry appears in the Home Assistant **Media** browser
- [ ] T016 [US3] Verify snapshots and clips are accessible and playable within the HA UI

**Checkpoint**: All user stories should now be functional.

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T017 [P] Update `specs/062-frigate-ha-integration/quickstart.md` with any discovered installation nuances
- [ ] T018 Run final validation of all success criteria defined in `spec.md`
- [ ] T019 [P] Document any manual UI steps required in the project's permanent documentation if necessary
- [ ] T020 Verify SC-004: Perform a rolling restart of the K3s cluster nodes and verify that the Home Assistant Frigate entities automatically return to a "Connected" state without manual intervention.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Can start immediately.
- **Foundational (Phase 2)**: Depends on Setup completion.
- **User Stories (Phase 3+)**: Depend on Foundational (Phase 2) completion.
- **Polish (Final Phase)**: Depends on all user stories being complete.

### Implementation Strategy

1. **Foundational**: Get HACS and the component in place (T004-T007).
2. **MVP**: Configure the integration via YAML (T008-T011). This provides the most value immediately.
3. **Refine**: Verify MQTT and Media features (T012-T016).
