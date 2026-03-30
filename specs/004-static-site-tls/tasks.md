# Tasks: Static Site with End-to-End TLS

**Input**: Design documents from `/specs/004-static-site-tls/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

**Organization**: Tasks are grouped by user story. US1 (cert issuance) is foundational — US2 (site reachable) requires the cert to be Ready, and US3 (redirect) extends the static-site role. All role files for US2/US3 can be authored in parallel with US1; runtime testing is sequential.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup

**Purpose**: Confirm existing structure before modifications.

- [x] T001 Verify existing files per plan.md: roles/traefik/files/values.yaml, roles/cloudflared/tasks/main.yml, playbooks/cluster/services-deploy.yml, playbooks/compute/edge-deploy.yml exist

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Cross-cutting config changes and the Traefik values update that all user stories depend on.

**⚠️ CRITICAL**: Traefik values update (T004) must be deployed before any story can be tested at runtime — websecure entrypoint is needed for certificate delivery (US1), HTTPS site (US2), and HTTPS redirect (US3).

- [x] T002 [P] Update group_vars/example.all.yml: add placeholder entries for `cloudflare_api_token` (Cloudflare API token with Zone:DNS:Edit + Zone:Zone:Read) and `acme_email` (Let's Encrypt account email) with descriptive comments
- [x] T003 [P] Update group_vars/compute.yml: add `cloudflare_tunnel_id: ""` placeholder and `cloudflared_ingress_rules:` list with fleet1.cloud (https:30443 + originServerName), www.fleet1.cloud (https:30443 + originServerName), whoami.fleet1.cloud (http:30080) per data-model.md
- [x] T004 [P] Update roles/traefik/files/values.yaml: change `ports.web` to add explicit `nodePort: 30080` and `redirectTo: {port: websecure, permanent: true}`; add `ports.websecure` block with `nodePort: 30443`, `tls.enabled: true`; add `providers.kubernetesCRD.enabled: true`; remove `publishedService.enabled` (LoadBalancer-only feature)

**Checkpoint**: Traefik values file updated — ready for user story file authoring.

---

## Phase 3: User Story 1 — Valid Certificate Issued and Auto-Renewed (Priority: P1) 🎯 MVP

**Goal**: Deploy cert-manager and issue a Let's Encrypt certificate for `fleet1.cloud` via Cloudflare DNS-01 challenge. Certificate auto-renews without operator intervention.

**Independent Test**: `kubectl wait certificate/fleet1-cloud-tls -n traefik --for=condition=Ready --timeout=300s` returns success. `kubectl describe certificate fleet1-cloud-tls -n traefik` shows `Ready: True`.

### Implementation for User Story 1

- [x] T005 [P] [US1] Create roles/cert-manager/defaults/main.yml: define `cert_manager_version: "v1.14.5"`, `cert_manager_namespace: "cert-manager"`, `acme_server: "https://acme-v02.api.letsencrypt.org/directory"`, `certificate_namespace: "traefik"`, `certificate_secret_name: "fleet1-cloud-tls"`
- [x] T006 [P] [US1] Create roles/cert-manager/templates/cloudflare-secret.yaml.j2: Secret in `cert-manager` namespace, `type: Opaque`, `stringData.api-token: "{{ cloudflare_api_token }}"` (key name must be exactly `api-token`)
- [x] T007 [P] [US1] Create roles/cert-manager/templates/cluster-issuer.yaml.j2: `ClusterIssuer/letsencrypt-prod`, `acme.email: {{ acme_email }}`, `acme.server: {{ acme_server }}`, `privateKeySecretRef.name: letsencrypt-prod-account-key`, `dns01.cloudflare.apiTokenSecretRef: {name: cloudflare-api-token-secret, key: api-token}`
- [x] T008 [P] [US1] Create roles/cert-manager/templates/certificate.yaml.j2: `Certificate/fleet1-cloud-tls` in `{{ certificate_namespace }}`, `secretName: {{ certificate_secret_name }}`, `issuerRef: {name: letsencrypt-prod, kind: ClusterIssuer}`, `dnsNames: [fleet1.cloud]`
- [x] T009 [US1] Create roles/cert-manager/tasks/main.yml: (1) helm repo add jetstack + update; (2) ensure cert-manager namespace; (3) helm upgrade --install cert-manager with `crds.enabled=true --wait --timeout 3m` + KUBECONFIG env; (4) kubectl rollout status deployment/cert-manager-webhook (mandatory — prevents admission errors); (5) template cloudflare-secret.yaml.j2 → /tmp/cf-secret.yaml with `no_log: true`; (6) kubectl apply /tmp/cf-secret.yaml; (7) file state=absent /tmp/cf-secret.yaml; (8) template + apply cluster-issuer.yaml.j2; (9) template + apply certificate.yaml.j2; (10) kubectl wait certificate/fleet1-cloud-tls --for=condition=Ready --timeout=300s
- [x] T010 [US1] Update playbooks/cluster/services-deploy.yml: insert `cert-manager` role before `traefik` in the servers play roles list; insert `static-site` role after `whoami` (placeholder for US2 — role will exist by then)

**Checkpoint**: Run services-deploy.yml up to cert-manager. Certificate reaches Ready. Re-run produces changed=0.

---

## Phase 4: User Story 2 — Static Site Reachable at fleet1.cloud over HTTPS (Priority: P2)

**Goal**: nginx static site deployed at `https://fleet1.cloud` with the cert-manager TLS certificate. Cloudflare tunnel updated to HTTPS backend with verified TLS.

