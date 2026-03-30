# Implementation Plan: Cluster Provisioning and Internet Exposure

**Branch**: `003-cluster-tunnel-expose` | **Date**: 2026-03-29 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/003-cluster-tunnel-expose/spec.md`

## Summary

Fix the K3s agent join bug (add server readiness wait + replace broken `creates:` guard with node-registration check), disable K3s's built-in Traefik, deploy Traefik v3 via Helm with HTTP-only values (Cloudflare terminates TLS), deploy a `traefik/whoami` test app with a standard Ingress, and expose it at `whoami.fleet1.cloud` via the existing Cloudflare tunnel. Cloudflare public hostname configuration remains a manual dashboard step.

## Technical Context

**Language/Version**: YAML (Ansible 2.x) — existing project conventions
**Primary Dependencies**:
- `k3s` — K3s server/agent install via `get.k3s.io` install script
- `helm` v3.14 — already installed by `roles/helm`
- `traefik/traefik` Helm chart v3.x from `traefik.github.io/charts`
- `traefik/whoami` container image — lightweight test app
- `kubectl` — available on server nodes after K3s install

**Storage**: N/A
**Testing**: Manual smoke tests per quickstart.md; idempotency verified by re-run
**Target Platform**: Raspberry Pi OS arm64 (4x CM5 cluster nodes)
**Project Type**: ansible-playbook (infrastructure management)
**Performance Goals**: N/A — provisioning automation
**Constraints**: All steps idempotent; no new secrets patterns; Cloudflare hostname config is manual
**Scale/Scope**: 4 cluster nodes (2 servers, 2 agents), 1 edge device (unchanged)

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Infrastructure as Code | ✅ PASS | All changes in playbooks/roles; no manual cluster steps |
| II. Idempotency | ✅ PASS | Agent join uses node-registration check; Helm uses `--install`; `kubectl apply` is idempotent |
| III. Reproducibility | ✅ PASS | Resolves the documented agent-join workaround; cluster fully rebuildable from playbooks |
| IV. Secrets Hygiene | ✅ PASS | K3s join token read at runtime from server; never committed |
| V. Simplicity | ✅ PASS | `kubectl apply` over collection; standard Ingress over IngressRoute CRD |
| VI. Encryption in Transit | ⚠️ EXCEPTION | Edge (10.1.10.x) → Traefik (10.1.20.x) is HTTP across VLAN boundary. Accepted: Cloudflare tunnel encrypts the public leg; internal hop is on a trusted network. Follow-on: add HTTPS backend to tunnel. |
| VII. Least Privilege | N/A | No new cross-VLAN routing rules in this feature |

**Post-design re-check**: VI exception is documented and justified. All other gates pass.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| VI — HTTP cross-VLAN | Cloudflare tunnel HTTP backend is the standard Cloudflare pattern for homelab ingress | Adding TLS on Traefik requires cert-manager or self-signed cert + tunnel `noTLSVerify` — out of scope for this feature; deferred to follow-on |

## Project Structure

### Documentation (this feature)

```text
specs/003-cluster-tunnel-expose/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── tasks.md
```

### Repository Root (after this feature)

```text
vanlab/
├── playbooks/
│   └── cluster/
│       ├── k3s-deploy.yml         # UPDATED — agent join fix, --disable traefik, node status
│       └── services-deploy.yml    # UPDATED — Traefik + whoami, wireguard removed from scope
│
└── roles/
    ├── traefik/
    │   ├── tasks/main.yml         # UPDATED — values file, --wait, HTTP-only, LB IP display
    │   └── files/
    │       └── values.yaml        # NEW — Traefik v3 Helm values
    └── whoami/                    # NEW
        ├── tasks/main.yml
        └── files/
            └── whoami.yaml        # K8s Deployment + Service + Ingress
```

## Key Implementation Notes

### K3s Deploy Changes (k3s-deploy.yml)

**Server play additions:**
- Add `--disable traefik` to `INSTALL_K3S_EXEC` to prevent K3s built-in Traefik conflicting with our Helm-deployed instance
- Add `wait_for: port: 6443` after server install before reading the token
- Read token with `slurp` + `b64decode | trim` (the `trim` is required — the token file has a trailing newline)

**Agent play fixes:**
- Replace `creates: /etc/systemd/system/k3s-agent.service` with a pre-check: `kubectl get node {{ inventory_hostname }}` via `delegate_to: node1`
- Only run the curl install when the node is NOT already registered
- After install: `kubectl wait --for=condition=Ready node/{{ inventory_hostname }}` via `delegate_to: node1`

**New final play — cluster status:**
- Run `kubectl get nodes -o wide` on node1 and display via `debug` (satisfies FR-008)

### Traefik Role Changes

**tasks/main.yml**: Copy `values.yaml` to `/tmp/traefik-values.yaml` on the server, then run `helm upgrade --install --values /tmp/traefik-values.yaml --wait --timeout 3m`. After Helm returns, wait for the LoadBalancer IP to be assigned (K3s klipper-lb takes 30–60s), then display it with `debug` so the operator knows what IP to enter in the Cloudflare dashboard.

**files/values.yaml**: `web` entrypoint exposed on port 80; `websecure` TLS disabled; dashboard disabled; `kubernetesIngress` provider enabled with `publishedService.enabled: true` so Ingress `.status.loadBalancer.ingress` is populated.

### Whoami Role (new)

**tasks/main.yml**: Copy `whoami.yaml` to `/tmp/whoami.yaml`, run `kubectl apply -f /tmp/whoami.yaml`, then `kubectl rollout status deployment/whoami -n traefik`.

**files/whoami.yaml**: Standard Kubernetes Ingress (not Traefik IngressRoute CRD) with:
- `traefik.io/router.entrypoints: web` annotation (Traefik v3 format)
- `ingressClassName: traefik`
- Host rule: `whoami.fleet1.cloud`

### services-deploy.yml Changes

Remove `wireguard` from the servers play (out of scope per spec assumptions). Final roles list: `helm`, `traefik`, `whoami`.
