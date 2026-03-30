# Quickstart: Static Site with End-to-End TLS

## Prerequisites

- K3s cluster from feature 003 is running (all 4 nodes Ready)
- CM5 edge device running cloudflared (feature 002), tunnel status Healthy
- Cloudflare API token with Zone:DNS:Edit and Zone:Zone:Read permissions for fleet1.cloud
- Tunnel UUID from the Cloudflare Zero Trust dashboard (Networks → Tunnels → your tunnel)
- Tunnel credentials file obtained (see Step 0)

## Step 0 — Obtain Tunnel Credentials File (one-time)

The local config.yml approach requires a credentials JSON file on the edge device. This replaces the token-only flow.

SSH to the CM5 edge device and run:
```bash
sudo cloudflared tunnel token --creds-file /etc/cloudflared/credentials.json <TUNNEL-NAME>
```

Verify the file exists:
```bash
sudo cat /etc/cloudflared/credentials.json
```

Expected: a JSON object with `AccountTag`, `TunnelSecret`, and `TunnelID` fields. Note the `TunnelID` value — this is your `cloudflare_tunnel_id`.

## Step 1 — Populate Secrets and Config

Add to `group_vars/all.yml` (gitignored):
```yaml
cloudflare_api_token: "<CLOUDFLARE_API_TOKEN>"
acme_email: "<YOUR_EMAIL>"
```

Add to `group_vars/compute.yml`:
```yaml
cloudflare_tunnel_id: "<TUNNEL-UUID>"

cloudflared_ingress_rules:
  - hostname: fleet1.cloud
    service: https://10.1.20.11:30443
    originServerName: fleet1.cloud
  - hostname: www.fleet1.cloud
    service: https://10.1.20.11:30443
    originServerName: fleet1.cloud
  - hostname: whoami.fleet1.cloud
    service: http://10.1.20.11:30080
```

## Step 2 — Update Cloudflare DNS

In the Cloudflare DNS dashboard for fleet1.cloud, ensure the following CNAME records exist (these route the domains through the tunnel):

- `fleet1.cloud` → `<TUNNEL-UUID>.cfargotunnel.com` (proxied)
- `www.fleet1.cloud` → `<TUNNEL-UUID>.cfargotunnel.com` (proxied)

The `whoami.fleet1.cloud` record from feature 003 should already exist.

## Step 3 — Update Edge Device (cloudflared config)

```bash
ansible-playbook -i hosts.ini playbooks/compute/edge-deploy.yml --ask-become-pass
```

Expected: cloudflared restarts with the new `config.yml`. The tunnel reconnects within a few seconds.

## Step 4 — Deploy cert-manager, Traefik (updated), and Static Site

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass
```

Expected output at completion:
- cert-manager installed and webhook Ready
- Cloudflare Secret and ClusterIssuer applied
- Certificate CR applied — cert-manager initiates DNS-01 challenge
- Certificate reaches Ready state (may take 2–5 minutes for DNS propagation + issuance)
- Traefik updated with websecure entrypoint on NodePort 30443
- Static site deployed and Rolling out

Monitor certificate issuance:
```bash
ssh fleetadmin@10.1.20.11 "kubectl describe certificate fleet1-cloud-tls -n traefik"
ssh fleetadmin@10.1.20.11 "kubectl describe challenge -n traefik"
```

## Step 5 — Verify HTTPS from Within the Network

```bash
# Direct test via NodePort (bypasses Cloudflare)
curl -H "Host: fleet1.cloud" https://10.1.20.11:30443/ --resolve fleet1.cloud:30443:10.1.20.11

# Should return the placeholder HTML page with no TLS errors
```

## Step 6 — Verify End-to-End from the Internet

From any browser or cellular device:
```bash
curl https://fleet1.cloud
```

Expected: placeholder HTML page, valid padlock, no certificate warnings.

Test redirect:
```bash
curl -I https://www.fleet1.cloud
```

Expected: `301 Moved Permanently` → `Location: https://fleet1.cloud`

## Step 7 — Verify Idempotency

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass
ansible-playbook -i hosts.ini playbooks/compute/edge-deploy.yml --ask-become-pass
```

Expected: both runs produce `changed=0`.

## Troubleshooting

**Certificate stuck in Pending/not Ready:**
```bash
ssh fleetadmin@10.1.20.11 "kubectl describe challenge -n traefik"
```
- `Error from Cloudflare API`: API token permissions insufficient — verify Zone:DNS:Edit and Zone:Zone:Read
- Challenge shows `Waiting for DNS propagation`: normal, wait 60–120s
- `secret not found`: Cloudflare API token Secret is in the wrong namespace — must be in `cert-manager`

**Traefik returns 404 for fleet1.cloud:**
- Certificate may not yet be Ready — check `kubectl get certificate -n traefik`
- Ingress may not be applied — check `kubectl get ingress -n traefik`

**`curl https://fleet1.cloud` returns connection refused:**
- cloudflared config may not have been updated — re-run edge-deploy.yml
- Check tunnel status: Cloudflare Zero Trust → Networks → Tunnels

**www redirect returns 308 instead of 301:**
- Traefik v3 uses 308 for non-GET requests; browsers follow it correctly. For strictly 301, configure `permanent: true` in the Middleware (already set).
