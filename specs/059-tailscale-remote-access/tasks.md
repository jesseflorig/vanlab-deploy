# Tasks: Tailscale Remote Access for fleet1.lan

**Input**: Design documents from `/specs/059-tailscale-remote-access/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

**No tests requested** — IaC feature; verification is done via `ansible-playbook --check` and live connectivity checks.

**Organization**: Tasks grouped by user story. US1 (service access + mTLS) is the highest-value story and the main implementation driver. US2 (SSH/Ansible access) is largely satisfied by the foundational Tailscale layer. US3 (idempotency/IaC quality) validates the automation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no shared dependencies)
- **[Story]**: User story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup (Role + Playbook Skeletons)

**Purpose**: Create all directory structures and stub files before implementation begins.

- [X] T001 Create `roles/tailscale/defaults/main.yml` with variables: `tailscale_auth_key`, `tailscale_advertise_routes` (default `""`), `tailscale_accept_routes` (default `true`), `tailscale_accept_dns` (default `false`)
- [X] T002 [P] Create `roles/tailscale/tasks/main.yml` as an empty task file with a comment header describing the role purpose
- [X] T003 [P] Create `roles/device-mtls/defaults/main.yml` with all variables from `data-model.md` § "roles/device-mtls — defaults/main.yml"
- [X] T004 [P] Create `roles/device-mtls/tasks/main.yml` as an empty task file with a comment header describing the role purpose
- [X] T005 [P] Create `roles/device-mtls/templates/` directory by adding a `.gitkeep` placeholder
- [X] T006 Add `tailscale_auth_key: "<REPLACE_WITH_TAILSCALE_AUTH_KEY>"` to `group_vars/example.all.yml` under a `# Tailscale` comment section

**Checkpoint**: Skeleton complete — ready to implement role bodies.

---

## Phase 2: Foundational — Tailscale Daemon + Network Layer

**Purpose**: Install and enroll Tailscale on all managed nodes with subnet routing. This phase is the prerequisite for ALL user stories.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete and manual admin console steps are performed.

### Tailscale Role Implementation

- [X] T007 Implement Tailscale apt repository setup in `roles/tailscale/tasks/main.yml`: add GPG key from `https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg`, add apt sources list entry to `/etc/apt/sources.list.d/tailscale.list`, run `apt-get update`, and install `tailscale` package. Use `ansible.builtin.apt_key`, `ansible.builtin.apt_repository`, and `ansible.builtin.apt` modules with idempotent state guards.
- [X] T008 Implement Tailscale service enable task in `roles/tailscale/tasks/main.yml`: ensure `tailscaled` systemd service is `enabled` and `started` using `ansible.builtin.service`.
- [X] T009 Implement IP forwarding sysctl task in `roles/tailscale/tasks/main.yml`: write `/etc/sysctl.d/99-tailscale.conf` with `net.ipv4.ip_forward = 1` and `net.ipv6.conf.all.forwarding = 1`, then reload with `ansible.posix.sysctl`. Use `when: tailscale_advertise_routes | length > 0` so it only runs on subnet router nodes.
- [X] T010 Implement Tailscale enrollment idempotency guard in `roles/tailscale/tasks/main.yml`: run `tailscale status --json` and register the result; set a fact `tailscale_enrolled` to `true` when `BackendState == "Running"`. Use `ansible.builtin.command` and `ansible.builtin.set_fact`.
- [X] T011 Implement `tailscale up` enrollment task in `roles/tailscale/tasks/main.yml`: run `tailscale up --auth-key={{ tailscale_auth_key }} --accept-routes={{ tailscale_accept_routes | lower }} --accept-dns={{ tailscale_accept_dns | lower }}{% if tailscale_advertise_routes %} --advertise-routes={{ tailscale_advertise_routes }}{% endif %}` only when `not tailscale_enrolled`. Mark task `no_log: true` to prevent auth key appearing in output. `changed_when: not tailscale_enrolled`.
- [X] T012 Implement key expiry disable task in `roles/tailscale/tasks/main.yml`: run `tailscale set --key-expiry-disabled` using `ansible.builtin.command`. Use `register` + `changed_when: "'Key expiry' in result.stdout or result.rc == 0"` and a status check to skip if already disabled.

