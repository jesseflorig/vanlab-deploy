# Tasks: NVR Frigate + Hailo-8 Provisioning

**Input**: Design documents from `/specs/041-nvr-frigate-hailo/`  
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US5)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the directory skeleton and project-level config for the NVR feature. No functional changes yet.

- [x] T001 Create `playbooks/nvr/nvr-provision.yml` — top-level playbook with `hosts: nvr` and phase-tagged `include_role: name: nvr` calls for tags: `host-setup`, `hailo`, `frigate-config`, `nfs-mount`, `frigate-service`
- [x] T002 Create `roles/nvr/` directory structure: `defaults/`, `tasks/`, `templates/`, `handlers/`
- [x] T003 [P] Add `[nvr]` group to `hosts.ini` with entry `nvr-host ansible_host=10.1.10.11`
- [x] T004 [P] Add all `nvr_*` placeholder variables to `group_vars/example.all.yml` per the variable interface in `specs/041-nvr-frigate-hailo/contracts/operator-variables.md`
- [x] T005 [P] Add `ha-frigate-config.txt` to `.gitignore` at repo root

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Ansible role scaffolding and Kubernetes namespace/storage-class resources that every user story depends on. Must be complete before any story work begins.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T006 Create `roles/nvr/defaults/main.yml` with all `nvr_*` variable defaults (empty strings for secrets; `nvr_recording_retain_days: 7`, `nvr_clips_retain_days: 30`, `nvr_cameras: []`)
- [x] T007 Create `roles/nvr/handlers/main.yml` with three handlers: `reload-udev` (`udevadm control --reload-rules && udevadm trigger`), `systemd-daemon-reload` (`systemctl daemon-reload`), `restart-frigate` (`systemctl restart frigate`)
- [x] T008 Create `roles/nvr/tasks/main.yml` — tag-based `include_tasks` routing: tag `host-setup` → `host-setup.yml`, tag `hailo` → `hailo.yml`, tag `frigate-config` → `frigate-config.yml`, tag `nfs-mount` → `nfs-mount.yml`, tag `frigate-service` → `frigate-service.yml`
- [x] T009 [P] Create `manifests/frigate/prereqs/namespace.yaml` — Namespace `frigate`, annotated with `argocd.argoproj.io/sync-wave: "0"`
- [x] T010 [P] Create `manifests/frigate/prereqs/storageclass.yaml` — StorageClass `longhorn-rwx`, provisioner `driver.longhorn.io`, `allowVolumeExpansion: true`, parameters: `numberOfReplicas: "2"`, `fsType: "ext4"`, `nfsOptions: "vers=4.1,noresvport"`, sync-wave: `"1"`
- [x] T011 Register frigate ArgoCD Application in `group_vars/all.yml` under `argocd_apps`: `name: frigate`, `namespace: frigate`, `path: manifests/frigate`, `prune: true`, `selfHeal: true`, `retry_limit: 5`, `repoURL: https://gitea.fleet1.cloud/gitadmin/vanlab`
- [x] T012 Add OPNsense firewall rules in the existing OPNsense Ansible role (or `playbooks/network/opnsense-rules.yml`): rule 1: source `10.1.10.11` → dest `10.1.20.0/24` port `8883` proto `tcp` (Frigate → MQTT broker); rule 2: source `10.1.20.0/24` → dest `10.1.10.11` port `5000` proto `tcp` (Traefik → Frigate web UI)

**Checkpoint**: Role skeleton exists, K8s namespace and StorageClass manifests are ready, ArgoCD app is registered, firewall rules are staged

---

## Phase 3: User Story 1 - Provision a Secure, Functional NVR Host (Priority: P1) 🎯 MVP

**Goal**: NVR host is hardened, Hailo-8 driver is installed and verified, Frigate is fully configured and ready to start (service start happens in US3 after NFS mount is available)

