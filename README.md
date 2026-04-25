# Vanlab

Ansible automation for the Vanlab homelab — K3s cluster, edge compute, and network infrastructure.

**Hardware**: 4x CM5 64GB w/ PoE HAT + M.2 2TB NVMe drives (cluster), 1x Waveshare CM5-PoE-BASE-A (edge)

## Prerequisites

Install Ansible collections once after cloning (or when `requirements.yml` changes):

```bash
ansible-galaxy collection install -r requirements.yml
```

Copy the secrets template and fill in real values:

```bash
cp group_vars/example.all.yml group_vars/all.yml
# Edit group_vars/all.yml with your credentials
```

## Quick Reference

| Category | Playbook | Command |
|----------|----------|---------|
| Cluster | Deploy K3s | `ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml --ask-become-pass` |
| Cluster | Deploy Services | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass` |
| Cluster | Deploy Loki only | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags loki --ask-become-pass` |
| Cluster | Deploy Alloy only | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags alloy --ask-become-pass` |
| Cluster | Sealed Secrets only | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags sealed-secrets --ask-become-pass` |
| Cluster | ArgoCD bootstrap | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap --ask-become-pass` |
| Edge | Deploy Cloudflared | `ansible-playbook -i hosts.ini playbooks/compute/edge-deploy.yml --ask-become-pass` |
| Network | OPNsense (check) | `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml --check` |
| Utilities | Disk Health | `ansible-playbook -i hosts.ini playbooks/utilities/disk-health.yml --ask-become-pass` |
| Utilities | Drain & Shutdown | `ansible-playbook -i hosts.ini playbooks/utilities/drain-shutdown.yml -e target=<node> --ask-become-pass` |
| Utilities | Deploy SSH Key | `ansible-playbook -i hosts.ini playbooks/utilities/deploy-ssh-key.yml --ask-become-pass` |
| Utilities | Seal secrets | `ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml --ask-become-pass` |
| Utilities | Gen Mosquitto passwd | `ansible-playbook -i hosts.ini playbooks/utilities/gen-mosquitto-passwd.yml -e "mqtt_user=<user> mqtt_pass=<pass>"` |

## Playbook Directory Structure

```
playbooks/
├── cluster/
│   ├── k3s-deploy.yml        — provision K3s server and agent nodes
│   └── services-deploy.yml   — deploy Helm, Traefik, Longhorn, ArgoCD, etc.
├── compute/
│   └── edge-deploy.yml       — install Cloudflared systemd service on CM5 edge device
├── network/
│   └── network-deploy.yml    — manage OPNsense router via REST API
└── utilities/
    ├── disk-health.yml           — enumerate NVMe drives and report capacity per node
    ├── deploy-ssh-key.yml        — deploy SSH public key to all nodes for passwordless access
    ├── drain-shutdown.yml        — drain a node and shut it down (-e target=<node>)
    ├── gen-mosquitto-passwd.yml  — generate a mosquitto_passwd hash from a plaintext password
    ├── read-k3s-token.yml        — read K3s join token from server node
    ├── seal-secrets.yml          — (re)generate sealed-secrets.yaml for the home-automation stack
    └── test-join-cmd.yml         — print K3s agent join command for manual use
