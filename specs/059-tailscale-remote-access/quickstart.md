# Deployment Runbook: Tailscale Remote Access

**Branch**: `059-tailscale-remote-access` | **Date**: 2026-04-30

---

## Prerequisites

- [ ] Tailscale Free Personal account created at [login.tailscale.com](https://login.tailscale.com)
- [ ] `group_vars/all.yml` exists (not committed, based on `group_vars/example.all.yml`)
- [ ] Cluster nodes reachable via LAN SSH

---

## Step 1 — Generate a Tailscale Auth Key

1. Go to [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys)
2. Click **Generate auth key**
3. Settings: **Reusable** ✅, **Pre-authorized** ✅, **Ephemeral** ❌
4. Copy the key value

---

## Step 2 — Store Auth Key in Ansible Vault

```bash
# Edit group_vars/all.yml and add:
tailscale_auth_key: "<paste key here>"

# Then encrypt the value using Ansible Vault if the file is vault-encrypted:
ansible-vault encrypt_string '<paste key here>' --name 'tailscale_auth_key'
# Paste the output block into group_vars/all.yml replacing the plaintext value
```

---

## Step 3 — Deploy Tailscale to All Nodes

```bash
# From repo root, on management laptop
ansible-playbook -i hosts.ini playbooks/compute/tailscale-deploy.yml --ask-vault-pass
```

This playbook:
- Installs Tailscale from official apt repo on all `cluster`, `compute`, and `nvr` nodes
- Enrolls each node into the tailnet using the auth key
- Configures `node1`, `node3`, `node5` as subnet routers advertising all 6 lab subnets
- Enables IP forwarding on subnet router nodes
- Disables key expiry on all nodes via `tailscale set --key-expiry-disabled`

**Expected output**: All 8 nodes show `✓ changed` on first run, `✓ ok` on subsequent runs.

---

## Step 4 — Approve Subnet Routes (Tailscale Admin Console)

1. Go to [login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)
2. For each of `node1`, `node3`, `node5`:
   - Click the three-dot menu → **Edit route settings**
   - Enable all advertised subnets: `10.1.1.0/24`, `10.1.10.0/24`, `10.1.20.0/24`, `10.1.30.0/24`, `10.1.40.0/24`, `10.1.50.0/24`
   - Click **Save**

---

## Step 5 — Configure Fleet1.lan Split-DNS

1. Go to [login.tailscale.com/admin/dns](https://login.tailscale.com/admin/dns)
2. Under **Nameservers**, click **Add nameserver** → **Custom**
3. Set: **Nameserver**: `10.1.1.1`, **Restrict to domain**: `fleet1.lan`
4. Click **Save**
5. Ensure **MagicDNS** is enabled (toggle at the top of the DNS page)

---

## Step 6 — Deploy Device CA and Traefik TLSOption

```bash
# From repo root, on management laptop
ansible-playbook -i hosts.ini playbooks/cluster/device-mtls-deploy.yml
```

This playbook:
- Creates the Device CA cert-manager resources (SelfSigned → CA → Issuer)
- Creates the laptop client cert-manager Certificate resource
- Extracts the Device CA public cert and creates the Traefik `device-ca-public` Secret
- Applies the Traefik `device-mtls` TLSOption in the `traefik` namespace
- Waits for the laptop client cert to be issued (Ready condition)

---

## Step 7 — Export Laptop Client Certificate

```bash
# Extract the client cert and key from the cluster Secret
kubectl get secret laptop-client-cert-tls -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > ~/laptop-client-cert.pem

kubectl get secret laptop-client-cert-tls -n cert-manager \
  -o jsonpath='{.data.tls\.key}' | base64 -d > ~/laptop-client-cert.key

# Create a PKCS12 bundle for browser import (macOS/Windows friendly)
openssl pkcs12 -export \
  -in ~/laptop-client-cert.pem \
  -inkey ~/laptop-client-cert.key \
  -out ~/laptop-client-cert.p12 \
  -name "fleet1-device-cert"
# Enter a passphrase when prompted; store it in your password manager
```

---

## Step 8 — Install Certificate on Management Laptop

**macOS**:
1. Double-click `laptop-client-cert.p12`
2. Choose **Login** keychain, enter the passphrase
3. In Keychain Access, find `fleet1-device-cert` → right-click → **Get Info** → expand **Trust** → set **When using this certificate** to **Always Trust**

**Browser** (if Keychain auto-import doesn't work):
- Chrome/Safari: Uses macOS Keychain automatically — no additional steps
- Firefox: `Settings → Privacy & Security → Certificates → View Certificates → Your Certificates → Import` → select `laptop-client-cert.p12`

---

## Step 9 — Apply Fleet1.lan IngressRoute Manifests

The fleet1.lan `IngressRoute` manifests with `tls.options: device-mtls@traefik` live in `manifests/`. Push to Gitea; ArgoCD applies them automatically:

```bash
git add manifests/
git commit -m "feat(mtls): add fleet1.lan IngressRoutes with device mTLS"
git push gitea 059-tailscale-remote-access
# Then create PR and merge per git workflow in CLAUDE.md
```

---

## Step 10 — Install Tailscale on Management Laptop

1. Download and install from [tailscale.com/download](https://tailscale.com/download)
2. Open Tailscale → click **Log in** → authenticate with the same account
3. In the menu bar icon → enable **Accept routes** 
4. Verify `tailscale status` shows the laptop enrolled

---

## Step 11 — End-to-End Verification

```bash
# Disconnect from LAN (use mobile hotspot or VPN to simulate external network)
# With Tailscale active:

# 1. Verify subnet routing
ping -c 3 10.1.1.1   # OPNsense should respond

# 2. Verify DNS resolution
nslookup gitea.fleet1.lan   # Should resolve to 10.1.20.x (Traefik node IP)

# 3. Verify mTLS enforcement (should fail — no cert)
curl -k https://gitea.fleet1.lan --no-cert
# Expected: connection rejected (SSL error) — NOT a login page

# 4. Verify mTLS access (should succeed — with cert)
curl -k https://gitea.fleet1.lan \
  --cert ~/laptop-client-cert.pem \
  --key ~/laptop-client-cert.key
# Expected: Gitea HTML response

# 5. Verify browser access
open https://gitea.fleet1.lan   # Browser should prompt to select client cert, then load page
```

---

## US2 Verification — Device mTLS Enforcement

Verify that fleet1.lan services require the device cert and reject connections without it.

```bash
# Prerequisites: Tailscale active, fleet1.lan DNS resolving (Steps 10 + 5 complete)

# 1. Confirm TLSOption is applied in the cluster
kubectl get tlsoption device-mtls -n traefik -o yaml
# Expected: clientAuth.clientAuthType == RequireAndVerifyClientCert

# 2. Confirm device-ca-public Secret exists in traefik namespace
kubectl get secret device-ca-public -n traefik
# Expected: Opaque secret with ca.crt key

# 3. Test rejection without client cert
curl -k --silent --write-out "%{http_code}" https://gitea.fleet1.lan -o /dev/null
# Expected: 000 (connection terminated) or 400 (no required SSL certificate)

# 4. Test success with client cert
curl -k --silent --write-out "%{http_code}" https://gitea.fleet1.lan \
  --cert ~/fleet1-laptop-cert.pem --key ~/fleet1-laptop-cert.key -o /dev/null
# Expected: 200 or 302

# 5. Test each fleet1.lan service (replace cert paths if needed)
for HOST in argocd.fleet1.lan grafana.fleet1.lan prometheus.fleet1.lan \
            hass.fleet1.lan node-red.fleet1.lan influxdb.fleet1.lan frigate.fleet1.lan; do
  CODE=$(curl -k --silent --write-out "%{http_code}" "https://$HOST" \
    --cert ~/fleet1-laptop-cert.pem --key ~/fleet1-laptop-cert.key -o /dev/null)
  echo "$HOST -> $CODE"
done
# Expected: all 200 or 302
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Node not in tailnet after playbook | Auth key expired or wrong type | Regenerate key in admin console |
| `tailscale up` fails with "already logged in" | Idempotency guard not triggering | Check `tailscale status --json` on node |
| Routes not accessible after approval | IP forwarding not enabled | `sysctl net.ipv4.ip_forward` on server node |
| `fleet1.lan` DNS not resolving | MagicDNS disabled or split-DNS not saved | Re-check admin console DNS settings |
| Browser rejects cert import | P12 passphrase mismatch | Re-export with `openssl pkcs12 -export` |
| 403 from service with valid cert | TLSOption not applied to IngressRoute | Check ArgoCD sync status |
| Gitea returning 502 | ArgoCD detecting fleet1.lan host conflict | Remove fleet1.lan from Helm chart Ingress values |

---

## Day-2 Operations

**Rotate Tailscale auth key**:
1. Generate new key in admin console
2. Update `tailscale_auth_key` in `group_vars/all.yml`
3. Re-run playbook only on nodes that need re-enrollment (`tailscale logout && tailscale up` will be triggered by status check)

**Renew laptop client cert** (cert-manager auto-renews 30 days before expiry — manual export only):
```bash
# After cert-manager auto-renews, re-export and reinstall:
# Repeat Steps 7–8 above
```

**Revoke device cert** (lost/stolen laptop):
```bash
# Delete the cert-manager Certificate resource (cert-manager deletes the Secret)
kubectl delete certificate laptop-client-cert -n cert-manager
# This invalidates the issued cert — Traefik will no longer accept it
# Also remove the laptop from the Tailscale admin console
```

**Add a new lab node** to Tailscale:
1. Add node to `hosts.ini`
2. Re-run `tailscale-deploy.yml` — new node enrolls automatically (reusable key still valid)
