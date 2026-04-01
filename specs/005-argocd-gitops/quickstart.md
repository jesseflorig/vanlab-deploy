# Quickstart: ArgoCD + Gitea GitOps

**Branch**: `005-argocd-gitops` | **Date**: 2026-03-31

## Prerequisites

- K3s cluster deployed and healthy (`playbooks/cluster/k3s-deploy.yml` complete)
- Longhorn installed and `longhorn` StorageClass is the cluster default
- Traefik ingress operational
- cert-manager operational with `letsencrypt-prod` ClusterIssuer
- DNS entries for `gitea.<domain>` and `argocd.<domain>` pointing to cluster ingress

## 1. Configure Secrets

Add the following to `group_vars/all.yml` (untracked):

```yaml
# Gitea admin account
gitea_admin_username: admin
gitea_admin_password: <your-password>
gitea_admin_email: admin@vanlab.local

# ArgoCD admin password (bcrypt hash)
# Generate: htpasswd -nbBC 10 "" <password> | tr -d ':\n' | sed 's/$2y/$2a/'
argocd_admin_password_bcrypt: "$2a$10$..."

# Gitea PAT for ArgoCD (create after Gitea is deployed — see step 4)
gitea_argocd_token: ""
```

## 2. Deploy Gitea and ArgoCD

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml
```

This runs the full services stack including the new `gitea` and `argocd` roles.

## 3. Verify Services

```bash
# Gitea
curl -I https://gitea.<domain>               # should return HTTP 200

# ArgoCD
curl -I https://argocd.<domain>              # should return HTTP 200
kubectl get pods -n argocd                    # all pods Running/Ready
kubectl get pods -n gitea                     # gitea-0 Running/Ready
kubectl get pvc -n gitea                      # gitea PVC Bound to longhorn volume
```

## 4. Create Gitea PAT for ArgoCD

1. Log into Gitea at `https://gitea.<domain>` with admin credentials
2. Navigate to **Settings → Applications → Generate Token**
3. Name: `argocd`, Scopes: `read:repository`
4. Copy the token and set `gitea_argocd_token` in `group_vars/all.yml`

## 5. Bootstrap ArgoCD → Gitea Connection

Re-run the playbook to apply the bootstrap role with the token now set:

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap
```

## 6. Register Your First GitOps App

1. Create a repository in Gitea containing your manifests or Helm values
2. Add an entry to `argocd_apps` in `group_vars/all.yml`:
   ```yaml
   argocd_apps:
     - name: my-service
       repo: admin/my-service
       path: .
       namespace: my-service
       revision: main
   ```
3. Re-run the bootstrap step:
   ```bash
   ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap
   ```
4. Open the ArgoCD dashboard at `https://argocd.<domain>` — the app should appear
   and begin syncing.

## Rollback

To roll back a service to a previous state:

```bash
# In the Gitea repo for that service:
git revert <bad-commit-sha>
git push origin main
```

ArgoCD will detect the new commit and sync the cluster back within 3 minutes.
