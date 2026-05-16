---
description: "Task list for MinIO Object Storage (spec 060)"
---

# Tasks: MinIO Object Storage

**Input**: Design documents from `/specs/060-minio-object-store/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: This is a GitOps deployment spec — "tests" are verification commands (kubectl, mc, curl) executed against the live cluster, not unit tests. They are included as explicit verification tasks per user story.

**Organization**: Tasks are grouped by user story. US1 (P1) is the MVP — Longhorn has an off-cluster backup target. US2 and US3 (P2) layer general-purpose capacity and reproducibility verification on top.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Different file, no ordering dependency on incomplete tasks
- **[Story]**: US1 / US2 / US3 — phase ownership
- Paths are absolute or repo-relative from `/Users/jesse/Code/vanlab/`

## Path Conventions

GitOps manifest layout per Constitution Principle XI:

- `manifests/minio/prereqs/` — namespace, SealedSecrets, console IngressRoute
- `manifests/minio/apps/` — multi-source ArgoCD `Application` for the Helm chart
- `manifests/minio/minio-values.yaml` — chart values (no secrets)
- `group_vars/all.yml` (uncommitted) — source-of-truth credential variables
- `group_vars/example.all.yml` (committed) — placeholder keys
- `playbooks/utilities/seal-secrets.yml` — sealing playbook

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Branch scaffolding and directory layout.

- [x] T001 Verify on feature branch `060-minio-object-store` (`git status` shows clean, branch matches); if not, `git checkout -b 060-minio-object-store` from current `main`
- [x] T002 Create directory `manifests/minio/prereqs/` and `manifests/minio/apps/` (empty; `.gitkeep` not needed since real files land here next)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Secrets, Helm chart pin, ArgoCD Application wiring, and console ingress — everything the MinIO instance needs in order to come up Synced + Healthy. **All US1/US2/US3 verification depends on this phase completing.**

**⚠️ CRITICAL**: User-story phases cannot run until ArgoCD reports both `minio-prereqs` and `minio` Applications Synced + Healthy.

### Secrets source-of-truth

- [x] T003 Generate four credential values locally (e.g., `pwgen -s 32 1` for the root password; `pwgen -s 20 1` for the Longhorn access key; `pwgen -s 40 1` for the Longhorn secret key); add the four keys (`minio_root_user`, `minio_root_password`, `longhorn_minio_access_key`, `longhorn_minio_secret_key`) to `group_vars/all.yml`
- [x] T004 [P] Add placeholder entries (no real values) for the same four keys to `group_vars/example.all.yml`

### Sealing playbook

- [x] T005 Extend `playbooks/utilities/seal-secrets.yml` to emit `manifests/minio/prereqs/sealed-secrets.yaml` containing two `SealedSecret` resources: `minio-root` (keys: `rootUser`, `rootPassword`) and `longhorn-minio-credentials-source` (keys: `accessKey`, `secretKey`) — both scoped to namespace `minio`
- [x] T006 Run `ansible-playbook playbooks/utilities/seal-secrets.yml`; verify the generated `manifests/minio/prereqs/sealed-secrets.yaml` contains zero plaintext values and exactly two `SealedSecret` resources

### Prereqs manifests

- [x] T007 [P] Create `manifests/minio/prereqs/namespace.yaml` — `Namespace` named `minio`, annotation `argocd.argoproj.io/sync-wave: "0"`, labels per data-model.md
- [x] T008 [P] Create `manifests/minio/prereqs/ingress-route.yaml` — Traefik `IngressRoute` `minio-console` in namespace `minio`, entryPoints `["websecure"]`, match `` Host(`minio.fleet1.lan`) ``, service `minio-console:9001`, TLS via fleet1.lan wildcard cert (spec 054), annotation `argocd.argoproj.io/sync-wave: "2"`

### Helm values + multi-source Application

- [x] T009 Run `helm search repo minio/minio --versions | head -5` (after `helm repo add minio https://charts.min.io/ && helm repo update`); record the latest stable 5.x chart version — this is the `targetRevision` for T011
- [x] T010 [P] Create `manifests/minio/minio-values.yaml` — chart values: `mode: standalone`, `replicas: 1`, `persistence.enabled: true`, `persistence.storageClass: longhorn`, `persistence.size: 200Gi`, `auth.existingSecret: minio-root` (verify exact values-key against chart docs at the pinned version), no `users[]`/`buckets[]` (provisioned manually per R4), resources sized for arm64 CM5
- [x] T011 Create `manifests/minio/apps/minio-app.yaml` — ArgoCD multi-source `Application` per data-model.md: source[0] = Helm chart `minio/minio` at the version from T009, valueFiles `["$values/manifests/minio/minio-values.yaml"]`; source[1] = Gitea `vanlab` repo ref `values`; destination namespace `minio`; `syncPolicy.automated.{prune,selfHeal}: true`, `retry.limit: 5`