```

## Inventory Groups

| Group | Members | Notes |
|-------|---------|-------|
| `servers` | node1, node3, node5 | K3s control-plane + etcd nodes (10.1.20.11, .13, .15) |
| `agents` | node2, node4, node6 | K3s worker nodes (10.1.20.12, .14, .16) |
| `cluster` | servers + agents | Full K3s cluster |
| `compute` | edge | CM5 Cloudflared device (10.1.10.x) |

OPNsense (10.1.1.1) and unmanaged switches are documented as topology comments in `hosts.ini` — managed via `network-deploy.yml` using the `oxlorg.opnsense` REST API collection.

### etcd Topology

The cluster uses K3s embedded etcd. Server count **must be odd** (1, 3, or 5) for quorum:

| Servers | Fault tolerance |
|---------|----------------|
| 1 | None — any failure = cluster down |
| 3 | 1 node |
| 5 | 2 nodes |

The first entry in `[servers]` initializes the etcd cluster (`--cluster-init`). Additional entries join the quorum automatically on the next `k3s-deploy.yml` run.

### Promoting a node from agent to server

1. Move the node from `[agents]` to `[servers]` in `hosts.ini`
2. Uninstall the agent: `ansible <node> -i hosts.ini -m shell -a "k3s-agent-uninstall.sh" --become`
3. Re-run: `ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml`
4. Verify: `kubectl get nodes` — promoted node shows `control-plane,etcd` role

## Cluster Rebuild (etcd Migration)

A full rebuild is required when migrating datastores or recovering from total cluster loss. All Longhorn PVC data is lost — ensure the Gitea repo is up to date before starting (ArgoCD restores apps automatically).

> **Note**: SealedSecrets are encrypted with the cluster's controller private key. After a rebuild, a new key is generated and you must re-seal all secrets before ArgoCD can deploy the home-automation stack. See [Sealed Secrets — cluster rebuild](#cluster-rebuild-1) below.

```bash
# 1. Uninstall agents
ansible agents -i hosts.ini -m shell -a "k3s-agent-uninstall.sh" --become

# 2. Uninstall server(s)
ansible servers -i hosts.ini -m shell -a "k3s-uninstall.sh" --become

# 3. Deploy etcd-backed cluster (~3 min)
ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml

# 4. Deploy all services including Sealed Secrets controller (~12 min)
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml

# 5. Re-seal secrets with the new cluster key and commit
ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml
git add manifests/home-automation/prereqs/sealed-secrets.yaml
git commit -m "chore: re-seal secrets after cluster rebuild"
git push gitea main

# 6. Bootstrap GitOps (after creating a new Gitea PAT in group_vars/all.yml)
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap
```

Total rebuild time: ~15–20 minutes. ArgoCD syncs apps from Gitea automatically within 3 minutes of coming online.

## Exposing a New Service via Cloudflare Tunnel

Every new Traefik ingress needs a matching public hostname rule in Cloudflare Zero Trust before it's reachable externally.

1. **Traefik ingress** — add annotations to route via the `websecure` entrypoint:
   ```yaml
   traefik.ingress.kubernetes.io/router.entrypoints: websecure
   traefik.ingress.kubernetes.io/router.tls: "true"
   ```

2. **Cloudflare Zero Trust → Tunnels → Public Hostnames** — add a rule:
   - **Subdomain**: the new subdomain (e.g. `grafana`)
   - **Domain**: `fleet1.cloud`
   - **Service**: `https://10.1.20.11:30443`
   - **TLS → Origin Server Name**: the full hostname (e.g. `grafana.fleet1.cloud`)

   Creating the public hostname rule automatically creates the Cloudflare DNS CNAME. **Do not create the CNAME manually first** — the rule creation will fail if the DNS record already exists.

   Setting the origin server name lets cloudflared send the correct SNI during the TLS handshake with Traefik, allowing the wildcard cert (`*.fleet1.cloud`) to verify cleanly. Do **not** use "No TLS Verify" — that bypasses certificate validation entirely.

## GitOps

The cluster runs ArgoCD backed by a self-hosted Gitea instance for fully declarative application delivery.

### Infrastructure vs application workloads

Not everything in the cluster is ArgoCD-managed. The boundary is defined by **bootstrap ordering**: ArgoCD needs certain services running before it can sync anything, so those services must be Ansible-managed.

**Ansible/Helm-managed (infrastructure) — never migrate to ArgoCD:**

| Service | Reason |
|---------|--------|
| Traefik | Ingress controller — must exist before any service is reachable |
| cert-manager | PKI — TLS certs must exist before services can come up |
| Longhorn | Storage — PVCs must exist before stateful workloads can start |
| Sealed Secrets | Secret encryption controller — must exist before ArgoCD syncs encrypted secrets |
| Gitea | ArgoCD's source-of-truth — can't sync from Gitea if Gitea isn't running |
| ArgoCD | The GitOps controller itself — can't manage its own bootstrap |
| kube-prometheus-stack | Cluster observability infrastructure — same category as Traefik/Longhorn |

**ArgoCD-managed (application workloads) — all new apps go here:**

