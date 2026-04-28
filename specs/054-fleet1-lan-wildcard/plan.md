# Implementation Plan: fleet1.lan Local DNS with Internal Wildcard TLS

**Branch**: `054-fleet1-lan-wildcard` | **Date**: 2026-04-27 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/054-fleet1-lan-wildcard/spec.md`

## Summary

Add `fleet1.lan` as an internal-only domain by: (1) provisioning a cert-manager CA chain and
`*.fleet1.lan` wildcard cert stored in the `traefik` namespace, (2) configuring OPNsense Unbound
with a wildcard DNS override and a NAT port-forward so standard HTTPS port 443 reaches Traefik's
NodePort 30443, and (3) distributing the CA root cert to the management laptop via Ansible. Traefik
serves the wildcard cert automatically via SNI using a `TLSStore` CRD.

## Technical Context

**Language/Version**: YAML (Ansible 2.x + Kubernetes manifests)
**Primary Dependencies**: cert-manager (already deployed), Traefik (already deployed), OPNsense
Unbound REST API (`oxlorg.opnsense`), `kubectl` (on cluster server nodes)
**Storage**: N/A — cert-manager secrets are in-cluster etcd; no PVC required
**Testing**: Manual verification via `dig`, `curl`, browser trust check
**Target Platform**: K3s cluster (arm64, Raspberry Pi CM5) + OPNsense router + macOS management laptop
**Project Type**: Infrastructure automation (Ansible role + playbook)
**Performance Goals**: DNS resolution latency ≤ 30ms on LAN; TLS handshake ≤ 300ms
**Constraints**: Wildcard cert must auto-renew; CA private key must never leave the cluster
**Scale/Scope**: Single cluster; single wildcard cert; single management laptop for CA trust

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I — Infrastructure as Code | ✅ Pass | All changes via Ansible playbooks and Kubernetes manifests |
| II — Idempotency | ✅ Pass | `kubectl apply`, API upsert, and fingerprint-guarded keychain install |
| III — Reproducibility | ✅ Pass | PKI role runs as part of `services-deploy.yml`; documented in quickstart |
| IV — Secrets Hygiene | ✅ Pass | CA key in cluster Secret only; never committed; PKI via cert-manager |
| V — Simplicity | ✅ Pass | One new role, two playbook additions, one NAT rule, one DNS override |
| VI — Encryption in Transit | ✅ Pass | `fleet1.lan` is HTTPS-only; no HTTP on internal domain |
| IX — Secure Service Exposure | ✅ Pass | Internal wildcard CA cert; auto-renewed; no self-signed leaf certs |
| XI — GitOps Deployment | ✅ Pass | fleet1.lan PKI is cluster infrastructure → Ansible-managed (not ArgoCD) |

No violations. Complexity Tracking section not required.

## Project Structure

### Documentation (this feature)

```text
specs/054-fleet1-lan-wildcard/
├── plan.md              # This file
├── research.md          # Phase 0 — all decisions documented
├── data-model.md        # Phase 1 — entities and cert chain
├── quickstart.md        # Phase 1 — end-to-end run guide
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
roles/pki/                         ← NEW role — fleet1.lan internal CA + wildcard cert
├── defaults/
│   └── main.yml                   ← cert duration vars, namespace names
├── tasks/
│   └── main.yml                   ← apply selfsigned-issuer (idempotent), CA chain, wildcard cert, TLSStore
└── templates/
    ├── fleet1-lan-ca-issuer.yaml.j2      ← selfsigned-issuer ClusterIssuer (idempotent create)
    ├── fleet1-lan-ca-cert.yaml.j2        ← CA Certificate + CA ClusterIssuer
    ├── fleet1-lan-wildcard-cert.yaml.j2  ← *.fleet1.lan Certificate (traefik namespace)
    └── fleet1-lan-tls-store.yaml.j2      ← TLSStore CRD with fleet1-lan-wildcard-tls

playbooks/cluster/
└── services-deploy.yml            ← UPDATED: include pki role with --tags pki

playbooks/compute/
└── ca-trust-deploy.yml            ← NEW playbook — fetches CA root from cluster, installs to macOS keychain

playbooks/network/
└── network-deploy.yml             ← UPDATED: add Unbound host override + NAT port-forward tasks
```

**Structure Decision**: Single-project layout. The `roles/pki/` role is cluster infrastructure
(analogous to `roles/cert-manager/`). The CA trust playbook lives in `playbooks/compute/` as it
targets the management laptop, consistent with the compute playbook group.