**Independent Test**: `curl https://fleet1.cloud` returns the placeholder HTML page with a valid TLS certificate and no warnings.

### Implementation for User Story 2

- [x] T011 [P] [US2] Create roles/cloudflared/templates/config.yml.j2: Jinja2 template with `tunnel: {{ cloudflare_tunnel_id }}`, `credentials-file: /etc/cloudflared/credentials.json`, `ingress:` loop over `cloudflared_ingress_rules` rendering hostname/service/originRequest blocks, catch-all `service: http_status:404`
- [x] T012 [US2] Update roles/cloudflared/defaults/main.yml: add `cloudflare_tunnel_id: ""` and `cloudflared_ingress_rules: []` default values
- [x] T013 [US2] Update roles/cloudflared/tasks/main.yml: (1) add `ansible.builtin.template` task deploying `config.yml.j2` → `/etc/cloudflared/config.yml` (mode 0600, owner root, `notify: Restart cloudflared`); (2) update the cloudflared systemd unit `ExecStart` line from `--token-file /etc/cloudflared/tunnel-token` to `--config /etc/cloudflared/config.yml`
- [x] T014 [P] [US2] Create roles/static-site/files/site.yaml: 4 resources — `ConfigMap/static-site-html` (namespace traefik, index.html placeholder content); `Deployment/static-site` (nginx:alpine, mounts ConfigMap at /usr/share/nginx/html); `Service/static-site` (ClusterIP port 80); `Ingress/fleet1-cloud` (ingressClassName: traefik, annotation `traefik.ingress.kubernetes.io/router.entrypoints: websecure`, tls.secretName: fleet1-cloud-tls, host: fleet1.cloud)
- [x] T015 [US2] Create roles/static-site/tasks/main.yml: copy files/site.yaml → /tmp/site.yaml; kubectl apply -f /tmp/site.yaml; kubectl rollout status deployment/static-site -n traefik --timeout=60s

**Checkpoint**: Run services-deploy.yml + edge-deploy.yml. `curl https://fleet1.cloud` returns HTML with valid cert. Re-run produces changed=0.

---

## Phase 5: User Story 3 — All Non-Apex Requests Redirect to fleet1.cloud (Priority: P3)

**Goal**: `www.fleet1.cloud` and any unrecognised subdomain permanently redirect (301) to `https://fleet1.cloud` via Traefik Middleware + IngressRoute.

**Independent Test**: `curl -I https://www.fleet1.cloud` returns `301 Moved Permanently` with `Location: https://fleet1.cloud`.

### Implementation for User Story 3

- [x] T016 [P] [US3] Create roles/static-site/files/redirects.yaml: 2 resources using `traefik.io/v1alpha1` API group — `Middleware/redirect-to-apex` (redirectRegex: `regex: "^https?://[^.]+\\.fleet1\\.cloud(.*)"`, `replacement: "https://fleet1.cloud${1}"`, `permanent: true`); `IngressRoute/wildcard-subdomain-redirect` (entryPoints: [websecure], tls.secretName: fleet1-cloud-tls, route match: `HostRegexp(` + backtick + `^[^.]+\.fleet1\.cloud$` + backtick + `)`, priority: 1, middleware: redirect-to-apex, service: `noop@internal` kind: TraefikService)
- [x] T017 [US3] Update roles/static-site/tasks/main.yml: add copy files/redirects.yaml → /tmp/redirects.yaml and kubectl apply -f /tmp/redirects.yaml after the existing site.yaml apply tasks

**Checkpoint**: `curl -I https://www.fleet1.cloud` → 301 → https://fleet1.cloud. Re-run produces changed=0.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final idempotency and end-to-end validation.

