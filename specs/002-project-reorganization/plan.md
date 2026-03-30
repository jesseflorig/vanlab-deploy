# Implementation Plan: Project Reorganization

**Branch**: `002-project-reorganization` | **Date**: 2026-03-29 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-project-reorganization/spec.md`

## Summary

Reorganize the Ansible project from a cluster-centric flat layout to a multi-device
structure supporting K3s cluster nodes (server/agent), a CM5 edge device running
Cloudflared as a standalone systemd service, and an OPNsense router managed via REST API.
Playbooks move to `playbooks/<category>/`, group vars split by device category, and the
`cloudflared` role is rewritten from Helm/K8s to native systemd.

## Technical Context

**Language/Version**: YAML (Ansible 2.x) — existing project conventions
**Primary Dependencies**:
- `oxlorg.opnsense` collection via `requirements.yml` — OPNsense REST API
- `cloudflared` Debian apt package (Cloudflare official repo, arm64) — replaces Helm role
- Standard Ansible built-ins: `apt`, `systemd_service`, `copy`, `apt_repository`

**Storage**: N/A
**Testing**: Manual smoke tests per quickstart.md; idempotency verified by re-run
**Target Platform**: Raspberry Pi OS arm64 (cluster + edge), OPNsense router (REST API)
**Project Type**: ansible-playbook (infrastructure management)
**Performance Goals**: N/A — structural reorganization
**Constraints**: Zero disruption to existing cluster; all playbooks MUST function after
move; no new secrets patterns beyond existing gitignored `all.yml`
**Scale/Scope**: 4 cluster nodes, 1 edge device, 1 router

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Infrastructure as Code | ✅ PASS | All changes in playbooks/inventory/roles |
| II. Idempotency | ✅ PASS | All new tasks use declarative Ansible modules |
| III. Reproducibility | ✅ PASS | Improved — `requirements.yml` added, structure clearer |
| IV. Secrets Hygiene | ✅ PASS | OPNsense creds in gitignored `all.yml`; token file mode 0600 |
| V. Simplicity | ✅ PASS | Flat role structure maintained; no new abstractions |
| VI. Encryption in Transit | N/A | Structural change; no new cross-VLAN traffic |
| VII. Least Privilege | N/A | Structural change only |

**Post-design re-check**: All gates pass. No violations.

## Project Structure (Target)

### Documentation (this feature)

```text
specs/002-project-reorganization/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── tasks.md
```

### Repository Root (after reorganization)

```text
vanlab/
├── ansible.cfg                    # NEW
├── requirements.yml               # NEW — oxlorg.opnsense collection
├── hosts.ini                      # UPDATED — server/agent, topology comments
│
├── group_vars/
│   ├── all.yml                    # gitignored (unchanged)
│   ├── example.all.yml            # UPDATED — new secrets template
│   ├── cluster.yml                # NEW
│   ├── network.yml                # NEW
│   └── compute.yml                # NEW
│
├── playbooks/
│   ├── cluster/
│   │   ├── k3s-deploy.yml         # MOVED + group refs updated
│   │   └── services-deploy.yml    # MOVED + edge play removed + traefik to servers
│   ├── network/
│   │   └── network-deploy.yml     # NEW
│   ├── compute/
│   │   └── edge-deploy.yml        # NEW
│   └── utilities/
│       ├── check_hosts.yml        # MOVED from root
│       ├── disk-health.yml        # MOVED from root
│       ├── read-k3s-token.yml     # MOVED from utilities/
│       └── test-join-cmd.yml      # MOVED from utilities/
│
└── roles/
    ├── cloudflared/               # REWRITTEN — systemd, not Helm
    ├── helm/                      # unchanged
    ├── traefik/                   # unchanged
    ├── wireguard/                 # unchanged
    └── disk-health/               # unchanged
```

**Structure Decision**: Single repo, playbooks by device category. OPNsense managed via
localhost REST API (not SSH). Existing `utilities/` root dir retired — contents move to
`playbooks/utilities/`.

## Key Implementation Notes

### Inventory Changes

- `[masters]` → `[servers]`, `[workers]` → `[agents]`
- `[edge]` group removed (was node2 hosting Traefik + Cloudflared in K8s)
- `[k3s_cluster:children]` → `[cluster:children]`
- `[compute]` group added for CM5 edge device at `10.1.10.x`
- OPNsense and all switches documented as topology comments only

### services-deploy.yml Changes

- `hosts: masters` play: rename to `hosts: servers`, add `traefik` role
- `hosts: edge` play: **removed entirely**
- `hosts: workers` play: rename to `hosts: agents`

### cloudflared Role Rewrite

Old: `helm upgrade --install cloudflared ...` — cluster-dependent Kubernetes deployment.
New: native systemd service on CM5 using Cloudflare's official Debian apt repo (arm64).

1. Add Cloudflare GPG key + apt repo
2. Install `cloudflared` package via apt
3. Write tunnel token to `/etc/cloudflared/tunnel-token` (mode 0600)
4. Create + enable systemd unit (`ansible.builtin.systemd_service`)

Token sourced from `cloudflare_tunnel_token` in `group_vars/all.yml` (existing pattern).

### New Files

- `ansible.cfg` — sets `inventory = hosts.ini` and disables host key checking
- `requirements.yml` — pins `oxlorg.opnsense >= 25.0.0`
- `playbooks/network/network-deploy.yml` — scaffolds OPNsense API connectivity check
- `playbooks/compute/edge-deploy.yml` — deploys Cloudflared to CM5
