# Data Model: Prometheus Longhorn Monitoring

**Branch**: `009-prometheus-longhorn-monitoring` | **Date**: 2026-04-01

This feature is infrastructure automation — no application data model. Relevant entities are
Kubernetes resources and Ansible variables.

## Kubernetes Resources

### Namespace

| Resource | Value |
|----------|-------|
| Name | `monitoring` |
| Purpose | Isolates all kube-prometheus-stack components |

### Persistent Volume Claims

| Name | Namespace | Size | StorageClass | Consumer |
|------|-----------|------|--------------|----------|
| `prometheus-monitoring-db` | `monitoring` | 20Gi | `longhorn` | Prometheus |
| `alertmanager-monitoring-alertmanager-db` | `monitoring` | 5Gi | `longhorn` | Alertmanager |
| `monitoring-grafana` | `monitoring` | 5Gi | `longhorn` | Grafana |

### Ingress Resources

| Hostname | Backend | Namespace |
|----------|---------|-----------|
| `grafana.fleet1.cloud` | Grafana service port 80 | `monitoring` |
| `prometheus.fleet1.cloud` | Prometheus service port 9090 | `monitoring` |

### ServiceMonitor (cross-namespace)

| Name | Namespace | Targets |
|------|-----------|---------|
| `longhorn-backend` | `longhorn-system` | Longhorn manager metrics |

Discovered by Prometheus because `serviceMonitorSelectorNilUsesHelmValues: false`
(cluster-wide ServiceMonitor discovery).

## Ansible Variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `grafana_admin_password` | `group_vars/all.yml` (secret) | Grafana admin login |
| `grafana_hostname` | `group_vars/all.yml` | Ingress hostname |
| `prometheus_hostname` | `group_vars/all.yml` | Ingress hostname |
| `monitoring_namespace` | `roles/kube-prometheus-stack/defaults/main.yml` | K8s namespace |
| `prometheus_stack_version` | `roles/kube-prometheus-stack/defaults/main.yml` | Helm chart version |
| `prometheus_storage_size` | `roles/kube-prometheus-stack/defaults/main.yml` | PVC size (default: 20Gi) |
