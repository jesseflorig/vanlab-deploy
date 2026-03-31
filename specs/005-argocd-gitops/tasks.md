---
description: "Task list for ArgoCD + Gitea GitOps deployment"
---

# Tasks: ArgoCD + Gitea GitOps

**Input**: Design documents from `/specs/005-argocd-gitops/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no incomplete-task dependencies)
- **[Story]**: User story this task belongs to (US1/US2/US3)
- Exact file paths included in every task description

## Path Conventions

Ansible project at repository root: `roles/`, `playbooks/`, `group_vars/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create role directory skeletons and wire new roles into the deployment playbook.

- [ ] T001 Create directory structure `roles/gitea/{defaults,tasks,templates}/` (empty dirs with `.gitkeep`)
- [ ] T002 [P] Create directory structure `roles/argocd/{defaults,tasks,templates}/` (empty dirs with `.gitkeep`)
- [ ] T003 [P] Create directory structure `roles/argocd-bootstrap/{defaults,tasks,templates}/` (empty dirs with `.gitkeep`)
- [ ] T004 [P] Add secret variable placeholders to `group_vars/example.all.yml`: `gitea_admin_username`, `gitea_admin_password`, `gitea_admin_email`, `argocd_admin_password_bcrypt` (with generation command comment), `gitea_argocd_token`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Integrate new roles into the cluster services playbook — required before any role can be tested end-to-end.

**⚠️ CRITICAL**: No user story can be fully tested until this phase is complete.

- [ ] T005 Add `gitea`, `argocd`, and `argocd-bootstrap` role entries (in that order) to the `Install Host Tools` play in `playbooks/cluster/services-deploy.yml`; tag each with `gitea`, `argocd`, and `argocd-bootstrap` respectively to allow targeted re-runs

**Checkpoint**: Playbook wiring complete — user story role implementation can now proceed.

---

## Phase 3: User Story 1 — Declarative Service Deployment (Priority: P1) 🎯 MVP

**Goal**: Gitea and ArgoCD deployed on the cluster; ArgoCD syncs a test application from a Gitea repository automatically within 3 minutes of a commit.