### Playbook

- [X] T013 Create `playbooks/compute/tailscale-deploy.yml` with two plays: (1) `hosts: cluster,compute,nvr` / `become: true` / `roles: [tailscale]` for basic enrollment on all nodes; (2) Annotate that `tailscale_advertise_routes` is set per-group in `group_vars/servers.yml`. Add `pre_tasks` with an assertion that `tailscale_auth_key is defined and tailscale_auth_key | length > 0` following the pattern in `playbooks/compute/edge-deploy.yml`.
- [X] T014 Create `group_vars/servers.yml` (new file) containing `tailscale_advertise_routes: "10.1.1.0/24,10.1.10.0/24,10.1.20.0/24,10.1.30.0/24,10.1.40.0/24,10.1.50.0/24"` so server nodes automatically get subnet router configuration.

### Manual Admin Console Steps (document-only tasks)

- [X] T015 Add a comment block to `playbooks/compute/tailscale-deploy.yml` header (after the YAML `---`) explaining the two required manual admin console steps that must be performed after the playbook: (1) approve advertised routes for node1, node3, node5 at `login.tailscale.com/admin/machines`; (2) configure fleet1.lan custom DNS nameserver (`10.1.1.1`) at `login.tailscale.com/admin/dns`. Reference `specs/059-tailscale-remote-access/quickstart.md` Steps 4 and 5.

**Checkpoint**: After running `tailscale-deploy.yml` and completing Steps 4–5 from quickstart.md, SSH to any node via its LAN IP from an external network with Tailscale active. This validates US2 independently.

---

## Phase 3: User Story 1 — Fleet1.lan Service Access + mTLS (Priority: P1) 🎯 MVP

**Goal**: Management laptop can access all fleet1.lan services (Gitea, ArgoCD, Grafana, etc.) by hostname immediately after opening Tailscale, with mTLS device cert verification blocking any non-certified client.

**Independent Test**: From a mobile hotspot with Tailscale active + device cert installed in browser: open `https://gitea.fleet1.lan` → page loads. Without client cert: connection rejected (not a login page).

### Device CA and mTLS Infrastructure (Ansible role + playbook)

