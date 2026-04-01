# Research: Prometheus Longhorn Monitoring

**Branch**: `009-prometheus-longhorn-monitoring` | **Date**: 2026-04-01

## Decision 1: Helm Chart and Repository

**Decision**: Use `prometheus-community/kube-prometheus-stack` from `https://prometheus-community.github.io/helm-charts`.

**Rationale**: Single chart deploys Prometheus Operator, Prometheus, Alertmanager, Grafana, node-exporter, and kube-state-metrics. The stack is pre-wired — ServiceMonitors are automatically discovered and Grafana is pre-configured with a Prometheus datasource. Alternative (deploying each component separately) adds significant integration complexity for no homelab benefit (Principle V).

---

## Decision 2: K3s-Specific Scraper Disables

**Decision**: Disable `kubeControllerManager`, `kubeScheduler`, `kubeEtcd`, and `kubeProxy` in Helm values.

**Rationale**: K3s embeds these control-plane components in the kubelet process — they don't expose the standard metrics endpoints that kube-prometheus-stack expects. Leaving them enabled causes permanent scrape failures and alert noise. `kubeEtcd` is also disabled because K3s manages etcd internally and doesn't expose the etcd metrics endpoint on the standard port.

**What remains enabled**: `kubelet`, `kube-state-metrics`, `node-exporter`, `coreDNS`, `apiserver` — all function normally under K3s.

---

## Decision 3: ServiceMonitor Discovery

**Decision**: Set `serviceMonitorSelectorNilUsesHelmValues: false` on Prometheus so it discovers ALL ServiceMonitors cluster-wide (not just those matching the Helm release label).

**Rationale**: Longhorn's ServiceMonitor lives in `longhorn-system`, not in the `monitoring` namespace. Setting this to `false` means Prometheus watches all namespaces for ServiceMonitors regardless of labels, which is the simplest approach for a homelab. In production you'd scope this more tightly, but Principle V applies here.

**Longhorn ServiceMonitor**: Enabled via `monitoring.enabled: true` in the Longhorn Helm values (already in the role's values template — needs verification and the flag added if absent).

---

## Decision 4: Grafana Dashboard Provisioning

**Decision**: Provision the Longhorn dashboard (ID 13032) using Grafana's `dashboards` values key, which uses the Grafana sidecar to fetch from the internet at deploy time.

**Rationale**: Avoids embedding a large JSON blob in the repo. Grafana's built-in dashboard provisioning via `grafana.dashboards.<folder>.<name>.gnetId` fetches from grafana.com automatically. No ConfigMap, no manual import, no stored JSON.

```yaml
grafana:
  dashboards:
    default:
      longhorn:
        gnetId: 13032
        revision: 6
        datasource: Prometheus
```

**Alternative considered**: ConfigMap with embedded JSON — rejected because it requires keeping the JSON in sync with upstream and adds ~100KB to the repo.

---

## Decision 5: Storage Sizing

**Decision**: Prometheus: `20Gi`, Grafana: `5Gi`, Alertmanager: `5Gi`. All use `storageClassName: longhorn`.

**Rationale**: 20Gi covers ~2 weeks of homelab metrics (4 nodes, ~5000 series, 15s scrape interval). Grafana and Alertmanager are small. All use Longhorn for Principle VIII compliance.

---

## Decision 6: Ingress

**Decision**: Grafana at `grafana.fleet1.cloud`, Prometheus at `prometheus.fleet1.cloud`. Both via Traefik with TLS annotations (wildcard cert already in place).

**Rationale**: Follows the established `<service>.fleet1.cloud` pattern. Alertmanager does not get a public ingress in this feature (no alert rules configured yet).

---

## Decision 7: Role Structure

**Decision**: Single new role `kube-prometheus-stack` in `roles/`. No separate role for dashboards.

**Rationale**: The dashboard is provisioned via Helm values (not a separate resource), so no separate role is needed. Principle V — simplest adequate structure.

**Role added to `services-deploy.yml`** before `traefik` with tag `monitoring`:
```yaml
- role: kube-prometheus-stack
  tags: [monitoring]
```

Placed before traefik so the monitoring namespace exists before any traefik-dependent resources, but after longhorn (Prometheus needs storage).

---

## Decision 8: Longhorn ServiceMonitor Values Update

**Decision**: Add `monitoring.enabled: true` to the Longhorn Helm values template if not already present.

**Rationale**: The Longhorn chart includes a ServiceMonitor but it is disabled by default. Enabling it here is the correct approach — no separate manifest needed.

---

## Helm Values Summary

```yaml
# kube-prometheus-stack values for K3s arm64
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 20Gi

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 5Gi

grafana:
  adminPassword: "{{ grafana_admin_password }}"
  persistence:
    enabled: true
    storageClassName: longhorn
    size: 5Gi
  ingress:
    enabled: true
    ingressClassName: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      traefik.ingress.kubernetes.io/router.tls: "true"
    hosts:
      - "{{ grafana_hostname }}"
  dashboards:
    default:
      longhorn:
        gnetId: 13032
        revision: 6
        datasource: Prometheus
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: default
          orgId: 1
          folder: ""
          type: file
          disableDeletion: false
          options:
            path: /var/lib/grafana/dashboards/default

# Disable K3s unavailable control-plane scrapers
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeEtcd:
  enabled: false
kubeProxy:
  enabled: false

# Prometheus ingress (basic auth not configured — behind Cloudflare Access)
prometheus:
  ingress:
    enabled: true
    ingressClassName: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      traefik.ingress.kubernetes.io/router.tls: "true"
    hosts:
      - "{{ prometheus_hostname }}"
```