**Independent Test**: Run `ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml --tags host-setup,hailo,frigate-config`; then verify `hailortcli fw-control identify` reports Hailo-8 and `/dev/hailo0` exists; verify `/var/lib/frigate/config/config.yml` is rendered with `type: hailo8`

**⚠️ Note**: US1 tests fully pass only after US3 (NFS mount + service start) — the service unit declares `Requires=mnt-frigate-clips.mount`

### Implementation for User Story 1

- [x] T013 [US1] Create `roles/nvr/tasks/host-setup.yml` — install Docker CE (official Docker APT repo, idempotent); disable and mask unnecessary services (`snapd`, `avahi-daemon` if present); configure `/etc/ssh/sshd_config`: disable root login, disable password auth, allow only key-based; install and configure `ufw`: default deny incoming, allow SSH (22) and Frigate web (5000); ensure `docker` group exists and Ansible remote user is a member
- [x] T014 [P] [US1] Create `roles/nvr/tasks/hailo.yml` — add Raspberry Pi APT signing key; add RPi APT source list entry; `apt update`; install `hailo-all` and `linux-headers-{{ ansible_kernel }}`; template `51-hailo-udev.rules.j2` to `/etc/udev/rules.d/51-hailo-udev.rules`; notify `reload-udev` handler; assert `stat /dev/hailo0` exists with `fail_msg: "Hailo-8 device node /dev/hailo0 not found — check driver install and reboot if needed"`; add verification task: `command: hailortcli fw-control identify` with `changed_when: false`
- [x] T015 [P] [US1] Create `roles/nvr/templates/51-hailo-udev.rules.j2` — udev rule: `SUBSYSTEM=="misc", DEVPATH=="*hailo*", MODE="0660", GROUP="docker"` (grants Docker containers access to `/dev/hailo0` via the docker group)
- [x] T016 [US1] Create `roles/nvr/tasks/frigate-config.yml` — create dirs `/var/lib/frigate/config/certs`, `/var/lib/frigate/config/model_cache`, `/var/lib/frigate/media`; template MQTT CA cert to `/var/lib/frigate/config/certs/ca.crt` (mode 0644); template MQTT client cert to `/var/lib/frigate/config/certs/frigate-client.crt` (mode 0644); template MQTT client key to `/var/lib/frigate/config/certs/frigate-client.key` (mode 0600, owner root); template `frigate-config.yml.j2` to `/var/lib/frigate/config/config.yml` (notify `restart-frigate` on change); template `ha-frigate-config.txt.j2` to `{{ playbook_dir }}/../ha-frigate-config.txt` (local write, `delegate_to: localhost`)
- [x] T017 [US1] Create `roles/nvr/templates/frigate-config.yml.j2` — complete Frigate config: `detectors.hailo8.type: hailo8`, `detectors.hailo8.device: PCIe`; `model` block (yolov8s.hef path, nhwc/rgb, yolo-generic, 640×640); `mqtt` block (host: `{{ nvr_mqtt_broker_ip }}`, port: 8883, tls certs paths, topic_prefix: frigate, client_id: frigate-nvr); `record` block (enabled: true, retain: `{{ nvr_recording_retain_days }}` days, mode: motion, events retain: `{{ nvr_clips_retain_days }}` days); `cameras` Jinja2 loop over `{{ nvr_cameras }}`; `media` paths pointing to `/media/frigate/recordings` and `/media/frigate/clips`
- [x] T018 [P] [US1] Create `roles/nvr/templates/frigate.service.j2` — systemd unit: `[Unit] After=docker.service network-online.target mnt-frigate-clips.mount; Requires=docker.service mnt-frigate-clips.mount`; `[Service] Restart=always; RestartSec=10`; `ExecStartPre=-/usr/bin/docker stop frigate; ExecStartPre=-/usr/bin/docker rm frigate`; `ExecStart=/usr/bin/docker run --name frigate --privileged --shm-size=256m -p 5000:5000 -p 8554:8554 --device /dev/hailo0:/dev/hailo0 -v /var/lib/frigate/config:/config -v /var/lib/frigate/media:/media/frigate -v /mnt/frigate-clips:/media/frigate/clips ghcr.io/blakeblackshear/frigate:stable`; `[Install] WantedBy=multi-user.target`

