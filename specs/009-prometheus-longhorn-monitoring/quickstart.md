# Quickstart: Prometheus Longhorn Monitoring

**Branch**: `009-prometheus-longhorn-monitoring` | **Date**: 2026-04-01

## Prerequisites

- Longhorn is deployed and healthy (`kubectl get pods -n longhorn-system`)
- Traefik is deployed with wildcard TLS cert in `traefik` namespace
- `group_vars/all.yml` contains `grafana_admin_password`, `grafana_hostname`, `prometheus_hostname`

## Deploy

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags monitoring
```

First deploy takes ~3–5 minutes (Helm chart pull + PVC provisioning + pod startup).

## Verify

```bash
# All monitoring pods running
ansible node1 -i hosts.ini -m shell -a "kubectl get pods -n monitoring" --become

# Prometheus targets (check for UP status)
# Open https://prometheus.fleet1.cloud/targets

# Grafana
# Open https://grafana.fleet1.cloud — log in with grafana_admin_password
```

## Access Dashboards

1. Open `https://grafana.fleet1.cloud`
2. Log in with username `admin` and the password from `group_vars/all.yml`
3. Navigate to Dashboards → Default → Longhorn (provisioned automatically)

## Re-run (idempotent)

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags monitoring
```

Safe to re-run — Helm upgrade is a no-op if values are unchanged.

## Longhorn ServiceMonitor

The Longhorn ServiceMonitor is enabled via the Longhorn Helm values (`monitoring.enabled: true`).
Prometheus discovers it automatically via cluster-wide ServiceMonitor scanning. No manual
configuration required after initial deploy.

## DNS

Add `grafana.fleet1.cloud` and `prometheus.fleet1.cloud` to your Cloudflare DNS if not already
covered by the wildcard CNAME (`*.fleet1.cloud → tunnel`).