- [X] T016 [US1] Create `roles/device-mtls/templates/device-ca-cert.yaml.j2`: cert-manager `Certificate` resource with `isCA: true`, `commonName: device-ca`, `secretName: {{ device_mtls_ca_secret_name }}`, `algorithm: RSA size: 4096`, `duration: {{ device_mtls_ca_duration }}`, `renewBefore: {{ device_mtls_ca_renew_before }}`, `issuerRef.name: selfsigned-issuer` / `kind: ClusterIssuer`. Follow the pattern in `roles/pki/templates/fleet1-lan-ca-cert.yaml.j2`.
- [X] T017 [P] [US1] Create `roles/device-mtls/templates/device-ca-issuer.yaml.j2`: cert-manager `ClusterIssuer` named `{{ device_mtls_ca_name }}-issuer` using `ca.secretName: {{ device_mtls_ca_secret_name }}`. Follow the pattern in `roles/pki/templates/fleet1-lan-ca-cert.yaml.j2` (second document in that template).
- [X] T018 [P] [US1] Create `roles/device-mtls/templates/device-client-cert.yaml.j2`: cert-manager `Certificate` named `{{ device_mtls_client_cert_name }}` in namespace `{{ device_mtls_ca_namespace }}`, `usages: [client auth]`, `secretName: {{ device_mtls_client_cert_name }}-tls`, `duration: {{ device_mtls_client_cert_duration }}`, `renewBefore: {{ device_mtls_client_cert_renew_before }}`, `issuerRef.name: {{ device_mtls_ca_name }}-issuer` / `kind: ClusterIssuer`.
- [X] T019 [P] [US1] Create `roles/device-mtls/templates/device-tls-option.yaml.j2`: Traefik `TLSOption` named `{{ device_mtls_tls_option_name }}` in namespace `{{ device_mtls_traefik_namespace }}` with `spec.clientAuth.secretNames: [{{ device_mtls_ca_public_secret_name }}]` and `clientAuthType: RequireAndVerifyClientCert`.
- [X] T020 [US1] Implement `roles/device-mtls/tasks/main.yml` with the following sequential tasks (all `run_once: true`, `environment.KUBECONFIG: /etc/rancher/k3s/k3s.yaml`): (1) render `device-ca-cert.yaml.j2` to `/tmp/device-ca-cert.yaml` and `kubectl apply` it; (2) wait for Device CA Certificate `Ready` condition (`kubectl wait certificate/{{ device_mtls_ca_name }} -n {{ device_mtls_ca_namespace }} --for=condition=Ready --timeout=60s`); (3) render and apply `device-ca-issuer.yaml.j2`; (4) render and apply `device-client-cert.yaml.j2`; (5) wait for laptop client cert `Ready`; (6) extract Device CA public cert from the `device-ca-tls` Secret (`kubectl get secret {{ device_mtls_ca_secret_name }} -n {{ device_mtls_ca_namespace }} -o jsonpath='{.data.tls\.crt}'`) and register it as `device_ca_public_cert`; (7) create the `device-ca-public` Opaque Secret in the `{{ device_mtls_traefik_namespace }}` namespace with key `ca.crt` containing the decoded cert (use `--dry-run=client -o yaml | kubectl apply -f -` for idempotency); (8) render and apply `device-tls-option.yaml.j2`; (9) remove all `/tmp/device-*.yaml` temp files. Follow the cert-manager task patterns in `roles/cert-manager/tasks/main.yml`.
- [X] T021 [US1] Create `playbooks/cluster/device-mtls-deploy.yml`: single play with `hosts: servers`, `become: true`, `roles: [device-mtls]`. Add a pre-task assertion that `cert-manager` is running (`kubectl get pods -n cert-manager | grep -c Running`).

### Fleet1.lan IngressRoute Manifests (ArgoCD-managed)

- [X] T022 [US1] Create `manifests/gitea/fleet1-lan-ingressroute.yaml`: Traefik `IngressRoute` named `gitea-fleet1-lan` in namespace `gitea`, `entryPoints: [websecure]`, `tls.options: name: device-mtls / namespace: traefik` (no `tls.secretName` — relies on TLSStore wildcard), `routes[0].match: Host("gitea.fleet1.lan")`, `services[0].name: gitea-http / port: 3000`. Use the pattern from `manifests/frigate/ingressroute.yaml`.
- [X] T023 [P] [US1] Create `manifests/argocd/fleet1-lan-ingressroute.yaml`: same pattern, namespace `argocd`, `Host("argocd.fleet1.lan")`, backend `argocd-server:443`. Add passthrough header annotation if ArgoCD requires HTTPS to backend (mirror what the existing ArgoCD Helm Ingress does for the fleet1.lan host).
- [X] T024 [P] [US1] Create `manifests/monitoring/fleet1-lan-ingressroutes.yaml`: single file with two `IngressRoute` documents (separated by `---`) for `grafana.fleet1.lan` → `kube-prometheus-stack-grafana:80` and `prometheus.fleet1.lan` → `prometheus-operated:9090` (or the correct kube-prometheus-stack service name). Both with `tls.options: device-mtls@traefik`. Namespace: `monitoring`.
- [X] T025 [P] [US1] Create `manifests/frigate/fleet1-lan-ingressroute.yaml`: same pattern, namespace `frigate`, `Host("frigate.fleet1.lan")`, backend `frigate:5000`. After this file is created, remove the `Host("frigate.fleet1.lan")` route from the existing `manifests/frigate/ingressroute.yaml` (keep the `fleet1.cloud` route in that file).
- [X] T026 [P] [US1] Create `manifests/home-automation/fleet1-lan-ingressroutes.yaml`: single file with IngressRoute documents for `hass.fleet1.lan` → `home-assistant:8080`, `influxdb.fleet1.lan` → `influxdb:8086`, and `node-red.fleet1.lan` → `node-red:1880`. All with `tls.options: device-mtls@traefik`. Namespace: `home-automation`. After creation, delete `manifests/home-automation/influxdb-fleet1-lan-ingress.yaml` (it is superseded by this file).

