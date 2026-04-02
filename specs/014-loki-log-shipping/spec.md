# Feature Specification: Add Grafana Loki Log Aggregation

**Feature Branch**: `014-loki-log-shipping`
**Created**: 2026-04-02
**Status**: Draft
**Input**: User description: "Add Grafana Loki to the infra helm deployment and integrate appropriate log shipping for the cluster"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View cluster logs in Grafana (Priority: P1)

An operator opens the Grafana dashboard and can search, filter, and tail live logs from any pod or node in the cluster without needing SSH access. Logs are aggregated from all 6 nodes and available in a single query interface.

**Why this priority**: The core value of this feature — replacing ad-hoc `kubectl logs` with a persistent, searchable log store. Everything else builds on this.

**Independent Test**: Open Grafana → Explore → select Loki datasource → query `{namespace="argocd"}` → logs from ArgoCD pods appear in real time.

**Acceptance Scenarios**:

1. **Given** the cluster is running, **When** an operator queries logs by namespace in Grafana, **Then** logs from all pods in that namespace are returned within 30 seconds.
2. **Given** a pod has restarted, **When** an operator queries logs for that pod, **Then** logs from before the restart are still accessible (not lost on pod eviction).
3. **Given** logs are flowing, **When** an operator filters by log level (e.g., `level=error`), **Then** only matching entries are returned.

---

### User Story 2 - Logs persist across pod restarts and node reboots (Priority: P2)

Log data survives pod evictions, node reboots, and cluster maintenance windows. An operator can query logs from the past 7 days without gaps caused by infrastructure events.

**Why this priority**: Without persistence, log aggregation provides no advantage over `kubectl logs`. Historical logs are critical for post-incident investigation.

**Independent Test**: Restart a pod, then query its logs in Grafana — pre-restart logs are present alongside post-restart logs with no gap.

**Acceptance Scenarios**:

1. **Given** a pod is evicted from a node, **When** an operator queries logs for that pod after eviction, **Then** logs up to the moment of eviction are still available.
2. **Given** a node reboots, **When** the node comes back online, **Then** the log shipper resumes automatically and no logs are duplicated.

---

### User Story 3 - Node-level system logs are captured (Priority: P3)

Logs from the underlying OS and K3s system services are shipped alongside pod logs, giving operators visibility into infrastructure-level events.

**Why this priority**: Pod logs alone miss node-level failures (OOM kills, kernel events, K3s crashes). This closes the observability gap.

**Independent Test**: Query logs in Grafana for a specific node — system-level service logs appear alongside pod logs from the same node.

**Acceptance Scenarios**:

1. **Given** log shipping is running, **When** an operator queries logs for a specific node, **Then** both pod logs and system service logs from that node are returned.

---

### Edge Cases

- What happens if a log shipper pod on a node crashes — are logs buffered and replayed, or lost?
- What if log storage fills up — does it drop new logs or evict old ones?
- What happens if a node is offline during log shipping — does the shipper catch up when it reconnects?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The cluster MUST aggregate logs from all pods across all namespaces into a central log store.
- **FR-002**: The cluster MUST ship node-level system logs alongside pod logs.
- **FR-003**: Log data MUST be persisted on durable cluster storage and survive pod restarts and node reboots.
- **FR-004**: Logs MUST be queryable from the existing Grafana instance without deploying a separate UI.
- **FR-005**: The log shipper MUST run on every node so each node ships its own logs.
- **FR-006**: The log store MUST be deployed as part of the existing Ansible infrastructure deployment, following the same pattern as the monitoring stack.
- **FR-007**: Re-running the deployment playbook MUST NOT cause data loss or duplicate log entries (idempotent).
- **FR-008**: Log retention MUST default to 7 days and be configurable.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Logs from all 6 cluster nodes appear in Grafana within 60 seconds of being generated.
- **SC-002**: Logs from the past 7 days are queryable without gaps after a full cluster deployment.
- **SC-003**: Re-running the services deployment leaves the log store intact with no data loss.
- **SC-004**: An operator can find a specific log entry across all namespaces in under 30 seconds using label filters.

## Assumptions

- The existing Grafana instance deployed with the monitoring stack will be used — no separate Grafana deployment is needed.
- Longhorn is available and healthy for persistent log storage.
- Log shipping is infrastructure (Ansible-managed), not an application workload — it must be running before ArgoCD can sync anything useful.
- Node-level log access requires the shipper to run with elevated host privileges.
- 7-day retention is sufficient for the homelab use case.
- The log store is for internal cluster observability only — no external log export is required.
