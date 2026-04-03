# Data Model: Home Automation Stack

**Phase**: 1 — Design
**Branch**: `016-home-automation-stack`
**Date**: 2026-04-02

---

## Services & Storage

### Mosquitto

| Entity | Details |
|--------|---------|
| Namespace | `home-automation` |
| Helm chart | `helmforgedev/mosquitto` @ `https://helmforgedev.github.io/charts/` |
| Image | `eclipse-mosquitto:2.0.22` (arm64 native) |
| PVC | `mosquitto-data`, 1Gi, `storageClass: longhorn` |
| Ports | 8883 (MQTTS only; 1883 disabled) |
| TLS Secret | `mosquitto-tls` — cert-manager Certificate; `dnsNames: [mqtt.fleet1.cloud]`; issuerRef: `letsencrypt-prod` ClusterIssuer |
| Client CA Secret | `mosquitto-client-ca` — cert-manager Certificate; issuerRef: `home-automation-ca` (internal SelfSigned CA) |
| Password file | `mosquitto-passwords` K8s Secret; key `passwordfile`; hashed with `mosquitto_passwd` |
| Reloader | `stakater/Reloader` watches `mosquitto-tls` Secret; triggers rolling restart on change |

**mosquitto.conf key settings**:
```
listener 8883
cafile /certs/ca.crt
certfile /certs/tls.crt
keyfile /certs/tls.key
require_certificate true
use_identity_as_username true
password_file /mosquitto/passwd/passwordfile
```

---

### Home Assistant

| Entity | Details |
|--------|---------|
| Namespace | `home-automation` |
| Helm chart | `pajikos/home-assistant` @ `http://pajikos.github.io/home-assistant-helm-chart/` |
| Image | `ghcr.io/home-assistant/home-assistant:latest` (arm64 native) |
| PVC | `home-assistant-config`, 10Gi, `storageClass: longhorn` |
| External hostname | `hass.fleet1.cloud` (Traefik HTTPS) |
| Ingress | Standard `networking.k8s.io/v1` Ingress with Traefik annotations + `fleet1-cloud-tls` Secret |
| Config injection | ConfigMap `home-assistant-config-extra` mounted at `/config/packages/` containing `configuration.yaml` fragments |

**configuration.yaml additions** (via ConfigMap):
```yaml
# http.yaml — Traefik reverse proxy trust
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 10.42.0.0/16   # K3s pod CIDR

# influxdb2.yaml — InfluxDB long-term storage
influxdb2:
  host: influxdb.home-automation.svc.cluster.local
  port: 8086
  token: !secret influxdb_token
  organization: !secret influxdb_org_id
  bucket: homeassistant
```

**secrets.yaml** (on PVC, written by Ansible on first deploy — not committed):
```yaml
influxdb_token: <INFLUXDB_TOKEN>
influxdb_org_id: <INFLUXDB_ORG_ID_HEX>
```

---

### InfluxDB

| Entity | Details |
|--------|---------|
| Namespace | `home-automation` |
| Helm chart | `influxdata/influxdb2` @ `https://helm.influxdata.com/` |
| Image | `influxdb:2.7.4-alpine` (arm64 native) |
| PVC | `influxdb-data`, 20Gi, `storageClass: longhorn` |
| External hostname | `influxdb.fleet1.cloud` (Traefik HTTPS) |
| Ingress | Standard `networking.k8s.io/v1` Ingress with Traefik annotations |
| Credentials Secret | `influxdb-auth` K8s Secret; keys: `admin-password`, `admin-token` |
| Chart values | `adminUser.existingSecret: influxdb-auth` |
| Default bucket | `homeassistant` (created by chart init container) |
| Default org | `vanlab` |

---

### Node-RED

| Entity | Details |
|--------|---------|
| Namespace | `home-automation` |
| Helm chart | `schwarzit/node-red` @ `https://schwarzit.github.io/node-red-chart/` |
| Image | `nodered/node-red:4.1.2` (arm64 native) |
| PVC | `node-red-data`, 5Gi, `storageClass: longhorn` |
| External hostname | `node-red.fleet1.cloud` (Traefik HTTPS) |
| Ingress | Standard `networking.k8s.io/v1` Ingress with Traefik annotations |
| Admin auth | `settings.js` via ConfigMap; bcrypt-hashed password from `group_vars/all.yml` |
| MQTT client cert | `node-red-mqtt-client` K8s Secret; cert-manager Certificate (issuerRef: `home-automation-ca`); CN: `node-red` |

---

## cert-manager Resources

### Internal CA Issuer

```yaml
# SelfSigned bootstrap issuer → issues the CA cert
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer

# CA Certificate (stored as Secret in cert-manager ns)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: home-automation-ca
  namespace: cert-manager
spec:
  isCA: true
  secretName: home-automation-ca-secret
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer

# CA-backed issuer for client cert issuance
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: home-automation-ca
spec:
  ca:
    secretName: home-automation-ca-secret
```

### Mosquitto Server Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: mosquitto-tls
  namespace: home-automation
spec:
  secretName: mosquitto-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - mqtt.fleet1.cloud
```

### Node-RED Client Certificate (for Mosquitto mTLS)

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: node-red-mqtt-client
  namespace: home-automation
spec:
  secretName: node-red-mqtt-client
  issuerRef:
    name: home-automation-ca
    kind: ClusterIssuer
  commonName: node-red
  usages:
    - client auth
```

### Home Assistant Client Certificate (for Mosquitto mTLS)

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: home-assistant-mqtt-client
  namespace: home-automation
