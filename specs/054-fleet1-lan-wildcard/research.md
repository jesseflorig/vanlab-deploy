# Research: fleet1.lan Local DNS with Internal Wildcard TLS

## Decision 1: PKI Pattern — cert-manager CA Chain

**Decision**: Reuse the existing `selfsigned-issuer` ClusterIssuer (bootstrapped by home-automation
prereqs) to issue a new `fleet1-lan-ca` Certificate in the `cert-manager` namespace. A second
`fleet1-lan-ca` ClusterIssuer is then created using that CA secret to sign the wildcard cert.

**Rationale**: The `selfsigned-issuer` ClusterIssuer already exists in the cluster (deployed by
ArgoCD as part of home-automation prereqs). Reusing it avoids re-creating a resource that may
already exist and follows the same chain pattern established for the MQTT mTLS PKI. The CA private
key never leaves the cluster — cert-manager holds it in a K8s Secret that is never committed to Git,
satisfying Constitution Principle IV.

**Alternatives considered**:
- Generate CA externally (openssl) and store as SealedSecret — rejected: Principle IV states PKI
  lifecycle MUST be managed via cert-manager; manual key generation is prohibited.
- Re-use `home-automation-ca` ClusterIssuer — rejected: the MQTT CA is application-scoped and its
  name/CN would be misleading for a cluster-wide LAN PKI.

---

## Decision 2: Wildcard Cert Namespace — `traefik`

**Decision**: Issue `*.fleet1.lan` Certificate into the `traefik` namespace as secret
`fleet1-lan-wildcard-tls`. The CA Certificate (`fleet1-lan-ca`) is issued into `cert-manager`
namespace, consistent with `home-automation-ca`.

**Rationale**: Traefik requires TLS secrets to be in its own namespace to reference them in
`TLSStore` and `IngressRoute` resources. The cert-manager namespace is the conventional home for
CA certificates. This mirrors the existing pattern: `fleet1-cloud-tls` lives in `traefik` namespace.

---

## Decision 3: Traefik TLS Serving — `TLSStore` Certificates List (SNI-based)

**Decision**: Deploy a `TLSStore` Kubernetes CRD resource (name: `default`, namespace: `traefik`)
with a `certificates` list entry referencing `fleet1-lan-wildcard-tls`. Traefik automatically
selects the correct cert based on SNI — `*.fleet1.lan` requests get the internal wildcard,
`*.fleet1.cloud` requests get the Let's Encrypt wildcard (already the `defaultCertificate`).

**Rationale**: No per-service IngressRoute changes are needed. Traefik's SNI-based cert selection
means adding one `TLSStore` manifest covers all current and future `fleet1.lan` services.

**Note**: The existing Traefik Helm values define `tlsStore.default.defaultCertificate` pointing at
`fleet1-cloud-tls`. The `TLSStore` CRD applied separately takes precedence (Helm values set the
initial store; the CRD is authoritative post-deploy). The `defaultCertificate` remains
`fleet1-cloud-tls`; the `certificates` list addition is additive.

**Alternatives considered**:
- Per-IngressRoute `tls.secretName` — rejected: requires updating every service's IngressRoute;
  high maintenance overhead as services grow.
- Modify Traefik Helm values to include the fleet1.lan cert — rejected: the cert doesn't exist at
  Helm install time; chicken-and-egg ordering problem.

---

## Decision 4: DNS Implementation — OPNsense Unbound Host Override

**Decision**: Add a host override in OPNsense Unbound via the REST API:
- Host: `*` (wildcard), Domain: `fleet1.lan`, IP: `10.1.20.11` (K3s server node1)
- Applied via `ansible.builtin.uri` calls to the Unbound API in `network-deploy.yml`

**Rationale**: OPNsense Unbound already manages all LAN DNS. The `oxlorg.opnsense` collection
provides Unbound host override support. `node1` (`10.1.20.11`) is the primary K3s server and a
stable target. DNS does not need to be multi-node for this feature (Traefik runs across all nodes
but a single A record is sufficient for homelab).

**Alternatives considered**:
- Multiple A records (round-robin) — not needed for homelab scale; adds complexity with no benefit.
- CoreDNS in-cluster — out of scope; this feature targets LAN clients, not pods.

---

## Decision 5: Port 443 Access — OPNsense NAT Port Forward

**Decision**: Add an OPNsense NAT port-forward rule: TCP traffic from the management VLAN
(`10.1.1.0/24`) destined for `10.1.20.11:443` is redirected to `10.1.20.11:30443`.
This is applied via the OPNsense NAT API (`/api/firewall/nat/`) in `network-deploy.yml`.

**Rationale**: Traefik runs as NodePort on `30443`. Without port bridging, `*.fleet1.lan` DNS would
resolve to `10.1.20.11` and standard HTTPS (port 443) connections would be refused. OPNsense
handles all inter-VLAN routing; a NAT redirect rule is the minimal change that bridges the gap
without modifying Traefik or adding new infrastructure.

**Alternatives considered**:
- `hostPort: 443` on Traefik — rejected: requires Traefik pod privilege escalation; changes
  existing infrastructure; outside this feature's scope.
- kube-vip LoadBalancer IP — rejected: new infrastructure (kube-vip not installed); disproportionate
  for this feature.
- Document port 30443 in URLs — rejected: defeats the purpose of clean `*.fleet1.lan` hostnames.

---

## Decision 6: CA Root Distribution — Ansible + macOS Keychain

**Decision**: New playbook `playbooks/compute/ca-trust-deploy.yml` targeting `localhost` (management
laptop). Steps:
1. Fetch `fleet1-lan-ca-secret` from the cluster (delegate to a server node, `kubectl get secret`)
2. Extract the `ca.crt` field (base64-decoded)
3. Install into macOS System Keychain: `security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain`
4. Guard with idempotency check: skip if fingerprint already present (`security find-certificate`)

**Rationale**: macOS is the management laptop OS (confirmed from user context). The System Keychain
is trusted by Safari, Chrome, Firefox (when system root trust is enabled), and curl. The `security`
CLI is available on all macOS versions. Ansible `become: true` with `sudo` handles the System
Keychain write permission.

**Alternatives considered**:
- Login Keychain — rejected: per-user only; System Keychain works for all users and CLI tools.
- Manual cert distribution (download + double-click) — rejected: not idempotent; not automatable.

---

## Decision 7: Ansible vs ArgoCD Ownership

**Decision**: `fleet1.lan` PKI is **Ansible-managed infrastructure**, not an ArgoCD application.
A new `roles/pki/` role applies the CA chain and wildcard cert via `kubectl apply`. The `TLSStore`
CRD is applied by the same role. This role runs as part of `playbooks/cluster/services-deploy.yml`
with a `--tags pki` tag.

**Rationale**: The fleet1.lan CA and wildcard cert are cluster-wide infrastructure (like the
fleet1.cloud cert managed by the cert-manager role). Constitution Principle XI identifies cert-manager
as infrastructure — Ansible-managed. The `home-automation-ca` precedent (ArgoCD-managed) is
application-scoped PKI, which is a different category. Cluster-wide PKI belongs with Ansible.

**Alternatives considered**:
- ArgoCD-managed `manifests/fleet1-lan/` — rejected: cert resources are infrastructure; mixing
  them with app manifests blurs the Ansible/ArgoCD boundary defined in the constitution.