| ArgoCD App | Manifests | Description |
|------------|-----------|-------------|
| `static-site` | `manifests/static-site/` | fleet1.cloud landing page |
| `redirects` | `manifests/redirects/` | Wildcard subdomain → apex redirect |
| `home-automation-prereqs` | `manifests/home-automation/prereqs/` | Namespace, certs, SealedSecrets, ConfigMaps |
| `home-automation-apps` | `manifests/home-automation/apps/` | ArgoCD Applications for each HA service |

The rule of thumb: if the cluster can't function or recover without it, it's infrastructure. If it's a workload that runs *on top of* the cluster, it's an application and belongs in `manifests/` under ArgoCD.

### Deployment workflow

1. Add Gitea and ArgoCD secret values to `group_vars/all.yml`:

   ```yaml
   gitea_admin_username: admin
   gitea_admin_password: <password>
   gitea_admin_email: <email>
   argocd_admin_password_bcrypt: <bcrypt-hash>
   gitea_argocd_token: <gitea-pat>
   ```

   Generate the ArgoCD bcrypt hash:

   ```bash
   htpasswd -nbBC 10 "" <password> | tr -d ':\n' | sed 's/$2y/$2a/'
   ```

2. Run the full services playbook:

   ```bash
   ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass
   ```

3. Access the dashboards at `https://gitea.fleet1.cloud` and `https://argocd.fleet1.cloud`.

### Registering a new application

Add an entry to `argocd_apps` in `group_vars/all.yml`:

```yaml
argocd_apps:
  - name: my-service
    repo: org/repo          # Gitea org/repo path
    path: .                 # path within the repo containing manifests or Helm chart
    namespace: my-service   # destination namespace
    revision: main          # branch, tag, or commit SHA
```

Then re-run only the bootstrap role:

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap --ask-become-pass
```

### Rollback procedure

ArgoCD continuously reconciles the cluster to match the desired state in Gitea. To roll back a bad deployment:

1. Revert the commit in Gitea (via the Gitea web UI or `git revert` + push).
2. ArgoCD detects the change and automatically re-syncs within 3 minutes.
3. Verify the application returns to `Synced/Healthy`:

   ```bash
   kubectl get applications -n argocd
   ```

No direct `kubectl` intervention is required — the Git history is the source of truth.

### Smoke test

Verify the full GitOps stack is healthy after deployment:

```bash
ansible-playbook -i hosts.ini playbooks/cluster/argocd-smoke-test.yml --ask-become-pass
```

## Sealed Secrets

The home-automation stack uses [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) to store encrypted secret values safely in Git. The Sealed Secrets controller runs in `kube-system` and holds a private key that only it can decrypt; the public key is used to encrypt secrets locally.

### How it works

```
group_vars/all.yml          seal-secrets.yml playbook         Git (safe to commit)
(plaintext, gitignored)  →  kubeseal encryption            →  SealedSecret YAML
                                                               (AES-256 encrypted)
                                         ↓ ArgoCD applies
                                    cluster decrypts
                                         ↓
                                    Kubernetes Secret
                                    (normal secret in cluster)