**Independent Test**: Run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml`; then push a commit to a Gitea repo registered in `argocd_apps` and confirm the ArgoCD application transitions to `Synced` without manual intervention. Verify with `kubectl get applications -n argocd`.

### Implementation for User Story 1

- [ ] T006 [P] [US1] Create `roles/gitea/defaults/main.yml` — define `gitea_version` (latest stable), `gitea_namespace: gitea`, `gitea_hostname: gitea.vanlab.local`, `gitea_pvc_size: 10Gi`, `gitea_storage_class: longhorn`
- [ ] T007 [P] [US1] Create `roles/argocd/defaults/main.yml` — define `argocd_chart_version` (latest stable), `argocd_namespace: argocd`, `argocd_hostname: argocd.vanlab.local`
- [ ] T008 [P] [US1] Create `roles/argocd-bootstrap/defaults/main.yml` — define `argocd_namespace: argocd`, `gitea_hostname: gitea.vanlab.local`, `gitea_argocd_token: ""`, `argocd_apps: []`
- [ ] T009 [US1] Create `roles/gitea/templates/values.yaml.j2` — configure: SQLite database (`gitea.config.database.DB_TYPE: sqlite3`), Longhorn PVC (`persistence.storageClass: longhorn`, `persistence.size: {{ gitea_pvc_size }}`, `persistence.enabled: true`), Kubernetes Ingress enabled (`ingress.enabled: true`, `ingressClassName: traefik`, annotations for `traefik.ingress.kubernetes.io/router.entrypoints: websecure` and `cert-manager.io/cluster-issuer: letsencrypt-prod`, TLS secret `gitea-tls`), admin account seeding disabled (handled via group_vars Secret)
- [ ] T010 [US1] Create `roles/gitea/tasks/main.yml` — in order: add `gitea-charts` Helm repo (`https://dl.gitea.com/charts/`), create `gitea` namespace (idempotent), render `values.yaml.j2` to `/tmp/gitea-values.yaml`, run `helm upgrade --install gitea gitea-charts/gitea --namespace gitea --version {{ gitea_version }} --values /tmp/gitea-values.yaml --atomic --timeout 5m`, wait for `statefulset/gitea` rollout, verify Gitea PVC is Bound (`kubectl get pvc -n gitea gitea`)
- [ ] T011 [US1] Create `roles/argocd/templates/values.yaml.j2` — configure: `configs.secret.argocdServerAdminPassword: "{{ argocd_admin_password_bcrypt }}"`, `server.ingress.enabled: true` with `ingressClassName: traefik`, annotations for websecure entrypoint and `cert-manager.io/cluster-issuer: letsencrypt-prod`, TLS secret `argocd-tls`, host `{{ argocd_hostname }}`; disable dex (`dex.enabled: false`); `server.insecure: true` (TLS terminated at ingress)
- [ ] T012 [US1] Create `roles/argocd/tasks/main.yml` — in order: add `argo` Helm repo (`https://argoproj.github.io/argo-helm`), create `argocd` namespace (idempotent), render `values.yaml.j2` to `/tmp/argocd-values.yaml`, run `helm upgrade --install argo-cd argo/argo-cd --namespace argocd --version {{ argocd_chart_version }} --values /tmp/argocd-values.yaml --atomic --timeout 5m`, wait for `deployment/argocd-server` rollout, wait for `deployment/argocd-repo-server` rollout, wait for `statefulset/argocd-application-controller` rollout
- [ ] T013 [P] [US1] Create `roles/argocd-bootstrap/templates/repo-secret.yaml.j2` — Kubernetes Secret with `argocd.argoproj.io/secret-type: repository` label, `url: https://{{ gitea_hostname }}`, `type: git`, `username: argocd`, `password: {{ gitea_argocd_token }}`
- [ ] T014 [P] [US1] Create `roles/argocd-bootstrap/templates/application.yaml.j2` — ArgoCD `Application` CRD (see `contracts/argocd-application.yaml`); use `item.name`, `item.repo`, `item.path`, `item.namespace`, `item.revision` from loop variable; include `automated.prune: true`, `automated.selfHeal: true`, `syncOptions: [CreateNamespace=true]`
- [ ] T015 [US1] Create `roles/argocd-bootstrap/tasks/main.yml` — skip entire role if `gitea_argocd_token` is empty (display warning and end play); render + apply `repo-secret.yaml.j2` to `/tmp/argocd-repo-secret.yaml`; loop over `argocd_apps` to render + apply `application.yaml.j2` for each entry; register change status from `kubectl apply` output

**Checkpoint**: US1 complete — run the playbook, push a commit to a registered Gitea repo, and verify `kubectl get application -n argocd` shows `Synced/Healthy` within 3 minutes.

---

## Phase 4: User Story 2 — Sync Status Visibility (Priority: P2)

**Goal**: ArgoCD dashboard accessible via HTTPS at `https://argocd.vanlab.local`; Gitea web UI accessible at `https://gitea.vanlab.local`. Both served through Traefik with valid TLS certs.

**Independent Test**: Run `curl -sI https://argocd.vanlab.local` and `curl -sI https://gitea.vanlab.local` from within the cluster network — both return `HTTP/2 200` (or redirect to login). Navigate to ArgoCD dashboard; all registered applications are listed with sync and health status visible.

### Implementation for User Story 2

- [ ] T016 [P] [US2] Add cert readiness wait to `roles/gitea/tasks/main.yml` — `kubectl wait certificate/gitea-tls -n gitea --for=condition=Ready --timeout=3m` with retries; add `curl -sI https://{{ gitea_hostname }}` probe task and fail with helpful message if non-2xx/3xx
- [ ] T017 [P] [US2] Add cert readiness wait to `roles/argocd/tasks/main.yml` — `kubectl wait certificate/argocd-tls -n argocd --for=condition=Ready --timeout=3m` with retries; add `curl -sI https://{{ argocd_hostname }}` probe task and fail with helpful message if non-2xx/3xx
- [ ] T018 [US2] Add `ansible.builtin.debug` summary task at the end of `roles/argocd/tasks/main.yml` printing dashboard URL and admin login reminder: `"ArgoCD dashboard: https://{{ argocd_hostname }} — log in with admin / <password from all.yml>"`

**Checkpoint**: US2 complete — both dashboards reachable over HTTPS with valid TLS certs; ArgoCD shows all registered apps with status.

---

## Phase 5: User Story 3 — Git-Driven Rollback (Priority: P3)

**Goal**: Operator can revert a bad deployment by reverting a Git commit in Gitea; ArgoCD automatically restores the prior cluster state within 3 minutes.

