# CLI Contract: Rack Shutdown

**Feature**: 040-rack-shutdown-script  
**Date**: 2026-04-16

## Entry Points

### Primary (Makefile)

```bash
make shutdown              # Full rack shutdown
make shutdown-dry-run      # Dry run — prints planned actions, no execution
```

### Direct (ansible-playbook)

```bash
ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml
ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml --check   # dry-run
ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml -v        # verbose
ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml --check -v
```

## Behavior Contract

### Normal run

1. Prints a pre-flight summary (reachable hosts, Longhorn health).
2. If any pre-flight warnings exist, prints them and pauses for 5 seconds before proceeding (allows Ctrl+C to abort).
3. Proceeds through the shutdown sequence: agents → servers → edge → OPNsense.
4. Prints a status line for each step: `[START]`, `[OK]`, or `[WARN]`/`[FAIL]`.
5. Halts on critical failures (drain timeout, mid-sequence host unreachable).
6. The OPNsense step completes when the shutdown command is sent — confirmation of halt is not possible (network drops).
7. Exits 0 on success; exits non-zero if a critical step failed.

### Dry run (`--check`)

1. Prints each action the playbook would take, in sequence.
2. No SSH connections are made to cluster nodes or OPNsense.
3. The pre-flight kubectl and Longhorn checks still run (read-only, no side effects).
4. Exits 0.

## Prerequisites

The operator's workstation must have:
- Ansible installed and `hosts.ini` accessible at the repo root
- SSH agent or keys configured for `fleetadmin` on cluster/edge hosts
- SSH credentials for OPNsense (`root` or named admin) in `group_vars/network.yml`
- `kubectl` configured (used by the pre-flight Longhorn check; optional if Longhorn check is disabled)

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All steps completed successfully (or dry-run completed) |
| 1 | Critical failure: drain timeout, unexpected host unreachable mid-sequence, or pre-flight aborted by operator |
| 2 | Ansible configuration error (missing inventory group, missing variable) |

## Out of Scope

- Partial shutdown (single component) — use `drain-shutdown.yml -e target=<node>` for individual nodes
- Restart / power-on sequencing — out of scope for this feature
- Automated/scheduled shutdown — this is an operator-initiated utility only
