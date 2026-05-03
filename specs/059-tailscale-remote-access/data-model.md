# Configuration Schema: Tailscale Remote Access

**Branch**: `059-tailscale-remote-access` | **Date**: 2026-04-30

---

## Ansible Role Variables

### `roles/tailscale` — defaults/main.yml

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `tailscale_auth_key` | string | Yes | Reusable pre-authorized auth key. Must be Vault-encrypted in `group_vars/all.yml`. |
| `tailscale_advertise_routes` | string | Conditional | Comma-separated CIDR list. Set on `servers` group; empty string for `agents`, `compute`, `nvr`. Default: `""` |
| `tailscale_accept_routes` | bool | No | Whether node accepts routes advertised by subnet routers. Default: `true` |
| `tailscale_accept_dns` | bool | No | Whether node uses Tailscale DNS. Always `false` for lab nodes (they use OPNsense). Default: `false` |

**Server nodes value** (set in playbook `host_vars` or `group_vars/servers.yml`):
```yaml
tailscale_advertise_routes: "10.1.1.0/24,10.1.10.0/24,10.1.20.0/24,10.1.30.0/24,10.1.40.0/24,10.1.50.0/24"
```

**All other nodes**: `tailscale_advertise_routes` is empty (default).

---

### `roles/device-mtls` — defaults/main.yml

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `device_mtls_ca_name` | string | No | Name for the Device CA cert-manager Certificate. Default: `device-ca` |
| `device_mtls_ca_namespace` | string | No | Namespace for CA resources. Default: `cert-manager` |
| `device_mtls_ca_secret_name` | string | No | K8s Secret name holding the Device CA cert+key. Default: `device-ca-tls` |
| `device_mtls_ca_duration` | string | No | CA certificate lifetime. Default: `87600h` (10 years) |
| `device_mtls_ca_renew_before` | string | No | CA renewal window. Default: `720h` (30 days) |
| `device_mtls_client_cert_name` | string | No | Name for the laptop client cert. Default: `laptop-client-cert` |
| `device_mtls_client_cert_duration` | string | No | Client cert lifetime. Default: `8760h` (1 year) |
| `device_mtls_client_cert_renew_before` | string | No | Client cert renewal window. Default: `720h` (30 days) |
| `device_mtls_traefik_namespace` | string | No | Namespace where TLSOption and CA public Secret are created. Default: `traefik` |
| `device_mtls_tls_option_name` | string | No | Name of the Traefik TLSOption resource. Default: `device-mtls` |
| `device_mtls_ca_public_secret_name` | string | No | Name of the Opaque Secret in Traefik namespace holding CA cert only. Default: `device-ca-public` |

---

## Kubernetes Resource Schemas

### cert-manager: Device CA Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: device-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: device-ca
  secretName: device-ca-tls
  privateKey:
    algorithm: RSA
    size: 4096
  duration: 87600h    # 10 years
  renewBefore: 720h
  issuerRef:
    name: selfsigned-issuer   # Existing ClusterIssuer from roles/pki
    kind: ClusterIssuer
```

### cert-manager: Device CA ClusterIssuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: device-ca-issuer
spec:
  ca:
    secretName: device-ca-tls
```

### cert-manager: Laptop Client Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: laptop-client-cert
  namespace: cert-manager
spec:
  commonName: management-laptop
  secretName: laptop-client-cert-tls
  usages:
    - client auth
  duration: 8760h       # 1 year
  renewBefore: 720h
  issuerRef:
    name: device-ca-issuer
    kind: ClusterIssuer
```

### Kubernetes: Device CA Public Secret (Traefik namespace)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: device-ca-public
  namespace: traefik
type: Opaque
data:
  ca.crt: <base64-encoded Device CA public cert — extracted from device-ca-tls Secret>
```

> This Secret contains ONLY the CA public certificate — no private key. Created by Ansible by extracting `.data["tls.crt"]` from `device-ca-tls` and re-encoding it.

### Traefik: TLSOption for mTLS

```yaml
apiVersion: traefik.io/v1alpha1
kind: TLSOption
metadata:
  name: device-mtls
  namespace: traefik
spec:
  clientAuth:
    secretNames:
      - device-ca-public
    clientAuthType: RequireAndVerifyClientCert
```

### Traefik: Fleet1.lan IngressRoute Pattern (with TLSOption)

Template for all fleet1.lan services:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: <service>-fleet1-lan
  namespace: <service-namespace>
spec:
  entryPoints:
    - websecure
  tls:
    options:
      name: device-mtls
      namespace: traefik
  routes:
    - match: Host(`<service>.fleet1.lan`)
      kind: Rule
      services:
        - name: <backend-service>
          port: <backend-port>
```

> **Note**: `spec.tls` does NOT specify `secretName` for fleet1.lan routes. The wildcard certificate (`fleet1-lan-wildcard-tls`) is provided via the existing Traefik TLSStore (from `roles/pki/templates/fleet1-lan-tls-store.yaml.j2`) and selected by SNI automatically. The `options` field adds mTLS client verification on top.

---

## Fleet1.lan IngressRoute Inventory

| Service | Manifest Location | Backend Service:Port | Namespace |
|---------|------------------|---------------------|-----------|
| Gitea | `manifests/gitea/fleet1-lan-ingressroute.yaml` | `gitea-http:3000` | `gitea` |
| ArgoCD | `manifests/argocd/fleet1-lan-ingressroute.yaml` | `argocd-server:443` | `argocd` |
| Grafana | `manifests/monitoring/fleet1-lan-ingressroutes.yaml` | `kube-prometheus-stack-grafana:80` | `monitoring` |
| Frigate | `manifests/frigate/fleet1-lan-ingressroute.yaml` | `frigate:5000` | `frigate` |
| Home Assistant | `manifests/home-automation/fleet1-lan-ingressroutes.yaml` | `home-assistant:8080` | `home-automation` |
| InfluxDB | `manifests/home-automation/fleet1-lan-ingressroutes.yaml` | `influxdb:8086` | `home-automation` |
| Node-RED | `manifests/home-automation/fleet1-lan-ingressroutes.yaml` | `node-red:1880` | `home-automation` |

---

## Entity Relationships

```
Tailscale Admin Console
  ├── Tailnet (Free Personal)
  │   ├── node1 (subnet router) ←── advertises 10.1.1.0/24 … 10.1.50.0/24
  │   ├── node3 (subnet router) ←── advertises 10.1.1.0/24 … 10.1.50.0/24
  │   ├── node5 (subnet router) ←── advertises 10.1.1.0/24 … 10.1.50.0/24
  │   ├── node2, node4, node6, edge, nvr-host (enrolled, no route advertising)
  │   └── management-laptop (manual install, Accept Routes + Accept DNS)
  └── DNS: fleet1.lan → 10.1.1.1 (OPNsense Unbound)

cert-manager (cluster)
  ├── selfsigned-issuer (existing ClusterIssuer)
  │   └── device-ca (new CA Certificate, isCA: true)
  │        └── device-ca-issuer (new ClusterIssuer)
  │             └── laptop-client-cert (client auth Certificate)
  │                  └── laptop-client-cert-tls (K8s Secret → exported to laptop)
  └── device-ca-tls (K8s Secret: CA cert + key → CA cert extracted to device-ca-public)

Traefik (cluster)
  ├── device-ca-public (Opaque Secret, traefik namespace: CA cert only)
  ├── device-mtls (TLSOption: RequireAndVerifyClientCert ← device-ca-public)
  └── fleet1.lan IngressRoutes → tls.options: device-mtls@traefik
```
