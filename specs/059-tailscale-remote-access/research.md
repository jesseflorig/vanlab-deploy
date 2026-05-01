# Research: Tailscale Remote Access for fleet1.lan

**Branch**: `059-tailscale-remote-access` | **Date**: 2026-04-30

---

## 1. Tailscale Package Availability (arm64 / Raspberry Pi OS)

**Decision**: Use the official Tailscale apt repository (`packages.tailscale.com/stable/debian`).

**Rationale**: Tailscale publishes official arm64 (aarch64) Debian packages. The install procedure is a standard apt repo + GPG key setup, identical to x86 but using the `arm64` package variant. No third-party repos or manual binary downloads required.

**Key install steps for Ansible**:
```bash
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian bookworm main" | tee /etc/apt/sources.list.d/tailscale.list
apt-get update && apt-get install -y tailscale
```

**Alternatives considered**: Snap package (not standard on Raspberry Pi OS), Nix/manual binary (violates Principle V simplicity).

---

## 2. Tailscale Enrollment and Idempotency

**Decision**: Check `tailscale status --json | jq -r '.BackendState'` before enrolling. If `"Running"` and the tailnet matches, skip `tailscale up`. Use `tailscale up` only on first enroll or if state is `"NeedsLogin"`.

**Rationale**: `tailscale up` is not idempotent by default — re-running it with an auth key re-authenticates the node, which can cause tailnet admin console churn and is a no-op at best. A status check gate makes the role safe to re-run.

**Idempotency pattern**:
```bash
BACKEND=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "NeedsLogin"')
if [ "$BACKEND" != "Running" ]; then
  tailscale up --auth-key="{{ tailscale_auth_key }}" --advertise-routes="..." --accept-dns=false
fi
```

**Note**: `--accept-dns=false` is required on all nodes. Nodes use OPNsense Unbound for DNS; Tailscale's split-DNS should not override system DNS on the nodes themselves (only on the management laptop).

**Alternatives considered**: Always running `tailscale up --auth-key=...` (causes spurious admin console re-registration), using `tailscale login --authkey` instead of `tailscale up` (deprecated in favor of `tailscale up`).

---

## 3. Subnet Routing Configuration

**Decision**: Server nodes (`node1`, `node3`, `node5`) run with `--advertise-routes`. Agent and compute/nvr nodes do NOT advertise routes. All nodes use `--accept-routes=true` so that Tailscale's routing table is populated even on non-advertising nodes (enables future Tailscale SSH if desired).

**Advertised subnets** (all six lab subnets):
```
10.1.1.0/24,10.1.10.0/24,10.1.20.0/24,10.1.30.0/24,10.1.40.0/24,10.1.50.0/24
```

**IP forwarding**: Must be enabled before `tailscale up` on subnet router nodes:
```bash
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.d/99-tailscale.conf
sysctl -p /etc/sysctl.d/99-tailscale.conf
```

**Admin console manual step**: Advertised routes must be approved in the Tailscale admin console (`https://login.tailscale.com/admin/machines`) for each server node. This cannot be automated without a Tailscale OAuth client (out of scope for v1). Document as a post-deployment manual step.

**Alternatives considered**: Using only one subnet router (rejected: single point of failure), using all 6 nodes as routers (rejected: Principle V — only server nodes have the reliability profile for subnet routing).

---

## 4. Tailscale Key Expiry

**Decision**: Use `tailscale set --key-expiry-disabled` on each node after enrollment.

**Rationale**: Available since Tailscale v1.48 (current stable is v1.80+). This is a local node command — it sends a request to the Tailscale coordination server to disable key expiry for this specific device. No Tailscale API key required. Run once after enrollment; idempotent (safe to run if already disabled).

**Command**:
```bash
tailscale set --key-expiry-disabled
```

**Verification**:
```bash
tailscale status --json | jq '.Self.KeyExpiry'
# Returns "0001-01-01T00:00:00Z" when key expiry is disabled
```

**Alternatives considered**: Tailscale API (`POST /api/v2/device/{id}/key?keyExpiryDisabled=true`) — requires an API OAuth key stored in group_vars; more complex for no benefit since the CLI approach works. Admin console manual click — violates Principle I.