- [x] T018 Idempotency: re-run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --ask-become-pass` and confirm changed=0
- [x] T019 Idempotency: re-run `ansible-playbook -i hosts.ini playbooks/compute/edge-deploy.yml --ask-become-pass` and confirm changed=0
- [x] T020 End-to-end: verify `https://fleet1.cloud` loads with valid padlock from outside network (per quickstart.md Step 6)
- [x] T021 Redirect: verify `curl -I https://www.fleet1.cloud` returns 301 → https://fleet1.cloud (per quickstart.md Step 6)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: No dependencies — can start immediately after setup
- **US1 (Phase 3)**: Depends on T004 (Traefik values) at runtime; T005–T008 files can be authored in parallel with Phase 2
- **US2 (Phase 4)**: Files can be authored in parallel with US1; runtime test requires US1 cert to be Ready
- **US3 (Phase 5)**: T016 can be authored in parallel with US2; T017 depends on T015 (tasks file must exist first)
- **Polish (Phase 6)**: Requires all stories deployed and tested

### User Story Dependencies

- **US1**: Cert issuance — foundational; must reach Ready before US2 can serve HTTPS
- **US2**: Site + cloudflared — runtime requires US1 cert; files are independent
- **US3**: Redirect rules — runtime requires US2 Traefik IngressRoute CRD provider enabled (T004)

### Within Each User Story

- T005–T008 [P]: all new files in the cert-manager role, fully independent
- T009: depends on T005–T008 (tasks file references the template files)
- T010: depends on T009 existing (services-deploy must reference a real role)
- T011 [P]: new file, independent
- T012 → T013: sequential (T013 modifies same tasks/main.yml that T012 adds context for)
- T014 [P]: new file, independent of T011–T013
- T015: depends on T014 (tasks file applies site.yaml which must exist)
- T016 [P]: new file, can be authored any time after T015 structure is known
- T017: depends on T015 (must add to existing tasks/main.yml, not create it)

### Parallel Opportunities

- T002, T003, T004 can all run in parallel (Phase 2)
- T005, T006, T007, T008, T011, T014, T016 can all run in parallel (different files)
- T018 and T019 can run in parallel (different playbooks)

---

## Parallel Example: Author all role files simultaneously

```text
# All of these touch different files and have no inter-dependencies:
Parallel A: T005 — roles/cert-manager/defaults/main.yml
Parallel B: T006 — roles/cert-manager/templates/cloudflare-secret.yaml.j2
Parallel C: T007 — roles/cert-manager/templates/cluster-issuer.yaml.j2
Parallel D: T008 — roles/cert-manager/templates/certificate.yaml.j2
Parallel E: T011 — roles/cloudflared/templates/config.yml.j2
Parallel F: T014 — roles/static-site/files/site.yaml
Parallel G: T016 — roles/static-site/files/redirects.yaml

# After T005–T008 exist:
Sequential: T009 — roles/cert-manager/tasks/main.yml

# After T014 exists:
Sequential: T015 — roles/static-site/tasks/main.yml

# After T015 exists:
Sequential: T017 — update tasks/main.yml to add redirects.yaml apply
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (T001) + Phase 2 (T002–T004)
2. Complete Phase 3 / US1 (T005–T010)
3. **STOP and VALIDATE**: Run services-deploy.yml, confirm `kubectl wait certificate/fleet1-cloud-tls --for=condition=Ready`
4. Proceed to US2 only after cert is issued

### Incremental Delivery

1. T001–T004 → foundation ready
2. T005–T010 → cert issued → validate (US1 MVP)
3. T011–T016 → site live over HTTPS + cloudflared updated → validate (US2)
4. T016–T017 → redirects working → validate (US3)
5. T018–T021 → idempotency + E2E sign-off

---

## Notes

- No tests requested in spec — no test tasks generated
- The operator one-time prerequisite (`cloudflared tunnel token --creds-file`) is in quickstart.md Step 0 — not an Ansible task
- `cloudflare_tunnel_id` is not a secret — safe to commit in compute.yml
- `cloudflare_api_token` and `acme_email` go in gitignored `group_vars/all.yml`
- T009 step 4 (webhook rollout wait) is mandatory — skipping it causes admission errors on K3s
- T016 uses `traefik.io/v1alpha1` API group (v3) — NOT `traefik.containo.us/v1alpha1` (v2, removed in v3)
- T016 `HostRegexp` uses plain Go regex syntax: backtick-wrapped `^[^.]+\.fleet1\.cloud$` — NOT v2 named-group syntax
