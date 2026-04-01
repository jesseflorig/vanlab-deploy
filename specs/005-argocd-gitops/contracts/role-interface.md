# Ansible Role Interface Contract

**Branch**: `005-argocd-gitops` | **Date**: 2026-03-31

This document defines the public variable interface for each new Ansible role. All
variables must be overridable via `group_vars/all.yml`. Defaults live in each role's
`defaults/main.yml`.

---

## roles/gitea

| Variable | Default | Required in all.yml | Description |
|----------|---------|---------------------|-------------|
| `gitea_version` | `"1.22.x"` | No | Helm chart version to install |
| `gitea_namespace` | `"gitea"` | No | Kubernetes namespace |
| `gitea_hostname` | `"gitea.vanlab.local"` | No | Ingress hostname |
| `gitea_pvc_size` | `"10Gi"` | No | Gitea data PVC size |
| `gitea_storage_class` | `"longhorn"` | No | StorageClass (Principle VIII) |
| `gitea_admin_username` | — | **Yes** | Admin account username |
| `gitea_admin_password` | — | **Yes** | Admin account password (plaintext in all.yml) |
| `gitea_admin_email` | — | **Yes** | Admin account email |

---

## roles/argocd

| Variable | Default | Required in all.yml | Description |
|----------|---------|---------------------|-------------|
| `argocd_version` | `"7.x.x"` | No | Helm chart version to install |
| `argocd_namespace` | `"argocd"` | No | Kubernetes namespace |
| `argocd_hostname` | `"argocd.vanlab.local"` | No | Ingress hostname |
| `argocd_admin_password_bcrypt` | — | **Yes** | bcrypt hash of admin password |

Generate the bcrypt hash:
```bash
htpasswd -nbBC 10 "" <password> | tr -d ':\n' | sed 's/$2y/$2a/'
```

---

## roles/argocd-bootstrap

| Variable | Default | Required in all.yml | Description |
|----------|---------|---------------------|-------------|
| `gitea_argocd_token` | — | **Yes** | Gitea PAT with `read:repository` scope for ArgoCD |
| `gitea_hostname` | `"gitea.vanlab.local"` | No | Used to build repo URLs in Application manifests |
| `argocd_apps` | `[]` | No | List of Application definitions to bootstrap (see schema below) |

### `argocd_apps` entry schema

```yaml
argocd_apps:
  - name: my-service           # ArgoCD Application name
    repo: org/repo             # Gitea org/repo path
    path: .                    # path within the repo
    namespace: my-service      # destination namespace
    revision: main             # branch or tag
```