```

SealedSecrets are **namespace-scoped and cluster-scoped** — a secret sealed for `home-automation` on this cluster cannot be decrypted by any other cluster or namespace.

### Secrets managed as SealedSecrets

| Secret name | Namespace | Contents |
|-------------|-----------|----------|
| `mosquitto-passwords` | `home-automation` | Mosquitto password file entry |
| `influxdb-auth` | `home-automation` | InfluxDB admin password + operator token |
| `home-assistant-influxdb` | `home-automation` | InfluxDB token + org ID for HA integration |
| `node-red-admin` | `home-automation` | Node-RED admin bcrypt hash + credential secret |

### Rotating a secret

1. Update the value(s) in `group_vars/all.yml`
2. Re-run the seal utility:
   ```bash
   ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml --ask-become-pass
   ```
3. Commit and push the regenerated file:
   ```bash
   git add manifests/home-automation/prereqs/sealed-secrets.yaml
   git commit -m "chore: rotate <secret-name>"
   git push gitea main
   ```
4. ArgoCD detects the change and applies the new SealedSecret within 3 minutes. The Sealed Secrets controller decrypts it and updates the underlying Kubernetes Secret automatically.

### Cluster rebuild

After a full cluster rebuild, the Sealed Secrets controller generates a new key pair. All existing SealedSecrets in Git are now undecryptable. Re-sealing is required before ArgoCD can bring up the home-automation stack:

```bash
# After services-deploy.yml completes (controller is running):
ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml --ask-become-pass
git add manifests/home-automation/prereqs/sealed-secrets.yaml
git commit -m "chore: re-seal secrets after cluster rebuild"
git push gitea main
```

### Backing up the controller key

The Sealed Secrets controller private key is stored as a Kubernetes Secret in `kube-system`. Back it up before decommissioning the cluster if you want to restore existing SealedSecrets without re-sealing:

```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-key-backup.yaml
# Store this file securely (it contains the private key)
```

To restore on a new cluster:
```bash
kubectl apply -f sealed-secrets-key-backup.yaml
kubectl rollout restart deployment/sealed-secrets-controller -n kube-system
```

## Home Automation Stack

The `home-automation` namespace runs four integrated services. They are managed by **ArgoCD** (not Ansible directly) — configuration lives in `manifests/home-automation/` and the source of truth is Git.

| Service | URL | Access |
|---------|-----|--------|
| Home Assistant | `https://hass.fleet1.cloud` | Public via Cloudflare Tunnel |
| Node-RED | `https://node-red.fleet1.cloud` | Public via Cloudflare Tunnel |
| InfluxDB | `https://influxdb.fleet1.cloud` | Public via Cloudflare Tunnel |
| Mosquitto | `mqtts://10.1.20.11:8883` | LAN only (LoadBalancer, no tunnel) |

### Architecture

```
manifests/home-automation/
├── prereqs/                    ← ArgoCD app: home-automation-prereqs
│   ├── namespace.yaml          (sync wave 0)
│   ├── ca-issuer.yaml          (sync wave 1-3) cert-manager CA chain for mTLS
│   ├── certificates.yaml       (sync wave 4)  TLS + mTLS certs
│   ├── config-extra.yaml       (sync wave 4)  Home Assistant packages ConfigMap
│   └── sealed-secrets.yaml     (sync wave 5)  encrypted secrets (generated by utility)
│
├── apps/                       ← ArgoCD app: home-automation-apps
│   ├── mosquitto-app.yaml      ArgoCD Application → helmforgedev/mosquitto
│   ├── influxdb-app.yaml       ArgoCD Application → influxdata/influxdb2
│   ├── home-assistant-app.yaml ArgoCD Application → pajikos/home-assistant
│   └── node-red-app.yaml       ArgoCD Application → schwarzit/node-red
│
├── mosquitto-values.yaml       Helm values for Mosquitto
├── influxdb-values.yaml        Helm values for InfluxDB
├── home-assistant-values.yaml  Helm values for Home Assistant
└── node-red-values.yaml        Helm values for Node-RED
```

Each `*-app.yaml` is a **multi-source ArgoCD Application**: one source is the upstream Helm chart repo (public), the second source is this Gitea repo providing the values file.

### First-time bootstrap

The home-automation stack bootstraps as part of the full services deployment, with one manual step after InfluxDB is first deployed.

```bash
# 1. Fill in all home-automation secrets in group_vars/all.yml (see example.all.yml)

# 2. Deploy the full stack (installs Sealed Secrets controller and Helm charts via Ansible)
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass

# 3. Get InfluxDB org ID — log in at https://influxdb.fleet1.cloud,
#    copy the hex UUID from the URL (/orgs/<hex-id>), set influxdb_org_id in group_vars/all.yml

# 4. Seal secrets with the cluster's controller key
ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml --ask-become-pass

# 5. Commit the generated SealedSecrets
git add manifests/home-automation/prereqs/sealed-secrets.yaml
git commit -m "feat: add sealed secrets for home-automation stack"
git push gitea main

# 6. Register ArgoCD apps (home-automation-prereqs, home-automation-apps)
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap --ask-become-pass
```

ArgoCD takes over from this point. The Ansible home-automation roles are retained as a fallback but are no longer the source of truth.

### Upgrading a Helm chart

Edit the chart version in the relevant `*-app.yaml` file and the matching `*-values.yaml` if the new version has changed value keys:

```bash
# Example: upgrade Mosquitto from 1.0.7 to 1.1.0
vim manifests/home-automation/apps/mosquitto-app.yaml   # change targetRevision
vim manifests/home-automation/mosquitto-values.yaml     # adjust values if needed
git commit -am "chore(mosquitto): upgrade chart to 1.1.0"
git push gitea main
# ArgoCD auto-syncs within 3 minutes
```

### Changing Helm values

Edit `manifests/home-automation/<service>-values.yaml` directly:

```bash
vim manifests/home-automation/home-assistant-values.yaml
git commit -am "feat(hass): bump image tag to 2025.4"
git push gitea main
```

### Mosquitto client certificates (mTLS)

Mosquitto enforces mTLS — every client must present a certificate signed by the `home-automation-ca` ClusterIssuer. Home Assistant and Node-RED receive their certs automatically via cert-manager Certificate objects in `prereqs/certificates.yaml`.

**Issuing a cert for an IoT device:**

```bash
# Render a client cert manifest (uses roles/mosquitto/templates/client-cert.yaml.j2)
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml \
  -e "cert_name=my-sensor cert_namespace=home-automation cert_cn=my-sensor cert_secret_name=my-sensor-mqtt-client" \
  --tags mosquitto
```

Or add a Certificate object to `manifests/home-automation/prereqs/certificates.yaml` directly and let ArgoCD apply it.

See `specs/016-home-automation-stack/quickstart.md` for VLAN-segmented IoT device setup.

### Integration wiring

| From | To | Protocol | Auth |
|------|----|----------|------|
| Home Assistant | Mosquitto | MQTTS (8883) | mTLS client cert (`home-assistant-mqtt-client`) |
| Node-RED | Mosquitto | MQTTS (8883) | mTLS client cert (`node-red-mqtt-client`) |
| Home Assistant | InfluxDB | HTTP (8086) | Bearer token (`INFLUXDB_TOKEN` env var) |
| IoT devices | Mosquitto | MQTTS (8883) | mTLS client cert + password file |

Mosquitto is LAN-only (K3s ServiceLB exposes it at `10.1.20.11:8883`). It is not routed through Traefik or the Cloudflare tunnel.

The InfluxDB token and org ID are stored in the `home-assistant-influxdb` SealedSecret and injected into the Home Assistant container as environment variables (`INFLUXDB_TOKEN`, `INFLUXDB_ORG_ID`). The `influxdb2.yaml` package config reads them via `!env_var`.

## NVR — Frigate + Hailo-8

Dedicated NVR host at `10.1.10.11` running Frigate with Hailo-8 PCIe object detection. Event clips are stored on a Longhorn RWX volume (50Gi, NFS-mounted). The cluster Traefik ingress exposes `frigate.fleet1.cloud`. Detection events are published to the MQTT broker for Home Assistant consumption.

See `specs/041-nvr-frigate-hailo/quickstart.md` for the full operator runbook.

### First-time provisioning (two-phase)

**Phase A** — provision host, install Hailo driver, render Frigate config:

```bash
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml \
  --tags host-setup,hailo,frigate-config
```

Then push the branch, merge via PR, and wait for ArgoCD to sync `manifests/frigate/`. Once the Longhorn share-manager pod is Running, obtain the NFS endpoint:

```bash
kubectl get svc -n longhorn-system -l longhorn.io/pvc-name=frigate-clips \
  -o jsonpath='{.items[0].spec.clusterIP}'
```

Set `nvr_longhorn_nfs_ip` and `nvr_longhorn_nfs_path` in `group_vars/all.yml`.

**Phase B** — configure NFS mount and start Frigate:

```bash
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml \
  --tags nfs-mount,frigate-service
```

### Re-provisioning

Safe to run without tags at any time:

```bash
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml
```

### Integration wiring

| From | To | Protocol | Auth |
|------|----|----------|------|
| Frigate | Mosquitto | MQTTS (8883) | mTLS client cert (`nvr_mqtt_client_cert`) |
| Traefik | Frigate | HTTP (5000) | n/a (Traefik terminates TLS externally) |
| Home Assistant | Frigate | HTTPS (frigate.fleet1.cloud) | Frigate auth |
