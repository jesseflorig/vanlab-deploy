# Tasks: MQTT migrate to fleet1.lan

**Input**: Design documents from `/specs/056-mqtt-lan-migration/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, quickstart.md ✓

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: File edits and OPNsense rule that MUST be applied before US1 can be verified. All T001–T006 edits touch different files and can be done in parallel.

**⚠️ CRITICAL**: All T001–T006 must complete before T007–T009 can run.

- [x] T001 [P] Update Mosquitto server cert SAN in `manifests/home-automation/prereqs/certificates.yaml` — replace `mqtt.fleet1.cloud` with `mqtt.fleet1.lan` in `spec.dnsNames` (retain `mosquitto.home-automation.svc.cluster.local` and `mosquitto.home-automation`)
- [x] T002 [P] Update Traefik TCP route in `manifests/home-automation/prereqs/mosquitto-tcp-route.yaml` — replace `HostSNI('mqtt.fleet1.cloud')` with `HostSNI('mqtt.fleet1.lan')` in both the comment and the `match:` field
- [x] T003 [P] Update Ansible role default in `roles/mosquitto/defaults/main.yml` — change `mosquitto_hostname` from `mqtt.fleet1.cloud` to `mqtt.fleet1.lan`
- [x] T004 [P] Add MQTTS DNAT rule to `playbooks/network/network-deploy.yml` — add a new entry to the `dnat_rules` (or equivalent structure) that mirrors the existing HTTPS DNAT pattern: destination `10.1.20.11:8883` → target `10.1.20.11:30883`, description `fleet1.lan MQTTS → Traefik NodePort`; use the same idempotent upsert pattern (check `descr` field before creating)
- [x] T005 [P] Rename MQTT broker variable in `roles/nvr/defaults/main.yml` — replace `nvr_mqtt_broker_ip: "10.1.20.11"` with `nvr_mqtt_broker_host: "mqtt.fleet1.lan"`
- [x] T006 [P] Update Frigate config template in `roles/nvr/templates/frigate-config.yml.j2` — change `host: "{{ nvr_mqtt_broker_ip }}"` to `host: "{{ nvr_mqtt_broker_host }}"`
- [x] T007 Apply DNAT rule — run `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml`; confirm the `fleet1.lan MQTTS → Traefik NodePort` rule shows `changed` or already exists (depends on T004)
- [x] T008 Commit and push manifest and role changes to Gitea — stage T001 + T002 + T003 + T005 + T006 changes, commit with message `feat(mqtt): migrate broker hostname to mqtt.fleet1.lan`, push to `gitea 056-mqtt-lan-migration` (depends on T001–T003, T005–T006)
- [x] T009 Wait for ArgoCD to sync and cert-manager to reissue `mosquitto-tls` — monitor ArgoCD at `https://argocd.fleet1.cloud`; run `kubectl get certificate -n home-automation mosquitto-tls` until STATUS is `Ready` (depends on T008)

**Checkpoint**: DNAT rule live, manifests synced, new cert issued — US1 verification can now begin.

---

## Phase 2: User Story 1 — MQTT accessible via fleet1.lan (Priority: P1) 🎯 MVP

**Goal**: Internal clients can reach the MQTT broker at `mqtt.fleet1.lan:8883` using MQTTS. Frigate is reconfigured to use the hostname. HA and Node-RED are unaffected.

**Independent Test**: An MQTT client connects, publishes, and receives a test message via `mqtt.fleet1.lan:8883`; cert validation passes; Frigate logs show connected.

- [x] T010 [US1] Verify cert SAN — run `kubectl get secret -n home-automation mosquitto-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text | grep -A5 "Subject Alternative"` and confirm `mqtt.fleet1.lan` is listed (depends on T009)
- [x] T011 [US1] Verify Traefik TCP route — run `kubectl get ingressroutetcp -n home-automation mosquitto-mqtts -o yaml` and confirm `match` contains `HostSNI('mqtt.fleet1.lan')` (depends on T009)
- [ ] T012 [US1] Verify MQTT connection via `mqtt.fleet1.lan:8883` — from management host, run `mosquitto_pub` with the home-automation CA cert and a client cert against `mqtt.fleet1.lan:8883`; confirm publish succeeds and TLS cert validation passes (SC-001, SC-002 from quickstart.md)
- [x] T013 [US1] Deploy updated Frigate config to NVR host — run `ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml`; confirm the task that writes `frigate-config.yml` shows `changed` (depends on T008)
- [x] T014 [US1] Verify Frigate MQTT connection — check Frigate UI at `https://frigate.fleet1.lan` for MQTT connected status; run `ssh nvr "docker logs frigate 2>&1 | grep -i mqtt | tail -20"` and confirm no TLS errors or connection refused (depends on T013)
- [ ] T015 [US1] Verify HA MQTT automations — confirm Home Assistant MQTT device states and automations remain functional (no regressions from cert reissue); HA uses `mosquitto.home-automation.svc.cluster.local` and should be unaffected but verify no disruption occurred

**Checkpoint**: `mqtt.fleet1.lan:8883` reachable; cert validated; Frigate connected; HA unaffected. US1 complete — proceed to US2.

