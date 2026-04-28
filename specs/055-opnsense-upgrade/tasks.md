# Tasks: OPNsense 23.7 → 26.1 Upgrade

**Input**: Design documents from `/specs/055-opnsense-upgrade/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (independent checks with no ordering dependency)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- This is a procedural upgrade — "file paths" refer to OPNsense UI paths or shell commands
- All hops are strictly sequential; no parallelism across hops

---

## Phase 1: Setup (Pre-Flight)

**Purpose**: Verify the cluster and router are in a known-good state before touching anything.
All failures here must be resolved before proceeding.

- [ ] T001 [P] Verify cluster health — run `kubectl get nodes` from management laptop; confirm all 6 nodes show `Ready`
- [ ] T001b [P] Verify OPNsense is reachable — confirm web UI loads at `https://10.1.1.1` and dashboard shows version `23.7.x`
- [ ] T001c [P] Verify existing Unbound overrides — run `dig mqtt.fleet1.cloud @10.1.1.1`; confirm it returns `10.1.20.x`; run `dig grafana.fleet1.lan @10.1.1.1`; confirm it returns `10.1.20.11` (verifies 054 Unbound task already applied)
- [ ] T001d [P] Verify management laptop SSH access to OPNsense — run `ssh root@10.1.1.1`; confirm login succeeds (fallback console if web UI becomes unavailable mid-upgrade)
- [ ] T001e [P] Note current firewall rule count — in OPNsense web UI go to Firewall → Rules and record total rule count per interface; used to verify no rules are lost post-upgrade

**Checkpoint**: All pre-flight checks pass before any backup or upgrade step begins

---

## Phase 2: Foundational (Initial Backup)

**Purpose**: Export the 23.7 configuration before any changes. This is the master rollback point.

- [ ] T002 Export OPNsense 23.7 config — in web UI: System → Configuration → Backups → Download; save file as `opnsense-23.7-pre.xml` on management laptop; confirm file is non-empty (>10KB)

**Checkpoint**: `opnsense-23.7-pre.xml` saved and verified before proceeding to any hop

---

## Phase 3: User Story 1 — Router Upgraded with All Services Restored (Priority: P1) 🎯 MVP

**Goal**: Execute all 5 sequential major-version hops from 23.7 to 26.1. Each hop follows the
same pattern: backup → upgrade → reboot → verify. No hop begins until the previous one is verified.

**Independent Test**: `kubectl get nodes` shows all Ready; `dig mqtt.fleet1.cloud @10.1.1.1` returns correct IP; dashboard shows version 26.1.x.

### Hop 1: 23.7 → 24.1

- [ ] T003 [US1] Trigger 23.7 → 24.1 upgrade — SSH to `10.1.1.1`; at console menu press `12` (Major Upgrade); when prompted enter `24.1`; wait for download, apply, and automatic reboot (~15 min); router will be unreachable during reboot
- [ ] T004 [US1] Verify hop 1 (24.1) — confirm dashboard shows `24.1.x`; run `kubectl get nodes` (all Ready); run `dig mqtt.fleet1.cloud @10.1.1.1` (returns 10.1.20.x); **WireGuard focus**: verify WireGuard tunnel is up under VPN → WireGuard → Status (WireGuard moved to core in 24.1 — this is the primary risk for this hop)

### Hop 2: 24.1 → 24.7

- [ ] T005 [US1] Export 24.1 config backup — System → Configuration → Backups → Download; save as `opnsense-24.1-pre.xml` on management laptop
- [ ] T006 [US1] Trigger 24.1 → 24.7 upgrade — at console menu press `12`; enter `24.7`; wait for reboot
- [ ] T007 [US1] Verify hop 2 (24.7) — confirm dashboard shows `24.7.x`; run `kubectl get nodes` (all Ready); run `dig mqtt.fleet1.cloud @10.1.1.1`; check WireGuard status still active

