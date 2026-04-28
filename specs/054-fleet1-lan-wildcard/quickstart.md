# Quickstart: fleet1.lan Local DNS with Internal Wildcard TLS

## Prerequisites

- OPNsense credentials in `group_vars/all.yml`: `opnsense_api_key`, `opnsense_api_secret`
- `ansible-galaxy collection install -r requirements.yml` run
- cert-manager deployed and healthy in cluster

## Step 1 — Deploy PKI (CA Chain + Wildcard Cert + TLSStore)

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags pki
```

Wait for cert issuance (~30s for internal CA, no DNS-01 challenge needed):

```bash
kubectl get certificate -n cert-manager fleet1-lan-ca
kubectl get certificate -n traefik fleet1-lan-wildcard-tls
```

Both should show `READY = True`.

## Step 2 — Apply DNS Override and NAT Rule

```bash
ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml
```

Verify DNS resolution from the management laptop:

```bash
dig grafana.fleet1.lan @10.1.1.1
# Expected: A record → 10.1.20.11
```

## Step 3 — Distribute CA Root to Management Laptop

```bash
ansible-playbook -i hosts.ini playbooks/compute/ca-trust-deploy.yml
```

Verify trust (after running):

```bash
curl -v https://grafana.fleet1.lan
# Expected: TLS handshake succeeds, cert CN = *.fleet1.lan
```

## Step 4 — Add IngressRoute Entries for fleet1.lan

For each service, add a `fleet1.lan` host rule to its IngressRoute. Example for Grafana:

```yaml
- match: Host(`grafana.fleet1.lan`)
  kind: Rule
  services:
    - name: kube-prometheus-stack-grafana
      port: 80
```

The TLSStore will automatically serve `fleet1-lan-wildcard-tls` for `*.fleet1.lan` SNI connections.

## Idempotency

All steps are safe to re-run:
- `services-deploy.yml --tags pki`: cert-manager CRs are idempotent via `kubectl apply`
- `network-deploy.yml`: Unbound override and NAT rule are created-or-updated
- `ca-trust-deploy.yml`: checks for existing cert fingerprint before installing