---

## 5. Tailscale Auth Key Type

**Decision**: Generate a **reusable, pre-authorized** auth key in the Tailscale admin console (not ephemeral, not one-time).

**Rationale**: Reusable + pre-authorized allows the Ansible role to enroll all 8 nodes without consuming the key. Pre-authorized means nodes join the tailnet without requiring manual approval per-device in the admin console. Reusable keys can be rotated post-deployment by replacing the value in `group_vars/all.yml` and re-running the playbook only on nodes that need re-enrollment.

**Storage**: `group_vars/all.yml` as `tailscale_auth_key: <vault-encrypted-value>`. Template key in `group_vars/example.all.yml` as `tailscale_auth_key: "<REPLACE_WITH_TAILSCALE_AUTH_KEY>"`.

**Alternatives considered**: Ephemeral keys (auto-removed from tailnet when device disconnects — wrong for always-on servers), one-time keys (consumed on first use — can't enroll 8 nodes with one key).

---

## 6. DNS Split Configuration (fleet1.lan → OPNsense Unbound)

**Decision**: Configure a custom nameserver in the Tailscale admin console: `fleet1.lan` → `10.1.1.1`. This is a manual step done once via the admin console UI (`DNS` tab → `Add nameserver` → `Custom` → domain: `fleet1.lan`, server: `10.1.1.1`).

**Rationale**: Tailscale's split-DNS feature (available on the free plan) routes DNS queries for a specific domain to a specified nameserver. OPNsense Unbound at `10.1.1.1` already resolves all `fleet1.lan` names. The management laptop DNS is unchanged; only `fleet1.lan` queries are routed to OPNsense via Tailscale.

**Management laptop requirement**: MagicDNS must be enabled in the tailnet settings and `Accept DNS` must be enabled on the management laptop Tailscale client. All other network DNS is unaffected (split tunnel).

**Automation**: The Tailscale API supports DNS configuration (`POST /api/v2/tailnet/-/dns/nameservers`) but requires an OAuth client. For a one-time homelab setup, the admin console UI is the appropriate path.

**Alternatives considered**: Global DNS override (routes ALL DNS through OPNsense — breaks non-lab DNS resolution on the laptop), manual `/etc/hosts` entries on laptop (rejected: rejected in spec FR-005).

---

## 7. Device Certificate Architecture

**Decision**: Create a dedicated **Device CA** (separate from the existing `fleet1-lan-ca`) using the same cert-manager SelfSigned → CA → Issuer pattern from `roles/pki`. Issue the management laptop's client certificate from this Device CA.

**Rationale**: Separating the device auth CA from the server TLS CA follows the principle of CA isolation — a compromise of one CA doesn't affect the other, and each can be rotated independently. The pattern is already established in `roles/pki` (SelfSigned ClusterIssuer → CA Certificate → CA ClusterIssuer).

**CA hierarchy**:
```
selfsigned-issuer (existing ClusterIssuer in roles/pki)
  └── device-ca                   (new: cert-manager Certificate, isCA: true)
       └── device-ca-issuer        (new: cert-manager ClusterIssuer using device-ca Secret)
            └── laptop-client-cert (new: cert-manager Certificate for management laptop)
```

**CA namespace**: `cert-manager` (same as existing CA resources, consistent with pki role).

**Client cert params**:
- `usages: ["client auth"]`
- `duration: 8760h` (1 year)
- `renewBefore: 720h` (30 days before expiry)
- `commonName: management-laptop`

**Alternatives considered**: Reusing `fleet1-lan-ca` as issuer (rejected: CA isolation — device certs and server TLS certs should have separate trust roots), manual cert generation with openssl (rejected: violates Principle IV — PKI must be managed as code via cert-manager).

---

## 8. Traefik mTLS Configuration

**Decision**: Create a named Traefik `TLSOption` resource (`device-mtls`) in the `traefik` namespace. Apply it selectively to fleet1.lan `IngressRoute` CRDs via `spec.tls.options: device-mtls@traefik`. Do NOT use the `default` TLSOption (would break fleet1.cloud public routes and intra-cluster service traffic).

**TLSOption spec**:
```yaml
apiVersion: traefik.io/v1alpha1
kind: TLSOption
metadata:
  name: device-mtls
  namespace: traefik
spec:
  clientAuth:
    secretNames:
      - device-ca-public  # Opaque Secret with ca.crt only (NOT tls.key)
    clientAuthType: RequireAndVerifyClientCert
```

**CA cert Secret** (`device-ca-public` in `traefik` namespace): Opaque Secret containing only the Device CA public certificate (`ca.crt` key). Created by Ansible by extracting `tls.crt` from the cert-manager-managed `device-ca-tls` Secret. This prevents Traefik from accessing the CA private key.

**IngressRoute scope**: Only `fleet1.lan` IngressRoute CRDs receive `tls.options: device-mtls@traefik`. The existing Helm-chart-managed Kubernetes `Ingress` resources (which cover both fleet1.cloud and fleet1.lan) are NOT modified. Instead, standalone `IngressRoute` CRDs are created in `manifests/` for each fleet1.lan service hostname.

**Cross-namespace TLSOption reference**: Traefik supports cross-namespace TLSOption references using `name@namespace` syntax. All IngressRoutes in any namespace can reference `device-mtls@traefik`.

**Alternatives considered**: `default` TLSOption (rejected: breaks public services and intra-cluster traffic), Traefik middleware (rejected: mTLS operates at TLS layer before HTTP, cannot be a middleware), modifying Helm chart Ingress values to add TLS options (rejected: Helm Ingress covers both .cloud and .lan, can't scope TLSOption per-hostname within one Ingress).

---

## 9. Fleet1.lan IngressRoute Split Strategy

**Decision**: Create standalone `IngressRoute` CRD manifests for each `fleet1.lan` service. The existing Helm-chart `Ingress` resources (covering fleet1.cloud) remain unchanged; they continue to handle fleet1.cloud routes. The new fleet1.lan `IngressRoute` manifests carry the `tls.options: device-mtls@traefik` annotation and route to the same backend service.

**Services requiring fleet1.lan IngressRoute manifests**:

| Service | Backend Service | Namespace | Existing fleet1.lan route |
|---------|----------------|-----------|--------------------------|
| Gitea | `gitea-http:3000` | `gitea` | In Helm Ingress (to be superseded) |
| ArgoCD | `argocd-server:443` | `argocd` | In Helm Ingress (to be superseded) |
| Grafana | `kube-prometheus-stack-grafana:80` | `monitoring` | In Helm Ingress (to be superseded) |
| Frigate | `frigate:5000` | `frigate` | In `manifests/frigate/ingressroute.yaml` (to be split out) |
| Home Assistant | `home-assistant:8080` | `home-automation` | In existing Ingress/IngressRoute |
| InfluxDB | `influxdb:8086` | `home-automation` | In `manifests/home-automation/influxdb-fleet1-lan-ingress.yaml` (to be replaced with IngressRoute) |
| Node-RED | `node-red:1880` | `home-automation` | In existing Ingress |

**Helm Ingress cleanup**: Remove `fleet1.lan` hostnames from Helm chart values once the standalone IngressRoute manifests are in place, to prevent duplicate routing. This is done per service during the implementation phase.

**Rationale**: Keeping the two domain groups in separate resources (Ingress for .cloud, IngressRoute for .lan) allows independent TLS config per resource and avoids Helm chart modifications that would be overwritten on chart upgrade.

---

## Summary of Resolved Unknowns

| Item | Resolution |
|------|-----------|
| Tailscale arm64 availability | Confirmed: official apt packages.tailscale.com |
| `tailscale up` idempotency | `tailscale status` gate pre-check |
| Key expiry disable mechanism | `tailscale set --key-expiry-disabled` (v1.48+, no API key needed) |
| Auth key type | Reusable + pre-authorized, stored in Ansible Vault |
| DNS split config | Manual: Tailscale admin console custom nameserver |
| Device CA pattern | New Device CA via cert-manager, separate from fleet1-lan-ca |
| Traefik mTLS scope | Named TLSOption `device-mtls@traefik`, fleet1.lan IngressRoutes only |
| Fleet1.lan route split | Standalone IngressRoute CRDs in `manifests/` per service |
