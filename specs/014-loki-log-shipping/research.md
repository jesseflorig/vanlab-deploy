# Research: Grafana Loki Log Aggregation

## Decision 1: Loki Helm Chart

**Decision**: Use `grafana/loki` chart v6.x (not `grafana/loki-stack`)

**Rationale**: `loki-stack` is deprecated as of 2025 and frozen at old versions. The standalone `grafana/loki` chart is actively maintained and supports all deployment modes.

**Chart**: `grafana/loki` — current stable: **6.55.0**
**Repo**: `https://grafana.github.io/helm-charts`

**Alternatives considered**:
- `grafana/loki-stack` — deprecated, bundles Grafana we don't need, rejected

---

## Decision 2: Loki Deployment Mode

**Decision**: `SingleBinary` (monolithic) mode

**Rationale**: For a 6-node homelab with low log volume, SingleBinary runs all Loki components in a single process. Simplest to operate, cheapest on ARM64 resources, and supports filesystem storage (no object storage needed). Principle V (Simplicity).

**Helm values**:
```yaml
deploymentMode: SingleBinary

singleBinary:
  replicas: 1
  persistence:
    enabled: true
    size: 20Gi
    storageClass: longhorn

# Disable multi-component replicas (used by Distributed/SimpleScalable modes)
distributor:   { replicas: 0 }
ingester:      { replicas: 0 }
querier:       { replicas: 0 }
queryFrontend: { replicas: 0 }
```

**Alternatives considered**:
- `SimpleScalable` — being deprecated; rejected
- `Distributed` — production-scale, excessive for homelab; rejected

---

## Decision 3: Log Shipper — Grafana Alloy (not Promtail)

**Decision**: Use `grafana/alloy` chart (not Promtail)

**Rationale**: Promtail reached EOL February 28, 2026. Using it now means immediate technical debt with no upstream support. Grafana Alloy is the official successor, actively maintained, and supports the same pod log and journald scraping. Alloy uses more CPU (~10x vs Promtail), but on CM5 64GB nodes this is not a concern.

**Chart**: `grafana/alloy` — current stable: **0.12.x**
**Repo**: `https://grafana.github.io/helm-charts`

**Alloy config approach**: Alloy uses a declarative River/HCL config file. Key components for this use case:
- `discovery.kubernetes` — discover pods via API
- `loki.source.kubernetes` — tail container logs from discovered pods
- `loki.source.journal` — tail journald for node-level system logs
- `loki.write` — push to Loki endpoint

**Alternatives considered**:
- `grafana/promtail` — EOL as of Feb 2026; rejected
- `grafana/loki-stack` (bundled Promtail) — same EOL issue; rejected

---

## Decision 4: K3s Log Paths for Alloy

**Decision**: Mount `/var/log/pods` for pod logs, `/run/log/journal` + `/etc/machine-id` for journald

**K3s-specific paths** (containerd runtime):
- Pod logs: `/var/log/pods/` (standard Kubernetes path, works on K3s)
- Journald: `/run/log/journal/` (volatile) and `/var/log/journal/` (persistent if configured)
- Machine ID: `/etc/machine-id` (required by journald scraper)

**Alloy requires**:
- `hostPath` volume mounts for log directories
- `privileged: false` is fine; needs `readOnly` host mounts
- Tolerations to run on server/control-plane nodes

---

## Decision 5: Loki Storage Backend

**Decision**: Filesystem backend with Longhorn PVC (20Gi)

**Rationale**: For SingleBinary mode with 7-day retention at homelab log volumes, filesystem storage with a Longhorn PVC is the simplest approach. Longhorn provides replica storage across nodes (Principle VIII). No S3/MinIO complexity needed.

**Helm values**:
```yaml
loki:
  storage:
    type: filesystem
  storageConfig:
    filesystem:
      directory: /var/loki/chunks

singleBinary:
  persistence:
    enabled: true
    size: 20Gi
    storageClass: longhorn
```

**Alternatives considered**:
- MinIO object storage — adds another service dependency; overkill for homelab; rejected
- `local-path` StorageClass — not replicated, lost on node failure; rejected (Principle VIII)

---

## Decision 6: Grafana Datasource Integration

**Decision**: Add Loki as `additionalDataSources` in the existing kube-prometheus-stack Helm values

**Rationale**: The cluster already has Grafana from kube-prometheus-stack. Adding Loki as an additional datasource via the chart values keeps it declarative and idempotent (Principle II).

**Helm values addition to kube-prometheus-stack**:
```yaml
grafana:
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki.monitoring.svc.cluster.local:3100
      access: proxy
      isDefault: false
      jsonData:
        maxLines: 1000
```

**Service DNS**: Loki will be deployed to the `monitoring` namespace (same as kube-prometheus-stack), so the cluster-local URL is `http://loki.monitoring.svc.cluster.local:3100`.

**Note**: Grafana datasources configured via Helm values are provisioned as ConfigMaps and loaded automatically on pod start. No manual restart needed unless the pod was already running with a stale config.

---

## Decision 7: Log Retention

**Decision**: 7-day default (168h), configurable via Ansible variable

**Implementation**: Loki compactor handles retention. Must be enabled explicitly.

**Helm values**:
```yaml
loki:
  limits_config:
    retention_period: 168h
  compactor:
    retention_enabled: true
    delete_request_store: filesystem
    working_directory: /var/loki/retention
```

**Note**: Retention requires index period of 24h (the default). Changes are not retroactive to existing chunks.

---

## Deployment Order

Loki must deploy before Alloy (Alloy needs the Loki endpoint to push to). Both deploy after kube-prometheus-stack (shared `monitoring` namespace + Grafana datasource update happens in the same playbook run).

```
kube-prometheus-stack → loki → alloy
```
