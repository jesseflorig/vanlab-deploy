# Tasks: fleet1.lan Local DNS with Internal Wildcard TLS

**Input**: Design documents from `/specs/054-fleet1-lan-wildcard/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- All paths are relative to repository root

---

## Phase 1: Setup

**Purpose**: Create the new `roles/pki/` directory skeleton before any files are written into it.

- [x] T001 Create `roles/pki/` directory structure with subdirectories `defaults/`, `tasks/`, and `templates/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: PKI role files and cluster cert resources that US1, US2, and US3 all depend on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete — the wildcard cert must exist before DNS + NAT are useful, and before CA distribution can happen.

- [x] T002 [P] Create `roles/pki/defaults/main.yml` — define vars: `pki_ca_namespace: cert-manager`, `pki_cert_namespace: traefik`, `pki_ca_secret_name: fleet1-lan-ca-secret`, `pki_wildcard_secret_name: fleet1-lan-wildcard-tls`, `pki_ca_duration: 87600h`, `pki_ca_renew_before: 720h`, `pki_wildcard_duration: 8760h`, `pki_wildcard_renew_before: 720h`
- [x] T003 [P] Create `roles/pki/templates/fleet1-lan-ca-issuer.yaml.j2` — `ClusterIssuer` named `selfsigned-issuer` with `selfSigned: {}`; include a comment that this resource already exists from home-automation prereqs and the apply is idempotent
- [x] T004 [P] Create `roles/pki/templates/fleet1-lan-ca-cert.yaml.j2` — two resources: (1) `Certificate` named `fleet1-lan-ca` in `{{ pki_ca_namespace }}` with `isCA: true`, RSA 4096, `secretName: {{ pki_ca_secret_name }}`, `issuerRef: selfsigned-issuer`; (2) `ClusterIssuer` named `fleet1-lan-ca` with `ca.secretName: {{ pki_ca_secret_name }}`; add ArgoCD sync-wave annotations wave 1 and wave 2 respectively (even though Ansible manages this, wave annotations document intended order)
- [x] T005 [P] Create `roles/pki/templates/fleet1-lan-wildcard-cert.yaml.j2` — `Certificate` named `fleet1-lan-wildcard-tls` in `{{ pki_cert_namespace }}` with `secretName: {{ pki_wildcard_secret_name }}`, `dnsNames: ["*.fleet1.lan"]`, `issuerRef: fleet1-lan-ca (ClusterIssuer)`, `duration: {{ pki_wildcard_duration }}`, `renewBefore: {{ pki_wildcard_renew_before }}`
- [x] T006 [P] Create `roles/pki/templates/fleet1-lan-tls-store.yaml.j2` — `TLSStore` named `default` in `traefik` namespace; add `certificates` list entry with `secretName: {{ pki_wildcard_secret_name }}`; note that the `defaultCertificate` (`fleet1-cloud-tls`) is left unchanged — this is an additive `certificates` entry only
- [x] T007 Create `roles/pki/tasks/main.yml` — tasks in order: (1) render and apply `fleet1-lan-ca-issuer.yaml.j2` via `kubectl apply` with `KUBECONFIG`; (2) render and apply `fleet1-lan-ca-cert.yaml.j2`; (3) wait for `fleet1-lan-ca` Certificate `Ready` with `kubectl wait --timeout=60s`; (4) render and apply `fleet1-lan-wildcard-cert.yaml.j2`; (5) wait for `fleet1-lan-wildcard-tls` Certificate `Ready --timeout=60s`; (6) render and apply `fleet1-lan-tls-store.yaml.j2`; all kubectl commands use `run_once: true` delegated to first server node; follow `changed_when` pattern from `roles/cert-manager/tasks/main.yml`
- [x] T008 Add pki role to `playbooks/cluster/services-deploy.yml` — include `roles/pki` with `tags: [pki]` following the same include pattern used for other infrastructure roles in that playbook

**Checkpoint**: Run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags pki` — both `fleet1-lan-ca` and `fleet1-lan-wildcard-tls` Certificates must show `READY=True`

---

## Phase 3: User Story 1 - Internal Services Resolve via fleet1.lan (Priority: P1) 🎯 MVP

**Goal**: `*.fleet1.lan` resolves to `10.1.20.11` on the LAN; HTTPS connections on port 443 reach Traefik on port 30443; Traefik serves the internal wildcard cert via SNI.

**Independent Test**: `dig grafana.fleet1.lan @10.1.1.1` returns `10.1.20.11`; `curl -v https://grafana.fleet1.lan` (after CA trust in US2) completes TLS handshake with cert `*.fleet1.lan`.

