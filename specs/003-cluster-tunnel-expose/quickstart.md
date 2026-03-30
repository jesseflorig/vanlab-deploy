# Quickstart: Cluster Provisioning and Internet Exposure

## Prerequisites

- All 4 cluster nodes provisioned with Raspberry Pi OS, reachable via SSH
- CM5 edge device running Cloudflared (feature 002) with tunnel status Healthy
- `group_vars/all.yml` populated with SSH credentials
- Ansible control machine has `hosts.ini` with correct node IPs

## Step 1 — Verify All Nodes Are Reachable

```bash
ansible-playbook -i hosts.ini playbooks/utilities/check_hosts.yml --limit cluster
```

Expected: all 4 cluster nodes (node1–node4) respond ONLINE.

## Step 2 — Provision the K3s Cluster

```bash
ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml --ask-become-pass
```

Expected output at completion:
- All 4 nodes listed as `Ready` in the node status display
- No manual intervention required to join agents

Verify cluster health independently:
```bash
# SSH to node1 and check nodes
ssh fleetadmin@10.1.20.11 "kubectl get nodes -o wide"
```

## Step 3 — Deploy Traefik and Whoami

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass
```

Expected output at completion:
- Traefik deployed and Ready in `traefik` namespace
- Traefik NodePort address displayed (e.g., `http://10.1.20.11:30080`) — **note this URL**
- Whoami deployment rolled out and Ready

Verify Traefik is reachable from within the network:
```bash
curl -H "Host: whoami.fleet1.cloud" http://<node1-IP>:30080/
```

Expected: HTML/text response from the whoami app showing request headers.

## Step 4 — Configure Cloudflare Tunnel Hostname (manual)

In the Cloudflare Zero Trust dashboard:

1. Networks → Tunnels → your tunnel → Configure → Public Hostnames
2. Add hostname:
   - Subdomain: `whoami`
   - Domain: `fleet1.cloud`
   - Type: `HTTP`
   - URL: `<node1-IP>:30080`
3. Save

## Step 5 — Verify End-to-End from the Internet

From a device on cellular (outside your home network):

```bash
curl https://whoami.fleet1.cloud
```

Expected: response showing request headers including `X-Forwarded-For` and `X-Forwarded-Host`, confirming the full path: internet → Cloudflare → tunnel → CM5 → Traefik → whoami pod.

## Idempotency Check

Re-run either playbook against a fully provisioned cluster — both should produce `changed=0`:

```bash
ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml --ask-become-pass
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass
```