### Remove Duplicate Fleet1.lan Hosts from Helm Chart Values

- [X] T027 [US1] Remove `- host: "gitea.fleet1.lan"` entry from `roles/gitea/templates/values.yaml.j2` Ingress hosts section. The fleet1.lan route is now handled by `manifests/gitea/fleet1-lan-ingressroute.yaml`.
- [X] T028 [P] [US1] Remove `- name: "argocd.fleet1.lan"` entry from `roles/argocd/templates/values.yaml.j2` Ingress extraHosts section. The fleet1.lan route is now handled by `manifests/argocd/fleet1-lan-ingressroute.yaml`.
- [X] T029 [P] [US1] Remove `"prometheus.fleet1.lan"` and `"grafana.fleet1.lan"` entries from `roles/kube-prometheus-stack/templates/values.yaml.j2` Ingress hosts sections. The fleet1.lan routes are now handled by `manifests/monitoring/fleet1-lan-ingressroutes.yaml`.
- [X] T030 [P] [US1] Remove `- host: node-red.fleet1.lan` from `manifests/home-automation/node-red-values.yaml` and `- host: hass.fleet1.lan` from `manifests/home-automation/home-assistant-values.yaml`. The fleet1.lan routes are now handled by `manifests/home-automation/fleet1-lan-ingressroutes.yaml`.

### Laptop Certificate Export

- [X] T031 [US1] Add an export helper script at `scripts/export-device-cert.sh` (chmod +x): uses `kubectl get secret laptop-client-cert-tls -n cert-manager` to extract `tls.crt` and `tls.key`, writes them to `~/fleet1-laptop-cert.pem` and `~/fleet1-laptop-cert.key`, then runs `openssl pkcs12 -export` to produce `~/fleet1-laptop-cert.p12` with an interactive passphrase prompt. Add a `.gitignore` entry ensuring `*.pem`, `*.key`, and `*.p12` files in the repo root are excluded.

**Checkpoint**: After deploying device-mtls role, pushing IngressRoute manifests, and installing the cert on the laptop — verify US1 independent test from quickstart.md Step 11.

---

## Phase 4: User Story 2 — SSH + Ansible Access to All Lab Nodes (Priority: P2)

**Goal**: From an external network with Tailscale active, SSH directly to any node by LAN IP and run Ansible playbooks against the full inventory.

**Independent Test**: From a mobile hotspot with Tailscale active: `ssh fleetadmin@10.1.20.11` succeeds without any tunneling configuration.

**Note**: SSH and Ansible reachability is largely delivered by Phase 2 (subnet routing). This phase covers verification and any remaining configuration.