- [x] T009 [US1] Add Unbound host override tasks to `playbooks/network/network-deploy.yml` — verified API endpoints: search with `POST /api/unbound/settings/searchHostOverride` (body: `{"current":1,"rowCount":100,"searchPhrase":""}`), create with `POST /api/unbound/settings/addHostOverride` (body: `{"host":{"enabled":"1","hostname":"*","domain":"fleet1.lan","rr":"A","server":"10.1.20.11","description":"fleet1.lan wildcard → Traefik"}}`), delete with `POST /api/unbound/settings/delHostOverride/<uuid>`, apply with `POST /api/unbound/service/reconfigure`; idempotency: search existing overrides by domain `fleet1.lan` and hostname `*` before creating; only apply reconfigure when a change was made; follow `url_username`/`url_password` auth pattern from existing tasks
- [ ] T010 [US1] ⚠️ BLOCKED — Port 443→30443 bridging: OPNsense 23.7 exposes no REST API for NAT port-forward rules (`/api/firewall/nat` returns 400; HAProxy plugin not installed). Requires a decision — see implementation notes below.

**Checkpoint**: `dig *.fleet1.lan @10.1.1.1` resolves to `10.1.20.11`; `curl -k https://grafana.fleet1.lan` (insecure) returns HTTP 200 or redirect (TLS trust not yet installed)

---

## Phase 4: User Story 2 - CA Root Trust Distributed to Managed Clients (Priority: P2)

**Goal**: Internal CA root cert installed in macOS System Keychain on management laptop; all browsers and CLI tools trust `*.fleet1.lan` certs.

**Independent Test**: After running the playbook, `curl https://grafana.fleet1.lan` (no `--insecure`) succeeds; browser shows green padlock on any `*.fleet1.lan` service.

- [x] T011 [US2] Create `playbooks/compute/ca-trust-deploy.yml` — playbook targeting `localhost` with `connection: local`; tasks: (1) delegate to `groups['servers'][0]` — run `kubectl get secret {{ pki_ca_secret_name }} -n cert-manager -o jsonpath='{.data.ca\.crt}'` and base64-decode to `/tmp/fleet1-lan-ca.crt` on the server; (2) `ansible.builtin.fetch` the cert file from the server to `/tmp/fleet1-lan-ca.crt` on localhost; (3) check if cert fingerprint already exists in System Keychain via `security find-certificate -a -Z /Library/Keychains/System.keychain` and register result; (4) install cert only when fingerprint absent: `security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/fleet1-lan-ca.crt` with `become: true`; (5) remove temp file `/tmp/fleet1-lan-ca.crt`; include a header comment describing usage and prerequisites

**Checkpoint**: Run `ansible-playbook -i hosts.ini playbooks/compute/ca-trust-deploy.yml`; then `curl https://grafana.fleet1.lan` succeeds without `--insecure`; re-running the playbook produces no changes

---

## Phase 5: User Story 3 - Traefik Ingresses Serve the Wildcard TLS Cert (Priority: P3)

**Goal**: All major cluster services are accessible via `*.fleet1.lan` hostnames through Traefik, served with the internal wildcard cert. The TLSStore CRD (T006/T007) already handles cert selection — these tasks add `fleet1.lan` host rules to each service's ingress configuration.

**Independent Test**: Navigate to `https://grafana.fleet1.lan`, `https://argocd.fleet1.lan`, `https://gitea.fleet1.lan`, and `https://frigate.fleet1.lan` — each loads with a valid cert and no TLS warning.

- [x] T012 [P] [US3] Update `roles/traefik/files/values.yaml` — extend `ingressRoute.dashboard.matchRule` from `Host(\`traefik.fleet1.cloud\`)` to `Host(\`traefik.fleet1.cloud\`) || Host(\`traefik.fleet1.lan\`)`
- [x] T013 [P] [US3] Update `roles/kube-prometheus-stack/templates/values.yaml.j2` — in the `grafana.ingress.hosts` list add `grafana.fleet1.lan`; in the `prometheus.prometheusSpec` ingress `hosts` list add `prometheus.fleet1.lan`; in the `alertmanager` ingress `hosts` list add `alertmanager.fleet1.lan` (if alertmanager ingress is enabled)
- [x] T014 [P] [US3] Update `roles/argocd/templates/values.yaml.j2` — the current `server.ingress.hostname` is a single value; add `server.ingress.extraHosts` list with host `argocd.fleet1.lan` and path `/` (Bitnami ArgoCD chart pattern); if `extraHosts` is not supported by the current chart version, add a separate `IngressRoute` CRD manifest in `roles/argocd/templates/` for `argocd.fleet1.lan`
- [x] T015 [P] [US3] Update `roles/gitea/templates/values.yaml.j2` — the `ingress.hosts` field is a list; add an entry for host `gitea.fleet1.lan` with `paths: [{path: /, pathType: Prefix}]`
- [x] T016 [P] [US3] Update `manifests/frigate/ingressroute.yaml` — add a second route to the existing `IngressRoute` resource with `match: Host(\`frigate.fleet1.lan\`)` pointing to the same Frigate service on port 5000; no new TLS secretName needed (wildcard TLSStore handles cert selection by SNI)
- [x] T017 [P] [US3] Add `fleet1.lan` IngressRoute entries for home-automation services — update `manifests/home-automation/home-assistant-values.yaml` to add `homeassistant.fleet1.lan` to the Helm ingress hosts; update `manifests/home-automation/node-red-values.yaml` to add `node-red.fleet1.lan`; update `manifests/home-automation/influxdb-values.yaml` to add `influxdb.fleet1.lan`

