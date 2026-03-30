# Data Model: Cluster Provisioning and Internet Exposure

**Feature**: 003-cluster-tunnel-expose
**Date**: 2026-03-29

---

## Repository Structure (Changes Only)

```text
vanlab/
├── playbooks/
│   └── cluster/
│       ├── k3s-deploy.yml          # UPDATED — agent join fix, --disable traefik, node status display
│       └── services-deploy.yml     # UPDATED — Traefik + whoami only (no wireguard)
│
└── roles/
    ├── traefik/
    │   ├── tasks/main.yml          # UPDATED — values file, --wait flag, HTTP-only
    │   └── files/
    │       └── values.yaml         # NEW — Helm values for Traefik v3
    └── whoami/                     # NEW
        ├── tasks/main.yml          # apply manifest, wait for rollout, display LB IP
        └── files/
            └── whoami.yaml         # K8s Deployment + Service + Ingress
```

---

## Playbook Changes

### playbooks/cluster/k3s-deploy.yml (updated)

**Play 1 — Prepare cluster nodes** (`hosts: cluster`)
- Disable swap, install packages, kernel modules, sysctl, cgroups — unchanged

**Play 2 — Install K3s server** (`hosts: servers`)
- Add `--disable traefik` to `INSTALL_K3S_EXEC`
- After install: `wait_for port: 6443` on the server host
- Read token from `/var/lib/rancher/k3s/server/token` (slurp + b64decode + trim)
- Set `k3s_node_token` fact

**Play 3 — Install K3s agents** (`hosts: agents`)
- Replace `creates:` guard with `kubectl get node {{ inventory_hostname }}` pre-check via `delegate_to: node1`
- Only run agent install when node is NOT already registered
- After install: `kubectl wait --for=condition=Ready node/{{ inventory_hostname }}` via `delegate_to: node1`

**Play 4 — Display cluster status** (`hosts: node1`)
- `kubectl get nodes -o wide` → register → debug display (satisfies FR-008)

---

### playbooks/cluster/services-deploy.yml (updated)

**Play 1 — Install cluster services** (`hosts: servers`)
- Roles: `helm`, `traefik`, `whoami` (wireguard removed per spec scope)

**Play 2 — Agent services** (`hosts: agents`)
- Unchanged (debug placeholder)

---

## Role Schemas

### roles/traefik/tasks/main.yml (updated)

| Step | Module | Key params |
|------|--------|-----------|
| Add Helm repo | `command` | `helm repo add traefik https://traefik.github.io/charts` |
| Update repos | `command` | `helm repo update` |
| Create namespace | `command` | `kubectl create namespace traefik --dry-run=client -o yaml \| kubectl apply -f -` |
| Copy values file | `copy` | src: `files/values.yaml`, dest: `/tmp/traefik-values.yaml` |
| Install Traefik | `command` | `helm upgrade --install traefik traefik/traefik --namespace traefik --values /tmp/traefik-values.yaml --wait --timeout 3m` |
| Wait for rollout | `command` | `kubectl rollout status deployment/traefik -n traefik --timeout=120s` |
| Wait for LB IP | `command` | `kubectl get svc traefik -n traefik -o jsonpath=...` with `until` loop |
| Display LB IP | `debug` | Show Traefik's external IP for Cloudflare dashboard configuration |

### roles/traefik/files/values.yaml (new)

```yaml
service:
  type: LoadBalancer
ports:
  web:
    port: 80
    expose:
      default: true
    exposedPort: 80
  websecure:
    expose:
      default: false
    tls:
      enabled: false
ingressRoute:
  dashboard:
    enabled: false
providers:
  kubernetesIngress:
    enabled: true
    publishedService:
      enabled: true
logs:
  access:
    enabled: true
```

---

### roles/whoami/tasks/main.yml (new)

| Step | Module | Key params |
|------|--------|-----------|
| Assert cluster ready | `command` | `kubectl get nodes` — fail if any node not Ready |
| Apply manifest | `command` | `kubectl apply -f /tmp/whoami.yaml` |
| Copy manifest | `copy` | src: `files/whoami.yaml`, dest: `/tmp/whoami.yaml` |
| Wait for rollout | `command` | `kubectl rollout status deployment/whoami -n traefik --timeout=60s` |

### roles/whoami/files/whoami.yaml (new)

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  namespace: traefik
spec:
  replicas: 1
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
        - name: whoami
          image: traefik/whoami:latest
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: whoami
  namespace: traefik
spec:
  selector:
    app: whoami
  ports:
    - name: http
      port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  namespace: traefik
  annotations:
    traefik.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: whoami.fleet1.cloud
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: whoami
                port:
                  number: 80
```

---

## group_vars / Inventory Changes

No changes required. All new variables (`k3s_master_ip`, `k3s_flannel_iface`) are already in `group_vars/cluster.yml`.

---

## Cloudflare Dashboard Configuration (manual — out of Ansible scope)

After `services-deploy.yml` runs and displays the Traefik LoadBalancer IP:

1. Go to Zero Trust → Networks → Tunnels → your tunnel → Configure → Public Hostnames
2. Add a public hostname:
   - **Subdomain**: `whoami`
   - **Domain**: `fleet1.cloud`
   - **Type**: HTTP
   - **URL**: `<Traefik LoadBalancer IP>:80`
3. Save — the tunnel picks up the change within seconds