- [X] T032 [US2] Add a verification section to `specs/059-tailscale-remote-access/quickstart.md` under a new `## US2 Verification` heading with the exact commands to verify SSH reachability to all 8 nodes and a test Ansible ping: `ansible -i hosts.ini all -m ping --ask-vault-pass`. (If quickstart.md already has this content, confirm it's accurate — no file edit needed, but mark T032 as confirming accuracy.)
- [X] T033 [US2] Update `README.md` (in the vanlab repo root) to add a `## Remote Access` section that documents: the Tailscale setup requirement, which nodes are subnet routers, the manual admin console steps, and a reference to `specs/059-tailscale-remote-access/quickstart.md` for the full runbook.

**Checkpoint**: After Phase 2 + manual admin console steps complete, US2 is independently verifiable via the commands in quickstart.md US2 Verification section.

---

## Phase 5: User Story 3 — Automated Provisioning + Idempotency (Priority: P3)

**Goal**: Running the Tailscale playbook twice produces zero changes on the second run; the roles are idempotent and fully code-managed.

**Independent Test**: `ansible-playbook -i hosts.ini playbooks/compute/tailscale-deploy.yml --ask-vault-pass` followed by a second run — second run shows `changed=0` for all hosts.

- [X] T034 [US3] Audit `roles/tailscale/tasks/main.yml` for idempotency: verify every task uses a `changed_when` expression (not just `rc == 0`), verify `tailscale up` is gated on the enrollment check from T010, verify the `tailscale set --key-expiry-disabled` task has a guard that reads current expiry state and skips if already disabled (use `tailscale status --json | jq '.Self.KeyExpiry'` — disabled shows `"0001-01-01T00:00:00Z"`).
- [X] T035 [US3] Audit `roles/device-mtls/tasks/main.yml` for idempotency: verify all `kubectl apply` commands use `--dry-run=client -o yaml | kubectl apply -f -` or equivalent; verify `kubectl wait` tasks use `changed_when: false`; verify temp file cleanup runs even if earlier tasks fail (use `always:` block for cleanup).
- [ ] T036 [US3] Run `ansible-playbook -i hosts.ini playbooks/compute/tailscale-deploy.yml --check --ask-vault-pass` and confirm the playbook passes check mode without errors. Fix any tasks that fail `--check` mode (e.g., tasks that use `command` with output-dependent logic — add `check_mode: false` with appropriate guards).

**Checkpoint**: Second run of tailscale-deploy.yml shows `changed=0`. US3 acceptance criteria met.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T037 [P] Verify `group_vars/example.all.yml` contains ALL new variables introduced by this feature: `tailscale_auth_key` with placeholder value. Check for any device-mtls role variables that may need defaults documented. No variable in `group_vars/all.yml` should be undocumented in `example.all.yml`.
- [X] T038 [P] Add a `# Tailscale` comment section and role description comment to `playbooks/cluster/device-mtls-deploy.yml` and `playbooks/compute/tailscale-deploy.yml` following the project convention (look at existing playbook comment headers).
- [ ] T039 Run the full end-to-end verification from `specs/059-tailscale-remote-access/quickstart.md` Step 11 on a real external network. Confirm: (a) subnet ping to `10.1.1.1` works, (b) `fleet1.lan` DNS resolves, (c) `curl` without cert is rejected, (d) `curl` with cert succeeds, (e) browser opens `https://gitea.fleet1.lan` with cert prompt and loads page.
- [X] T040 Update `specs/059-tailscale-remote-access/spec.md` status from `Draft` to `Implemented`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (role structure must exist)
- **Phase 3 (US1)**: Depends on Phase 2 completion + manual admin console Steps 4–5
- **Phase 4 (US2)**: Depends on Phase 2 completion + manual admin console Step 4 (route approval). Independent of Phase 3.
- **Phase 5 (US3)**: Depends on Phases 2 and 3 being complete (verifies both)
- **Phase 6 (Polish)**: Depends on Phases 2–5 complete

### User Story Dependencies

- **US1 (P1)**: Requires Phase 2 complete + admin console steps + Device CA role + IngressRoute manifests
- **US2 (P2)**: Requires Phase 2 complete + admin console route approval only — can be validated before US1
- **US3 (P3)**: Validates US1 + US2 automation quality

### Within Each Phase

- T007–T012 (role tasks): Must be sequential (each builds on the previous task file)
- T016–T019 (template files): All [P] — independent files, create in parallel
- T020 (role implementation): Depends on T016–T019 templates existing
- T022–T026 (IngressRoute manifests): All [P] — independent files
- T027–T030 (Helm cleanup): All [P] — independent files; should be done together with T022–T026 to avoid duplicate routing

---

## Parallel Opportunities

### Phase 1 — All skeleton files in parallel
```
T001 defaults/main.yml (tailscale)
T002 tasks/main.yml (tailscale)       ← parallel with T003, T004, T005, T006
T003 defaults/main.yml (device-mtls)
T004 tasks/main.yml (device-mtls)
T005 templates/.gitkeep (device-mtls)
T006 group_vars/example.all.yml
```

### Phase 3 — Templates and manifests in parallel
```
T016 device-ca-cert.yaml.j2
T017 device-ca-issuer.yaml.j2         ← parallel with T016, T018, T019
T018 device-client-cert.yaml.j2
T019 device-tls-option.yaml.j2
--- T020 depends on T016-T019 ---
T022 manifests/gitea/...
T023 manifests/argocd/...             ← parallel with T022, T024, T025, T026
T024 manifests/monitoring/...
T025 manifests/frigate/...
T026 manifests/home-automation/...
T027 roles/gitea cleanup
T028 roles/argocd cleanup             ← parallel with T027, T029, T030
T029 roles/kube-prometheus-stack cleanup
T030 manifests/home-automation values cleanup
```

---

## Implementation Strategy

### MVP First (US2 + Subnet Routing)

1. Complete Phase 1 (Setup)
2. Complete Phase 2 (Foundational — Tailscale daemon + routing)
3. Perform manual admin console Steps 4 (route approval) from quickstart.md
4. **STOP and VALIDATE**: SSH to `10.1.20.11` from external network — US2 working
5. Continue to Phase 3 for US1 (mTLS + service access)

### Incremental Delivery

1. Phase 1 + 2 → Tailscale on all nodes, subnet routing working
2. + Manual admin console steps → External SSH + Ansible access (US2 done)
3. + Admin console DNS config (Step 5) → Fleet1.lan DNS works over Tailscale
4. + Phase 3 → mTLS device certs + fleet1.lan IngressRoutes (US1 done)
5. + Phase 5 → Idempotency validated (US3 done)

### Commit Strategy

- Commit after T014 (Tailscale role + playbook complete, before running)
- Commit after T021 (device-mtls role + playbook complete)
- Commit after T031 (all IngressRoute manifests + Helm cleanup)
- Commit after T036 (idempotency verified, feature complete)
- Push to Gitea + merge per `CLAUDE.md` git workflow after each validated commit

---

## Notes

- All `kubectl` commands in Ansible tasks must use `environment: KUBECONFIG: /etc/rancher/k3s/k3s.yaml` and `run_once: true` (pattern from `roles/cert-manager/tasks/main.yml`)
- `no_log: true` is REQUIRED on any task that references `tailscale_auth_key`
- The `device-ca-public` Secret creation (step 7 in T020) requires base64 decoding the cert from the K8s Secret before writing it — the raw K8s Secret value is base64-encoded, and the new Secret's `ca.crt` value must also be base64-encoded for the YAML; handle this carefully to avoid double-encoding
- Fleet1.lan IngressRoutes do NOT specify `tls.secretName` — they rely on the Traefik TLSStore (`fleet1-lan-wildcard-tls`) for cert selection via SNI, same as the existing frigate IngressRoute pattern
- The `mosquitto-tcp-route.yaml` (`mqtt.fleet1.lan`) is a TCP IngressRoute for MQTT TLS — it does NOT get mTLS applied (IoT devices connecting to MQTT cannot present device certs). Leave it unchanged.
- MQTT (port 8883) does not need mTLS enforcement — it already uses cert-based client auth at the MQTT protocol level (from spec 056)
