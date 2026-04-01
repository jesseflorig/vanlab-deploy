<!--
SYNC IMPACT REPORT
==================
Version change: 1.2.0 → 1.3.0
Modified principles: None (existing principles unchanged)
Added sections:
  - Principle IX: Secure Service Exposure (HTTPS/MQTTS for all externally accessible services)
  - Principle X: Intra-Cluster Service Locality (CoreDNS overrides for cluster-to-cluster traffic)
  - Principle XI: GitOps Application Deployment (split manifests under manifests/, ArgoCD sync)
  - Technology Stack: added Gitea, ArgoCD, manifests/ structure
  - Deployment Workflow: updated to reflect GitOps layer
Removed sections: None
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ — Constitution Check gates align with IX/X/XI
  - .specify/templates/spec-template.md ✅ — No mandatory sections added/removed
  - .specify/templates/tasks-template.md ✅ — No structural changes required
  - .specify/templates/agent-file-template.md ✅ — No principle-named references
  - .specify/templates/constitution-template.md ✅ — Source template; no changes required
Deferred TODOs: None — all placeholders resolved.
-->

# Vanlab Constitution

## Core Principles

### I. Infrastructure as Code

All cluster topology, node configuration, and service deployments MUST be expressed in Ansible
playbooks or Helm charts. Manual changes applied directly to cluster nodes are prohibited. If
a change cannot be made via automation, the automation MUST be updated first before the change
is applied.

**Rationale**: Prevents configuration drift and ensures the cluster state is always auditable
and recoverable from the repository alone.

### II. Idempotency

Every Ansible playbook and Helm chart MUST be idempotent. Running any playbook or applying any
chart multiple times MUST produce the same end state without errors or unintended side effects.
Use Ansible `creates:`, `state:` guards, and Helm `--atomic` flags to enforce this.

**Rationale**: Idempotency enables safe re-runs during partial failures and cluster rebuilds
without risk of double-applying destructive operations.

### III. Reproducibility

The entire cluster MUST be rebuildable from scratch by following the documented procedure in
`README.md` combined with the playbooks and chart values in this repository. Every manual
remediation step (e.g., the current agent-join workaround) MUST be documented in `README.md`
until it is automated.

**Rationale**: A homelab cluster is frequently torn down and rebuilt. Full reproducibility
reduces recovery time and cognitive overhead.

### IV. Secrets Hygiene

Secrets, tokens, credentials, keys, certificate private keys, and CA material MUST never be
committed to the repository. Use `group_vars/example.all.yml` as the template; real values
MUST be provided via an untracked `group_vars/all.yml` or an external secrets mechanism
(e.g., Ansible Vault, environment variables). The `.gitignore` MUST exclude all files
containing live secrets or private key material.

The PKI lifecycle — CA creation, certificate issuance, and rotation — MUST be managed as code
via a tool such as `cert-manager`, `step-ca`, or Ansible-managed PKI roles. No certificates
or keys MAY be generated manually outside the repository workflow.

**Rationale**: The repository may be public or shared. Leaked credentials or private keys can
compromise the home network, exposed services, and any devices authenticating via certificates.

### V. Simplicity

Solutions MUST use the simplest adequate tool. Prefer plain Ansible tasks over custom modules,
prefer Helm community charts over hand-rolled manifests, and prefer a flat role structure over
deeply nested dependencies. Complexity MUST be justified by a concrete operational need;
speculative abstractions are not permitted.

**Rationale**: A homelab maintained by a small team (often one person) must be operable
without deep context. Simple automation is faster to debug and cheaper to maintain.

### VI. Encryption in Transit

All communication crossing a VLAN boundary MUST be encrypted. Specifically:

- MQTT MUST be served exclusively on MQTTS (port 8883); plaintext port 1883 MUST be disabled
  or firewall-blocked at the broker
- Traefik ingress MUST terminate TLS; HTTP MUST redirect to HTTPS
- No service exposed on `10.1.20.x` MUST accept plaintext connections from `10.1.30.x` or
  `10.1.40.x`
- Internal cluster service-to-service traffic SHOULD use mTLS where the workload supports it

**Rationale**: Camera and IoT VLANs are higher-attack-surface segments. Encrypting at the
boundary limits the blast radius of a compromised device.

### VII. Least Privilege & Certificate-Based Authentication

- MQTT clients (cameras on `10.1.30.x`, sensors on `10.1.40.x`) MUST authenticate using
  client certificates issued by the project's internal CA; username/password authentication
  alone is insufficient
- Firewall rules MUST be narrowly scoped: IoT devices MUST only reach the MQTT broker port;
  cameras MUST only reach their designated endpoints — no broad cross-VLAN routing
