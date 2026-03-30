# Data Model: Static Site with End-to-End TLS

**Feature**: 004-static-site-tls
**Date**: 2026-03-30

---

## Repository Structure (Changes Only)

```text
vanlab/
├── group_vars/
│   ├── compute.yml              # UPDATED — cloudflare_tunnel_id, cloudflared_ingress_rules
│   └── example.all.yml          # UPDATED — cloudflare_api_token, acme_email placeholders
│
├── playbooks/
│   ├── cluster/
│   │   └── services-deploy.yml  # UPDATED — add cert-manager and static-site roles
│   └── compute/
│       └── edge-deploy.yml      # UPDATED — add config.yml template task
│
└── roles/
    ├── cert-manager/            # NEW
    │   ├── defaults/main.yml
    │   ├── tasks/main.yml
    │   └── templates/
    │       ├── cloudflare-secret.yaml.j2
    │       ├── cluster-issuer.yaml.j2
    │       └── certificate.yaml.j2
    ├── cloudflared/             # UPDATED
    │   ├── defaults/main.yml    # UPDATED — add cloudflare_tunnel_id, cloudflared_ingress_rules
    │   ├── tasks/main.yml       # UPDATED — add config.yml template task + ExecStart update
    │   └── templates/           # NEW directory
    │       └── config.yml.j2
    ├── static-site/             # NEW
    │   ├── tasks/main.yml
    │   └── files/
    │       └── site.yaml        # Deployment + Service + Ingress + Middleware + IngressRoute
    └── traefik/
        └── files/
            └── values.yaml      # UPDATED — add websecure NodePort 30443, HTTP→HTTPS redirect, kubernetesCRD provider
```

---

## Playbook Changes

### playbooks/cluster/services-deploy.yml (updated)

**Play 1 — Install cluster services** (`hosts: servers`)
- Roles: `helm`, `cert-manager`, `traefik`, `whoami`, `static-site`
- `cert-manager` must precede `traefik` (Traefik updated values reference websecure which must exist)
- `cert-manager` must precede `static-site` (static-site waits for certificate Ready)

### playbooks/compute/edge-deploy.yml (updated)

**Play 1 — Deploy edge services** (`hosts: compute`)
- Existing `cloudflared` role gains a new template task; no new role added

---

## Role Schemas

### roles/cert-manager/defaults/main.yml (new)

```yaml
cert_manager_version: "v1.14.5"
cert_manager_namespace: "cert-manager"
acme_server: "https://acme-v02.api.letsencrypt.org/directory"
certificate_namespace: "traefik"
certificate_secret_name: "fleet1-cloud-tls"
# Required in group_vars/all.yml (gitignored):
#   cloudflare_api_token: "<token>"
#   acme_email: "<email>"
```

### roles/cert-manager/tasks/main.yml (new)

| Step | Module | Key params |
|------|--------|-----------|
| Add jetstack Helm repo | `command` | `helm repo add jetstack https://charts.jetstack.io` |
| Update repos | `command` | `helm repo update` |
| Ensure namespace | `shell` | `kubectl create namespace cert-manager --dry-run=client -o yaml \| kubectl apply -f -` |
| Install cert-manager | `command` | `helm upgrade --install cert-manager --set crds.enabled=true --wait --timeout 3m` |
| Wait for webhook | `command` | `kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=120s` |
| Template Cloudflare Secret | `template` | src: `cloudflare-secret.yaml.j2`, dest: `/tmp/cf-secret.yaml`, `no_log: true` |
| Apply Cloudflare Secret | `command` | `kubectl apply -f /tmp/cf-secret.yaml` |
| Remove temp secret file | `file` | `state: absent` |
| Template ClusterIssuer | `template` | src: `cluster-issuer.yaml.j2`, dest: `/tmp/cluster-issuer.yaml` |
| Apply ClusterIssuer | `command` | `kubectl apply -f /tmp/cluster-issuer.yaml` |
| Template Certificate CR | `template` | src: `certificate.yaml.j2`, dest: `/tmp/fleet1-certificate.yaml` |
| Apply Certificate CR | `command` | `kubectl apply -f /tmp/fleet1-certificate.yaml` |
| Wait for cert Ready | `command` | `kubectl wait certificate/fleet1-cloud-tls -n traefik --for=condition=Ready --timeout=300s` |

### roles/cert-manager/templates/ (new)

**cloudflare-secret.yaml.j2**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token-secret
  namespace: {{ cert_manager_namespace }}
type: Opaque
stringData:
  api-token: "{{ cloudflare_api_token }}"
```

**cluster-issuer.yaml.j2**:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: {{ acme_email }}
    server: {{ acme_server }}
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
```

**certificate.yaml.j2**:
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: fleet1-cloud-tls
  namespace: {{ certificate_namespace }}
spec:
  secretName: {{ certificate_secret_name }}
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - fleet1.cloud
```

---

### roles/traefik/files/values.yaml (updated)

```yaml
service:
  type: NodePort

ports:
  web:
    port: 8000
    exposedPort: 80
    protocol: TCP
    nodePort: 30080
    redirectTo:
      port: websecure
      permanent: true
  websecure:
    port: 8443
    exposedPort: 443
    protocol: TCP
    nodePort: 30443
    tls:
      enabled: true

