# Feature Specification: Add 4 Cameras to Frigate

**Feature Branch**: `049-frigate-cameras`  
**Created**: 2026-04-26  
**Status**: Draft  
**Input**: User description: "Add 4 cameras to Frigate (10.1.40.11-14). Each has a main stream (2688x1520@20fps) and detection substream (640x480@5fps)."

## Clarifications

### Session 2026-04-26

- Q: How long should Frigate retain detection event clips before automatically deleting them? → A: 30 days
- Q: Should detection event clips be archived to cloud storage before local deletion, or is local-only retention sufficient? → A: Local only — no cloud archival
- Q: Detection model and facial recognition scope — detection only or include facial recognition? → A: Detection only using `yolov8s` for people, vehicles, and animals; facial recognition is out of scope
- Q: How should continuous recordings on local NVMe be retained? → A: Storage-based — Frigate manages continuous recordings automatically by available disk space
- Q: Camera RTSP stream paths → A: EmpireTech IPC-T54IR-AS (Dahua OEM) — main stream `/cam/realmonitor?channel=1&subtype=0`, sub stream `/cam/realmonitor?channel=1&subtype=1`, port 554

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Live View for All Cameras (Priority: P1)

A homelab operator opens the Frigate dashboard and sees live video feeds from all 4 cameras. Each camera displays a real-time stream at full resolution.

**Why this priority**: Live view is the fundamental proof that cameras are connected and streaming correctly. Everything else (detection, recording) depends on working streams.

**Independent Test**: Can be fully tested by opening the Frigate UI and confirming all 4 camera feeds display live video without errors.

**Acceptance Scenarios**:

1. **Given** Frigate is running with the new configuration, **When** a user opens the Frigate dashboard, **Then** all 4 cameras (cam-01 through cam-04) appear and display live video
2. **Given** any single camera is unreachable, **When** Frigate loads, **Then** the remaining 3 cameras still display live feeds and the unreachable camera shows an error state

---

### User Story 2 - Object Detection on All Cameras (Priority: P2)

The system uses the Hailo accelerator to run object detection against the substream of each camera, detecting people, vehicles, and other configured objects.

**Why this priority**: Detection is the primary value of Frigate — without it the system is just a passive recorder.

**Independent Test**: Can be fully tested by walking in front of a camera and confirming a person detection event appears in the Frigate event log.

**Acceptance Scenarios**:

1. **Given** all 4 cameras are configured with detection substreams, **When** a person enters a camera's field of view, **Then** Frigate generates a detection event with a snapshot
2. **Given** the detection substream is 640x480@5fps, **When** Frigate processes frames, **Then** detection uses the substream (not the main stream) to minimize load on the accelerator

---

### User Story 3 - Continuous Recording on All Cameras (Priority: P3)

Frigate continuously records all 4 cameras to local storage. Detection event clips are saved separately to the shared storage volume and automatically purged after 30 days.

**Why this priority**: Recording is important for reviewing past events but is not required for the system to be useful in real-time.

**Independent Test**: Can be fully tested by waiting 5 minutes and confirming recording segments appear in Frigate's storage view for each camera.

**Acceptance Scenarios**:

1. **Given** all 4 cameras are streaming, **When** 5 minutes have passed, **Then** continuous recording segments are present on local NVMe storage for each camera
2. **Given** a detection event occurs, **When** the event completes, **Then** a clip is saved to the shared clips volume
3. **Given** a clip is older than 30 days, **When** Frigate's retention policy runs, **Then** the clip is automatically deleted

---

### Edge Cases

- What happens when a camera is temporarily offline and comes back? Frigate should reconnect automatically without a full restart.
- How does the system behave if all 4 cameras stream simultaneously at 2688x1520@20fps — is there sufficient bandwidth on the camera VLAN?
- What happens if the Hailo accelerator is saturated by 4 simultaneous detection streams?
- What happens when the clips volume approaches capacity before 30-day retention purge runs?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Frigate configuration MUST include all 4 cameras with IPs 10.1.40.11, 10.1.40.12, 10.1.40.13, and 10.1.40.14
- **FR-002**: Each camera MUST have a main stream configured at 2688x1520 resolution and 20fps
- **FR-003**: Each camera MUST have a detection substream configured at 640x480 resolution and 5fps
- **FR-004**: Frigate MUST use the detection substream (not the main stream) for object detection inference
- **FR-005**: Frigate MUST use the Hailo accelerator for object detection across all 4 cameras using the `yolov8s` compiled model
- **FR-005a**: Detection classes MUST include at minimum: person, car, truck, bicycle, dog, cat — facial recognition is explicitly out of scope
- **FR-006**: Camera credentials MUST be supplied via environment variables or secrets — not hardcoded in the configuration file
- **FR-007**: Each camera MUST have a unique, human-readable name in Frigate (e.g., `cam-01` through `cam-04`)
- **FR-008**: Frigate configuration changes MUST be applied via the existing Ansible playbook — no manual edits on the host
- **FR-009**: Detection event clips MUST be automatically purged after 30 days
- **FR-010**: Continuous recordings MUST be managed by available disk space — Frigate automatically removes the oldest segments when storage is low; no fixed time-based retention applies

### Key Entities

- **Camera**: An IP camera identified by address (10.1.40.11–14), with a main RTSP stream and a detection substream, each with defined resolution and framerate
- **Frigate Config**: The YAML configuration that maps camera definitions to detection, recording, and streaming behavior
- **Detection Substream**: The lower-resolution stream used exclusively for inference to reduce load on the accelerator
- **Clip**: A short video segment captured during a detection event, retained for 30 days then automatically deleted

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 4 camera live feeds are visible in the Frigate dashboard within 30 seconds of Frigate starting
- **SC-002**: Object detection events are generated for all 4 cameras — no camera consistently missing detections
- **SC-003**: Frigate reports detection is running on the Hailo accelerator (not CPU fallback) for all cameras
- **SC-004**: Continuous recording segments appear for all 4 cameras within 5 minutes of startup
- **SC-005**: A single camera going offline does not cause Frigate to lose feeds from the remaining 3 cameras
- **SC-006**: Detection event clips older than 30 days are automatically removed without manual intervention

## Assumptions

- Cameras at 10.1.40.11–14 are already physically installed, powered, and reachable on the camera VLAN
- Cameras are EmpireTech IPC-T54IR-AS-2.8mm-S3 (Dahua OEM); RTSP paths are confirmed: main stream `/cam/realmonitor?channel=1&subtype=0`, sub stream `/cam/realmonitor?channel=1&subtype=1`, port 554
- Camera RTSP credentials (username/password) are known and available to inject as secrets
- Frigate is already deployed and operational (from feature 041-nvr-frigate-hailo)
- The Hailo accelerator is already installed and confirmed working in Frigate
- Existing Ansible roles and playbooks for the NVR host will be extended, not replaced
- Detection uses the `yolov8s` Hailo `.hef` model compiled for Hailo-8; facial recognition is out of scope for this feature
- No cloud archival is required; clips are retained locally for 30 days and can be exported manually via the Frigate UI or direct filesystem access
- Camera VLAN (10.1.40.0/24) has sufficient bandwidth for 4 simultaneous main streams (~4×20Mbps typical at this resolution)
