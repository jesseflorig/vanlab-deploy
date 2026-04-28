# Implementation Plan: OPNsense 23.7 → 26.1 Upgrade

**Branch**: `055-opnsense-upgrade` | **Date**: 2026-04-27 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/055-opnsense-upgrade/spec.md`

## Summary

Upgrade OPNsense from EOL version 23.7.12_5 to current stable 26.1 via five sequential
major-version hops (23.7 → 24.1 → 24.7 → 25.1 → 25.7 → 26.1). Each hop requires a config
backup, the major upgrade via console or web UI, a reboot, and a verification pass before
proceeding. The upgrade is entirely procedural — no code is written. The primary outputs are
the upgraded router and confirmation that the Destination NAT REST API is accessible,
unblocking T010 in feature 054 (fleet1.lan).

## Technical Context

**Language/Version**: N/A — procedural upgrade (OPNsense web UI + SSH console)
**Primary Dependencies**: OPNsense firmware upgrade mechanism; management laptop SSH access to `10.1.1.1`
**Storage**: N/A — config backups stored as XML files on management laptop
**Testing**: Manual verification checklist per hop; Ansible `--check` mode for drift detection post-upgrade
**Target Platform**: OPNsense router at `10.1.1.1` (FreeBSD-based, x86_64)
**Project Type**: Infrastructure maintenance procedure
**Performance Goals**: Total downtime < 30 minutes cumulative across all hops; each individual hop reboot < 10 minutes
**Constraints**: Sequential hops only — no version skipping; full backup required before each hop; cluster must stay healthy between hops
**Scale/Scope**: Single router; 5 major version hops; ~3-hour maintenance window

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I — Infrastructure as Code | ⚠️ Exception | OPNsense firmware upgrades have no Ansible automation path; this is an accepted exception for router firmware, same as switch firmware. Procedure is documented per Principle III. |
| II — Idempotency | N/A | One-time upgrade procedure; not a repeatable playbook |
| III — Reproducibility | ✅ Pass | Full procedure documented in quickstart.md; config backups at each hop enable recovery |
| IV — Secrets Hygiene | ✅ Pass | No new secrets; existing API credentials reused; config backups contain secrets and must be stored only on the management laptop (gitignored) |
| V — Simplicity | ✅ Pass | In-place upgrade is the simplest adequate path; fresh install rejected (config loss) |
| IX — Secure Service Exposure | ✅ Pass | TLS/HTTPS exposure unchanged; upgrade does not alter cert config |
| XI — GitOps Deployment | ✅ Pass | No application workloads affected; router firmware is outside ArgoCD scope |

**Constitution Exception Justification (Principle I)**:
Router firmware upgrades cannot be automated via Ansible — no `opnsense-firmware-upgrade` module exists and SSH-based automation is fragile for a multi-reboot procedure. This exception is consistent with the existing treatment of switch firmware (GS308T/GS308EPP are also web-UI only). The procedure is fully documented in quickstart.md, satisfying Principle III.

## Project Structure

### Documentation (this feature)

```text
specs/055-opnsense-upgrade/
├── plan.md          # This file
├── research.md      # Upgrade path, breaking changes, decisions
├── data-model.md    # Hop states, backup artifacts, verification checklist items
├── quickstart.md    # Step-by-step upgrade execution guide
└── tasks.md         # Phase 2 output (/speckit.tasks command)
```

### Source Code Impact (repository root)

This feature produces no new source files. The only downstream code change is in a
separate feature branch (054-fleet1-lan-wildcard):

```text
playbooks/network/network-deploy.yml    ← T010 (blocked) becomes implementable
                                          after 26.1 upgrade confirms dnat API
```

**Structure Decision**: No new source code. All work is procedural (web UI + SSH console).
The repo gains only this feature's documentation artifacts. After upgrade is verified,
T010 in feature 054 is unblocked and its implementation should follow immediately.

## Post-Upgrade Follow-On

Once OPNsense 26.1 is confirmed running and the Destination NAT API is verified:

1. Switch back to branch `054-fleet1-lan-wildcard`
2. Implement T010: add `POST /api/firewall/dnat/addRule` tasks to `playbooks/network/network-deploy.yml`
3. Run `network-deploy.yml` to apply the 443→30443 NAT rule for `fleet1.lan`
4. Mark T010 complete and close out feature 054
