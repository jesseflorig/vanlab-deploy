# Feature Specification: NVR Host Provisioning with Frigate and Hailo-8 Acceleration

**Feature Branch**: `041-nvr-frigate-hailo`  
**Created**: 2026-04-25  
**Status**: Draft  
**Input**: User description: "Create provisioning IAC for a new NVR host at 10.1.10.11. It should run frigate securely and take advantage of the onbaord Hailo-8."

## Clarifications

### Session 2026-04-25

- Q: Should the NVR host join the K3s cluster (Frigate as K8s workload) or run Frigate standalone? → A: Standalone Frigate on the dedicated host. Longhorn used for clips only via NFS mount. Cluster Traefik routes to the host via IngressRoute pointing to 10.1.10.11.
- Q: What is the scope of Home Assistant integration provisioning? → A: Ansible fully configures Frigate's MQTT output; outputs a documented config block for the operator to apply to HA manually or via a separate HA playbook. Automated HA-side changes are out of scope.
- Q: How large should the Longhorn PVC for Frigate event clips be? → A: 50Gi
- Q: What hostname should the Traefik IngressRoute expose Frigate on? → A: frigate.fleet1.cloud

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Provision a Secure, Functional NVR Host (Priority: P1)

An operator runs the provisioning playbook against a fresh host at 10.1.10.11. After completion, the host is hardened, Frigate is running as a system service, the Hailo-8 is active as the object detection accelerator, and detection events are available.

**Why this priority**: Core deliverable — nothing else works without a provisioned, functional host.

**Independent Test**: Run the playbook against the target host, then verify Frigate's web UI is reachable, a camera stream appears, and detection events are logged with Hailo-8 as the active detector.

**Acceptance Scenarios**:

1. **Given** a fresh host at 10.1.10.11 with a supported OS, **When** the provisioning playbook runs to completion, **Then** Frigate is running, accessible via its web UI, and object detection is active using the Hailo-8 accelerator — not software-only inference.
2. **Given** the provisioned host, **When** an operator connects a camera stream, **Then** Frigate detects and records motion/object events without errors in the service logs.
3. **Given** the playbook has run, **When** the operator checks the Hailo-8 status, **Then** it is recognized as the active detector and inference load is visible on the accelerator (not the CPU).

---

### User Story 2 - Authenticated and Encrypted Access via Traefik (Priority: P2)

An operator or Home Assistant instance accesses Frigate's API and web interface through the cluster Traefik ingress. All traffic is TLS-encrypted and unauthenticated requests are rejected.

**Why this priority**: Security is a stated requirement; an open NVR on the LAN is unacceptable. Traefik provides the consistent routing model used by all other lab services.

**Independent Test**: Access Frigate via the Traefik-routed hostname — verify TLS is enforced and unauthenticated requests are rejected.

**Acceptance Scenarios**:

1. **Given** a provisioned host with Traefik IngressRoute configured, **When** a client connects to the Frigate hostname, **Then** the connection is TLS-encrypted via the cluster ingress and plaintext HTTP is rejected or redirected.
2. **Given** no credentials are provided, **When** a client requests the Frigate API, **Then** the request is rejected with an authentication error.
3. **Given** valid credentials are provided, **When** a client requests the Frigate API, **Then** the response is successful.

---

### User Story 3 - Event Clips Stored on Longhorn (Priority: P3)

Detection event clips are written to a Longhorn-backed NFS mount on the NVR host. Continuous recordings use local NVMe. Clips survive a local disk failure and are accessible from other cluster nodes.

**Why this priority**: Differentiates high-value event clips (replicated, durable) from bulk continuous recordings (local, high-throughput).

**Independent Test**: Trigger a detection event; verify the resulting clip appears on the Longhorn-backed mount rather than the local recording path.

**Acceptance Scenarios**:

1. **Given** a provisioned host with Longhorn NFS mount configured, **When** Frigate writes an event clip, **Then** the clip is written to the Longhorn-backed path, not the local NVMe path.
2. **Given** the Longhorn mount, **When** the mount approaches its configured size limit, **Then** the retention policy prunes old clips before the volume fills.

---

### User Story 4 - Home Assistant Integration (Priority: P4)

Home Assistant receives Frigate detection events via MQTT and can display camera feeds and trigger automations based on object detection results.

**Why this priority**: Closes the loop between the NVR and the home automation system; a Frigate installation without HA integration has limited operational value in this lab.

**Independent Test**: Trigger a detection event in Frigate; verify a corresponding event appears in Home Assistant's event log and the Frigate HA integration shows the camera entity.

**Acceptance Scenarios**:

1. **Given** the provisioned host with MQTT configured, **When** Frigate detects an object, **Then** an MQTT event is published to the broker and Home Assistant receives it.
2. **Given** the HA Frigate integration is configured, **When** an operator views HA, **Then** Frigate camera entities are visible and show live or last-snapshot state.

---

### User Story 5 - Idempotent Re-Provisioning (Priority: P5)

An operator re-runs the provisioning playbook on an already-configured host. No unintended changes are made; the playbook is safe to run repeatedly.

**Why this priority**: Operational hygiene — idempotency is required for safe config management.

**Independent Test**: Run the playbook twice in succession; the second run reports no meaningful changes and Frigate continues running without interruption.

**Acceptance Scenarios**:

1. **Given** a fully provisioned host, **When** the playbook is run again, **Then** it completes without errors and Frigate is uninterrupted.
2. **Given** a fully provisioned host where one config value was manually changed, **When** the playbook runs, **Then** it restores the desired state and reports only that change.