### ArgoCD app registration

- [x] T012 Add two entries to `argocd_apps` in `group_vars/all.yml`: `{ name: minio-prereqs, path: manifests/minio/prereqs }` and `{ name: minio, path: manifests/minio/apps }`

### Commit + deploy

- [ ] T013 Commit `manifests/minio/`, `group_vars/example.all.yml`, and the updated `playbooks/utilities/seal-secrets.yml` on branch `060-minio-object-store`; push to both `gitea` and `origin`; open a PR via Gitea API and merge per the CLAUDE.md git workflow
- [ ] T014 Run `ansible-playbook playbooks/cluster/services-deploy.yml --tags argocd-bootstrap` to register the two new ArgoCD Applications
- [ ] T015 Watch `https://argocd.fleet1.cloud` until both `minio-prereqs` and `minio` Applications reach Synced + Healthy (~3 min); resolve any sync errors before proceeding

**Checkpoint**: MinIO Pod is Running 1/1, PVC `Bound` at 200Gi on Longhorn, console IngressRoute responds with HTTP 200 at `https://minio.fleet1.lan/login`. ALL subsequent user-story phases can now begin.

---

## Phase 3: User Story 1 — Longhorn Has an Off-Cluster Backup Target (Priority: P1) 🎯 MVP

**Goal**: The `longhorn-backups` bucket exists, a Longhorn-scoped MinIO user (with credentials matching the sealed values in T006) can read/write only that bucket, and spec 061 has everything its contract enumerates.

