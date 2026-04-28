# Implementation Plan: fleet1.lan Infrastructure DNS Host Records

**Branch**: `057-add-lan-dns-hosts` | **Date**: 2026-04-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/057-add-lan-dns-hosts/spec.md`

## Summary

Add five explicit `fleet1.lan` infrastructure DNS host records to the OPNsense Unbound local resolver:
`opnsense.fleet1.lan` → `10.1.1.1`, `sw-main.fleet1.lan` → `10.1.1.10`, and
`sw-poe-1` through `sw-poe-3.fleet1.lan` → `10.1.1.11` through `10.1.1.13`. Implement the records
as an additive, idempotent extension to the existing network deployment playbook that already manages
Unbound host overrides.

## Technical Context

**Language/Version**: YAML (Ansible playbook syntax; existing project conventions)  
**Primary Dependencies**: OPNsense Unbound REST API via `ansible.builtin.uri`; existing OPNsense API credentials in `group_vars/all.yml`  
**Storage**: OPNsense Unbound configuration; no application or cluster storage  
**Testing**: Ansible check/run validation plus LAN DNS resolution checks with `dig` against `10.1.1.1`  
**Target Platform**: OPNsense local resolver for the `fleet1.lan` LAN environment  
**Project Type**: Infrastructure automation (Ansible network playbook)  
**Performance Goals**: All requested hostnames resolve from a LAN client within 2 seconds  
**Constraints**: Additive only; no unrelated DNS records modified; idempotent re-runs; conflicts surfaced before applying final state  
**Scale/Scope**: Five explicit A records for infrastructure devices in the `fleet1.lan` namespace

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I — Infrastructure as Code | Pass | DNS changes are planned as Ansible-managed OPNsense configuration. |
| II — Idempotency | Pass | Existing overrides are searched first; desired records are created only when absent. |
| III — Reproducibility | Pass | Re-running the network playbook recreates the DNS records from repository state. |
| IV — Secrets Hygiene | Pass | Uses existing OPNsense credentials from untracked `group_vars/all.yml`; no new secrets. |
| V — Simplicity | Pass | Extends the existing network playbook and Unbound API pattern; no new role required. |
| VI — Encryption in Transit | Pass | DNS labels do not create new plaintext service exposure. |
| VII — Least Privilege & Certificate-Based Authentication | Pass | No firewall or authentication expansion is introduced. |
| IX — Secure Service Exposure | Pass | This feature only adds local names for existing device addresses. |
| X — Intra-Cluster Service Locality | Pass | Not an intra-cluster service endpoint change. |
| XI — GitOps Application Deployment | Pass | OPNsense DNS is infrastructure and remains Ansible-managed. |

No violations. Complexity Tracking section not required.

## Project Structure

### Documentation (this feature)

```text
specs/057-add-lan-dns-hosts/
├── plan.md              # This file
├── research.md          # Phase 0 decisions
├── data-model.md        # Phase 1 entities and validation rules
├── quickstart.md        # Phase 1 validation guide
├── contracts/           # Phase 1 desired-record contract
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
playbooks/network/
└── network-deploy.yml   # UPDATE: add explicit infrastructure Unbound host overrides
```

**Structure Decision**: Single-project infrastructure layout. The existing `playbooks/network/network-deploy.yml`
already owns OPNsense API interactions, firewall rules, wildcard `fleet1.lan` Unbound records, and DNS reconfigure
calls, so the explicit infrastructure host records belong in the same playbook.

## Phase 0: Research

Research output is captured in [research.md](research.md). All implementation choices are resolved.

## Phase 1: Design & Contracts

Design output is captured in:

- [data-model.md](data-model.md)
- [contracts/unbound-host-overrides.md](contracts/unbound-host-overrides.md)
- [quickstart.md](quickstart.md)

## Constitution Check (Post-Design)

| Principle | Status | Notes |
|-----------|--------|-------|
| I — Infrastructure as Code | Pass | Design keeps all DNS state in the Ansible network playbook. |
| II — Idempotency | Pass | Desired records are represented as data and compared to existing Unbound overrides before creation. |
| III — Reproducibility | Pass | Quickstart validates rebuild/reapply from committed playbook state. |
| IV — Secrets Hygiene | Pass | No new secrets, credentials, or certificate material are introduced. |
| V — Simplicity | Pass | No new abstraction beyond a small desired-record list and loop. |
| VI — Encryption in Transit | Pass | No cross-VLAN plaintext path or new exposed service is added. |
| VII — Least Privilege & Certificate-Based Authentication | Pass | OPNsense API access pattern is unchanged. |
| IX — Secure Service Exposure | Pass | DNS records point at existing management addresses only. |
| X — Intra-Cluster Service Locality | Pass | Not applicable; no cluster service routing changes. |
| XI — GitOps Application Deployment | Pass | No application workload or ArgoCD manifest is involved. |

