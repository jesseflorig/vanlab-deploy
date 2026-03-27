# Research: Node Disk Health Check

**Feature**: 001-node-disk-health
**Date**: 2026-03-27

## Decision 1: Health Assessment Tool

**Decision**: Use `smartmontools` (`smartctl -j -A -H /dev/nvme0n1`) with JSON output.

**Rationale**: `smartctl` supports NVMe natively (v7.x+), is available in all Debian arm64
repositories, and outputs structured JSON parseable directly with Ansible's `from_json`
filter. A single tool handles the full device surface without conditional logic.

**Alternatives considered**:
- `nvme-cli` (`nvme smart-log`): More NVMe-specific but outputs plain text requiring
  regex parsing. Adds a second dependency for no gain on this hardware.

**Key health fields to evaluate** (from `nvme_smart_health_information_log`):

| Field | Threshold | Status |
|-------|-----------|--------|
| `critical_warning` | Must be 0 | CRITICAL if non-zero |
| `media_errors` | Must be 0 | CRITICAL if non-zero |
| `available_spare` | Alert if < 10 | WARNING |
| `percentage_used` | Alert if > 80 | WARNING |

---

## Decision 2: Block Device Enumeration

**Decision**: Use `lsblk -d -b -n -o NAME,SIZE,TYPE,MODEL` filtered for NVMe devices.

**Rationale**: `ansible_devices` gathered facts have a documented bug on Raspberry Pi OS
arm64 (Ansible issue #38742, #76762) — NVMe namespace data is unreliable. `lsblk` is
robust on Debian-based systems and provides name, size, and model in one call.

**Alternatives considered**:
- `ansible_devices`: Unreliable NVMe partition data on Pi kernel arm64 builds.
- `find /dev -name 'nvme*n1'`: Detects devices but no capacity metadata. Use as fallback
  only if `lsblk` is unavailable.

---

## Decision 3: Summary Report Output

**Decision**: Aggregate facts via `set_fact` on each node during the collection play; render
the report in a post-run play targeting `localhost` using `hostvars` and a Jinja2 `debug`
message block.

**Rationale**: Decouples data collection from presentation. All node facts are fully
populated in `hostvars` by the time the report play runs. No temp files needed — output
goes directly to stdout via `debug`.

**Alternatives considered**:
- Inline `debug` tasks per node: Output is scattered across the Ansible run, not consolidated.
- `template` module to file: Requires a file path and post-run `cat`; unnecessary complexity
  per Principle V.

---

## Decision 4: Playbook Exit Code Control

**Decision**: Use `any_errors_fatal: false` on the collection play to allow all nodes to
report, then assert health conditions in a final localhost play. Failed assertions produce
exit code 2.

**Rationale**: This pattern ensures all data is gathered before failure evaluation, satisfying
FR-006 (no abort mid-run) and FR-008 (non-zero exit on CRITICAL/missing).

**Alternatives considered**:
- `failed_when` per task: Only fails the individual task, not the full playbook based on
  cross-host analysis.
- `meta: end_play`: Aborts early — violates FR-006.

---

## Decision 5: smartmontools Installation

**Decision**: Install via `ansible.builtin.apt` with `state: present`, `cache_valid_time:
3600`, and `retries: 5 / delay: 10` — matching the existing pattern in `k3s-deploy.yml`.

**Rationale**: `state: present` is idempotent. `cache_valid_time` prevents redundant apt
cache updates on re-runs. Retry pattern is already established in the project and handles
Pi cluster network transients.

---

## Playbook Architecture

Two-play structure:

1. **Collection play** (`hosts: all`, `any_errors_fatal: false`)
   - Install smartmontools (prereq)
   - Enumerate block devices via `lsblk`
   - Check NVMe S.M.A.R.T. via `smartctl -j`
   - Set `node_disk_summary` fact per node

2. **Report + assert play** (`hosts: localhost`, `gather_facts: no`)
   - Render consolidated report from `hostvars`
   - Assert all nodes pass health thresholds
   - Fail playbook if any CRITICAL or MISSING conditions found