spec:
  secretName: home-assistant-mqtt-client
  issuerRef:
    name: home-automation-ca
    kind: ClusterIssuer
  commonName: home-assistant
  usages:
    - client auth
```

---

## Network Topology

```
External clients (IoT, cameras)
        |
        | MQTTS :8883 (TLS passthrough)
        v
   Traefik IngressRouteTCP
   HostSNI('mqtt.fleet1.cloud')
        |
        v
   Mosquitto :8883
   (terminates TLS, validates client cert)
        |
   +----+-------+
   |            |
   v            v
Home          Node-RED
Assistant     (in-cluster)
(in-cluster)
   |            |
   +----+-------+
        |
        v HTTP :8086
    InfluxDB
   (in-cluster)
        |
        v
     Grafana
   (existing, monitoring ns)
```

**In-cluster DNS names** (all within `home-automation` namespace):
- `mosquitto.home-automation.svc.cluster.local:8883`
- `home-assistant.home-automation.svc.cluster.local:8123`
- `influxdb.home-automation.svc.cluster.local:8086`
- `node-red.home-automation.svc.cluster.local:1880`

---

## Traefik Changes Required

The existing `roles/traefik/files/values.yaml` must have a new `mqtts` entrypoint added:

```yaml
# Add to ports: section
ports:
  # ... existing web, websecure ...
  mqtts:
    port: 8443        # internal container port (Traefik)
    exposedPort: 8883
    protocol: TCP
    nodePort: 30883
```

And the IngressRouteTCP for Mosquitto:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: mosquitto-mqtts
  namespace: home-automation
spec:
  entryPoints:
    - mqtts
  routes:
    - match: HostSNI(`mqtt.fleet1.cloud`)
      services:
        - name: mosquitto
          port: 8883
  tls:
    passthrough: true   # Mosquitto handles TLS/mTLS termination
```

---

## Secrets in group_vars/all.yml (new entries)

```yaml
# Home Automation Stack (used by services-deploy.yml → home-automation roles)

# InfluxDB credentials
influxdb_admin_password: <INFLUXDB_ADMIN_PASSWORD>
influxdb_admin_token: <INFLUXDB_ADMIN_TOKEN>   # used by HA integration
influxdb_org_id: <INFLUXDB_ORG_ID_HEX>         # hex UUID from InfluxDB UI URL

# Mosquitto password file entry (format: username:hashed_password)
# Generate with: mosquitto_passwd -b /dev/stdout <username> <password>
mosquitto_password_entry: <USERNAME:HASHED_PASSWORD>

# Node-RED admin password (bcrypt hash)
# Generate with: node -e "require('bcryptjs').hash('<password>', 8, (e,h) => console.log(h))"
node_red_admin_password_bcrypt: <BCRYPT_HASH>

# Home Assistant (no K8s secrets at deploy time — onboarding sets first admin user)
# InfluxDB token is written to HA's secrets.yaml on the PVC by Ansible
```

---

## Ansible Roles Structure

```
roles/
├── mosquitto/
│   ├── defaults/main.yml          # mosquitto_namespace, chart versions, PVC size
│   ├── tasks/main.yml             # helm repo, namespace, CA issuer, certs, secrets, helm install, IngressRouteTCP
│   └── templates/
│       ├── values.yaml.j2         # Helm values (TLS config, persistence, Reloader annotation)
│       ├── ca-issuer.yaml.j2      # SelfSigned ClusterIssuer + home-automation-ca
│       ├── server-cert.yaml.j2    # mosquitto-tls Certificate (Let's Encrypt)
│       ├── client-cert.yaml.j2    # parameterized client cert template
│       └── ingress-route-tcp.yaml.j2  # IngressRouteTCP for port 8883
├── influxdb/
│   ├── defaults/main.yml          # influxdb_namespace, chart version, PVC size, org, bucket
│   ├── tasks/main.yml             # helm repo, namespace, secret, helm install, wait
│   └── templates/
│       └── values.yaml.j2
├── home-assistant/
│   ├── defaults/main.yml          # ha_namespace, chart version, PVC size, hostname
│   ├── tasks/main.yml             # helm repo, namespace, client cert, configmap, secrets.yaml, helm install, ingress
│   └── templates/
│       ├── values.yaml.j2
│       ├── config-extra.yaml.j2   # ConfigMap with http.yaml + influxdb2.yaml fragments
│       └── ha-secrets.yaml.j2     # Task template to write HA secrets.yaml to PVC (post-install)
└── node-red/
    ├── defaults/main.yml           # nodered_namespace, chart version, PVC size, hostname
    ├── tasks/main.yml              # helm repo, namespace, client cert, admin secret, helm install, ingress
    └── templates/
        └── values.yaml.j2
```

---

## Playbook Integration

In `playbooks/cluster/services-deploy.yml`, add after `loki` and before `traefik`:

```yaml
    - role: mosquitto
      tags: [home-automation, mosquitto]
    - role: influxdb
      tags: [home-automation, influxdb]
    - role: home-assistant
      tags: [home-automation, hass]
    - role: node-red
      tags: [home-automation, node-red]
```

**Note**: `mosquitto` must be deployed before `home-assistant` and `node-red` because those roles create client certificates referencing the `home-automation-ca` ClusterIssuer created by the `mosquitto` role.

**Also required**: Update `roles/traefik/files/values.yaml` to add the `mqtts` entrypoint (port 8883) before deploying Mosquitto's IngressRouteTCP.