### Hop 3: 24.7 → 25.1

- [ ] T008 [US1] Export 24.7 config backup — System → Configuration → Backups → Download; save as `opnsense-24.7-pre.xml` on management laptop
- [ ] T009 [US1] Trigger 24.7 → 25.1 upgrade — at console menu press `12`; enter `25.1`; wait for reboot
- [ ] T010 [US1] Verify hop 3 (25.1) — confirm dashboard shows `25.1.x`; run `kubectl get nodes` (all Ready); **DHCP focus**: check Services → DHCPv4 shows service running on configured VLANs (ISC-DHCP migrates to plugin in this range — no active leases at risk, but service must be running); run `dig mqtt.fleet1.cloud @10.1.1.1`

### Hop 4: 25.1 → 25.7

- [ ] T011 [US1] Export 25.1 config backup — System → Configuration → Backups → Download; save as `opnsense-25.1-pre.xml` on management laptop
- [ ] T012 [US1] Trigger 25.1 → 25.7 upgrade — at console menu press `12`; enter `25.7`; wait for reboot
- [ ] T013 [US1] Verify hop 4 (25.7) — confirm dashboard shows `25.7.x`; **Unbound focus**: run `dig mqtt.fleet1.cloud @10.1.1.1` (Unbound settings format changed in 25.7 — if this fails, go to Services → Unbound DNS → General and re-apply settings); run `dig grafana.fleet1.lan @10.1.1.1` (confirms fleet1.lan override still in place); run `kubectl get nodes`

### Hop 5: 25.7 → 26.1

- [ ] T014 [US1] Export 25.7 config backup — System → Configuration → Backups → Download; save as `opnsense-25.7-pre.xml` on management laptop
- [ ] T015 [US1] Trigger 25.7 → 26.1 upgrade — at console menu press `12`; enter `26.1`; wait for reboot
- [ ] T016 [US1] Verify hop 5 (26.1) — confirm dashboard shows `26.1.x`; run `kubectl get nodes` (all Ready); run `dig mqtt.fleet1.cloud @10.1.1.1` and `dig grafana.fleet1.lan @10.1.1.1` (both must resolve correctly); check Firewall → Rules and confirm rule count matches pre-upgrade count noted in T001e; **NAT focus**: check that Firewall → NAT section now shows "Destination NAT" (renamed from Port Forward) and any existing rules migrated

**Checkpoint**: Dashboard shows 26.1.x; all cluster nodes Ready; all DNS overrides resolving; firewall rule count unchanged

---

## Phase 4: User Story 2 — Destination NAT API Available and Verified (Priority: P2)

**Goal**: Confirm the `/api/firewall/dnat/` endpoint is live and the existing API credentials authenticate successfully.

**Independent Test**: `POST /api/firewall/dnat/searchRule` returns a JSON object with `rows` key (not a 400 "controller not found" error).

- [ ] T017 [US2] Test Destination NAT API availability — run the following from management laptop and confirm response contains `rows` key:
  ```
  curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
    "https://10.1.1.1/api/firewall/dnat/searchRule" \
    -X POST -H "Content-Type: application/json" -d '{}' | python3 -m json.tool
  ```
  (Credentials are in `group_vars/all.yml`)
- [ ] T018 [US2] Verify API user has Destination NAT privilege — if T017 returns `403 Forbidden` (not 400): go to System → Access → Users → find the API user → edit privileges → add `Firewall: Rules` or equivalent dnat ACL group; re-test T017 until it returns 200

**Checkpoint**: T017 returns a valid JSON response with `rows` key; T018 is only needed if T017 returns 403

---

## Phase 5: User Story 3 — Upgrade Documented (Priority: P3)

**Goal**: Record any deviations from the planned procedure that future operators need to know.

**Independent Test**: `specs/055-opnsense-upgrade/quickstart.md` reflects what actually happened — no surprises undocumented.

- [ ] T019 [US3] Update `specs/055-opnsense-upgrade/quickstart.md` — annotate any steps that differed from the procedure (e.g., if the console menu option number changed, if a hop required extra steps for DHCP or Unbound recovery, if the API user needed privilege changes); leave the document accurate for future reference

---

## Final Phase: Polish & Follow-On

**Purpose**: Close out the blocker in feature 054 and confirm end-to-end.

- [ ] T020 Switch to branch `054-fleet1-lan-wildcard` and implement T010 — now that 26.1 is confirmed, add Destination NAT rule tasks to `playbooks/network/network-deploy.yml` using the verified `POST /api/firewall/dnat/addRule` endpoint; create a rule for TCP `10.1.20.11:443 → 10.1.20.11:30443` with description `fleet1.lan HTTPS → Traefik NodePort`; guard with `searchRule` idempotency check; include `apply` call
- [ ] T021 Run `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml` on branch 054 — verify the NAT rule appears in Firewall → Destination NAT in the OPNsense web UI
- [ ] T022 End-to-end fleet1.lan validation — run `ansible-playbook -i hosts.ini playbooks/compute/ca-trust-deploy.yml` (if not already done); navigate to `https://grafana.fleet1.lan` in browser; confirm valid cert and page loads

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — all T001x checks run in parallel; all must pass
- **Foundational (Phase 2)**: Depends on Phase 1 complete
- **US1 Hops (Phase 3)**: Strictly sequential — each hop depends on the previous hop's verify task passing
- **US2 (Phase 4)**: Depends on hop 5 (T016) complete
- **US3 (Phase 5)**: Depends on US1 + US2 complete
- **Polish**: Depends on US2 API verification passing (T017)

### Within US1

All hops are strictly sequential. Within each verification task (T004, T007, T010, T013, T016), individual checks (dig, kubectl, browser) can run in parallel but must all pass before the next hop begins.

### Parallel Opportunities

**Phase 1 only** — all pre-flight checks run in parallel:
```
T001  kubectl get nodes
T001b OPNsense web UI version check
T001c dig mqtt.fleet1.cloud + dig grafana.fleet1.lan
T001d SSH to 10.1.1.1
T001e Record firewall rule counts
```

No other parallelism — every subsequent task is sequential by nature of the upgrade procedure.

---

## Implementation Strategy

### MVP: Get to 26.1 Running (US1 Only)

1. Phase 1: Pre-flight (all T001x in parallel)
2. Phase 2: T002 initial backup
3. Phase 3: Execute hops 1–5 sequentially, verifying after each
4. **STOP and validate**: Dashboard shows 26.1.x, cluster healthy, DNS resolving
5. Proceed to US2 (API check) only after US1 is solid

### Full Delivery

1. MVP (US1) → US2 (API verify) → T020–T022 (T010 unblocked in 054)

### Abort Criteria

Stop the upgrade and restore the most recent pre-hop backup if:
- A hop's reboot results in OPNsense not responding after 15 minutes
- Cluster nodes become unreachable after a hop and don't recover within 5 minutes
- Unbound DNS fails to resolve after hop 4 (25.7) and restart doesn't fix it
- Any pre-flight check (Phase 1) fails — resolve before starting

---

## Notes

- Credentials for API calls: `opnsense_api_key` and `opnsense_api_secret` in `group_vars/all.yml`
- T003/T006/T009/T012/T015 (upgrade triggers) are manual operations at the OPNsense console — they cannot be automated
- The console menu option `12` is the documented path for major upgrades; if unavailable in a given version, use System → Firmware → Settings in the web UI to switch release branch
- DHCP risk is low (no active leases), but service-running check is still required in T010
- WireGuard moved to core in 24.1 — if tunnel breaks post-24.1, check VPN → WireGuard → Instances and re-enable
- After completing T022, mark T010 as complete in `specs/054-fleet1-lan-wildcard/tasks.md`
