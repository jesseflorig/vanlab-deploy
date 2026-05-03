# Implementation Plan: Tailscale Remote Access for fleet1.lan

**Branch**: `059-tailscale-remote-access` | **Date**: 2026-04-30 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/059-tailscale-remote-access/spec.md`

## Summary

Install Tailscale on all 8 managed nodes via a new Ansible role; configure the three K3s server nodes as subnet routers advertising all six lab subnets; wire up split-DNS for `fleet1.lan` via the Tailscale admin console. Layer mTLS device-certificate verification on Traefik using a new Device CA (cert-manager) and per-route TLSOption CRDs — applied only to `fleet1.lan` IngressRoute resources — so that only the management laptop (holding the issued client cert) can access internal services.

## Technical Context

**Language/Version**: YAML (Ansible 2.x), YAML (Kubernetes manifests / Traefik CRDs / cert-manager CRDs)
**Primary Dependencies**:
- Tailscale apt package (packages.tailscale.com, arm64 — confirmed available)
- cert-manager (already deployed as cluster infrastructure, `roles/cert-manager`)
- Traefik (already deployed as cluster infrastructure, `roles/traefik`)
- Bitnami Sealed Secrets (already deployed — not needed for this feature but context)

**Storage**: N/A — Tailscale daemon is stateless; device cert private key lives in cluster-managed K8s Secret (never committed to Git)
**Testing**: `ansible-playbook --check`, `tailscale status --json` verification tasks, `curl` with/without client cert against fleet1.lan service
**Target Platform**: Raspberry Pi OS (Debian arm64) for all cluster/compute/nvr nodes
**Project Type**: Infrastructure automation (IaC)
**Performance Goals**: N/A
**Constraints**: arm64 package availability required; Tailscale auth key must never be committed in plaintext; fleet1.lan mTLS must NOT apply to fleet1.cloud routes (which are public-facing)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. IaC | ✅ Pass | Tailscale via Ansible role; Device CA + TLSOption via Ansible kubectl tasks; IngressRoute updates via ArgoCD manifests |
| II. Idempotency | ✅ Pass | `tailscale status` guard before `tailscale up`; `--dry-run -o yaml \| kubectl apply` for K8s resources |
| III. Reproducibility | ✅ Pass | Auth key in `group_vars/all.yml`; all role tasks fully automated |
| IV. Secrets Hygiene | ✅ Pass | Auth key in Ansible Vault (`group_vars/all.yml`); CA private key managed by cert-manager, never committed; laptop cert/key exported to a local file, never committed |
| V. Simplicity | ✅ Pass | Official Tailscale apt package; Device CA reuses existing pki role pattern; no custom coordination server |
| VI. Encryption in Transit | ✅ Pass | Tailscale tunnel uses WireGuard encryption for all remote traffic |
| VII. Least Privilege | ✅ Pass | mTLS device cert directly implements this principle for management access |
| VIII. Persistent Storage | N/A | No stateful K8s storage required |
| IX. Secure Service Exposure | ✅ Pass | mTLS adds device-level authentication on top of existing HTTPS |
| X. Intra-Cluster Locality | ✅ Pass | TLSOption applied only to fleet1.lan IngressRoutes; fleet1.cloud routes and intra-cluster service-to-service traffic unaffected |
| XI. GitOps Application Deployment | ✅ Pass | Tailscale + Device CA are infrastructure (Ansible); IngressRoute mTLS updates go through `manifests/` → ArgoCD |

No violations. No complexity justifications required.

**Post-Phase 1 re-check**: Confirmed — Device CA follows the existing `pki` role pattern (SelfSigned → CA → Issuer) and does not introduce new patterns.

## Project Structure

### Documentation (this feature)

```text
specs/059-tailscale-remote-access/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (configuration schema)
├── quickstart.md        # Phase 1 output (deployment runbook)
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
# New Ansible role — Tailscale daemon
roles/tailscale/
├── tasks/
│   └── main.yml          # Install, enroll, configure routes, disable key expiry
└── defaults/
    └── main.yml          # tailscale_advertise_routes (server nodes only), tailscale_auth_key ref

# New Ansible role — Device CA + Traefik TLSOption
roles/device-mtls/
├── tasks/
│   └── main.yml          # Apply Device CA, Client Cert, extract CA cert, apply TLSOption
└── templates/
    ├── device-ca-cert.yaml.j2        # cert-manager CA Certificate (isCA: true)
    ├── device-ca-issuer.yaml.j2      # cert-manager CA-based ClusterIssuer
    ├── device-client-cert.yaml.j2    # cert-manager Certificate for management laptop
    ├── device-ca-public-secret.yaml.j2  # Opaque Secret with CA cert only (for Traefik)
    └── device-tls-option.yaml.j2     # Traefik TLSOption: RequireAndVerifyClientCert

# New playbooks
playbooks/compute/tailscale-deploy.yml   # Runs tailscale role on cluster + compute + nvr
playbooks/cluster/device-mtls-deploy.yml # Runs device-mtls role on servers (run_once)

# group_vars additions
group_vars/all.yml                  # Add: tailscale_auth_key (Ansible Vault encrypted)
group_vars/example.all.yml          # Add: tailscale_auth_key: "<REPLACE_WITH_TAILSCALE_AUTH_KEY>"

# Existing IngressRoute manifests to update (add tls.options per fleet1.lan route)
# Pattern: each fleet1.lan hostname needs a standalone IngressRoute with TLSOption
# Fleet1.cloud routes remain in the existing Ingress/IngressRoute unchanged
manifests/frigate/
└── ingressroute-lan.yaml           # New: frigate.fleet1.lan IngressRoute + TLSOption

# For Helm-based services (Gitea, ArgoCD, kube-prometheus-stack, etc.):
# The existing Helm chart Ingress covers both fleet1.cloud + fleet1.lan in one resource.
# Fleet1.lan routes are split into standalone IngressRoute CRDs in manifests/:
manifests/gitea/
└── fleet1-lan-ingressroute.yaml    # gitea.fleet1.lan standalone IngressRoute + TLSOption
manifests/argocd/
└── fleet1-lan-ingressroute.yaml    # argocd.fleet1.lan standalone IngressRoute + TLSOption
manifests/monitoring/
└── fleet1-lan-ingressroutes.yaml   # grafana/prometheus/alertmanager fleet1.lan IngressRoutes
manifests/home-automation/
└── fleet1-lan-ingressroutes.yaml   # ha/influxdb/nodered fleet1.lan IngressRoutes + TLSOption
```

**Structure Decision**: Two new Ansible roles keep concerns separated per Principle V. Tailscale daemon is a node-level concern; Device CA + TLSOption is a cluster-level concern. IngressRoute mTLS updates are in `manifests/` (ArgoCD-managed) to maintain the GitOps split. Fleet1.lan routes are split out from their existing Helm-chart-managed Ingress resources into standalone IngressRoute CRDs that can carry the TLSOption.

## Complexity Tracking

No constitution violations. No complexity justifications required.