**Checkpoint**: Host is hardened; Hailo-8 driver is installed; `/dev/hailo0` exists; Frigate config is rendered; service unit template is ready (service not yet running — awaits US3)

---

## Phase 4: User Story 2 - Authenticated Access via Traefik (Priority: P2)

**Goal**: `frigate.fleet1.cloud` routes via cluster Traefik ingress to the NVR host with TLS termination; unauthenticated requests are rejected by Frigate

**Independent Test**: After ArgoCD syncs these manifests, `curl -I https://frigate.fleet1.cloud` returns a valid TLS response; unauthenticated `curl https://frigate.fleet1.cloud/api/stats` returns 401

### Implementation for User Story 2

- [x] T019 [US2] Create `manifests/frigate/prereqs/certificate.yaml` — cert-manager `Certificate`: `name: frigate-tls`, `namespace: frigate`, `secretName: wildcard-fleet1-cloud-tls`, `issuerRef.name: letsencrypt-dns`, `issuerRef.kind: ClusterIssuer`, `dnsNames: [frigate.fleet1.cloud]`; sync-wave `"2"`
- [x] T020 [P] [US2] Create `manifests/frigate/service.yaml` — `Service` named `frigate` in `frigate` namespace, `spec.type: ClusterIP`, port `name: http, port: 5000, targetPort: 5000` (no selector — traffic routed via Endpoints resource)
- [x] T021 [P] [US2] Create `manifests/frigate/endpoints.yaml` — `Endpoints` named `frigate` in `frigate` namespace, `subsets[0].addresses[0].ip: 10.1.10.11`, `subsets[0].ports[0].name: http, port: 5000`
- [x] T022 [US2] Create `manifests/frigate/ingressroute.yaml` — Traefik `IngressRoute`: `name: frigate`, `namespace: frigate`, `entryPoints: [websecure]`, route `match: Host("frigate.fleet1.cloud")`, service `name: frigate, port: 5000`, `tls.secretName: wildcard-fleet1-cloud-tls`
- [x] T023 [P] [US2] Create `manifests/frigate/prereqs/sealed-secrets.yaml` — placeholder `SealedSecret` resource (empty, namespace `frigate`); sync-wave `"3"`; required by project convention for all namespaces with potential future secrets

**Checkpoint**: Committing and pushing these manifests + ArgoCD sync makes `frigate.fleet1.cloud` resolve and route through Traefik with TLS (Frigate does not need to be running yet for the IngressRoute to exist)

---

## Phase 5: User Story 3 - Event Clips on Longhorn (Priority: P3)

**Goal**: 50Gi Longhorn RWX PVC is created, NFS-mounted on the NVR host, and Frigate service is started with `/mnt/frigate-clips` as the clips path; clips written to Longhorn, not local NVMe

**Independent Test**: Run `ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml --tags nfs-mount,frigate-service`; verify `systemctl is-active mnt-frigate-clips.mount` and `systemctl is-active frigate`; verify `docker logs frigate 2>&1 | grep -i hailo` shows Hailo-8 as detector; trigger detection event and verify clip appears under `/mnt/frigate-clips`

**⚠️ Prerequisite**: `nvr_longhorn_nfs_ip` and `nvr_longhorn_nfs_path` must be set in `group_vars/all.yml` before running Phase B. See `specs/041-nvr-frigate-hailo/quickstart.md` Step 4 for how to obtain these values after ArgoCD syncs the PVC.

### Implementation for User Story 3

