# Research: ArgoCD + Gitea GitOps

**Branch**: `005-argocd-gitops` | **Date**: 2026-03-31

## Decision 1: Gitea Helm Chart Source

**Decision**: Use the official Gitea Helm chart from `https://dl.gitea.com/charts/`
(chart name: `gitea-charts/gitea`).

**Rationale**: Official chart with arm64 support confirmed; actively maintained;
supports SQLite, PostgreSQL, and MySQL backends via `gitea.config.database.DB_TYPE`.
PVC configuration is straightforward via `persistence.storageClass`.

**Alternatives considered**:
- `gitea` from Bitnami: Heavier, more opinionated; introduces an extra dependency
  on the Bitnami chart ecosystem. Rejected (Principle V — simplicity).

---

## Decision 2: Gitea Database Backend

**Decision**: SQLite (`gitea.config.database.DB_TYPE: sqlite3`).

**Rationale**: Single-operator homelab with no concurrent write load. SQLite data
is stored within the Gitea PVC (automatically covered by Longhorn replication).
No additional Deployment, Service, or Secret needed for a database sidecar.

**Alternatives considered**:
- PostgreSQL sidecar: Required by the Gitea chart's bundled PostgreSQL sub-chart.
  Adds a second PVC, second StatefulSet, and credential management overhead.
  Rejected (Principle V — no concrete operational need for a separate DB at this scale).

---

## Decision 3: ArgoCD Persistent Storage

**Decision**: No Longhorn PVC for ArgoCD. Redis cache uses `emptyDir`.

**Rationale**: ArgoCD is intentionally stateless — all application state lives in
Kubernetes CRDs (Application, AppProject) and the source Git repo. Redis is a
write-through cache; its loss causes a brief re-sync delay, not data loss.
Constitution Principle VIII exempts ephemeral scratch space and cache from the
Longhorn PVC requirement.

**Alternatives considered**:
- Longhorn PVC for Redis: Would persist cache across pod restarts but provides no
  operational benefit since ArgoCD rebuilds it from K8s/Git on startup.
  Rejected (unnecessary complexity, no durable-data requirement).

---

## Decision 4: ArgoCD Bootstrap Strategy

**Decision**: Ansible Jinja2 templates applied via `kubectl apply` — a Repository
Credential Secret and one or more ArgoCD Application manifests are templated and
applied during the `argocd-bootstrap` role.

**Rationale**: Consistent with the existing `cert-manager` role pattern (Jinja2 →
`/tmp/` → `kubectl apply`). Requires no additional CLI tool (no `argocd` CLI
dependency). The initial Application manifests are version-controlled in the role's
`templates/` directory, satisfying Principle I.

**Alternatives considered**:
- ArgoCD CLI (`argocd app create`): Requires CLI installation and login token
  management in the playbook. Rejected (adds complexity, breaks idempotency model).
- "App of Apps" pattern: Bootstrap Application that references a meta-repo.
  Overkill for initial deployment; can be adopted later if app count grows.
  Deferred (Principle V).

---

## Decision 5: arm64 Compatibility

**Decision**: Both charts are arm64-compatible at the versions pinned in role
defaults.

**Rationale**:
- Gitea publishes multi-arch images (`gitea/gitea`) with arm64 support since v1.14.
- ArgoCD publishes multi-arch images (`quasar.io/argoproj/argocd`) with arm64
  support since v2.5.
- Both chart's upstream container images pull from their respective registries
  without requiring additional `nodeAffinity` or image overrides on arm64 nodes.

**Alternatives considered**: N/A — no viable arm64 alternative charts exist for
these specific tools.

---

## Decision 6: Ingress Strategy

**Decision**: Kubernetes `Ingress` resource with `ingressClassName: traefik` and
TLS via cert-manager, consistent with the existing `static-site` role pattern.

**Rationale**: The project already uses `networking.k8s.io/v1 Ingress` with Traefik
annotations (`traefik.ingress.kubernetes.io/router.entrypoints: websecure`).
Reusing this pattern keeps all ingress definitions uniform.

**Alternatives considered**:
- Traefik `IngressRoute` CRD: More expressive but not used elsewhere in the project.
  Introducing it for two new services would create inconsistency. Rejected (Principle V).
- Helm chart built-in ingress values: Both charts expose `ingress.enabled` and
  `ingress.tls` parameters, which generate the same standard Ingress resource.
  **Selected**: use chart-native ingress values where available (reduces templated files).

---

## Decision 7: Secrets Management

**Decision**: Gitea admin credentials and ArgoCD admin password stored in untracked
`group_vars/all.yml`, templated into Kubernetes Secrets during Ansible deployment.

**Variables required** (to be added to `group_vars/example.all.yml`):
- `gitea_admin_username`
- `gitea_admin_password`
- `gitea_admin_email`
- `argocd_admin_password_bcrypt` — bcrypt hash of the ArgoCD admin password;
  generate with: `htpasswd -nbBC 10 "" <password> | tr -d ':\n' | sed 's/$2y/$2a/'`
- `gitea_argocd_token` — Gitea personal access token (PAT) created for ArgoCD
  to authenticate against Gitea repos; generated post-deploy via Gitea API or UI
  and stored here for idempotent re-provisioning

**Rationale**: Follows the established pattern in `group_vars/example.all.yml`.
No secrets are committed. Principle IV compliant.
