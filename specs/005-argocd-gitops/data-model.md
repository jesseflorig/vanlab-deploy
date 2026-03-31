# Data Model: ArgoCD + Gitea GitOps

**Branch**: `005-argocd-gitops` | **Date**: 2026-03-31

## Kubernetes Resources Created

### Gitea

| Resource | Name | Namespace | Notes |
|----------|------|-----------|-------|
| Namespace | `gitea` | — | Created by Ansible before Helm |
| StatefulSet | `gitea` | `gitea` | Managed by Helm chart |
| Service | `gitea-http` | `gitea` | Port 3000 (HTTP) |
| Service | `gitea-ssh` | `gitea` | Port 22 (SSH — optional, disabled if not needed) |
| PersistentVolumeClaim | `gitea` | `gitea` | `storageClass: longhorn`, `10Gi`, `accessModes: ReadWriteOnce` |
| Secret | `gitea-admin` | `gitea` | Admin username + password (templated from group_vars) |
| Ingress | `gitea` | `gitea` | `ingressClassName: traefik`, TLS via cert-manager |
| Certificate | `gitea-tls` | `gitea` | Issued by `letsencrypt-prod` ClusterIssuer |

### ArgoCD

| Resource | Name | Namespace | Notes |
|----------|------|-----------|-------|
| Namespace | `argocd` | — | Created by Ansible before Helm |
| Deployment | `argocd-server` | `argocd` | UI + API server |
| Deployment | `argocd-repo-server` | `argocd` | Git repo cloning |
| Deployment | `argocd-application-controller` | `argocd` | StatefulSet; reconciliation loop |
| Deployment | `argocd-redis` | `argocd` | Cache; `emptyDir` (not durable) |
| Deployment | `argocd-dex-server` | `argocd` | OIDC; disabled if SSO not used |
| Service | `argocd-server` | `argocd` | Port 443 (HTTPS) |
| Secret | `argocd-initial-admin-secret` | `argocd` | bcrypt password set via Helm values |
| Ingress | `argocd-server` | `argocd` | `ingressClassName: traefik`, TLS via cert-manager |
| Certificate | `argocd-tls` | `argocd` | Issued by `letsencrypt-prod` ClusterIssuer |

### ArgoCD Bootstrap Resources

| Resource | Name | Namespace | Notes |
|----------|------|-----------|-------|
| Secret | `gitea-repo-creds` | `argocd` | Type `repository`; Gitea PAT token for ArgoCD |
| Application | `<app-name>` | `argocd` | One per GitOps-managed service; Jinja2 templated |

---

## Entity Relationships

```
Gitea Repository
  └── contains ──► Helm values / manifests / ArgoCD Application YAML
       │
ArgoCD watches via ──► Repository Credential Secret (gitea-repo-creds)
       │
ArgoCD Application Definition
  ├── source: Gitea repo URL + path + targetRevision
  └── destination: cluster namespace
       │
       ▼
Sync Event (ArgoCD history)
  ├── revision (Git SHA)
  ├── timestamp
  ├── result: Succeeded | Failed
  └── message
```

---

## State Transitions: Application Sync Status

```
Unknown ──► OutOfSync ──► Syncing ──► Synced
                │                        │
                └── SyncFailed ◄─────────┘ (on error)
```

Health states (parallel, independent of sync):
- `Healthy` — all resources running as expected
- `Progressing` — rollout in progress
- `Degraded` — one or more resources in error state
- `Missing` — resource not found in cluster

---

## PVC Specification (Principle VIII compliance)

```yaml
# Gitea data volume — the only durable PVC in this feature
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitea
  namespace: gitea
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn          # explicit per Principle VIII
  resources:
    requests:
      storage: 10Gi                   # explicit; no unbounded claims
```

ArgoCD Redis uses `emptyDir` (cache only; loss is non-destructive per research.md §Decision 3).