- All firewall rules and broker ACLs MUST be expressed as code and managed through this
  repository (per Principle I)

**Rationale**: Cert-based auth prevents credential-stuffing attacks and makes device
revocation explicit and auditable. Narrow firewall rules contain lateral movement if a
device is compromised.

### VIII. Persistent Storage

All cluster services requiring durable storage MUST use Longhorn-backed
`PersistentVolumeClaim` resources. Specifically:

- PVCs MUST reference the `longhorn` StorageClass (the cluster default)
- `hostPath` volumes and `emptyDir` MUST NOT be used for stateful workloads; they are
  permitted only for ephemeral scratch space or read-only config mounts
- Volume size requests MUST be explicit; `storage: ""` or unbounded claims are not permitted
- Helm chart values that expose a `storageClass` parameter MUST set it to `longhorn`
  explicitly rather than relying on the cluster default, to make the dependency auditable

**Rationale**: Longhorn provides replicated, node-failure-tolerant block storage backed by
each node's local NVMe. Using it consistently for all stateful workloads ensures data
survives single-node failures and keeps storage configuration observable in the repository.

### IX. Secure Service Exposure

All services exposed externally MUST be served over HTTPS or its protocol equivalent:

- HTTP services MUST NOT be exposed externally; Traefik MUST redirect HTTP → HTTPS for all
  ingress routes
- MQTT MUST be served exclusively on MQTTS (port 8883); plaintext MQTT (port 1883) MUST be
  disabled or firewall-blocked
- Services MUST use TLS certificates issued by a trusted CA (e.g., Let's Encrypt via
  cert-manager DNS-01); self-signed certificates are permitted only for internal cluster
  service-to-service communication where verification is explicitly disabled by design
- Wildcard certificates (`*.fleet1.cloud`) MUST be used where a single cert covers multiple
  subdomains, and MUST be issued and rotated automatically via cert-manager

**Rationale**: Plaintext external access exposes credentials and data to interception.
Automated certificate management removes the operational burden of manual rotation and
eliminates certificate expiry incidents.

### X. Intra-Cluster Service Locality

Cluster-to-cluster service communication MUST route internally and MUST NOT traverse public
infrastructure. Specifically:

- Any public hostname used as a service endpoint (e.g., `gitea.fleet1.cloud`) MUST have a
  corresponding CoreDNS override that resolves it to an internal cluster IP or node IP within
  the `10.1.20.x` subnet
- CoreDNS overrides MUST be managed as Kubernetes ConfigMaps rendered by Ansible templates and
  applied as part of the bootstrap role; manual `kubectl patch` of CoreDNS config is prohibited
- Services that communicate intra-cluster MUST be verified to resolve internally before
  declaring the integration complete (e.g., ArgoCD → Gitea MUST resolve to the cluster node,
  not egress through the Cloudflare Tunnel)

**Rationale**: Routing intra-cluster traffic through public infrastructure (Cloudflare Tunnel,
DNS, CDN) adds unnecessary latency, external dependency, and potential data exposure. Keeping
traffic on the LAN ensures service connectivity is independent of internet availability.

### XI. GitOps Application Deployment

Application workloads MUST be defined as Kubernetes manifests and synced to the cluster via
ArgoCD. Infrastructure components (Helm-managed: Traefik, cert-manager, Longhorn, Gitea,
ArgoCD itself) remain Ansible-managed and are excluded from this principle.

- Application manifests MUST live under `manifests/` at the repository root, organized in
  per-app subdirectories (e.g., `manifests/static-site/`, `manifests/my-app/`)
- Each app subdirectory MUST map to exactly one ArgoCD `Application` resource registered via
  the `argocd_apps` variable in `group_vars/all.yml`
- ArgoCD Applications MUST be configured with `automated.prune: true` and
  `automated.selfHeal: true` so the cluster state always converges to the Git state
- Manifests MUST be pushed to the Gitea repository (`gitea.fleet1.cloud`) and synced from
  there; ArgoCD MUST NOT sync directly from GitHub
- New application workloads MUST NOT be deployed via `kubectl apply` or Ansible `command`
  tasks; the GitOps loop is the sole deployment mechanism for application manifests

**Rationale**: GitOps provides a single source of truth for cluster application state, enables
git-driven rollbacks (revert a commit → ArgoCD restores prior state), and makes every
deployment auditable via the Gitea commit history.

## Technology Stack

The canonical technology choices for this project are:

