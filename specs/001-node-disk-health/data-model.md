# Data Model: Node Disk Health Check

**Feature**: 001-node-disk-health
**Date**: 2026-03-27

## Entities

### Node

Represents a cluster member targeted by the playbook.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `hostname` | string | `inventory_hostname` | Ansible inventory hostname |
| `reachable` | bool | Play result | False if SSH unreachable |
| `drives` | list[Drive] | Collected during run | Empty list if unreachable |
| `overall_status` | HealthStatus | Derived | Worst status across all drives |

**Validation**:
- A node with `reachable: true` and `drives: []` MUST report `overall_status: MISSING`.
- A node with `reachable: false` MUST report `overall_status: UNREACHABLE`.

---

### Drive

Represents a single NVMe block storage device on a node.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `device` | string | `lsblk` | e.g. `nvme0n1` |
| `model` | string | `lsblk` | Drive model string |
| `size_bytes` | int | `lsblk -b` | Raw bytes |
| `size_human` | string | Derived | Human-readable (e.g. `2.0T`) |
| `used_bytes` | int | `df` | Bytes in use across partitions |
| `free_bytes` | int | `df` | Bytes available |
| `use_pct` | int | `df` | Percentage used (0–100) |
| `smart_critical_warning` | int | `smartctl` JSON | 0 = no warning |
| `smart_media_errors` | int | `smartctl` JSON | 0 = no errors |
| `smart_available_spare` | int | `smartctl` JSON | Percentage (0–100) |
| `smart_percentage_used` | int | `smartctl` JSON | NVMe endurance indicator |
| `health_status` | HealthStatus | Derived | See derivation rules below |
| `smart_supported` | bool | `smartctl` result | False if drive lacks S.M.A.R.T. |

**Health status derivation rules** (evaluated in order, first match wins):

1. `smartctl` command fails or `smart_supported: false` → `UNKNOWN`
2. `smart_critical_warning != 0` OR `smart_media_errors > 0` → `CRITICAL`
3. `smart_available_spare < 10` OR `smart_percentage_used > 80` → `WARNING`
4. Otherwise → `HEALTHY`

---

### HealthStatus

Categorical enumeration of drive or node health.

| Value | Meaning |
|-------|---------|
| `HEALTHY` | All S.M.A.R.T. indicators within normal range |
| `WARNING` | Degraded indicators; monitor closely |
| `CRITICAL` | Active fault detected; immediate attention required |
| `UNKNOWN` | S.M.A.R.T. data unavailable or unreadable |
| `MISSING` | Node reachable but no drives detected |
| `UNREACHABLE` | Node did not respond to SSH |

---

### RunReport

The consolidated output produced at the end of playbook execution.

| Field | Type | Notes |
|-------|------|-------|
| `generated_at` | ISO8601 datetime | Ansible `ansible_date_time.iso8601` |
| `nodes` | list[Node] | All nodes from inventory |
| `total_nodes` | int | Count of all inventory nodes |
| `reachable_nodes` | int | Nodes that responded |
| `healthy_nodes` | int | Nodes where all drives are HEALTHY |
| `warning_nodes` | int | Nodes with at least one WARNING drive |
| `critical_nodes` | int | Nodes with at least one CRITICAL drive |
| `missing_nodes` | int | Reachable nodes with no drives detected |
| `unreachable_nodes` | int | Nodes that did not respond |
| `overall_result` | `PASS` / `FAIL` | FAIL if any CRITICAL or MISSING |

---

## Ansible Fact Schema

The `node_disk_summary` fact set on each node during the collection play:

```yaml
node_disk_summary:
  hostname: "10.1.20.11"
  reachable: true
  overall_status: "HEALTHY"          # HEALTHY | WARNING | CRITICAL | MISSING | UNKNOWN
  drives:
    - device: "nvme0n1"
      model: "WD_BLACK SN770 2TB"
      size_human: "2.0T"
      used_bytes: 42949672960
      free_bytes: 2100000000000
      use_pct: 2
      health_status: "HEALTHY"
      smart_critical_warning: 0
      smart_media_errors: 0
      smart_available_spare: 100
      smart_percentage_used: 0
      smart_supported: true
```
