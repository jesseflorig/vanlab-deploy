# Tasks: NVMe Migration for Longhorn Storage

**Input**: Design documents from `/specs/037-nvme-migration/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓

**Organization**: Tasks are grouped by user story. US1→US2→US3→US4 are strictly sequential — each depends on the prior story's completion.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to

---

## Phase 1: Setup

**Purpose**: Create the role skeleton and playbook file.

- [ ] T001 Create directory structure: `roles/nvme-prep/defaults/`, `roles/nvme-prep/tasks/`, `roles/nvme-prep/handlers/`
- [ ] T002 [P] Create `roles/nvme-prep/defaults/main.yml` with vars: `nvme_device: /dev/nvme0n1`, `nvme_partition: /dev/nvme0n1p1`, `nvme_mount_path: /mnt/nvme`, `nvme_label: longhorn-nvme`, `nvme_mount_opts: "defaults,noatime,nodiratime,nofail,x-systemd.device-timeout=30s"`, `nvme_longhorn_reserved_bytes: 53687091200`
- [ ] T003 [P] Create `roles/nvme-prep/handlers/main.yml` with a `Reboot node` handler using `ansible.builtin.reboot` (`reboot_timeout: 300`, `post_reboot_delay: 30`)
- [ ] T004 Create `playbooks/utilities/nvme-migrate.yml` with file header comment explaining purpose, prerequisites, and usage (`ansible-playbook -i hosts.ini playbooks/utilities/nvme-migrate.yml`)

---

## Phase 2: Foundational

**Purpose**: `roles/nvme-prep/tasks/main.yml` core task file — shared by all nodes, must be complete before Play 1 can run.

**⚠️ CRITICAL**: US1 cannot begin until this phase is complete.

- [ ] T005 Create `roles/nvme-prep/tasks/main.yml` — add package install task: `ansible.builtin.apt` installing `e2fsprogs` and `parted` (`state: present`, `update_cache: false`)
- [ ] T006 Add mount point creation task to `roles/nvme-prep/tasks/main.yml`: `ansible.builtin.file` ensuring `{{ nvme_mount_path }}` exists (`state: directory`, `mode: "0755"`)
- [ ] T007 Add idempotency probe to `roles/nvme-prep/tasks/main.yml`: `ansible.builtin.command: blkid -o value -s UUID {{ nvme_partition }}` registered as `nvme_part_uuid` (`changed_when: false`, `failed_when: false`)

**Checkpoint**: Role skeleton complete — US1 implementation tasks can now begin.

---

## Phase 3: User Story 1 — NVMe Preparation (Priority: P1) 🎯 MVP

**Goal**: All 6 nodes have `nvme0n1p1` formatted ext4, mounted at `/mnt/nvme`, persisted in fstab, with PCIe ASPM disabled.

**Independent Test**: SSH to any node and run `df -h /mnt/nvme` — must show ~1.7T filesystem on `/dev/nvme0n1p1`. Run `grep nvme /etc/fstab` — must show UUID-based entry. Run `grep pcie_aspm /boot/firmware/cmdline.txt` — must show `pcie_aspm=off`.

- [ ] T008 [US1] Add partitioning tasks to `roles/nvme-prep/tasks/main.yml`: `community.general.parted` creating GPT label on `{{ nvme_device }}` then partition 1 spanning `0%`–`100%` — both gated on `when: nvme_part_uuid.stdout == ""`
- [ ] T009 [US1] Add format task to `roles/nvme-prep/tasks/main.yml`: `community.general.filesystem` with `fstype: ext4`, `dev: {{ nvme_partition }}`, `force: false`, `opts: "-L {{ nvme_label }}"` — gated on `when: nvme_part_uuid.stdout == ""`
- [ ] T010 [US1] Add post-format UUID probe to `roles/nvme-prep/tasks/main.yml`: `ansible.builtin.command: blkid -o value -s UUID {{ nvme_partition }}` registered as `nvme_uuid_final` (`changed_when: false`, `failed_when: nvme_uuid_final.stdout == ""`)
- [ ] T011 [US1] Add fstab/mount task to `roles/nvme-prep/tasks/main.yml`: `ansible.posix.mount` with `path: {{ nvme_mount_path }}`, `src: "UUID={{ nvme_uuid_final.stdout | trim }}"`, `fstype: ext4`, `opts: {{ nvme_mount_opts }}`, `state: mounted`, `dump: "0"`, `passno: "2"`
- [ ] T012 [US1] Add PCIe ASPM disable task to `roles/nvme-prep/tasks/main.yml`: `ansible.builtin.lineinfile` on `/boot/firmware/cmdline.txt` using `backrefs: true`, `regexp: '^((?!.*pcie_aspm=off).*)$'`, `line: '\1 pcie_aspm=off'` — notify `Reboot node` handler
- [ ] T013 [US1] Add Play 1 to `playbooks/utilities/nvme-migrate.yml`: `hosts: cluster`, `become: true`, includes `nvme-prep` role; add a pre-task that asserts `nvme0n1` exists (`lsblk /dev/nvme0n1`) with `fail_msg` directing to check hardware

**Checkpoint**: Run `ansible-playbook -i hosts.ini playbooks/utilities/nvme-migrate.yml --tags nvme-prep` (or limit to Play 1) on one node. Verify `/mnt/nvme` is mounted and fstab entry exists. Node reboots if first run.

---

## Phase 4: User Story 2 — Longhorn Disk Registration (Priority: P2)

**Goal**: Longhorn knows about `/mnt/nvme` on each node as a schedulable disk; eMMC stops accepting new replicas.

**Independent Test**: `kubectl get nodes.longhorn.io -n longhorn-system -o json | jq '.items[].spec.disks'` — each node must have an `nvme-disk` entry with `allowScheduling: true` and the `default-disk-*` entry with `allowScheduling: false`.

**Depends on**: US1 complete (all nodes must have `/mnt/nvme` mounted before Longhorn can validate the path).

- [ ] T014 [US2] Add Play 2 to `playbooks/utilities/nvme-migrate.yml`: `hosts: servers[0]`, `become: true` — loop over `groups['cluster']`, `kubectl patch nodes.longhorn.io <node> -n longhorn-system --type merge` adding `nvme-disk` entry with `path: /mnt/nvme`, `allowScheduling: true`, `evictionRequested: false`, `storageReserved: {{ nvme_longhorn_reserved_bytes }}`, `diskType: filesystem`, `tags: []`
- [ ] T015 [US2] Add wait-for-schedulable task in Play 2: for each node, poll `kubectl get nodes.longhorn.io <node> -n longhorn-system -o json | jq '.status.diskStatus["nvme-disk"].conditions[] | select(.type=="Schedulable") | .status'` until value is `"True"` — `retries: 20`, `delay: 15`
- [ ] T016 [US2] Add eMMC scheduling-disable task in Play 2: for each node, discover the eMMC disk key with `kubectl get nodes.longhorn.io <node> -n longhorn-system -o json | jq -r '.spec.disks | keys[] | select(startswith("default-disk"))'`, then `kubectl patch --type merge` setting `allowScheduling: false` on that key; register key as `emmc_disk_key` for use in later plays

**Checkpoint**: Verify in Longhorn UI or via `kubectl get nodes.longhorn.io` that each node shows both disks, `nvme-disk` schedulable, `default-disk-*` not schedulable. New PVC test should land on NVMe.

---

## Phase 5: User Story 3 — Replica Migration (Priority: P3)

**Goal**: All existing volume replicas moved from eMMC to NVMe; no volume enters a permanently degraded state.

**Independent Test**: For each node, `kubectl get nodes.longhorn.io <node> -n longhorn-system -o json | jq '.status.diskStatus["<emmc-key>"].scheduledReplica | length'` returns `0`.

**Depends on**: US2 complete (NVMe disk must be schedulable before eviction can find a target).

- [ ] T017 [US3] Add Play 3 to `playbooks/utilities/nvme-migrate.yml`: `hosts: servers[0]`, `become: true` — for each node, re-discover eMMC disk key (same `jq` query as T016), then `kubectl patch nodes.longhorn.io <node> -n longhorn-system --type merge` setting `allowScheduling: false` and `evictionRequested: true` on the eMMC key
- [ ] T018 [US3] Add eviction polling loop in Play 3: after patching each node, poll `kubectl get nodes.longhorn.io <node> -n longhorn-system -o json | jq '.status.diskStatus["<emmc-key>"].scheduledReplica | length'` every 30 seconds — `retries: 60` (30 minutes total), `delay: 30`; fail with a clear message if timeout is reached; process nodes sequentially (one at a time) to maintain replica availability

**Checkpoint**: All 6 nodes report `scheduledReplica | length == 0` on their eMMC disk key. Run `kubectl get volumes.longhorn.io -n longhorn-system` — all volumes should be `Healthy`.

---

## Phase 6: User Story 4 — eMMC Disk Removal (Priority: P4)

**Goal**: eMMC disk entries removed from all Longhorn node CRDs; `/var/lib/longhorn` on eMMC is no longer a Longhorn disk.

**Independent Test**: `kubectl get nodes.longhorn.io -n longhorn-system -o json | jq '.items[].spec.disks | keys'` — each node must show only `["nvme-disk"]` (no `default-disk-*` keys).

**Depends on**: US3 complete (`scheduledReplica` must be empty before removal).

- [ ] T019 [US4] Add Play 4 to `playbooks/utilities/nvme-migrate.yml`: `hosts: servers[0]`, `become: true` — for each node, assert `scheduledReplica | length == 0` on eMMC key (safety gate); fail with message "Replicas still present on eMMC — do not remove disk" if non-zero
- [ ] T020 [US4] Add disk removal task in Play 4: for each node that passed the safety gate, `kubectl patch nodes.longhorn.io <node> -n longhorn-system --type json -p '[{"op":"remove","path":"/spec/disks/<emmc-key>"}]'`; handle transient "spec and status of disks are being synced" error with `retries: 3`, `delay: 15`
- [ ] T021 [US4] Add verification task in Play 4: for each node, assert `kubectl get nodes.longhorn.io <node> -n longhorn-system -o json | jq '.spec.disks | keys | length'` equals `1` (only `nvme-disk` remains)

**Checkpoint**: Longhorn UI shows each node with a single disk (`nvme-disk`, ~1.7TB). eMMC data directory `/var/lib/longhorn` remains on disk but is no longer registered.

---

## Phase 7: Polish & Validation

**Purpose**: Verify the full migration end-to-end and ensure no regressions.

- [ ] T022 Add `tags` to each play in `playbooks/utilities/nvme-migrate.yml` (`nvme-prep`, `longhorn-register`, `longhorn-evict`, `longhorn-cleanup`) so individual phases can be re-run in isolation
- [ ] T023 Add Play 5 (eMMC data cleanup) to `playbooks/utilities/nvme-migrate.yml`: `hosts: cluster`, `become: true` — for each node, assert `/mnt/nvme/longhorn-disk.cfg` exists (confirms NVMe is active Longhorn disk), then remove `/var/lib/longhorn/replicas/` with `ansible.builtin.file: path=/var/lib/longhorn/replicas state=absent` and remove `/var/lib/longhorn/longhorn-disk.cfg` with `ansible.builtin.file: state=absent`; leave `/var/lib/longhorn/` directory intact
- [ ] T024 [P] Run `ansible-playbook -i hosts.ini playbooks/utilities/disk-health.yml` — all 6 nodes must show NVMe `PRESENT` and the new mount visible in the report
- [ ] T025 [P] Run `ansible-playbook -i hosts.ini playbooks/cluster/longhorn-smoke-test.yml` — PVC must be provisioned, data written, pod deleted and recreated, data verified persistent; confirms NVMe-backed Longhorn is fully functional
- [ ] T026 Verify Longhorn UI storage summary shows ~10TB usable (6 × 1.7TB ÷ 2 replicas) replacing the previous ~168GB from eMMC

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — T002, T003, T004 can start immediately; T001 must precede T002/T003
- **Foundational (Phase 2)**: Depends on T001 — T005→T006→T007 sequential (same file)
- **US1 (Phase 3)**: Depends on Foundational — T008→T009→T010→T011→T012 sequential (same file); T013 last
- **US2 (Phase 4)**: Depends on US1 complete on all 6 nodes (Longhorn validates disk path at registration)
- **US3 (Phase 5)**: Depends on US2 complete (`nvme-disk` must be `Schedulable: true`)
- **US4 (Phase 6)**: Depends on US3 complete (`scheduledReplica` must be empty)
- **Polish (Phase 7)**: T022 (tags) first, then T023 (eMMC cleanup) sequential, then T024 and T025 can run in parallel

### Within Each User Story

- `roles/nvme-prep/tasks/main.yml` tasks (T005–T012) are sequential — appended to the same file in order
- Play-level tasks in `nvme-migrate.yml` (T013, T014–T016, T017–T018, T019–T021) are sequential per play
- Node iteration within each play is sequential (one node at a time) to preserve replica availability during eviction

### Parallel Opportunities

- T002 and T003 (defaults + handlers) can be written in parallel — different files
- T004 (playbook stub) can be written in parallel with T002/T003
- T024 and T025 (validation smoke tests) can run in parallel after T023 (eMMC cleanup) completes

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1 + Phase 2 → role skeleton ready
2. Complete Phase 3 (US1) → all nodes have NVMe mounted
3. **STOP and VALIDATE**: SSH to each node, confirm `/mnt/nvme` is mounted, fstab persisted, ASPM disabled
4. Longhorn data still on eMMC — no risk yet

### Incremental Delivery

1. Setup + Foundational → role skeleton
2. US1 → NVMe mounted on all nodes ✓
3. US2 → Longhorn sees NVMe, eMMC stops accepting replicas ✓
4. US3 → Replicas migrate to NVMe (observe via Longhorn UI) ✓
5. US4 → eMMC removed from Longhorn ✓
6. Polish → smoke test confirms full functionality ✓

---

## Notes

- Nodes are processed **one at a time** during eviction (US3) — with 2-replica volumes, evicting one node at a time ensures the other replica remains available on a different node
- The eMMC disk key (`default-disk-<fsid>`) varies per node and must be discovered at runtime with `jq`
- The `Reboot node` handler in the `nvme-prep` role only fires when `cmdline.txt` is changed (first run); subsequent runs are fully idempotent with no reboot
- The playbook is designed to be re-runnable per phase using `--tags`; if a play partially completes, re-running is safe
- Node5 was previously cordoned but is now uncordoned and treated identically to all other nodes
- `nofail,x-systemd.device-timeout=30s` in fstab is mandatory — without it, a NVMe enumeration failure at boot drops the node into emergency mode; on server nodes (node1, node3, node5) this risks etcd quorum loss
- eMMC cleanup (T023) asserts `/mnt/nvme/longhorn-disk.cfg` exists before deleting eMMC replica data — this is the safety gate preventing accidental deletion if run out of order