---

### Edge Cases

- What happens if the Hailo-8 driver fails to load or the device is not detected? Frigate must fail fast with a clear error rather than silently falling back to CPU inference.
- What happens if the Longhorn NFS mount is unavailable at Frigate startup? Frigate must not write clips to the local path as a silent fallback.
- What happens if the playbook is run against a host that already has an incompatible version of Frigate installed?
- How does the system handle the local NVMe filling up from continuous recordings? Frigate manages retention automatically for local recordings.
- What happens if the MQTT broker is unreachable at provisioning time or at runtime?
- What happens if a camera stream is unreachable at provisioning time?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The provisioning automation MUST configure the host at 10.1.10.11 as a dedicated NVR running Frigate as a standalone system service (not a Kubernetes workload).
- **FR-002**: Frigate MUST be configured to use the onboard Hailo-8 as its primary object detection accelerator.
- **FR-003**: The host MUST be security-hardened as part of provisioning (unnecessary services disabled, firewall rules applied, SSH hardened).
- **FR-004**: Frigate's web interface and API MUST require authentication; unauthenticated access MUST be rejected.
- **FR-005**: All external access to Frigate MUST be routed through the cluster Traefik ingress at `frigate.fleet1.cloud` via an IngressRoute pointing to 10.1.10.11; TLS MUST be enforced.
- **FR-006**: The Hailo-8 drivers and runtime MUST be installed and verified as part of provisioning.
- **FR-007**: Frigate MUST be managed as a system service that restarts automatically on failure and survives host reboots.
- **FR-008**: The provisioning automation MUST be idempotent — safe to run multiple times without unintended side effects.
- **FR-009**: Continuous recordings MUST use the local NVMe disk with an automated retention policy to prevent uncontrolled disk growth.
- **FR-010**: Detection event clips MUST be written to a Longhorn-backed NFS mount provisioned on the NVR host; clips MUST NOT be written to the local NVMe path.
- **FR-011**: The Longhorn NFS volume for clips MUST have a retention policy; old clips MUST be pruned before the volume fills.
- **FR-012**: Frigate MUST publish detection events to the existing MQTT broker so Home Assistant can consume them.
- **FR-013**: The provisioning automation MUST output a documented HA Frigate integration config block (as a task summary or variable file) that an operator can apply to Home Assistant manually or via a separate HA-targeted playbook.
- **FR-014**: The provisioning automation MUST follow existing project conventions (Ansible, consistent inventory and variable structure).

### Key Entities

- **NVR Host**: The machine at 10.1.10.11 running Frigate as a standalone service; has an onboard Hailo-8 accelerator.
- **Frigate Instance**: The NVR service — manages camera streams, runs object detection, stores continuous recordings locally and clips on Longhorn.
- **Hailo-8 Accelerator**: The hardware AI inference chip; must be the active detector, not a fallback.
- **Camera**: An RTSP or similar stream source fed into Frigate; zero or more configured at provision time.
- **Longhorn NFS Volume**: Replicated cluster storage, NFS-mounted on the NVR host, used exclusively for event clips; provisioned at 50Gi.
- **MQTT Broker**: Existing broker in the lab; Frigate publishes detection events to it for Home Assistant consumption.
- **Traefik IngressRoute**: Cluster ingress resource that routes `frigate.fleet1.cloud` to Frigate on 10.1.10.11 with TLS termination.
- **Credentials**: Authentication material for accessing the Frigate interface; provisioned securely.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Provisioning completes on a fresh host in a single playbook run with no manual steps required.
- **SC-002**: Object detection inference runs on the Hailo-8 — CPU utilization during active detection is consistent with hardware-accelerated workloads (not software-only).
- **SC-003**: All Frigate API and UI endpoints refuse unauthenticated requests 100% of the time.
- **SC-004**: Re-running the playbook on an already-provisioned host produces no unintended service interruptions.
- **SC-005**: Frigate automatically recovers from a crash or reboot without operator intervention.
- **SC-006**: Continuous recording disk usage on local NVMe stays within configured bounds; old footage is pruned automatically.
- **SC-007**: Detection event clips are written to the Longhorn-backed NFS mount and are accessible from the cluster after a local disk failure.
- **SC-008**: Home Assistant receives Frigate detection events within 5 seconds of the event occurring.
- **SC-009**: Frigate camera entities are visible and functional in Home Assistant after provisioning.

## Assumptions

- The host at 10.1.10.11 is already network-reachable from the Ansible control node and has a supported Linux OS installed.
- SSH access with sufficient privilege (sudo) is available to the Ansible control node for this host.
- The Hailo-8 is physically installed in the host and recognized by the OS (PCIe or USB, as applicable).
- Camera stream URLs (RTSP or similar) will be provided as variables at provisioning time, or an empty camera list is acceptable for initial provisioning.
- TLS certificates will use a self-signed or internal CA cert consistent with existing lab practices.
- Home Assistant is already running in the lab environment with an accessible MQTT broker.
- Longhorn is already deployed in the lab Kubernetes cluster; a PVC and NFS export for Frigate clips will be created as part of this feature.
- Traefik is already the ingress controller for the lab cluster; an IngressRoute for Frigate will be created as part of this feature.
- Frigate runs standalone on the host (not as a Kubernetes workload); the NVR host does NOT join the K3s cluster.
- Continuous recordings use local NVMe for throughput; only event clips use Longhorn NFS.
