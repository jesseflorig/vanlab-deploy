# Research: OPNsense Metrics Collection

## Exporter Selection

**Decision**: AthennaMind/opnsense-exporter v0.0.14
**Rationale**: Only actively-maintained Go exporter that covers the full OPNsense REST API surface (interfaces, gateways, firewall, protocols, services, VPN, firmware, ARP, DNS). Last release March 13 2026. Apache-2.0. ~240 GitHub stars.
**Alternatives considered**:
- `d3m0nz/opnsense_exporter` — Python, abandoned
- `cairijun/prometheus_opnsense_exporter` — Go, minimal docs/maintenance
- `tyriis/opnsense-exporter` — TypeScript/NestJS, only covers DHCP leases
- OPNsense built-in `os-node-exporter` plugin — standard node_exporter on port 9100; no OPNsense-specific data (firewall, gateways, VPN); complementary not primary

**Container image**: `ghcr.io/athennamind/opnsense-exporter:0.0.14`
**Metrics port**: `8080`
**Upstream k8s manifests**: `deploy/k8s/` (Deployment + ScrapeConfig) — no Helm chart; will write our own manifests

---

## Helm Chart

**Decision**: None (write plain Kubernetes manifests)
**Rationale**: No upstream Helm chart exists on ArtifactHub or in the repo. The exporter is a single stateless Deployment + Service + ScrapeConfig — simple enough to manage as raw manifests. A custom Helm chart would add complexity with no benefit (Principle V).

---

## Grafana Dashboard

**Decision**: gnetId `21113` (OPNSense Exporter — official companion dashboard)
**Rationale**: Built specifically for the AthennaMind exporter; most current (matched to current metric names). Provisioned via kube-prometheus-stack Helm values alongside the existing Longhorn dashboard (gnetId 13032).
**Alternatives considered**:
- gnetId 19366 — generic, not tuned to AthennaMind metric labels
- gnetId 22569 — public variant, less complete
- gnetId 17547 — requires Loki syslog shipping from OPNsense (separate feature)

---

## OPNsense Authentication

**Decision**: HTTP Basic Auth with API key:secret pair (standard OPNsense API auth)
**Rationale**: Only authentication method supported by the OPNsense REST API. No token or OAuth alternative exists.

**How to generate**:
1. OPNsense WebUI → System → Access → Users → select/create dedicated user
2. Scroll to "API keys" section → click `+`
3. Download the one-time `.txt` file containing `key=` and `secret=`
4. The secret is shown only once — store immediately in `group_vars/all.yml`

**Required ACL permissions** for the API user (grant in User edit → Privileges):
- Diagnostics: ARP Table, Firewall statistics, Netstat
- Status: Services, System Status, Gateways, VPN: WireGuard, OpenVPN Instances
- System: Firmware, Cron, DNS resolver (Unbound)

**Env vars** (injected via SealedSecret):
```
OPNSENSE_EXPORTER_OPS_API_KEY=<key>
OPNSENSE_EXPORTER_OPS_API_SECRET=<secret>
OPNSENSE_EXPORTER_OPS_HOST=10.1.1.1
OPNSENSE_EXPORTER_OPS_PROTOCOL=https
OPNSENSE_EXPORTER_OPS_INSECURE=true
```

**TLS note**: OPNsense uses a self-signed certificate by default; `OPNSENSE_EXPORTER_OPS_INSECURE=true` skips verification. The REST API call goes pod → OPNsense management IP (private network, not crossing public internet) so TLS verification skip is acceptable.

**Unbound DNS metrics**: Requires enabling "Extended statistics" in OPNsense: Services → Unbound DNS → Advanced → Extended statistics: ✓

---

## Key Metrics Exposed

| Category | Example metrics |
|---|---|
| Interfaces | bytes_total (in/out), input/output_errors_total, mtu_bytes — per interface label |
| Gateways | status (1=up), loss_percentage, rtt_milliseconds, rttd_milliseconds |
| Firewall (pf) | in/out ipv4/ipv6 pass/block packets; firewall_status |
| Protocols | tcp_connection_count_by_state (ESTABLISHED, TIME_WAIT…), sent/received_packets_total; udp, icmp variants |
| Services | running_total, stopped_total, status per service name |
| VPN | WireGuard peer bytes/handshake; IPsec phase1/phase2 bytes/rekey; OpenVPN instances |
| Firmware | os_version, needs_reboot, new_packages |
| ARP | arp_table_entries (labeled: ip, mac, hostname, interface) |
| DNS | unbound_dns_uptime_seconds (requires extended stats enabled) |

**Known gap**: No `pf_states` (active connection table entry count) — only pf packet counters. State table exhaustion monitoring not possible with this exporter currently.

---

## Prometheus Scrape Integration

**Decision**: Use `ScrapeConfig` CRD (`monitoring.coreos.com/v1alpha1`)
**Rationale**: kube-prometheus-stack already includes the Prometheus Operator CRDs; `ScrapeConfig` is available and is the operator-native way to add scrape targets without editing Helm values. The exporter's upstream `deploy/k8s/scrape.yaml` uses this CRD directly.
**Alternative considered**: Adding a `additionalScrapeConfigs` entry to kube-prometheus-stack Helm values — works but requires Ansible re-run to change any scrape config; ScrapeConfig CRD is more GitOps-friendly.

No changes to `roles/kube-prometheus-stack/templates/values.yaml.j2` are needed for scraping. Only the Grafana dashboard entry (gnetId 21113) needs to be added to the Helm values.

---

## Network Reachability

**Decision**: Exporter pod reaches OPNsense REST API at `https://10.1.1.1` from cluster VLAN `10.1.20.x`
**Rationale**: OPNsense is the default gateway for `10.1.20.x`; traffic from cluster pods destined for `10.1.1.1` routes to OPNsense itself. OPNsense's "Anti-lockout" rule and typical LAN→firewall rules allow HTTPS access to the management interface from trusted VLANs. A dedicated firewall rule may be needed to explicitly permit `10.1.20.0/24 → 10.1.1.1:443` if not already present — this should be verified and codified as an Ansible task using `community.opnsense`.

---

## Deployment Pattern

**Decision**: Plain Kubernetes manifests under `manifests/monitoring/`, ArgoCD-managed
**Rationale**: Exporter is a single stateless Deployment + Service — no Helm chart overhead needed. Consistent with `manifests/redirects/` and `manifests/static-site/` patterns in the repo. SealedSecret for API credentials follows Principle IV.

```
manifests/monitoring/
├── prereqs/
│   ├── namespace.yaml        (sync wave 0 — idempotent; monitoring ns already exists)
│   └── sealed-secrets.yaml   (sync wave 1 — generated by seal-secrets.yml)
└── exporter/
    ├── deployment.yaml       (AthennaMind exporter + env from Secret)
    ├── service.yaml          (ClusterIP on port 8080)
    └── scrapeconfig.yaml     (ScrapeConfig targeting the Service)
```

Two ArgoCD Applications registered in `argocd_apps`:
- `monitoring-prereqs` → `manifests/monitoring/prereqs`
- `monitoring-apps` → `manifests/monitoring/exporter`