- [x] T024 [US3] Create `manifests/frigate/pvc.yaml` — `PersistentVolumeClaim`: `name: frigate-clips`, `namespace: frigate`, `annotations: {longhorn.external.share: "true"}`, `accessModes: [ReadWriteMany]`, `storageClassName: longhorn-rwx`, `resources.requests.storage: 50Gi`
- [x] T025 [US3] Create `roles/nvr/tasks/nfs-mount.yml` — assert `nvr_longhorn_nfs_ip != ""` (fail with message: "nvr_longhorn_nfs_ip is not set — run ArgoCD sync first and obtain Longhorn NFS endpoint per quickstart.md Step 4"); assert `nvr_longhorn_nfs_path != ""`; create directory `/mnt/frigate-clips` (mode 0755); template `frigate-clips.mount.j2` to `/etc/systemd/system/mnt-frigate-clips.mount`; notify `systemd-daemon-reload` handler; enable and start `mnt-frigate-clips.mount`; verify mountpoint: `ansible.builtin.command: mountpoint -q /mnt/frigate-clips` with `changed_when: false`, `failed_when: result.rc != 0`
- [x] T026 [P] [US3] Create `roles/nvr/templates/frigate-clips.mount.j2` — systemd mount unit: `[Unit] Description=Longhorn NFS Clips Volume; After=network-online.target`; `[Mount] What={{ nvr_longhorn_nfs_ip }}:{{ nvr_longhorn_nfs_path }}; Where=/mnt/frigate-clips; Type=nfs; Options=vers=4.1,noresvport,_netdev`; `[Install] WantedBy=multi-user.target`
- [x] T027 [US3] Create `roles/nvr/tasks/frigate-service.yml` — template `frigate.service.j2` to `/etc/systemd/system/frigate.service`; notify `systemd-daemon-reload` handler; flush handlers (`meta: flush_handlers`); enable and start `frigate` service; wait for port 5000 to be listening: `ansible.builtin.wait_for: host: 127.0.0.1, port: 5000, timeout: 60`; verify Hailo device is active: `ansible.builtin.command: docker exec frigate hailortcli fw-control identify` with `changed_when: false`

**Checkpoint**: Full US1 + US3 stack is now testable end-to-end — Frigate is running, Hailo-8 is the active detector, `/mnt/frigate-clips` is mounted from Longhorn

---

## Phase 6: User Story 4 - Home Assistant Integration (Priority: P4)

**Goal**: Ansible outputs `ha-frigate-config.txt` containing the HA Frigate integration YAML block ready for operator to apply to Home Assistant

**Independent Test**: After running the full playbook, `cat ha-frigate-config.txt` at repo root contains valid HA integration YAML with the correct MQTT broker IP, topic prefix, and camera names; applying it to HA produces Frigate camera entities in the HA device list

### Implementation for User Story 4

- [x] T028 [P] [US4] Create `roles/nvr/templates/ha-frigate-config.txt.j2` — renders a ready-to-apply Home Assistant Frigate integration config block: MQTT broker host/port, topic_prefix `frigate`, camera entry for each item in `nvr_cameras` with name, snapshot URL (`http://10.1.10.11:5000/api/{{ cam.name }}/latest.jpg`), and stream URL; include operator instructions at top of file explaining how to add to HA `configuration.yaml` or via the Frigate integration in the HA UI
- [x] T029 [US4] Update `roles/nvr/tasks/frigate-config.yml` to add a task that templates `ha-frigate-config.txt.j2` to `{{ playbook_dir }}/../ha-frigate-config.txt` using `delegate_to: localhost`; add a debug message task: `ansible.builtin.debug: msg: "HA integration config written to ha-frigate-config.txt — apply this to Home Assistant per quickstart.md Step 7"`

**Checkpoint**: After running the playbook, `ha-frigate-config.txt` exists at repo root with all camera entries and is ready for operator to apply to HA

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Idempotency verification, documentation, and final repo hygiene

