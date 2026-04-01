# Feature Specification: Prometheus Longhorn Monitoring

**Feature Branch**: `009-prometheus-longhorn-monitoring`
**Created**: 2026-04-01
**Status**: Draft
**Input**: User description: "Deploy kube-prometheus-stack, Longhorn ServiceMonitor, and a community longhorn dashboard"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View Cluster and Node Metrics in Grafana (Priority: P1)

An operator opens Grafana at `https://grafana.fleet1.cloud` and sees live metrics for all
cluster nodes — CPU, memory, disk, and network — without any manual configuration.

**Why this priority**: Core value of the monitoring stack. Proves Prometheus is scraping
and Grafana is connected. Everything else builds on this.

**Independent Test**: Open `https://grafana.fleet1.cloud`, log in, and verify the default
Kubernetes node dashboards show data for all 4 cluster nodes.

**Acceptance Scenarios**:

1. **Given** the monitoring stack is deployed, **When** a user opens Grafana, **Then** they can log in with the configured admin password and see the default home dashboard.
2. **Given** Prometheus is running, **When** the user navigates to Explore, **Then** a query for `node_cpu_seconds_total` returns data for all cluster nodes.

---

### User Story 2 - View Longhorn Storage Metrics in Grafana (Priority: P2)

An operator opens the Longhorn dashboard in Grafana and sees volume health, replica status,
disk usage, and I/O metrics for the cluster's storage.

**Why this priority**: The specific motivation for this feature — visibility into Longhorn
storage health without logging into the Longhorn UI.

**Independent Test**: Open the Longhorn dashboard in Grafana and verify volume and disk
metrics are populated for the cluster's PVCs.

**Acceptance Scenarios**:

1. **Given** the Longhorn ServiceMonitor is enabled and the dashboard is provisioned, **When** a user opens the Longhorn dashboard in Grafana, **Then** metrics for volumes, replicas, and disk usage are visible.
2. **Given** Longhorn is healthy, **When** the user views the dashboard, **Then** all volumes show healthy status and replica counts match expectations.

---

### User Story 3 - Access Prometheus UI for Ad-Hoc Queries (Priority: P3)

An operator opens `https://prometheus.fleet1.cloud` and can run PromQL queries to
investigate metrics or validate alert rules.

**Why this priority**: Useful for debugging but not required for day-to-day operation.
Grafana covers most query needs.

**Independent Test**: Open `https://prometheus.fleet1.cloud`, run a PromQL query, confirm
results are returned.

**Acceptance Scenarios**:

1. **Given** Prometheus is deployed with an ingress, **When** a user visits the Prometheus UI, **Then** the Targets page shows all scrapers as UP (excluding K3s control-plane components which are disabled).

---

### Edge Cases

- What happens if Longhorn is not yet deployed when monitoring is installed? (ServiceMonitor will exist but have no targets — safe, no crash.)
- What happens if Prometheus PVC runs out of space? (Prometheus stops ingesting; operator must expand the PVC or reduce retention.)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: kube-prometheus-stack MUST be deployed via Helm into a dedicated `monitoring` namespace.
- **FR-002**: Prometheus MUST use a Longhorn-backed PVC (`storageClassName: longhorn`) for metric storage.
- **FR-003**: Grafana MUST use a Longhorn-backed PVC for dashboard and plugin persistence.
- **FR-004**: K3s control-plane scrapers (kubeControllerManager, kubeScheduler, kubeEtcd, kubeProxy) MUST be disabled to prevent scrape errors.
- **FR-005**: Grafana MUST be accessible at `https://grafana.fleet1.cloud` via Traefik ingress with TLS.
- **FR-006**: Prometheus MUST be accessible at `https://prometheus.fleet1.cloud` via Traefik ingress with TLS.
- **FR-007**: The Longhorn ServiceMonitor MUST be enabled in the Longhorn Helm values so Prometheus discovers Longhorn targets automatically.
- **FR-008**: The community Longhorn Grafana dashboard (ID 13032) MUST be provisioned automatically — no manual import required.
- **FR-009**: The deployment MUST be idempotent — re-running the playbook produces no errors on an already-deployed stack.
- **FR-010**: Grafana admin password MUST be stored in `group_vars/all.yml` and never committed to the repository.

### Key Entities

- **Monitoring namespace**: `monitoring` — all kube-prometheus-stack resources live here.
- **Prometheus PVC**: Longhorn-backed, `20Gi`, retains metrics for ~2 weeks at homelab scrape volume.
- **Grafana PVC**: Longhorn-backed, `5Gi`, persists dashboards and plugin state.
- **Longhorn ServiceMonitor**: Lives in `longhorn-system`, discovered by Prometheus via label selector.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Grafana loads at `https://grafana.fleet1.cloud` within 3 seconds of a browser request.
- **SC-002**: The Longhorn dashboard in Grafana shows data within 5 minutes of deployment completing.
- **SC-003**: All Prometheus scrape targets (excluding intentionally disabled K3s control-plane targets) show `UP` status on the Targets page.
- **SC-004**: Re-running the monitoring playbook tag produces zero Ansible failures and no unintended changes to running Prometheus/Grafana state.

## Assumptions

- Longhorn is already installed and healthy before this feature is deployed.
- Traefik is already deployed with TLS termination and the wildcard `*.fleet1.cloud` certificate in the `traefik` namespace.
- The `longhorn` StorageClass is the cluster default and is available for PVC provisioning.
- AlertManager is deployed as part of kube-prometheus-stack but no alert rules are configured in this feature (future scope).
- The Longhorn dashboard JSON is fetched at deploy time via Grafana's built-in dashboard provisioning (no manual download required).
