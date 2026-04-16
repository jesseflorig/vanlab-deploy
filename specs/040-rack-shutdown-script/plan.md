# Implementation Plan: Rack Shutdown Script

**Branch**: `040-rack-shutdown-script` | **Date**: 2026-04-16 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `/specs/040-rack-shutdown-script/spec.md`

## Summary

An Ansible playbook (`playbooks/utilities/rack-shutdown.yml`) that safely shuts down the vanlab rack in dependency order: K3s agent nodes → K3s server nodes → edge host (cloudflared) → OPNsense. Invoked via `make shutdown`; `--check` mode provides dry-run preview. Pre-flight checks warn on unhealthy state but do not block. The OPNsense final step uses `async: 5, poll: 0` + `ignore_unreachable: true` to handle SSH session loss gracefully.

## Technical Context

**Language/Version**: YAML (Ansible 2.x) — existing project conventions  
**Primary Dependencies**: Ansible, kubectl (delegated to localhost for Longhorn pre-flight check), SSH  
**Storage**: N/A — no persistent state; playbook is stateless  
**Testing**: Manual validation against live rack; dry-run (`--check`) for non-destructive verification  
**Target Platform**: Operator workstation (macOS or Linux); targets arm64 Raspberry Pi CM5 nodes, Ubuntu Bookworm edge host, OPNsense (FreeBSD)  
**Project Type**: Ansible utility playbook + Makefile entry point  
**Performance Goals**: Full rack shutdown in under 10 minutes (SC-003)  
**Constraints**: Must not require new credentials; must handle SSH loss on final step without false failure  
**Scale/Scope**: 6 cluster nodes, 1 edge host, 1 OPNsense instance

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I — Infrastructure as Code | ✅ Pass | Shutdown is expressed as an Ansible playbook; no manual steps |
| II — Idempotency | ⚠️ Justified violation | Shutdown is inherently destructive/non-idempotent by design. Mitigation: pre-flight skips already-offline nodes gracefully. See Complexity Tracking. |
| III — Reproducibility | ✅ Pass | Playbook lives in the repo; invocation documented in quickstart.md |
| IV — Secrets Hygiene | ✅ Pass | Uses existing SSH keys; OPNsense credentials go in untracked `group_vars/network.yml`, not in `hosts.ini` |
| V — Simplicity | ✅ Pass | Standard Ansible shell/command/systemd modules; no custom roles or modules |
| XI — GitOps | ✅ Pass | This is infrastructure tooling, not an application workload; Ansible-managed is correct |

**Post-design re-check**: No new violations introduced by Phase 1 design. OPNsense credentials handled per Principle IV (untracked group_vars).

## Project Structure

### Documentation (this feature)

```text
specs/040-rack-shutdown-script/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── cli.md           # Phase 1 output — CLI/Makefile interface contract
└── tasks.md             # Phase 2 output (/speckit.tasks — not created here)
```

### Source Code (repository root)

```text
playbooks/utilities/
└── rack-shutdown.yml    # New: full rack shutdown playbook

Makefile                 # New: make shutdown, make shutdown-dry-run targets

hosts.ini                # Modified: add [network] group for OPNsense (no ansible_host — use SSH config alias)
```

No new `group_vars/` files needed. All SSH credentials (user, key, port) are in `~/.ssh/config` and resolved automatically when Ansible uses the SSH alias `opnsense`. OPNsense user is `fleetadmin` (differs from `fleetadmin` in `[all:vars]`); set `ansible_ssh_private_key_file=~/.ssh/id_rsa` on the `[network]` group to ensure key auth is used instead of the global `ansible_ssh_pass`.

**Structure Decision**: Single utility playbook in the existing `playbooks/utilities/` directory, consistent with `drain-shutdown.yml`, `seal-secrets.yml`, and other utilities. No new role or directory structure needed.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Principle II (Idempotency) — shutdown is not idempotent | Shutdown is destructive by design; the goal is to halt all components | There is no idempotent equivalent of "turn everything off"; the pre-flight skip for already-offline nodes is the closest mitigation available |

## Implementation Notes

### Playbook Structure (5 plays)

```
Play 1: Pre-flight (hosts: localhost)
  - Check reachability of all inventory hosts (warn on failure)
  - Check Longhorn volume health via kubectl (warn on degraded volumes)
  - Print summary; pause 5s if any warnings (allows Ctrl+C)

Play 2: Drain + shutdown agent nodes (serial: 1)
  - hosts: agents (node2, node4, node6)
  - Drain each node from servers[0] via kubectl (run_once on servers[0])
  - systemctl stop k3s-agent
  - shutdown -h now (async: 5, poll: 0)
  - wait_for_connection timeout to confirm node offline

Play 3: Drain + shutdown server nodes (serial: 1)
  - hosts: servers (node1, node3, node5)
  - Drain from a peer server (servers[1] if target is servers[0], etc.)
  - Special handling for last server: skip drain (no API server to drain to)
  - systemctl stop k3s
  - shutdown -h now (async: 5, poll: 0)

Play 4: Shutdown edge host (hosts: compute)
  - systemctl stop cloudflared
  - shutdown -h now (async: 5, poll: 0)

Play 5: Shutdown OPNsense (hosts: network)
  - shutdown -h now
  - async: 5, poll: 0
  - ignore_unreachable: true
  - Print notice: "OPNsense shutdown command sent — network connectivity will drop"
```

### hosts.ini Change

Add below the `[compute]` section:

```ini
[network]
opnsense  ansible_ssh_private_key_file=~/.ssh/id_rsa
```

No `ansible_host` — Ansible passes the alias `opnsense` to SSH, which `~/.ssh/config` resolves to `10.1.1.1` with `User fleetadmin`. Setting `ansible_ssh_private_key_file` explicitly ensures key auth is used rather than the global `ansible_ssh_pass=fleetadmin` from `[all:vars]` (which would fail on OPNsense with the wrong password).

### Makefile

```makefile
shutdown:
	ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml

shutdown-dry-run:
	ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml --check
```

### Key Design Decision: kubectl drain source

Research confirmed the existing project pattern runs kubectl from a server node (not localhost). The rack-shutdown playbook will follow the same pattern for consistency — drain tasks are delegated to `servers[0]` (or a remaining peer for server drains), not to localhost. The operator's workstation kubeconfig is used only for the pre-flight Longhorn health check (delegated to localhost).
