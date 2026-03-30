# Implementation Plan: Static Site with End-to-End TLS

**Branch**: `004-static-site-tls` | **Date**: 2026-03-30 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/004-static-site-tls/spec.md`

## Summary

Deploy cert-manager via Helm with a Cloudflare DNS-01 ClusterIssuer to automatically obtain and renew a Let's Encrypt certificate for `fleet1.cloud`. Update Traefik values to enable the websecure entrypoint (NodePort 30443) with a global HTTP→HTTPS redirect. Deploy a minimal nginx static site with a standard Kubernetes Ingress referencing the cert-manager TLS secret. Add a Traefik Middleware + IngressRoute to catch all `*.fleet1.cloud` subdomains and redirect permanently to `https://fleet1.cloud`. Switch cloudflared from dashboard-managed routes to a local `config.yml` with `originServerName: fleet1.cloud` for verified end-to-end TLS.

## Technical Context

**Language/Version**: YAML (Ansible 2.x) — existing project conventions
**Primary Dependencies**:
- `jetstack/cert-manager` Helm chart v1.14.5 from `https://charts.jetstack.io`
- `cert-manager.io/v1` CRDs — ClusterIssuer, Certificate
- `traefik.io/v1alpha1` CRDs — Middleware, IngressRoute (v3 API group)
- `nginx:alpine` container image — static site serving
- `cloudflared` — updated from token-only to local config.yml management

**Storage**: N/A — no persistent storage required
**Testing**: Manual smoke tests per quickstart.md; idempotency verified by re-run
**Target Platform**: Raspberry Pi OS arm64 (K3s cluster nodes + CM5 edge device)
**Project Type**: ansible-playbook (infrastructure management)
**Performance Goals**: N/A — provisioning automation
**Constraints**: All steps idempotent; Cloudflare API token never committed; Let's Encrypt staging server used for development, production for final deployment
**Scale/Scope**: 4 cluster nodes, 1 edge device; single public domain

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Infrastructure as Code | ✅ PASS | All changes in playbooks/roles; cloudflared switches from dashboard-managed to code-managed config |
| II. Idempotency | ✅ PASS | cert-manager re-apply is idempotent; Helm `--install`; `kubectl apply` idempotent; cloudflared template only restarts on change |
| III. Reproducibility | ✅ PASS | Cluster fully rebuildable; cert auto-reissues on rebuild via DNS-01 |
| IV. Secrets Hygiene | ✅ PASS | Cloudflare API token in gitignored `all.yml`; rendered Secret temp file deleted immediately after apply; TLS private key stays in cluster Secret, never in repo |
| V. Simplicity | ✅ PASS | Standard Kubernetes Ingress for apex route; IngressRoute CRD only where required (wildcard host matching); nginx:alpine for static site |
| VI. Encryption in Transit | ✅ PASS | This feature closes the previous VI exception; end-to-end TLS is the primary deliverable |
| VII. Least Privilege | ✅ PASS | Cloudflare API token scoped to Zone:DNS:Edit + Zone:Zone:Read only; no broader permissions |

**Post-design re-check**: Feature 003's Principle VI exception (HTTP cross-VLAN) is resolved by this feature. All gates pass.

## Complexity Tracking

No constitution violations requiring justification. cert-manager adds infrastructure complexity but is directly mandated by FR-001 (auto-obtained cert) and FR-002 (auto-renewal) — the only simpler alternative (Cloudflare Origin Certificate) would require manual renewal and is inconsistent with Principle IV's requirement that PKI lifecycle be managed as code.

## Project Structure

### Documentation (this feature)

```text
specs/004-static-site-tls/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── tasks.md
```

### Repository Root (after this feature)

```text
vanlab/
├── group_vars/
│   ├── compute.yml              # UPDATED — cloudflare_tunnel_id, cloudflared_ingress_rules
│   └── example.all.yml          # UPDATED — cloudflare_api_token, acme_email placeholders
│
├── playbooks/
│   ├── cluster/
│   │   └── services-deploy.yml  # UPDATED — cert-manager + static-site roles added
│   └── compute/
│       └── edge-deploy.yml      # UPDATED — config.yml template task
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
    │   ├── defaults/main.yml    # add cloudflare_tunnel_id, cloudflared_ingress_rules defaults
    │   ├── tasks/main.yml       # add config.yml template task, update ExecStart
    │   └── templates/           # NEW
    │       └── config.yml.j2
    ├── static-site/             # NEW
    │   ├── tasks/main.yml
    │   └── files/
    │       └── site.yaml
    └── traefik/
        └── files/
            └── values.yaml      # UPDATED — websecure NodePort 30443, HTTP→HTTPS, kubernetesCRD
```