---

## Phase 3: User Story 2 — mqtt.fleet1.cloud retired cleanly (Priority: P2)

**Goal**: `mqtt.fleet1.cloud` is removed from all DNS and routing configuration. No dangling records or rules remain.

**Independent Test**: `mqtt.fleet1.cloud` returns NXDOMAIN on internal DNS lookup. All clients continue working via `mqtt.fleet1.lan`.

**⚠️ Do NOT start this phase until T015 (US1 checkpoint) passes.**

- [x] T016 [US2] Confirm no active consumer still references `mqtt.fleet1.cloud` — search the repo with `grep -r "mqtt.fleet1.cloud" --include="*.yml" --include="*.yaml" --include="*.j2"` and verify only stale/commented references remain (the TCP route was already updated in T002)
- [ ] T017 [US2] Verify `mqtt.fleet1.cloud` is not a live public Cloudflare DNS record — run `dig mqtt.fleet1.cloud` from outside the network or check Cloudflare dashboard; if a public record exists, document and remove it separately before proceeding
- [x] T018 [US2] Check for any explicit Unbound override for `mqtt.fleet1.cloud` in OPNsense — log into OPNsense UI at `https://10.1.1.1` → Services → Unbound DNS → Host Overrides and look for a `mqtt` / `fleet1.cloud` entry; if found, remove it and apply Unbound config
- [x] T019 [US2] Verify `mqtt.fleet1.cloud` returns NXDOMAIN on internal DNS — run `dig mqtt.fleet1.cloud @10.1.1.1` from an internal host and confirm NXDOMAIN response (SC-004)

**Checkpoint**: `mqtt.fleet1.cloud` fully retired — NXDOMAIN on internal DNS, no Cloudflare record, no Unbound override. US2 complete.

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup stale references left over from the prior Helm-based Mosquitto deployment.

- [x] T020 [P] Remove stale `service: type: LoadBalancer` from `roles/mosquitto/templates/values.yaml.j2` — this template predates the raw-manifest approach and the LoadBalancer reference is no longer correct; change to `ClusterIP` or add a comment noting this template is for initial bootstrap reference only
- [ ] T021 Run final validation sequence from `quickstart.md` — execute all verification steps end-to-end and confirm all success criteria (SC-001 through SC-005) are met
- [x] T022 Create and merge PR — push branch to both remotes, create Gitea PR, merge, pull updated main, push to GitHub mirror, delete feature branch (follow CLAUDE.md git workflow)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 1)**: No dependencies — start immediately. T001–T006 are all parallel.
- **US1 (Phase 2)**: Depends on Phase 1 fully complete (T009 — cert Ready). T010–T012 can run in parallel after T009; T013 depends on T008; T014 depends on T013; T015 depends on T014.
- **US2 (Phase 3)**: Depends on US1 checkpoint (T015) — do NOT retire `.cloud` before `.lan` is verified.
- **Polish (Phase 4)**: Depends on US2 complete.

### Story Dependencies

- **US1 (P1)**: Depends only on Foundational phase — independently verifiable.
- **US2 (P2)**: Hard dependency on US1 verification (FR-004 in spec) — cannot run in parallel with US1.

### Parallel Opportunities

- T001–T006: All touch different files — fully parallel.
- T010–T012: All verification steps for the broker — parallel after T009.
- T013 (Frigate deploy) can begin once T008 (push to Gitea) is done, in parallel with T010–T012.

---

## Parallel Example: Phase 1

```bash
# Run all file edits in parallel (different files, no dependencies):
Task T001: Update manifests/home-automation/prereqs/certificates.yaml
Task T002: Update manifests/home-automation/prereqs/mosquitto-tcp-route.yaml
Task T003: Update roles/mosquitto/defaults/main.yml
Task T004: Update playbooks/network/network-deploy.yml (add DNAT rule)
Task T005: Update roles/nvr/defaults/main.yml (rename var)
Task T006: Update roles/nvr/templates/frigate-config.yml.j2

# Then sequentially:
T007: Run network-deploy.yml  (T004 done)
T008: git commit + push       (T001–T003, T005–T006 done)
T009: Wait for ArgoCD sync    (T008 done)
```

## Parallel Example: Phase 2 (US1 verification)

```bash
# After T009 (cert Ready):
Task T010: Verify cert SAN via kubectl
Task T011: Verify IngressRouteTCP via kubectl
Task T012: Test MQTT connection via mqtt.fleet1.lan:8883

# Independently (after T008):
Task T013: Run nvr-provision.yml → then T014: verify Frigate connected
```

---

## Implementation Strategy

### MVP (User Story 1 Only)

1. Complete Phase 1 (Foundational) — ~6 parallel file edits + 3 sequential apply steps
2. Complete Phase 2 (US1) — verification and Frigate deploy
3. **STOP and VALIDATE**: Confirm SC-001, SC-002, SC-003, SC-005 from spec
4. Ship — `mqtt.fleet1.lan` is live and stable

### Full Delivery

1. MVP above → US1 stable
2. Phase 3 (US2) — retire `mqtt.fleet1.cloud`
3. Phase 4 (Polish) — cleanup + PR merge