ingressRoute:
  dashboard:
    enabled: false

providers:
  kubernetesCRD:
    enabled: true
  kubernetesIngress:
    enabled: true

logs:
  access:
    enabled: true
```

---

### roles/static-site/tasks/main.yml (new)

| Step | Module | Key params |
|------|--------|-----------|
| Copy site manifest | `copy` | src: `files/site.yaml`, dest: `/tmp/site.yaml` |
| Apply site manifest | `command` | `kubectl apply -f /tmp/site.yaml` |
| Wait for rollout | `command` | `kubectl rollout status deployment/static-site -n traefik --timeout=60s` |

### roles/static-site/files/site.yaml (new)

Contains 5 resources:

**1. ConfigMap** — static HTML content:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: static-site-html
  namespace: traefik
data:
  index.html: |
    <!DOCTYPE html>
    <html lang="en">
    <head><meta charset="UTF-8"><title>fleet1.cloud</title></head>
    <body><h1>fleet1.cloud</h1><p>Coming soon.</p></body>
    </html>
```

**2. Deployment** — nginx serving the ConfigMap:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: static-site
  namespace: traefik
spec:
  replicas: 1
  selector:
    matchLabels:
      app: static-site
  template:
    metadata:
      labels:
        app: static-site
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
      volumes:
        - name: html
          configMap:
            name: static-site-html
```

**3. Service** — ClusterIP:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: static-site
  namespace: traefik
spec:
  selector:
    app: static-site
  ports:
    - port: 80
      targetPort: 80
```

**4. Ingress** — apex domain with TLS secret:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fleet1-cloud
  namespace: traefik
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - fleet1.cloud
      secretName: fleet1-cloud-tls
  rules:
    - host: fleet1.cloud
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: static-site
                port:
                  number: 80
```

**5. Middleware + IngressRoute** — wildcard subdomain redirect:
```yaml
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-to-apex
  namespace: traefik
spec:
  redirectRegex:
    regex: "^https?://[^.]+\\.fleet1\\.cloud(.*)"
    replacement: "https://fleet1.cloud${1}"
    permanent: true
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: wildcard-subdomain-redirect
  namespace: traefik
spec:
  entryPoints:
    - websecure
  tls:
    secretName: fleet1-cloud-tls
  routes:
    - match: HostRegexp(`^[^.]+\.fleet1\.cloud$`)
      kind: Rule
      priority: 1
      middlewares:
        - name: redirect-to-apex
      services:
        - name: noop@internal
          kind: TraefikService
```

---

### roles/cloudflared/ (updated)

**defaults/main.yml additions**:
```yaml
cloudflare_tunnel_id: ""          # Set in group_vars/compute.yml
cloudflared_ingress_rules: []     # Set in group_vars/compute.yml
```

**templates/config.yml.j2** (new):
```yaml
tunnel: {{ cloudflare_tunnel_id }}
credentials-file: /etc/cloudflared/credentials.json

ingress:
{% for rule in cloudflared_ingress_rules %}
  - hostname: {{ rule.hostname }}
    service: {{ rule.service }}
{% if rule.originServerName is defined %}
    originRequest:
      originServerName: {{ rule.originServerName }}
{% endif %}
{% endfor %}
  - service: http_status:404
```

**tasks/main.yml additions**:
- Deploy `config.yml.j2` template to `/etc/cloudflared/config.yml` with `notify: Restart cloudflared`
- Update systemd unit `ExecStart` to use `--config /etc/cloudflared/config.yml`

---

## group_vars Changes

### group_vars/compute.yml (updated)

```yaml
# Existing:
cloudflared_service_name: cloudflared
cloudflared_token_path: /etc/cloudflared/tunnel-token

# New:
cloudflare_tunnel_id: "<TUNNEL-UUID-from-dashboard>"

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

### group_vars/example.all.yml (updated)

Add placeholders:
```yaml
# cert-manager / Let's Encrypt
cloudflare_api_token: "<CLOUDFLARE_API_TOKEN_WITH_DNS_EDIT_PERMISSION>"
acme_email: "<YOUR_EMAIL_FOR_LETSENCRYPT_EXPIRY_NOTICES>"
```

---

## Secrets Not in Repository

| Secret | Storage | Notes |
|--------|---------|-------|
| `cloudflare_api_token` | `group_vars/all.yml` (gitignored) | Zone:DNS:Edit + Zone:Zone:Read scoped token |
| `acme_email` | `group_vars/all.yml` (gitignored) | Email for Let's Encrypt account registration |
| `cloudflare_tunnel_id` | `group_vars/compute.yml` (committed) | UUID only — not a secret, but needed for config.yml |
| Let's Encrypt account key | Kubernetes Secret `letsencrypt-prod-account-key` (auto-created by cert-manager) | Never committed |
| TLS certificate+key | Kubernetes Secret `fleet1-cloud-tls` in `traefik` ns (auto-created by cert-manager) | Never committed |
| Cloudflare tunnel credentials | `/etc/cloudflared/credentials.json` on CM5 | Managed separately; not in repo |