**Checkpoint**: Deploy updated configs (re-run Ansible roles for Ansible-managed services; push to Gitea for ArgoCD-managed services); verify each `fleet1.lan` hostname resolves and serves the wildcard cert

---

## Final Phase: Polish & Validation

**Purpose**: End-to-end verification and documentation.

- [x] T018 Add `ca-trust-deploy.yml` to the deploy documentation comment block at the top of `playbooks/compute/ca-trust-deploy.yml` — document that this playbook must be re-run on any new management machine or after an OS reinstall
- [x] T019 Update `group_vars/example.all.yml` — add commented-out placeholder for any new vars introduced by the pki role (e.g., `pki_ca_namespace`, `pki_cert_namespace`) so the template stays current
- [ ] T020 End-to-end validation per `specs/054-fleet1-lan-wildcard/quickstart.md` — run all four steps in order; confirm `READY=True` for both certs, DNS resolves correctly, CA trust is installed, and at least one `fleet1.lan` service loads without TLS warning in a browser

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — **BLOCKS all user stories**
- **US1 (Phase 3)**: Depends on Phase 2 (wildcard cert must exist before DNS+NAT are useful); independent of US2 and US3
- **US2 (Phase 4)**: Depends on Phase 2 (CA cert must exist in cluster to be fetched); independent of US1 and US3
- **US3 (Phase 5)**: Depends on Phase 2 (TLSStore must be deployed); benefits from US1 being done (DNS must resolve for browser test); independent of US2
- **Polish (Final Phase)**: Depends on all desired phases complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — no dependencies on US2 or US3
- **US2 (P2)**: Can start after Phase 2 — no dependencies on US1 or US3
- **US3 (P3)**: Can start after Phase 2; US1 should be complete for end-to-end browser testing, but service config changes (T012–T017) can be made in parallel with US1

### Within Each Phase

- T002–T006 are all parallel (different files)
- T007 depends on T002–T006 (templates must exist before tasks can reference them)
- T008 depends on T007
- T009 and T010 can run in either order (different API endpoints; both update `network-deploy.yml` — sequence them to avoid merge conflict)
- T012–T017 are all parallel (different files)

---

## Parallel Execution Examples

### Phase 2 (Foundational)

```
Parallel batch 1 — run all together:
  T002: roles/pki/defaults/main.yml
  T003: roles/pki/templates/fleet1-lan-ca-issuer.yaml.j2
  T004: roles/pki/templates/fleet1-lan-ca-cert.yaml.j2
  T005: roles/pki/templates/fleet1-lan-wildcard-cert.yaml.j2
  T006: roles/pki/templates/fleet1-lan-tls-store.yaml.j2

Sequential after batch 1:
  T007: roles/pki/tasks/main.yml
  T008: playbooks/cluster/services-deploy.yml (pki role inclusion)
```

### Phase 5 (US3)

```
Parallel batch — run all together:
  T012: roles/traefik/files/values.yaml
  T013: roles/kube-prometheus-stack/templates/values.yaml.j2
  T014: roles/argocd/templates/values.yaml.j2
  T015: roles/gitea/templates/values.yaml.j2
  T016: manifests/frigate/ingressroute.yaml
  T017: manifests/home-automation/*-values.yaml
```

---

## Implementation Strategy

### MVP (User Story 1 + 2 Only)

1. Complete Phase 1 (Setup) + Phase 2 (Foundational)
2. Run `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags pki`
3. Complete Phase 3 (US1) — DNS + NAT
4. Run `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml`
5. Complete Phase 4 (US2) — CA trust
6. Run `ansible-playbook -i hosts.ini playbooks/compute/ca-trust-deploy.yml`
7. **VALIDATE**: `curl https://grafana.fleet1.lan` (insecure cert, no IngressRoute yet for fleet1.lan, but DNS + TLS layer works)

### Full Delivery

1. MVP above
2. Complete Phase 5 (US3) — per-service IngressRoute additions
3. Deploy (re-run Ansible roles / push to Gitea for ArgoCD-managed services)
4. Validate all services via browser

---

## Notes

- [P] tasks operate on different files — safe to implement in a single parallel agent batch
- The TLSStore CRD (T006/T007) is the only thing needed for Traefik to serve the wildcard cert by SNI — no per-service TLS annotation is required for `fleet1.lan` hostnames
- OPNsense Unbound API endpoints verified live: `searchHostOverride`, `addHostOverride`, `delHostOverride/<uuid>`, `reconfigure` — all confirmed working at `10.1.1.1`
- T014 (ArgoCD): verify whether the installed Bitnami chart version supports `server.ingress.extraHosts` before implementing; fallback is a standalone IngressRoute CRD manifest
- US3 changes to Ansible-managed services (T012–T015) require re-running the relevant role or full `services-deploy.yml`; ArgoCD-managed services (T016–T017) sync automatically once pushed to Gitea main
