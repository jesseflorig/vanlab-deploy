# Feature Specification: Frigate Home Assistant Integration

**Feature Branch**: `062-frigate-ha-integration`  
**Created**: 2026-05-03  
**Status**: Draft  
**Input**: User description: "Add direct Frigate (http://10.1.10.11:5000) integration into Home Assistant"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View Frigate Cameras in Home Assistant (Priority: P1)

As a home security operator, I want to see my Frigate camera feeds directly within the Home Assistant dashboard so I can monitor my home from a single interface.

**Why this priority**: This is the core value of the integration. Being able to see the cameras is the most frequent use case.

**Independent Test**: Can be fully tested by adding a "Picture Entity" or "Frigate Card" to the HA dashboard and verifying the live stream from the NVR host (10.1.10.11).

**Acceptance Scenarios**:

1. **Given** Home Assistant and Frigate are running, **When** the Frigate integration is configured with the NVR URL, **Then** Frigate camera entities (e.g., `camera.front_door`) appear in Home Assistant.
2. **Given** a Frigate camera entity exists, **When** viewed in the HA dashboard, **Then** the live stream is visible and updates in real-time.

---

### User Story 2 - Receive Person/Object Detection Events (Priority: P2)

As a home automation enthusiast, I want detection events (like "Person detected") from Frigate to trigger automations in Home Assistant so I can get notified or turn on lights.

**Why this priority**: Detection events are the "intelligent" part of the NVR. They enable advanced automations which is a key reason for using Frigate with HA.

**Independent Test**: Can be tested by walking in front of a camera and verifying that the corresponding binary sensor in HA (e.g., `binary_sensor.front_door_person_motion`) switches to "Detected".

**Acceptance Scenarios**:

1. **Given** an object is detected by Frigate, **When** the MQTT message is sent to the broker, **Then** the associated binary sensor in Home Assistant updates its state immediately.

---

### User Story 3 - Access Frigate Media (Clips/Snapshots) (Priority: P3)

As a user, I want to review past event clips and snapshots from Frigate within Home Assistant so I can see what happened while I was away.

**Why this priority**: While useful, real-time monitoring and detection events are higher priority for immediate action. Media review is a secondary analysis task.

**Independent Test**: Can be tested by navigating to the Frigate Media Browser in HA and verifying that past event clips can be played.

**Acceptance Scenarios**:

1. **Given** a recorded event exists in Frigate, **When** accessing the HA Media Browser under "Frigate", **Then** the clip is listed and playable within the HA UI.

### Edge Cases

- **NVR Host Offline**: How does Home Assistant handle the cameras if the NVR host (10.1.10.11) is unreachable? (Entities should show "Unavailable").
- **MQTT Broker Connection Loss**: If the shared MQTT broker is down, do detection events still work via the API? (No, standard integration relies on MQTT for real-time events).
- **Restart Persistence**: Ensure the integration survives a Home Assistant pod restart (K3s StatefulSet).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow installation of the Frigate Custom Component (via HACS or manual deployment).
- **FR-002**: System MUST support configuration of the Frigate integration using the direct IP address: `http://10.1.10.11:5000`.
- **FR-003**: System MUST expose Frigate cameras as standard Home Assistant camera entities.
- **FR-004**: System MUST expose Frigate detection events as Home Assistant binary sensors and event entities.
- **FR-005**: System MUST utilize the existing MQTT broker for real-time event communication.

### Key Entities *(include if feature involves data)*

- **Frigate Integration**: The custom component bridge between HA and the NVR.
- **Camera Entity**: Representation of a physical camera stream within HA.
- **Detection Sensor**: A binary sensor reflecting the state of object detection (person, car, etc.) for a specific camera.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Integration installation and initial setup can be completed in under 10 minutes by an operator.
- **SC-002**: Camera stream latency in Home Assistant dashboard is within 2 seconds of the actual event (verified by comparing the HA stream timestamp/clock against the Frigate NVR native UI).
- **SC-003**: 100% of Frigate-detected events for "tracked" objects are reflected in HA binary sensors.
- **SC-004**: Integration survives a full K3s cluster restart without requiring manual re-configuration.

## Assumptions

- **HACS Availability**: It is assumed the user will either install HACS or allow manual file placement in the HA `custom_components` directory.
- **Network Connectivity**: The Home Assistant pod in the `home-automation` namespace has direct network access to the NVR host at `10.1.10.11` on port `5000`.
- **MQTT Setup**: The existing MQTT broker and client certificates in HA are correctly configured and shared with Frigate.
- **V1 Scope**: Advanced features like the "Frigate Card" (Lovelace custom card) are considered optional/secondary to the core integration.
