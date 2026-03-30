# Research: Static Site with End-to-End TLS

**Feature**: 004-static-site-tls
**Date**: 2026-03-30

---

## Decision 1: cert-manager Helm Install on K3s arm64

**Decision**: Install cert-manager via Helm from `https://charts.jetstack.io` with `crds.enabled=true`, `--wait --timeout 3m`, followed by an explicit `kubectl rollout status deployment/cert-manager-webhook` wait before applying any CRDs.

**Key parameters**:
```yaml
# Helm values (cert-manager-values.yaml)
crds:
  enabled: true
global:
  leaderElection:
    namespace: cert-manager
```

**K3s arm64 notes**:
- Official chart ships multi-arch images since v1.8 — no `nodeSelector` or image overrides needed on Raspberry Pi OS arm64
- `leaderElection.namespace: cert-manager` avoids a rare leader-election collision with k3s-managed controllers in `kube-system`
- `crds.enabled` key changed from `installCRDs` in v1.15+ — pin version in defaults to avoid surprise breaks
- An explicit webhook rollout wait is required: even with `--wait`, there is a ~5s window after Helm success where the webhook TLS cert is not yet injected; applying a ClusterIssuer in that window produces `x509: certificate signed by unknown authority` errors

**Recommended version**: v1.14.5 (stable, pre-CRD-rename — uses `crds.enabled` in Helm chart values consistently)

**Alternatives considered**:
- `kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/...`: rejected — not idempotent, harder to version-pin in Ansible
- Manual cert with Cloudflare Origin Certificate: rejected — violates Principle IV (PKI lifecycle must be managed as code) and requires manual renewal

---

## Decision 2: Cloudflare DNS-01 ClusterIssuer Pattern

**Decision**: Use a `ClusterIssuer` with a Cloudflare DNS-01 solver. The Cloudflare API token is stored in a Kubernetes `Secret` in the `cert-manager` namespace (the namespace ClusterIssuer solvers read from). Use the explicit `Certificate` CR approach (not Ingress annotations) for better debuggability.

**Cloudflare API token minimum permissions**:
- Zone → DNS → Edit
- Zone → Zone → Read

**Resource chain**:
```
group_vars/all.yml (cloudflare_api_token)
  → Secret/cloudflare-api-token-secret (ns: cert-manager)
  → ClusterIssuer/letsencrypt-prod
  → Certificate/fleet1-cloud-tls (ns: traefik)
  → Secret/fleet1-cloud-tls (ns: traefik)  ← Traefik TLS secret
```

**Secret format** (key name must be exactly `api-token`):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token-secret
  namespace: cert-manager
type: Opaque
stringData:
  api-token: "{{ cloudflare_api_token }}"
```

**ClusterIssuer**:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: "{{ acme_email }}"
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
```

**Certificate CR** (placed in `traefik` namespace to co-locate with the consuming workload):
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: fleet1-cloud-tls
  namespace: traefik
spec:
  secretName: fleet1-cloud-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - fleet1.cloud
```

**Verification command**:
```bash
kubectl wait certificate/fleet1-cloud-tls -n traefik --for=condition=Ready --timeout=300s
```

**Key gotchas**:
- `email` field is mandatory — Let's Encrypt refuses registration without it
- Secret must be in `cert-manager` namespace for ClusterIssuer solvers (not the Certificate's namespace)
- DNS propagation: Cloudflare is near-instant (~30s); cert-manager default wait is 60s — conservative but reliable
- Staging: use `https://acme-staging-v02.api.letsencrypt.org/directory` first to verify pipeline; switch to production after confirming DNS-01 works (rate limit: 5 duplicate certs/week)
- The Ansible template task for the Secret must use `no_log: true` to prevent the token appearing in `-v` output; the rendered temp file must be deleted immediately after `kubectl apply`

**Alternatives considered**:
- Ingress annotation (`cert-manager.io/cluster-issuer`): rejected — creates an implicit Certificate CR that is harder to inspect and debug; explicit CR is the recommended approach per cert-manager docs
- `step-ca` internal CA: rejected — adds more infrastructure than justified for a single public domain

---

## Decision 3: Traefik v3 Helm Values (websecure + HTTP→HTTPS redirect)

**Decision**: Update `roles/traefik/files/values.yaml` to:
1. Add `websecure` NodePort on 30443 with `tls.enabled: true`
2. Add `ports.web.redirectTo.port: websecure` for global HTTP→HTTPS redirect
3. Enable `kubernetesCRD` provider (needed for IngressRoute + Middleware resources)

**Updated values.yaml**:
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

**How `redirectTo` works**: The redirect fires at the entrypoint level — before any routing rule. Every HTTP request to port 30080 gets a 301 to HTTPS before Traefik evaluates any Ingress or IngressRoute. This is the Traefik v3 Helm-native approach; using `additionalArguments` with raw CLI flags is the v2 pattern and should be avoided.

**Note on previous values.yaml**: The `ports.web.nodePort: 30080` explicit value replaces the previous implied mapping. The previous `publishedService.enabled: true` under kubernetesIngress is removed — it was only needed for LoadBalancer service type IP propagation to Ingress status.