**Independent Test**: With the Longhorn-scoped credential, `mc ls vanlab-minio-longhorn/longhorn-backups` succeeds (empty exit 0), `mc pipe` to that bucket succeeds, and `mc ls vanlab-minio-longhorn/vanlab-archive` returns 403 (or empty if bucket doesn't exist yet — completed in US2). Spec 061's contract pre-flight checks all pass.

### Implementation for User Story 1

- [x] T016 [US1] Fetch live credentials into shell variables on the management laptop: `ROOT_USER`/`ROOT_PASS` from `Secret/minio-root`; `LH_AK`/`LH_SK` from `Secret/longhorn-minio-credentials-source` (exact commands in quickstart.md Step 6)
- [x] T017 [US1] Open a port-forward `kubectl port-forward -n minio svc/minio 9000:9000` in the background; capture `$PF_PID` for teardown
- [x] T018 [US1] Configure `mc` alias: `mc alias set vanlab-minio http://localhost:9000 "$ROOT_USER" "$ROOT_PASS"`
- [x] T019 [US1] Create the Longhorn backup bucket: `mc mb --ignore-existing vanlab-minio/longhorn-backups`
- [x] T020 [US1] Write the scoped policy JSON to `/tmp/longhorn-backups-rw.json` per data-model.md (Allow `s3:GetObject`/`PutObject`/`DeleteObject` on `arn:aws:s3:::longhorn-backups/*`; Allow `s3:ListBucket`/`GetBucketLocation` on `arn:aws:s3:::longhorn-backups`); register it with `mc admin policy create vanlab-minio longhorn-backups-rw /tmp/longhorn-backups-rw.json`
- [x] T021 [US1] Create the Longhorn user with the pre-generated keys: `mc admin user add vanlab-minio "$LH_AK" "$LH_SK"`; attach policy: `mc admin policy attach vanlab-minio longhorn-backups-rw --user "$LH_AK"`

### Verification for User Story 1

- [x] T022 [US1] Positive test: `mc alias set vanlab-minio-longhorn http://localhost:9000 "$LH_AK" "$LH_SK"`; `mc ls vanlab-minio-longhorn/longhorn-backups` → empty, exit 0; `echo hello | mc pipe vanlab-minio-longhorn/longhorn-backups/test-object.txt`; `mc ls vanlab-minio-longhorn/longhorn-backups` → sees the object; `mc rm vanlab-minio-longhorn/longhorn-backups/test-object.txt`
- [x] T023 [US1] **Critical FR-005 scope test**: `mc ls vanlab-minio-longhorn` should return only `longhorn-backups` (or 403 on bucket-list, depending on `mc` version). If the user can list other arbitrary buckets, the policy is over-broad — STOP and fix T020 before proceeding
- [x] T024 [US1] Tear down the port-forward: `kill $PF_PID`
- [x] T025 [US1] Confirm the contract handoff to spec 061: `contracts/longhorn-backup-target.md` is current; the `AWS_ENDPOINTS` value `http://minio.minio.svc.cluster.local:9000` matches the deployed `Service` (`kubectl get svc -n minio minio`)

**Checkpoint**: User Story 1 is complete — Longhorn has its backup target ready. Spec 061 can begin (after 060 is fully merged).

---

## Phase 4: User Story 2 — Future Apps Have a Cluster-Local S3 Endpoint (Priority: P2)

**Goal**: The reserved general-purpose `vanlab-archive` bucket exists; bucket isolation is verified end-to-end (the Longhorn credential proven in US1 cannot reach `vanlab-archive`).

**Independent Test**: `vanlab-archive` exists per `mc ls vanlab-minio/`; `mc ls vanlab-minio-longhorn/vanlab-archive` (with the Longhorn credential from US1) returns 403/Access Denied.

### Implementation for User Story 2

- [x] T026 [US2] Re-establish port-forward + root `mc` alias (T017–T018) if not still active
- [x] T027 [US2] Create the general-purpose bucket: `mc mb --ignore-existing vanlab-minio/vanlab-archive`

### Verification for User Story 2

- [x] T028 [US2] Bucket exists: `mc ls vanlab-minio/` shows both `longhorn-backups` and `vanlab-archive`
- [x] T029 [US2] **Scope isolation negative test**: with the Longhorn alias `vanlab-minio-longhorn`, run `mc ls vanlab-minio-longhorn/vanlab-archive` → MUST fail with 403/Access Denied. If it succeeds, the `longhorn-backups-rw` policy is too broad — return to T020 and re-scope
- [x] T030 [US2] Tear down port-forward: `kill $PF_PID`

**Checkpoint**: User Story 2 is complete — second bucket exists; per-bucket scoping is proven by negative test.

---

## Phase 5: User Story 3 — Deployment Is GitOps-Managed and Reproducible (Priority: P2)

**Goal**: Confirm the install is reproducible from Git alone, idempotent on re-sync, and that no plaintext credentials are committed.

**Independent Test**: ArgoCD shows zero resource diff after a manual re-sync; `git grep` for any of the four credential values from T003 returns zero hits across the repo; `mc admin user add` re-runs as a no-op.

### Verification for User Story 3

- [x] T031 [US3] ArgoCD idempotency: in the ArgoCD UI, click "Sync" on both `minio-prereqs` and `minio` Applications with `Apply Only`; verify zero resources changed (Synced status remains green with no out-of-sync items)
- [x] T032 [US3] [P] Secret-hygiene audit: from repo root, run `git grep -E '<one of the four plaintext values from T003>'` for each of the four credentials individually — all four MUST return zero matches across tracked files
- [x] T033 [US3] [P] Bootstrap idempotency: re-run the commands from T019, T020, T021 — `mc mb --ignore-existing` is a no-op; `mc admin policy create` against the same JSON is upsert-safe; `mc admin user add` with the same key/secret completes without error
- [x] T034 [US3] Verify arm64 image was pulled: `kubectl get pod -n minio -o jsonpath='{.items[0].spec.containers[0].image}'`; confirm the digest is the arm64 variant of the multi-arch manifest (per research.md R1)

**Checkpoint**: User Story 3 is complete — install is GitOps-managed, idempotent, and secret-clean.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup, monitoring hooks, and handoff to downstream specs.

- [x] T035 [P] Add a Prometheus alert for MinIO PVC at ≥70% used (per FR-010); the alert lives in the existing monitoring stack alerts directory and references `kubelet_volume_stats_used_bytes` filtered to the `minio` namespace
- [x] T036 [P] Note in `specs/061-longhorn-backup-target/spec.md` that spec 060 is now landed and the contract in `specs/060-minio-object-store/contracts/longhorn-backup-target.md` is current — flip 061's `NEEDS REVALIDATION` banner to ready-for-`/speckit.clarify` if appropriate (decision left to operator)
- [x] T037 Run the full `quickstart.md` end-to-end one more time against the deployed cluster as a final acceptance check; record any drift between the runbook and reality and fix the runbook before marking 060 done

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup; blocks all user stories
  - Within Phase 2: T003 → T005 → T006 (sealing depends on source-of-truth); T007/T008/T010 are [P] after T003; T011 depends on T009; T013 depends on T005–T012; T014 depends on T013; T015 depends on T014
- **US1 (Phase 3)**: Depends on Phase 2 checkpoint (MinIO Healthy)
  - T016 → T017 → T018 → T019 → T020 → T021 → T022 → T023 → T024 → T025 (strictly sequential — same `mc` session)
- **US2 (Phase 4)**: Depends on Phase 2; benefits from US1's port-forward staying open but can run independently
- **US3 (Phase 5)**: Depends on Phase 2; T032/T033 are [P]; T031 should run first to confirm baseline
- **Polish (Phase 6)**: Depends on US1/US2/US3 complete

### User Story Dependencies

- **US1 (P1)**: Independent — only depends on Phase 2.
- **US2 (P2)**: Independent of US1 *for bucket creation*; **US2's negative test (T029) depends on US1's Longhorn user existing** (T021) to verify scope.
- **US3 (P2)**: Independent — verifies the foundation rather than building on US1/US2 functionally. T033 re-runs US1/US2 commands so US3 should run last in practice.

### Parallel Opportunities

- T004 [P] alongside T003 (different files)
- T007, T008, T010 all [P] once T003 is done (different files)
- T032, T033 [P] within US3
- T035, T036 [P] within Polish

---

## Parallel Example: Phase 2 Foundational

```bash
# After T003 (secrets in group_vars/all.yml) completes:
# These three file creations have no inter-file dependencies:
Task: "Create manifests/minio/prereqs/namespace.yaml"               # T007
Task: "Create manifests/minio/prereqs/ingress-route.yaml"           # T008
Task: "Create manifests/minio/minio-values.yaml"                    # T010
```

```bash
# Within US3 verification:
Task: "git grep audit for plaintext credentials"                    # T032
Task: "mc bootstrap idempotency re-run"                             # T033
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Phase 1 + Phase 2 (foundational deploy)
2. Phase 3 (US1) — Longhorn-backups bucket + scoped user
3. **STOP and VALIDATE**: spec 061 can begin against this MVP

### Incremental Delivery

1. Foundation → MinIO Healthy
2. US1 → spec 061 unblocked (MVP — ship here if pressed for time)
3. US2 → general-purpose bucket reserved; future SSO/Loki specs unblocked
4. US3 → reproducibility audit; closes the GitOps verification loop
5. Polish → monitoring + downstream coordination

### Single-Operator Strategy

For a solo homelab operator: run phases strictly sequentially. The "parallel opportunities" above are noted for completeness but most are within-phase file edits that complete in seconds; the real bottleneck is waiting for ArgoCD to reach Synced + Healthy at T015.

---

## Notes

- This is a GitOps/Kubernetes deployment — "tasks" are manifest edits, playbook runs, and verification commands, not application code.
- Every `mc admin` step is upsert-safe per Constitution Principle II; re-running the US1/US2 commands is the idempotency proof in T033.
- T023 and T029 are the two security gates of this spec. Either failing means the policy in T020 is wrong — fix it before continuing rather than working around it.
- Rollback: see `quickstart.md` "Rollback" section. Since no real data lives in MinIO until spec 061's first sync, a 060 rollback is non-destructive.
