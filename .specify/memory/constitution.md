<!--
SYNC IMPACT REPORT
==================
Version change: [TEMPLATE] → 1.0.0 (initial); 1.0.0 → 1.0.1 (network topology); 1.0.1 → 1.1.0 (security hardening: principles VI + VII, IV expanded); 1.1.0 → 1.1.1 (topology refinement: edge VLAN, server/agent nomenclature, hardware corrections)
Modified principles: N/A (initial ratification from template)
Added sections:
  - Core Principles (5 principles)
  - Technology Stack
  - Deployment Workflow
  - Governance
Removed sections: N/A
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ — Constitution Check gates align with principles below
  - .specify/templates/spec-template.md ✅ — No mandatory sections added/removed; existing structure fits
  - .specify/templates/tasks-template.md ✅ — Task categories (idempotency checks, validation, secrets) reflected
  - .specify/templates/agent-file-template.md ✅ — No principle-named references; generic structure unchanged
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

## Technology Stack

The canonical technology choices for this project are:

- **Orchestration**: K3s (lightweight Kubernetes) on Raspberry Pi OS (Debian-based, arm64)
- **Automation**: Ansible — playbooks at repository root, roles in `roles/`
- **Package management**: Helm — charts managed via `roles/helm/` and `services-deploy.yml`
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

1. **Verify hosts**: `ansible-playbook -i hosts.ini check_hosts.yml`
2. **Deploy cluster**: `ansible-playbook -i hosts.ini k3s-deploy.yml`
3. **Deploy services**: `ansible-playbook -i hosts.ini services-deploy.yml`

- Playbooks MUST be run in the order above for a fresh cluster.
- Each playbook MUST be independently re-runnable (see Principle II).
- Known manual remediation steps are tracked in `README.md § Known Issue` until automated.
- All new roles or playbooks MUST include a brief description comment at the top of the file.

## Governance

This constitution supersedes all informal practices. Amendments require:

1. A clear description of the change and rationale committed alongside the amendment.
2. Version increment following semantic versioning:
   - **MAJOR**: Removal or backward-incompatible redefinition of a principle.
   - **MINOR**: New principle added or a section materially expanded.
   - **PATCH**: Clarifications, wording fixes, or non-semantic refinements.
3. `LAST_AMENDED_DATE` updated to the date of the commit.

All playbook PRs/reviews MUST verify compliance with the principles above, particularly
Idempotency (II) and Secrets Hygiene (IV). Complexity violations MUST be justified in the
PR description before merging.

**Version**: 1.1.1 | **Ratified**: 2026-03-27 | **Last Amended**: 2026-03-29