## Key Implementation Notes

### cert-manager Role (new)

1. Helm install with `crds.enabled=true`, `--wait --timeout 3m`
2. **Mandatory**: explicit `kubectl rollout status deployment/cert-manager-webhook` after Helm — prevents x509 admission errors from applying CRDs too soon
3. Cloudflare API token Secret: rendered via Jinja2 template with `no_log: true`, applied to `cert-manager` namespace, temp file deleted immediately after apply
4. ClusterIssuer: `letsencrypt-prod` using DNS-01 + Cloudflare solver; `email` field is mandatory
5. Certificate CR: placed in `traefik` namespace (same as consuming Traefik instance); `secretName: fleet1-cloud-tls`
6. Final task: `kubectl wait certificate/fleet1-cloud-tls -n traefik --for=condition=Ready --timeout=300s` — blocks until cert is issued (DNS-01 typically completes in 2–5 min)
7. All `kubectl` tasks use `KUBECONFIG: /etc/rancher/k3s/k3s.yaml` environment variable (consistent with existing Traefik role pattern)

### Traefik Role Changes

**files/values.yaml**: Updated to add:
- `ports.web.nodePort: 30080` (explicit pin) + `redirectTo.port: websecure, permanent: true`
- `ports.websecure.nodePort: 30443`, `tls.enabled: true`
- `providers.kubernetesCRD.enabled: true` (needed for Middleware + IngressRoute resources)
- Remove `publishedService.enabled: true` (only needed for LoadBalancer type)

The Traefik Helm upgrade runs with `--wait --timeout 3m` (already in place). The existing pod will restart to pick up the new entrypoint configuration.

### Static Site Role (new)

`roles/static-site/files/site.yaml` contains 5 Kubernetes resources in one file:
1. `ConfigMap/static-site-html` — placeholder HTML
2. `Deployment/static-site` — nginx:alpine, mounts ConfigMap at `/usr/share/nginx/html`
3. `Service/static-site` — ClusterIP port 80
4. `Ingress/fleet1-cloud` — apex domain, `ingressClassName: traefik`, `tls.secretName: fleet1-cloud-tls`, entrypoint annotation: `websecure`
5. `Middleware/redirect-to-apex` — redirectRegex catching `^https?://[^.]+\.fleet1\.cloud(.*)`
6. `IngressRoute/wildcard-subdomain-redirect` — `HostRegexp(` + "`" + `^[^.]+\.fleet1\.cloud$` + "`" + `)`, priority 1, references the Middleware

**Critical v3 syntax**: `HostRegexp` takes a plain Go regex (not v2 named-group syntax). `traefik.io/v1alpha1` API group (not `traefik.containo.us/v1alpha1`).

### Cloudflared Role Changes

**tasks/main.yml additions**:
- Template `config.yml.j2` → `/etc/cloudflared/config.yml` (mode 0600, notify: Restart cloudflared)
- Update systemd unit `ExecStart` line from `--token-file` to `--config /etc/cloudflared/config.yml`

**Pre-requisite for operator** (one-time, before running edge-deploy.yml):
```bash
sudo cloudflared tunnel token --creds-file /etc/cloudflared/credentials.json <TUNNEL-NAME>
```
This generates the credentials file that `config.yml` references. The existing tunnel token file remains for authentication fallback.

### services-deploy.yml Changes

Updated role order:
```yaml
roles:
  - helm
  - cert-manager   # NEW — must precede traefik and static-site
  - traefik
  - whoami
  - static-site    # NEW — must follow cert-manager (waits for cert Ready)
```

### group_vars/compute.yml Changes

Add `cloudflare_tunnel_id` (the tunnel UUID — not a secret, safe to commit) and `cloudflared_ingress_rules` list with per-hostname routing and `originServerName` for HTTPS backends.

### group_vars/example.all.yml Changes

Add placeholder entries for `cloudflare_api_token` and `acme_email` to document the required variables for fresh deployments.