**Independent Test**: Deploy a breaking change (e.g., invalid replica count) to a registered Gitea repo; wait for ArgoCD to sync and the app to degrade; revert the commit in Gitea; confirm ArgoCD re-syncs and the app returns to Healthy — no direct kubectl intervention.

### Implementation for User Story 3

- [ ] T019 [P] [US3] Create `playbooks/cluster/argocd-smoke-test.yml` — playbook that verifies the GitOps stack health: checks ArgoCD pods Running, checks Gitea pod Running, checks Gitea PVC Bound, checks ArgoCD can reach Gitea repo (via `kubectl exec` into argocd-repo-server to run `git ls-remote`), prints status summary
- [ ] T020 [US3] Update `README.md` with a **GitOps** section covering: deployment workflow, how to register a new app (`argocd_apps` in `group_vars/all.yml` + re-run bootstrap), and rollback procedure (git revert + push → auto-sync)

**Checkpoint**: US3 complete — smoke test playbook passes; rollback procedure documented and manually verified.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup and constitution compliance verification across all roles.

- [ ] T021 [P] Add description comment headers to `roles/gitea/tasks/main.yml`, `roles/argocd/tasks/main.yml`, and `roles/argocd-bootstrap/tasks/main.yml` per Constitution Principle I (all role task files must have a brief description comment at the top)
- [ ] T022 Add `gitea`, `argocd`, and `argocd-bootstrap` entries to `CLAUDE.md` Active Technologies section via the constitution update workflow

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — T001–T004 can all start in parallel
- **Foundational (Phase 2)**: Depends on T001 (role dirs must exist); T005 can run after T001
- **US1 (Phase 3)**: Depends on Phase 2 complete; T006/T007/T008/T013/T014 are parallel; T009 depends on T006; T010 depends on T009; T011 depends on T007; T012 depends on T011; T015 depends on T013 + T014
- **US2 (Phase 4)**: Depends on US1 — T016 depends on T010, T017 depends on T012, T018 depends on T012
- **US3 (Phase 5)**: Depends on US1 + US2; T019 and T020 can run in parallel
- **Polish (Phase 6)**: Depends on all user story phases complete

### User Story Dependencies

- **US1 (P1)**: Starts after Phase 2; no dependency on US2/US3 — independently testable via `kubectl port-forward`
- **US2 (P2)**: Depends on US1 (Ingress configuration is part of Helm values from US1); US2 adds verification
- **US3 (P3)**: Depends on US1 (GitOps loop must be functional); no new infrastructure

---

## Parallel Example: User Story 1

```bash
# These role defaults can be created simultaneously (different files):
Task T006: "Create roles/gitea/defaults/main.yml"
Task T007: "Create roles/argocd/defaults/main.yml"
Task T008: "Create roles/argocd-bootstrap/defaults/main.yml"
Task T013: "Create roles/argocd-bootstrap/templates/repo-secret.yaml.j2"
Task T014: "Create roles/argocd-bootstrap/templates/application.yaml.j2"

# Then sequentially (each depends on its defaults):
T009 (Gitea values template) → T010 (Gitea tasks)
T011 (ArgoCD values template) → T012 (ArgoCD tasks)
T015 (bootstrap tasks, depends on T013 + T014)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T004)
2. Complete Phase 2: Foundational (T005)
3. Complete Phase 3: US1 (T006–T015)
4. **STOP and VALIDATE**: `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml`; push a commit; verify sync in `kubectl get applications -n argocd`
5. MVP delivered: full GitOps loop operational

### Incremental Delivery

1. Setup + Foundational → Phase 1–2 complete
2. US1 → GitOps loop works (MVP!)
3. US2 → Dashboard accessible via HTTPS with valid TLS
4. US3 → Rollback documented and smoke test passing
5. Polish → Headers, CLAUDE.md updated

---

## Notes

- [P] tasks touch different files with no incomplete-task dependencies
- US3 requires no new role code — the GitOps loop (US1) is the rollback mechanism
- Gitea PVC **must** specify `storageClass: longhorn` and `storage: 10Gi` explicitly (Constitution Principle VIII)
- All secrets via `group_vars/all.yml` only — never commit live values (Constitution Principle IV)
- Run playbook with `--tags argocd-bootstrap` to re-apply Application definitions without redeploying services
- Commit after each task or logical group; mark tasks complete as you go
