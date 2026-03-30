# Feature Specification: Cluster Provisioning and Internet Exposure

**Feature Branch**: `003-cluster-tunnel-expose`
**Created**: 2026-03-29
**Status**: Draft
**Input**: User description: "Provision a working K3s cluster and expose a test web application through the Cloudflare tunnel."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - All Cluster Nodes Join and Are Ready (Priority: P1)

An operator runs a single playbook and ends up with a fully operational cluster: 2 server nodes and 2 agent nodes all in Ready state, with no manual intervention required to join agents. The known agent-join bug in the existing playbook is resolved.

**Why this priority**: Nothing else in this feature works without a functional cluster. This is the foundation all other stories depend on.

**Independent Test**: Run the cluster provisioning playbook and verify all 4 nodes appear as Ready using the cluster status check.

**Acceptance Scenarios**:

1. **Given** 4 freshly provisioned nodes, **When** the cluster playbook runs to completion, **Then** all 2 server and 2 agent nodes appear as Ready with no manual steps.
2. **Given** the cluster is up, **When** the operator checks node status, **Then** all 4 nodes show Ready and none are in NotReady or Unknown state.
3. **Given** the cluster playbook has run once, **When** it runs again, **Then** no changes are made and all nodes remain Ready.

---

### User Story 2 - Traefik Ingress Controller Is Deployed (Priority: P2)

An operator deploys Traefik as the cluster's ingress controller from a single playbook run. Traefik is reachable from within the network and ready to route incoming requests to cluster services.

**Why this priority**: Traefik is the routing layer that sits between the Cloudflare tunnel and cluster workloads. Required before any application can be exposed.

**Independent Test**: Deploy Traefik and confirm it responds to HTTP requests from within the network at the cluster's load balancer address.

**Acceptance Scenarios**:

1. **Given** the cluster is Ready, **When** the services playbook runs, **Then** Traefik is deployed and its load balancer address is reachable from within the network.
2. **Given** Traefik is deployed, **When** the services playbook runs again, **Then** no changes are made.

---

### User Story 3 - Whoami Test App Is Reachable from the Internet (Priority: P3)

An operator deploys a test web application to the cluster and accesses it from the public internet via `whoami.fleet1.cloud`. The request travels from the internet through the Cloudflare tunnel on the CM5 edge device, through Traefik, to the test app pod. This proves the full end-to-end path is functional.

**Why this priority**: Delivers the primary goal of the feature — validated internet connectivity into the homelab through the tunnel.

**Independent Test**: From a device on a cellular network, navigate to `whoami.fleet1.cloud` and receive a response showing request headers, confirming the full tunnel-to-cluster path works.

**Acceptance Scenarios**:

1. **Given** the cluster, Traefik, and whoami are deployed, **When** an external request hits `whoami.fleet1.cloud`, **Then** the response displays request headers returned by the whoami app.
2. **Given** the Cloudflare tunnel routes to Traefik, **When** the cluster is restarted, **Then** `whoami.fleet1.cloud` becomes reachable again once pods are ready, without any manual tunnel reconfiguration.
3. **Given** the whoami app is deployed, **When** the deployment playbook runs again, **Then** no changes are made.

---

### Edge Cases

- What if an agent node fails to join during initial provisioning? The playbook should report which node failed without leaving the cluster in a partial state.
- What if Traefik's load balancer address changes after a cluster restart? The tunnel route must remain valid.
- What if the whoami deployment playbook runs before the cluster is Ready? It should fail clearly rather than silently deploy to an unhealthy cluster.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The cluster provisioning playbook MUST join all agent nodes automatically without manual intervention, resolving the known join bug.
- **FR-002**: The cluster provisioning playbook MUST wait for the K3s server to be ready and retrieve the join token before attempting to join agent nodes.
- **FR-003**: Traefik MUST be deployed as the cluster ingress controller and reachable at a stable address within the network.
- **FR-004**: A whoami test application MUST be deployed to the cluster as a containerised workload.
- **FR-005**: A routing rule MUST direct requests for `whoami.fleet1.cloud` to the whoami application via Traefik.
- **FR-006**: The Cloudflare tunnel on the CM5 edge device MUST be configured to route `fleet1.cloud` traffic to Traefik's cluster address.
- **FR-007**: All provisioning steps MUST be idempotent — re-running any playbook MUST produce no changes when the target state is already met.
- **FR-008**: The operator MUST be able to verify cluster node status from the Ansible control machine without manually SSHing to a server node.

### Key Entities

- **K3s Cluster**: The collection of server and agent nodes forming the container orchestration platform.
- **Traefik**: The ingress controller that receives inbound traffic and routes it to cluster services based on hostname rules.
- **Whoami App**: A lightweight test workload that responds to HTTP requests with request metadata; validates the full routing path.
- **Tunnel Route**: The configuration binding a public hostname (`whoami.fleet1.cloud`) to Traefik's cluster address via the Cloudflare tunnel.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 4 cluster nodes (2 servers, 2 agents) reach Ready state from a clean start with zero manual steps.
- **SC-002**: `whoami.fleet1.cloud` responds successfully to an HTTP request from outside the home network within 30 seconds of the playbooks completing.
- **SC-003**: Re-running all provisioning playbooks against an already-provisioned cluster produces zero changes.
- **SC-004**: An operator can verify cluster node status and confirm tunnel reachability using only the documented README commands.

## Assumptions

- All 4 cluster nodes are freshly provisioned with Raspberry Pi OS and reachable via SSH before the cluster playbook runs.
- The CM5 edge device is already running Cloudflared (deployed in feature 002) and the tunnel is registered as Healthy in the Cloudflare dashboard.
- The Cloudflare tunnel public hostname (`whoami.fleet1.cloud` → Traefik) is configured via the Cloudflare Zero Trust dashboard — this step is not automated by Ansible.
- Traefik receives traffic on HTTP; TLS termination is handled by Cloudflare at the edge.
- The `wireguard` role currently in `services-deploy.yml` is out of scope for this feature.
