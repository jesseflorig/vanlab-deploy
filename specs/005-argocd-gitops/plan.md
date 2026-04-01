# Implementation Plan: ArgoCD + Gitea GitOps

**Branch**: `005-argocd-gitops` | **Date**: 2026-03-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/005-argocd-gitops/spec.md`

## Summary

Deploy Gitea (self-hosted Git) and ArgoCD (GitOps controller) to the K3s cluster via
new Ansible roles integrated into the existing `services-deploy.yml` playbook. Gitea
stores GitOps configuration (Helm values, manifests, ArgoCD Application definitions)
with a Longhorn-backed PVC. ArgoCD continuously reconciles the cluster to match the
desired state in Gitea, with sync status visible via a Traefik-fronted HTTPS dashboard.
A third bootstrap role creates the ArgoCD → Gitea repository credential and seeds
initial Application definitions from Ansible variables.

## Technical Context

**Language/Version**: YAML (Ansible 2.x) — existing project convention
**Primary Dependencies**:
- Gitea Helm chart (`gitea-charts/gitea`, `https://dl.gitea.com/charts/`) — SQLite backend
- ArgoCD Helm chart (`argo/argo-cd`, `https://argoproj.github.io/argo-helm`)
- Longhorn `v1.11.1` — already deployed; `longhorn` StorageClass (PVC for Gitea only)
- Traefik — already deployed; `networking.k8s.io/v1` Ingress with TLS
- cert-manager — already deployed; `letsencrypt-prod` ClusterIssuer

**Storage**: Longhorn PVC for Gitea data (`10Gi`, `storageClass: longhorn`);
ArgoCD Redis uses `emptyDir` (cache only — see research.md §Decision 3)

**Testing**: Ansible ad-hoc checks + `kubectl` rollout status + `curl` HTTP probes
(consistent with existing role validation patterns)

**Target Platform**: K3s on arm64 Raspberry Pi CM5 nodes (`10.1.20.x` cluster VLAN)

**Project Type**: Infrastructure-as-code (Ansible roles + Helm charts)

**Performance Goals**: GitOps sync latency ≤ 3 minutes (SC-001); dashboard load ≤ 30s (SC-002)

**Constraints**: arm64-compatible images only; no manual `kubectl` steps post-playbook;
all secrets via untracked `group_vars/all.yml`

**Scale/Scope**: Single operator; 4-node cluster; non-HA ArgoCD instance

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Infrastructure as Code | ✅ PASS | All resources deployed via Ansible roles + Helm; no manual steps |
| II. Idempotency | ✅ PASS | `helm upgrade --install`; `kubectl apply --dry-run` namespace creation; bootstrap role uses apply |
| III. Reproducibility | ✅ PASS | New roles added to `services-deploy.yml`; quickstart.md documents full procedure |
| IV. Secrets Hygiene | ✅ PASS | Gitea admin creds + ArgoCD bcrypt password + Gitea PAT → `group_vars/all.yml` (untracked); examples in `group_vars/example.all.yml` |
| V. Simplicity | ✅ PASS | SQLite (no separate DB); non-HA ArgoCD; standard Ingress (not IngressRoute CRD); flat role structure |
| VI. Encryption in Transit | ✅ PASS | Both services behind Traefik TLS via cert-manager; `websecure` entrypoint only |
| VII. Least Privilege | ✅ PASS | Gitea anonymous write disabled; ArgoCD repo credential uses scoped PAT (`read:repository` only) |
| VIII. Persistent Storage | ✅ PASS | Gitea PVC: `storageClass: longhorn`, `storage: 10Gi` (explicit); ArgoCD Redis `emptyDir` exempt (cache) |

**Post-design re-check**: All gates pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/005-argocd-gitops/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 output — 7 decisions resolved
├── data-model.md        # Phase 1 output — K8s resources + entity relationships
├── quickstart.md        # Phase 1 output — end-to-end deployment guide
├── contracts/
│   ├── argocd-application.yaml   # ArgoCD Application CRD schema/template
│   └── role-interface.md         # Ansible role defaults (public variable interface)
├── checklists/
│   └── requirements.md           # Spec quality checklist (all pass)
└── tasks.md             # Phase 2 output (/speckit.tasks — not yet created)
```

### Source Code (repository root)

```text
roles/
├── gitea/
│   ├── defaults/main.yml          # gitea_version, gitea_namespace, gitea_hostname,
│   │                              # gitea_pvc_size, gitea_storage_class
│   ├── files/values.yaml          # Helm values: SQLite DB, Longhorn PVC, Ingress
│   └── tasks/main.yml             # Helm repo add, install, wait for rollout
│
├── argocd/
│   ├── defaults/main.yml          # argocd_version, argocd_namespace, argocd_hostname
│   ├── files/values.yaml          # Helm values: admin password hash, Ingress, dex disabled
│   └── tasks/main.yml             # Helm repo add, install, wait for rollout
│
└── argocd-bootstrap/
    ├── defaults/main.yml          # gitea_argocd_token, gitea_hostname, argocd_apps: []
    ├── tasks/main.yml             # Apply repo credential Secret + Application manifests
    └── templates/
        ├── repo-secret.yaml.j2   # ArgoCD Repository credential Secret (Gitea PAT)
        └── application.yaml.j2   # ArgoCD Application CRD (one per argocd_apps entry)

playbooks/cluster/
└── services-deploy.yml            # Add gitea, argocd, argocd-bootstrap roles

group_vars/
└── example.all.yml                # Add gitea_admin_*, argocd_admin_password_bcrypt,
                                   # gitea_argocd_token placeholder entries
```

**Structure Decision**: Three flat roles (`gitea`, `argocd`, `argocd-bootstrap`) following
the existing role structure. Bootstrap is split from the core ArgoCD role so it can be
re-run independently when new apps are added (via `--tags argocd-bootstrap`).

## Complexity Tracking

No constitution violations. Table not required.
