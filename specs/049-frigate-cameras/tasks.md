# Tasks: Add 4 Cameras to Frigate

**Input**: Design documents from `/specs/049-frigate-cameras/`  
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓

**Organization**: Tasks grouped by user story — each story independently deployable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup (Pre-flight)

**Purpose**: Verify the environment is in a known-good state before making changes.

- [ ] T001 Verify Frigate is running and healthy on NVR host: `ssh fleetadmin@10.1.10.11 "sudo docker ps | grep frigate && sudo docker logs frigate --tail 20"`
- [ ] T002 Verify cameras are powered and reachable from management: `for i in 11 12 13 14; do ping -c1 10.1.40.$i; done` (expect: all 4 respond — or confirm they're isolated to camera VLAN and only reachable after firewall rule is applied)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Firewall access and variable schema documentation — must complete before any camera configuration can be tested.

**⚠️ CRITICAL**: Frigate cannot reach cameras on 10.1.40.x until the firewall rule is applied.

- [x] T003 [P] Add RTSP firewall rule to `playbooks/network/network-deploy.yml` `nvr_rules` list — insert seq 203 entry: `action: pass`, `interface: opt1`, `source_net: 10.1.10.11`, `destination_net: 10.1.40.0/24`, `destination_port: 554`, `description: "NVR Frigate → cameras RTSP"` (see data-model.md for full rule YAML)
- [x] T004 [P] Update `group_vars/example.all.yml` — replace the existing `nvr_cameras` example (single `rtsp_url`/`width`/`height` schema) with the dual-stream schema (`rtsp_main_url`, `rtsp_sub_url`) and add `nvr_camera_rtsp_user` / `nvr_camera_rtsp_pass` variable documentation with Dahua URL examples
- [ ] T005 Run `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml` to apply the new RTSP firewall rule
- [ ] T006 Verify NVR can reach cameras post-firewall: `ssh fleetadmin@10.1.10.11 "for i in 11 12 13 14; do nc -zv 10.1.40.\$i 554 && echo OK || echo FAIL; done"` — all 4 must show OK before proceeding

**Checkpoint**: NVR host can reach all 4 camera IPs on port 554. Variable schema is documented.

---

## Phase 3: User Story 1 — Live View for All Cameras (Priority: P1) 🎯 MVP

**Goal**: All 4 camera live feeds appear in the Frigate dashboard within 30 seconds of Frigate starting.

**Independent Test**: Open Frigate UI (`https://frigate.fleet1.cloud`) — all 4 cameras (cam-01 through cam-04) show live video. No Frigate restart required to recover a camera that reconnects.

### Implementation for User Story 1

- [x] T007 [P] [US1] Update `roles/nvr/templates/frigate-config.yml.j2` — rewrite the camera loop to render two ffmpeg inputs per camera: first input uses `cam.rtsp_main_url` with role `record`, second uses `cam.rtsp_sub_url` with role `detect`; change `detect.width` to hardcoded `640`, `detect.height` to `480`; remove `cam.width` and `cam.height` template variables
- [ ] T008 [P] [US1] Add camera RTSP credentials to `group_vars/all.yml` — add `nvr_camera_rtsp_user: "<username>"` and vault-encrypt `nvr_camera_rtsp_pass` using `ansible-vault encrypt_string`
- [ ] T009 [US1] Populate `nvr_cameras` in `group_vars/all.yml` with all 4 camera entries using confirmed Dahua RTSP paths (see contracts/nvr-cameras-schema.md for exact YAML) — depends on T007, T008
- [ ] T010 [US1] Run `ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml --tags frigate-config,frigate-service` to render and deploy the updated Frigate config — depends on T009
- [ ] T011 [US1] Validate US1: open Frigate UI and confirm all 4 cameras (cam-01 through cam-04) show live feeds; check Frigate logs for any RTSP connection errors: `ssh fleetadmin@10.1.10.11 "sudo docker logs frigate --tail 50 2>&1 | grep -E 'cam-0[1-4]|ERROR|WARN'"` — depends on T010

**Checkpoint**: All 4 camera live feeds visible in Frigate UI. US1 independently testable and complete.

---

## Phase 4: User Story 2 — Object Detection on All Cameras (Priority: P2)

**Goal**: Hailo accelerator detects people, vehicles, and animals on all 4 cameras via the sub stream. Detection events appear in Frigate's event log.

**Independent Test**: Walk in front of each camera — a person detection event with snapshot appears in the Frigate Events view for that camera within 10 seconds.

### Implementation for User Story 2

- [ ] T012 [US2] Verify Frigate stats confirm `hailo8l` is the active detector (not CPU fallback): open Frigate UI → System → confirm detector shows Hailo inference time, not `cpu` — depends on T011
- [x] T013 [P] [US2] Verify `roles/nvr/templates/frigate-config.yml.j2` objects.track list includes `person`, `car`, `truck`, `bicycle`, `dog`, `cat` — update if any are missing; re-run T010 if changes are made
- [ ] T014 [US2] Validate US2: trigger detection on each camera — walk in front of cam-01 through cam-04 and confirm detection events appear in Frigate Events with correct camera label and snapshot — depends on T012, T013

**Checkpoint**: Detection events generated for all 4 cameras using Hailo accelerator.

---

## Phase 5: User Story 3 — Continuous Recording on All Cameras (Priority: P3)

**Goal**: Continuous recordings accumulate on local NVMe; detection clip retention runs at 30 days; storage-based management prevents disk exhaustion.

**Independent Test**: After 5 minutes of uptime, recording segments appear under each camera's directory in Frigate's storage view. NFS clips mount is healthy.

### Implementation for User Story 3

- [ ] T015 [US3] Verify continuous recording segments appear after 5 minutes: `ssh fleetadmin@10.1.10.11 "find /var/lib/frigate/media -name '*.mp4' | head -20"` — expect files for all 4 cameras — depends on T011
- [ ] T016 [US3] Verify NFS clips mount is healthy and writable: `ssh fleetadmin@10.1.10.11 "df -h /mnt/frigate-clips && touch /mnt/frigate-clips/.test && rm /mnt/frigate-clips/.test"` — depends on T011
- [ ] T017 [US3] Verify rendered Frigate config has correct retention values — `ssh fleetadmin@10.1.10.11 "sudo cat /var/lib/frigate/config/config.yml | grep -A5 retain"` — confirm `events.retain.default: 30` and `retain.days: 7` (or current `nvr_recording_retain_days`) — depends on T010
- [ ] T018 [US3] Validate US3: trigger a detection event, wait for it to complete, confirm a clip appears in the Frigate Events view and is downloadable via the UI — depends on T015, T016

**Checkpoint**: All 3 user stories independently functional. Recording, detection, and live view all operational.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T019 [P] Update `specs/049-frigate-cameras/quickstart.md` — replace placeholder `<username>` / `<password>` text with actual camera credential variable references; confirm Step 1 ffprobe command reflects confirmed Dahua paths
- [ ] T020 [P] Verify `group_vars/example.all.yml` dual-stream schema example is clean and complete with Dahua URL format
- [ ] T021 Run full playbook idempotency check: re-run `ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml --tags frigate-config,frigate-service` a second time — confirm no errors, no unexpected changes, Frigate not restarted unnecessarily
- [ ] T022 Run network playbook idempotency check: re-run `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml` — confirm seq 203 rule is not duplicated
- [ ] T023 Commit all changes: `playbooks/network/network-deploy.yml`, `roles/nvr/templates/frigate-config.yml.j2`, `group_vars/example.all.yml` — push feature branch to Gitea and open PR

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — BLOCKS all camera config work
- **Phase 3 (US1)**: Depends on Phase 2 complete — T003/T004 can overlap with T007/T008
- **Phase 4 (US2)**: Depends on Phase 3 (US1) checkpoint — detection validates on top of live feeds
- **Phase 5 (US3)**: Depends on Phase 3 (US1) checkpoint — recording validates on top of live feeds
- **Phase 6 (Polish)**: Depends on all user stories validated

### User Story Dependencies

- **US1 (P1)**: Requires Phase 2 complete (firewall + schema docs)
- **US2 (P2)**: Requires US1 checkpoint (Frigate running with cameras)
- **US3 (P3)**: Requires US1 checkpoint (Frigate running with cameras); can run in parallel with US2

### Parallel Opportunities Within Phases

- T003 + T004 (Phase 2): Different files — run together
- T007 + T008 (Phase 3): Different files — run together before T009
- T012 + T013 (Phase 4): Independent checks — run together
- T015 + T016 + T017 (Phase 5): Independent checks — run together
- T019 + T020 (Phase 6): Different files — run together

---

## Parallel Example: Phase 2 + Phase 3 Setup

```bash
# Phase 2 — can run in parallel:
Task T003: "Add RTSP firewall rule to playbooks/network/network-deploy.yml"
Task T004: "Update group_vars/example.all.yml with dual-stream schema"

# Phase 3 — can start T007/T008 while T005/T006 run:
Task T007: "Update roles/nvr/templates/frigate-config.yml.j2 dual-stream loop"
Task T008: "Add RTSP credentials to group_vars/all.yml"
# Then sequentially:
Task T009 → T010 → T011
```

---

## Implementation Strategy

### MVP (User Story 1 Only)

1. Complete Phase 1: Setup pre-flight checks
2. Complete Phase 2: Firewall rule + schema docs (T003–T006)
3. Complete Phase 3: Template + vars + deploy + validate live feeds (T007–T011)
4. **STOP and VALIDATE**: All 4 cameras showing live video in Frigate UI
5. Detection (US2) and recording (US3) can be validated immediately after — no additional config changes needed

### Incremental Delivery

- **After T011**: Live view complete — US1 done
- **After T014**: Detection events confirmed — US2 done  
- **After T018**: Recording and retention confirmed — US3 done
- **After T023**: Branch merged, feature complete

### Notes

- `group_vars/all.yml` changes are **not committed** (gitignored) — only `example.all.yml` is committed
- The only files committed to Git are: `playbooks/network/network-deploy.yml`, `roles/nvr/templates/frigate-config.yml.j2`, `group_vars/example.all.yml`
- Vault-encrypt `nvr_camera_rtsp_pass` before writing to `group_vars/all.yml`
- If Frigate fails to connect to a camera after T010, check: firewall rule applied (T005/T006), RTSP credentials correct, camera web UI accessible on port 80