- [x] T030 Verify full playbook idempotency: run `ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml` twice against the provisioned host; confirm second run reports `changed=0` on all tasks; fix any non-idempotent tasks found
- [x] T031 [P] Add NVR provisioning section to `README.md`: document two-phase run requirement, pointer to `specs/041-nvr-frigate-hailo/quickstart.md`, and listing as a known manual step (per Principle III)
- [x] T032 [P] Push feature branch to both remotes and open PR per CLAUDE.md git workflow: `git push gitea 041-nvr-frigate-hailo && git push origin 041-nvr-frigate-hailo`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Foundational — NVR host is configured but service not yet started
- **US2 (Phase 4)**: Depends on Foundational only — Kubernetes manifests, independent of US1 host work
- **US3 (Phase 5)**: Depends on US1 (service template created) AND requires ArgoCD to sync the PVC (from US2/Phase 4 manifests push)
- **US4 (Phase 6)**: Depends on US1 (`frigate-config.yml` task file must exist)
- **Polish (Phase 7)**: Depends on US1–US4 complete

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational only — independently executable (host-setup, hailo, frigate-config tags)
- **US2 (P2)**: Depends on Foundational only — all Kubernetes manifests, no host dependency
- **US3 (P3)**: Depends on US1 (service template) AND US2 manifests being merged + ArgoCD synced (for PVC creation and NFS endpoint discovery)
- **US4 (P4)**: Depends on US1 (frigate-config.yml task file must exist to add the render task)

### Within Each Phase

- Templates before tasks that use them (within same story)
- `nfs-mount` task before `frigate-service` task (US3)
- ArgoCD sync of manifests/frigate/ before Phase B Ansible run

### Parallel Opportunities

- T003, T004, T005 can run in parallel (Phase 1)
- T009, T010 can run in parallel (Foundational — different files)
- T014, T015 can run in parallel (US1 Hailo tasks)
- T018, T019 (Phase 3) can run in parallel
- T020, T021 can run in parallel (US2 Service + Endpoints)
- T023 can run in parallel with T019, T020, T021 (US2)
- T026 can run in parallel with T024, T025 (US3 template vs. task files)
- T028 can run in parallel with other US4 work
- US1 host work (Phase 3) and US2 cluster work (Phase 4) can proceed in parallel after Foundational

---

## Parallel Example: US1 (Host Setup)

```bash
# These can run in parallel (different files):
Task T014: Create roles/nvr/tasks/hailo.yml
Task T015: Create roles/nvr/templates/51-hailo-udev.rules.j2
Task T018: Create roles/nvr/templates/frigate.service.j2

# These must run sequentially:
T013 host-setup.yml → T016 frigate-config.yml → T017 frigate-config.yml.j2 template
```

## Parallel Example: US2 + US1 (Concurrent Work)

```bash
# US1 host work and US2 cluster manifests are fully independent after Foundational:
Developer A: T013 → T014+T015 → T016 → T017 → T018  (US1 host work)
Developer B: T019 → T020+T021 → T022 → T023           (US2 cluster manifests)
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: US1 (host-setup, hailo, frigate-config templates)
4. Complete Phase 5: US3 (PVC + NFS + service start) — required to actually run Frigate
5. **STOP and VALIDATE**: Frigate running, Hailo-8 active, clips going to Longhorn NFS

### Incremental Delivery

1. Phase 1 + 2 → scaffolding ready
2. Phase 3 (US1) + Phase 5 (US3) → Frigate running with Hailo-8 + Longhorn clips ← **first demo milestone**
3. Phase 4 (US2) → `frigate.fleet1.cloud` accessible via Traefik ← **secure access milestone**
4. Phase 6 (US4) → HA integration config output ← **HA integration milestone**
5. Phase 7 → idempotency verified, docs updated ← **done**

---

## Notes

- [P] tasks operate on different files with no incomplete-task dependencies
- US1 service start is gated by US3 NFS mount — this is by design (systemd `Requires=`)
- The two-phase playbook run is the operator-facing manifestation of the US1→US3 dependency
- Verify `changed=0` on second playbook run before marking T030 complete
- `ha-frigate-config.txt` is gitignored and must be re-generated after any camera change
