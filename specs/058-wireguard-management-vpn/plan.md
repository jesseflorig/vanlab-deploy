# Implementation Plan: Wireguard VPN for management laptop access to fleet1.lan

**Branch**: `058-wireguard-management-vpn` | **Date**: 2026-04-28 | **Spec**: `specs/058-wireguard-management-vpn/spec.md`
**Input**: Feature specification from `/specs/058-wireguard-management-vpn/spec.md`

## Summary
The goal is to provide secure remote access to the `fleet1.lan` network for a management laptop by provisioning a Wireguard VPN server on the OPNsense router (`10.1.1.1`). This will be implemented using the OPNsense REST API via Ansible, ensuring the configuration is idempotent and managed as code. The solution includes server setup, peer (laptop) configuration, firewall rules, and DNS resolution.

## Technical Context
**Language/Version**: Ansible 2.x  
**Primary Dependencies**: `community.opnsense` collection, `os-wireguard` OPNsense plugin  
**Storage**: N/A  
**Testing**: Ansible `--check` mode, manual DNS/ping validation from client  
**Target Platform**: OPNsense 26.1+  
**Project Type**: Infrastructure as Code (Network)  
**Performance Goals**: Sub-5s handshake, line-speed or limited by WAN/CPU encryption performance  
**Constraints**: MUST NOT conflict with existing VLAN subnets; MUST use `10.1.254.0/24` for VPN space  
**Scale/Scope**: 1 management peer initially; scalable to more if needed

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Principle I (IaC)**: PASS. Managed via `network-deploy.yml`.
- **Principle II (Idempotency)**: PASS. Using OPNsense API with existence checks.
- **Principle IV (Secrets Hygiene)**: PASS. Wireguard private keys MUST be stored in `group_vars/all.yml` (gitignored).
- **Principle VI (Encryption in Transit)**: PASS. Wireguard is natively encrypted.
- **Principle VII (Least Privilege)**: PASS. Firewall rules will be scoped to allow VPN -> Mgmt/Cluster only.

## Project Structure

### Documentation (this feature)

```text
specs/058-wireguard-management-vpn/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           
│   └── wireguard-api.md # Phase 1 output
└── tasks.md             # Phase 2 output (future)
```

### Source Code (repository root)

```text
playbooks/
└── network/
    └── network-deploy.yml    # Updated with Wireguard tasks

group_vars/
├── all.yml                   # Untracked; updated with keys/subnet
└── example.all.yml           # Updated with placeholder vars
```

**Structure Decision**: Infrastructure as Code. Modifying the existing network playbook is the simplest and most maintainable approach, consistent with Principle V.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | | |
