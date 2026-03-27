# Implementation Plan: Node Disk Health Check

**Branch**: `001-node-disk-health` | **Date**: 2026-03-27 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-node-disk-health/spec.md`

## Summary

Add an Ansible playbook (`disk-health.yml`) that enumerates NVMe drives on all cluster nodes,
collects S.M.A.R.T. health data and capacity metrics, and produces a consolidated human-readable
report. The playbook exits non-zero if any drive is CRITICAL or any expected drive is missing,
enabling use in automated monitoring pipelines.

## Technical Context

**Language/Version**: YAML (Ansible 2.x) — follows existing project conventions
**Primary Dependencies**: `smartmontools` (apt) — installed idempotently by the playbook as a
prereq task; `lsblk` and `df` — standard utilities present on Raspberry Pi OS
**Storage**: N/A — read-only diagnostic; no persistent state
**Testing**: Manual re-run verification (idempotency); live cluster smoke test
**Target Platform**: Raspberry Pi OS arm64 (Debian-based), K3s cluster nodes on `10.1.20.x`
**Project Type**: ansible-playbook (diagnostic/utility)
**Performance Goals**: Full 6-node report in under 2 minutes (SC-001)
**Constraints**: Read-only — MUST NOT modify node state; MUST tolerate unreachable nodes
**Scale/Scope**: 6-node cluster (4 Pi5 currently, expandable)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Infrastructure as Code | ✅ PASS | Playbook is IaC; no manual steps |
| II. Idempotency | ✅ PASS | Read-only playbook; `smartmontools` installed with `state: present` |
| III. Reproducibility | ✅ PASS | Single playbook at repo root; covered by existing README pattern |
| IV. Secrets Hygiene | ✅ PASS | No secrets involved; read-only host inspection |
| V. Simplicity | ✅ PASS | Standard Linux tools (`lsblk`, `smartctl`), flat role, no custom modules |
| VI. Encryption in Transit | N/A | Local SSH inspection only; no cross-VLAN data flow |
| VII. Least Privilege | N/A | No new network access; read-only ops on cluster VLAN nodes |

**Post-design re-check**: All gates still pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/001-node-disk-health/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks — not created here)
```

### Source Code (repository root)

```text
disk-health.yml          # New diagnostic playbook
roles/
└── disk-health/
    └── tasks/
        └── main.yml     # Drive enumeration, S.M.A.R.T. check, fact setting
```

**Structure Decision**: Flat single-playbook structure at repo root, consistent with
`check_hosts.yml`, `k3s-deploy.yml`, and `services-deploy.yml`. Role encapsulates the
per-node tasks; the playbook wires together the collection play and the report/assert play.

## Implementation Notes

### Two-Play Architecture

**Play 1** — `hosts: all`, `any_errors_fatal: false`
- Prereq: install `smartmontools` via `apt` (idempotent)
- Enumerate block devices: `lsblk -d -b -n -o NAME,SIZE,TYPE,MODEL`, filter for `nvme`
- Collect capacity: `df -B1` on NVMe mount points
- Collect S.M.A.R.T.: `smartctl -j -A -H /dev/{{ device }}`, parse JSON with `from_json`
- Derive `health_status` per drive per rules in `data-model.md`
- Set `node_disk_summary` fact (schema in `data-model.md`)

**Play 2** — `hosts: localhost`, `gather_facts: no`
- Render report to stdout via `debug` using Jinja2 loop over `hostvars`
- Assert all nodes pass health thresholds (CRITICAL = 0, MISSING = 0)
- Fail playbook with exit code 2 if any assertion fails

### Key Design Decisions (from research.md)

- Use `smartctl -j` not `nvme-cli` — JSON output, single dependency, unified device support
- Use `lsblk -d` not `ansible_devices` — avoids known NVMe enumeration bugs on Pi arm64
- `any_errors_fatal: false` on collection play — ensures full data gathered before asserting
- `smartmontools` install mirrors `k3s-deploy.yml` pattern: `retries: 5`, `delay: 10`,
  `cache_valid_time: 3600`
