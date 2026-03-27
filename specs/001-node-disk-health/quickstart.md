# Quickstart: Node Disk Health Check

## Prerequisites

- Ansible installed on your control machine
- `hosts.ini` configured with cluster nodes
- SSH access to all nodes

## Run

Check disk health across all nodes:

```bash
ansible-playbook -i hosts.ini disk-health.yml
```

Check a specific node or group:

```bash
ansible-playbook -i hosts.ini disk-health.yml --limit masters
ansible-playbook -i hosts.ini disk-health.yml --limit 10.1.20.11
```

## Output

The playbook prints a summary report to stdout at the end of the run:

```
================================================================================
VANLAB DISK HEALTH REPORT — 2026-03-27T14:00:00Z
================================================================================

NODE: 10.1.20.11
  nvme0n1  WD_BLACK SN770 2TB  2.0T  2% used  [HEALTHY]

NODE: 10.1.20.12
  nvme0n1  WD_BLACK SN770 2TB  2.0T  1% used  [HEALTHY]

NODE: 10.1.20.13  [UNREACHABLE]

================================================================================
SUMMARY  total=6  healthy=5  warning=0  critical=0  missing=0  unreachable=1
RESULT: FAIL (1 unreachable node)
================================================================================
```

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | All reachable nodes have healthy drives |
| `2` | One or more nodes have CRITICAL, MISSING, or UNREACHABLE status |

## Integrate with Monitoring

The non-zero exit code on failure makes this playbook suitable for cron or CI pipelines:

```bash
ansible-playbook -i hosts.ini disk-health.yml || notify-admin "Disk health check failed"
```