- **Orchestration**: K3s (lightweight Kubernetes) on Raspberry Pi OS (Debian-based, arm64)
- **Automation**: Ansible — playbooks at repository root, roles in `roles/`
- **Package management**: Helm — charts managed via `roles/helm/` and `services-deploy.yml`
- **GitOps**: ArgoCD — syncs application manifests from `manifests/` in the Gitea repository;
  installed via `roles/argocd/`; bootstrapped via `roles/argocd-bootstrap/`
- **Git hosting**: Gitea — self-hosted at `gitea.fleet1.cloud`; installed via `roles/gitea/`;
  serves as the ArgoCD source-of-truth repository
- **Application manifests**: `manifests/<app-name>/` — one subdirectory per ArgoCD Application;
  each directory contains plain Kubernetes YAML synced automatically to the cluster
- **Storage**: Longhorn v1.11.1 — distributed block storage using the `longhorn` StorageClass;
  data stored at `/var/lib/longhorn` on each node's local NVMe disk; installed via
  `https://charts.longhorn.io`; requires `open-iscsi` and `nfs-common` on all nodes
- **Hardware**:
  - Cluster nodes: Raspberry Pi CM5 (64 GB) with PoE HAT and M.2 2TB NVMe storage
  - Edge device: Waveshare CM5-PoE-BASE-A (Raspberry Pi CM5, arm64 Debian-based)
  - Switches: 1× Netgear GS308T, 3× Netgear GS308EPP (Smart Managed Plus — VLAN-capable
    via web UI only; not Ansible-manageable)
  - Router: OPNsense (`10.1.1.1`) — managed via `community.opnsense` REST API
- **Network**:
  - `10.1.1.x` — management VLAN: OPNsense router (`10.1.1.1`), switch management
  - `10.1.10.x` — edge VLAN: CM5 Cloudflared device; outbound internet (443) only;
    allowed to reach Traefik on `10.1.20.x` (80/443); SSH access from management VLAN only
  - `10.1.20.x` — cluster VLAN: K3s server/agent nodes, ingress via Traefik,
    VPN via WireGuard, MQTT broker
  - `10.1.30.x` — camera VLAN: IP cameras (isolated; access to MQTT broker on `10.1.20.x`
    MUST be explicitly permitted via firewall rules managed in this repository)
  - `10.1.40.x` — IoT VLAN: sensors publishing to the MQTT broker on `10.1.20.x`
    (cross-VLAN routing MUST be managed as code per Principle I)
- **Inventory**: `hosts.ini` — MUST list all nodes with their roles (`servers`, `agents`
  for K3s cluster; `network` for OPNsense; `compute` for edge device)

Deviations from this stack MUST be documented in `README.md` with a rationale.

## Deployment Workflow

### Infrastructure (Ansible-managed)

1. **Verify hosts**: `ansible-playbook -i hosts.ini check_hosts.yml`
2. **Deploy cluster**: `ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml`
3. **Deploy services**: `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml`
4. **Bootstrap GitOps**: `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap`

- Playbooks MUST be run in the order above for a fresh cluster.
- Each playbook MUST be independently re-runnable (see Principle II).
- Known manual remediation steps are tracked in `README.md § Known Issues` until automated.
- All new roles or playbooks MUST include a brief description comment at the top of the file.

### Application Workloads (GitOps-managed)

1. Add or update manifests under `manifests/<app-name>/`
2. Register the app in `argocd_apps` in `group_vars/all.yml` (first deployment only)
3. Re-run `--tags argocd-bootstrap` to register new ArgoCD Applications (first deployment only)
4. Commit and push to Gitea (`git push gitea main`)
5. ArgoCD automatically syncs within 3 minutes; monitor via `https://argocd.fleet1.cloud`

- Direct `kubectl apply` of application manifests is prohibited (see Principle XI).
- Rollbacks are performed by reverting the Git commit in Gitea; ArgoCD restores prior state.

## Governance

This constitution supersedes all informal practices. Amendments require:

1. A clear description of the change and rationale committed alongside the amendment.
2. Version increment following semantic versioning:
   - **MAJOR**: Removal or backward-incompatible redefinition of a principle.
   - **MINOR**: New principle added or a section materially expanded.
   - **PATCH**: Clarifications, wording fixes, or non-semantic refinements.
3. `LAST_AMENDED_DATE` updated to the date of the commit.

All playbook PRs/reviews MUST verify compliance with the principles above, particularly
Idempotency (II), Secrets Hygiene (IV), Persistent Storage (VIII), Secure Service Exposure
(IX), and GitOps Deployment (XI). Complexity violations MUST be justified in the PR
description before merging.

**Version**: 1.3.0 | **Ratified**: 2026-03-27 | **Last Amended**: 2026-03-31