**Alternatives considered**:
- `redirectScheme` Middleware applied per-Ingress: rejected — requires middleware attachment on every Ingress; entrypoint-level redirect is global and simpler
- Keep websecure as LoadBalancer: rejected — previous feature established NodePort avoids klipper-lb dependency

---

## Decision 4: Wildcard Subdomain Redirect (Traefik v3 IngressRoute + Middleware)

**Decision**: Use a `Middleware` (redirectRegex) + `IngressRoute` (HostRegexp) to catch all `*.fleet1.cloud` requests and redirect permanently to `https://fleet1.cloud`. Standard Kubernetes Ingress cannot do wildcard host matching — IngressRoute CRD is required.

**Critical Traefik v3 syntax change** (HostRegexp):
- v2: `HostRegexp("{subdomain:.+}.fleet1.cloud")` — named capture group syntax
- v3: `HostRegexp(` + "`" + `^[^.]+\.fleet1\.cloud$` + "`" + `)` — plain Go regex string

Using v2 syntax in v3 silently fails to match. This is the most common v2→v3 migration bug.

**Middleware** (API group is `traefik.io/v1alpha1` in v3 — not `traefik.containo.us/v1alpha1`):
```yaml
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
```

**IngressRoute**:
```yaml
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

**Priority**: Setting `priority: 1` ensures this catch-all does not intercept specific valid routes (e.g., `whoami.fleet1.cloud` which has a more specific Host() rule with higher implicit priority). Lower number = lower priority in Traefik.

**Two-step redirect flow for HTTP subdomains**:
1. `http://www.fleet1.cloud:30080` → entrypoint-level redirect → `https://www.fleet1.cloud:30443` (301)
2. `https://www.fleet1.cloud:30443` → wildcard IngressRoute redirect → `https://fleet1.cloud` (301)

This is correct behaviour and the simpler setup than adding a second HTTP-entrypoint IngressRoute.

**Alternatives considered**:
- Catch-all via standard Kubernetes Ingress: rejected — `spec.rules[].host` does not support wildcard patterns in a way that supports middleware attachment
- Per-subdomain redirect rules: rejected — not scalable and violates Principle V

---

## Decision 5: Static Site Deployment

**Decision**: Deploy a minimal nginx pod serving a single `index.html` page from a `ConfigMap`. A standard Kubernetes `Ingress` for `fleet1.cloud` references the cert-manager-issued TLS secret directly via `spec.tls[].secretName`.

**Ingress for apex domain**:
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

**How Traefik discovers the cert**: Traefik's Kubernetes Ingress provider watches Ingress objects. When it sees `spec.tls[].secretName`, it reads the Secret from the Kubernetes API. The Secret must be in the same namespace as the Ingress. No `tls.stores` configuration is needed for per-Ingress certs.

**Namespace**: `traefik` — co-locate with Traefik and the Certificate Secret for simplicity (avoids cross-namespace Secret reads which require additional Traefik RBAC configuration).

**Alternatives considered**:
- Traefik `IngressRoute` CRD for the static site: rejected — standard Ingress is sufficient and simpler (Principle V)
- Separate `site` namespace: rejected — adds namespace management overhead; no benefit at homelab scale

---

## Decision 6: Cloudflared Tunnel Update (HTTPS Backend)

**Decision**: Switch from dashboard-managed routes to a local `config.yml` managed via an Ansible Jinja2 template. Update `ExecStart` to use `--config /etc/cloudflared/config.yml`. Add `originServerName: fleet1.cloud` to all HTTPS backend ingress rules.

**Rationale for local config**: Aligns with Principle I (Infrastructure as Code) and Principle II (Idempotency). Dashboard-managed routes cannot be reproduced from the repository alone (violates Principle III). The local config approach also allows `originServerName` to be set declaratively in code, which is required for verified TLS.

**Why `originServerName` is mandatory**: When cloudflared opens TLS to `https://10.1.20.11:30443`, without `originServerName` the SNI defaults to the IP address. Let's Encrypt certs have no IP SANs — verification fails. With `originServerName: fleet1.cloud`, the SNI sent is `fleet1.cloud`, Traefik presents the matching cert, and verification passes against Debian's system CA bundle.

**Config template** (`roles/cloudflared/templates/config.yml.j2`):
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

**Variables** (in `group_vars/compute.yml`):
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

**ExecStart change** (in cloudflared systemd unit template):
```
ExecStart=/usr/bin/cloudflared tunnel run --config /etc/cloudflared/config.yml
```

**Idempotency**: Ansible `template` module compares rendered output to file on disk. The existing `notify: Restart cloudflared` handler only fires on change — no restart if config is unchanged.

**Note on credentials**: The `credentials.json` file contains the tunnel credentials. In the current `--token-file` mode, credentials are embedded in the token. Switching to `--config` mode requires the credentials file to be present at `/etc/cloudflared/credentials.json`. The tunnel credentials can be obtained by running `cloudflared tunnel token --creds-file /etc/cloudflared/credentials.json <tunnel-name>` once, then Ansible manages the resulting file. The tunnel UUID (`cloudflare_tunnel_id`) is displayed in the Zero Trust dashboard.

**Alternative**: Dashboard-managed routes (no Ansible changes needed for routing, just add `originServerName` in UI): rejected — violates Principle I; not reproducible from repository.
