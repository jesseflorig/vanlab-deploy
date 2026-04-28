# Data Model: fleet1.lan Local DNS with Internal Wildcard TLS

## Key Entities

### Kubernetes Resources

| Resource | Kind | Namespace | Name | Purpose |
|----------|------|-----------|------|---------|
| Bootstrap Issuer | ClusterIssuer | cluster-scoped | `selfsigned-issuer` | Issues the fleet1.lan CA cert (already exists from home-automation) |
| LAN CA Certificate | Certificate | `cert-manager` | `fleet1-lan-ca` | Root CA for all `*.fleet1.lan` internal TLS; `isCA: true` |
| LAN CA Secret | Secret | `cert-manager` | `fleet1-lan-ca-secret` | Holds CA key + cert (managed by cert-manager; never committed to Git) |
| LAN CA Issuer | ClusterIssuer | cluster-scoped | `fleet1-lan-ca` | Signs `*.fleet1.lan` wildcard cert using the CA secret |
| Wildcard Certificate | Certificate | `traefik` | `fleet1-lan-wildcard-tls` | TLS cert for `*.fleet1.lan`; SNI-matched by Traefik |
| Wildcard Secret | Secret | `traefik` | `fleet1-lan-wildcard-tls` | Holds wildcard key + cert (managed by cert-manager) |
| TLS Store | TLSStore | `traefik` | `default` | Traefik certificate store; `fleet1-lan-wildcard-tls` added to `certificates` list |

### OPNsense Resources

| Resource | Type | Value | Purpose |
|----------|------|-------|---------|
| Unbound Host Override | DNS Override | `*.fleet1.lan` → `10.1.20.11` | Resolves all fleet1.lan subdomains to Traefik NodePort host |
| NAT Port Forward | Firewall NAT | `10.1.20.11:443` → `10.1.20.11:30443` | Bridges standard HTTPS port to Traefik NodePort |

### Ansible Resources

| Resource | Type | Location | Purpose |
|----------|------|----------|---------|
| PKI Role | Ansible Role | `roles/pki/` | Applies CA chain, wildcard cert, TLSStore CRD to cluster |
| CA Trust Playbook | Ansible Playbook | `playbooks/compute/ca-trust-deploy.yml` | Installs CA root cert on managed client machines |
| CA Root Bundle | File (temp) | `/tmp/fleet1-lan-ca.crt` (management laptop, transient) | Public CA cert fetched from cluster for keychain install |

## Certificate Chain

```
selfsigned-issuer (ClusterIssuer, already exists)
    └── fleet1-lan-ca (Certificate, cert-manager ns)
            └── fleet1-lan-ca (ClusterIssuer)
                    └── *.fleet1.lan (Certificate, traefik ns)
                            └── fleet1-lan-wildcard-tls (Secret, traefik ns)
                                    └── Traefik TLSStore (certificates list)
```

## Cert Parameters

| Field | Value | Rationale |
|-------|-------|-----------|
| CA key algorithm | RSA 4096 | Matches home-automation-ca pattern |
| CA duration | `87600h` (10 years) | Long-lived CA; rotation is a manual operation |
| CA renewBefore | `720h` (30 days) | cert-manager auto-renews |
| Wildcard duration | `8760h` (1 year) | Matches fleet1.cloud cert pattern |
| Wildcard renewBefore | `720h` (30 days) | cert-manager auto-renews |
| Wildcard dnsNames | `*.fleet1.lan` | Single wildcard covers all subdomains |
