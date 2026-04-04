# Research: NVMe Migration for Longhorn Storage

**Feature**: 037-nvme-migration | **Date**: 2026-04-04

---

## 1. NVMe Partitioning and Formatting (Idempotent Ansible)

**Decision**: Use `community.general.parted` + `community.general.filesystem` with a `blkid` probe guard.

**Rationale**: `community.general.filesystem` with `force: false` will not reformat an existing filesystem. Pairing it with a `blkid -o value -s UUID /dev/nvme0n1p1` probe and a `when: nvme_part_uuid.stdout == ""` guard makes the idempotency contract explicit and avoids even querying the device when already formatted. This is essential for a destructive disk operation.

```yaml
- name: Probe nvme0n1p1 for existing filesystem
  ansible.builtin.command: blkid -o value -s UUID /dev/nvme0n1p1
  register: nvme_part_uuid
  changed_when: false
  failed_when: false

- name: Create GPT partition table on nvme0n1
  community.general.parted:
    device: /dev/nvme0n1
    label: gpt
    state: present
  when: nvme_part_uuid.stdout == ""

- name: Create single partition spanning full nvme0n1
  community.general.parted:
    device: /dev/nvme0n1
    number: 1
    state: present
    part_start: "0%"
    part_end: "100%"
  when: nvme_part_uuid.stdout == ""

- name: Format nvme0n1p1 as ext4
  community.general.filesystem:
    fstype: ext4
    dev: /dev/nvme0n1p1
    force: false
    opts: "-L longhorn-nvme"
  when: nvme_part_uuid.stdout == ""
```

**Alternatives considered**:
- `ansible.builtin.command: parted -s ...` — not idempotent without explicit guards; rejected.
- `fdisk` — interactive by design; rejected.

---

## 2. fstab Mount Entry

**Decision**: UUID-based fstab entry via `ansible.posix.mount` with `state: mounted`.

**Rationale**: Device names (`/dev/nvme0n1p1`) are not stable across reboots when multiple block devices are present. The spec mandates UUID-based fstab. `ansible.posix.mount` with `state: mounted` both mounts immediately and writes the fstab entry idempotently.

```yaml
- name: Get UUID of nvme0n1p1
  ansible.builtin.command: blkid -o value -s UUID /dev/nvme0n1p1
  register: nvme_uuid_final
  changed_when: false
  failed_when: nvme_uuid_final.stdout == ""

- name: Mount /mnt/nvme and persist in fstab
  ansible.posix.mount:
    path: /mnt/nvme
    src: "UUID={{ nvme_uuid_final.stdout | trim }}"
    fstype: ext4
    opts: "defaults,noatime,nodiratime"
    state: mounted
    dump: "0"
    passno: "2"
```

`noatime,nodiratime` reduce unnecessary writes. `passno: 2` enables fsck after root; never use `passno: 0` on ext4 volumes.

**Alternatives considered**: `PARTUUID`, `LABEL=` — both stable, but UUID is most universally supported and already mandated by spec.

---

## 3. RPi CM5 Kernel Modules for NVMe

**Decision**: No additional kernel modules or udev rules needed. Install `e2fsprogs` and `parted`.

**Rationale**: The `nvme` driver is built into the Raspberry Pi Bookworm kernel for arm64 and auto-loads via udev on device detection. `util-linux` (providing `blkid`, `lsblk`) is already installed by `longhorn-prereqs`. Add `e2fsprogs` (for `mkfs.ext4`) and `parted` explicitly.

```yaml
- name: Install NVMe prep packages
  ansible.builtin.apt:
    name:
      - e2fsprogs
      - parted
    state: present
    update_cache: false
```

**Alternatives considered**: Explicit `nvme` entry in `/etc/modules-load.d/` — unnecessary maintenance noise; rejected.

---

## 4. Filesystem: ext4 vs XFS

**Decision**: **ext4**.

**Rationale**:
- Longhorn documentation recommends ext4 as the primary filesystem for the data path.
- Better tested on arm64/RPi CM5 — XFS has occasional journal recovery issues after unclean shutdown on ARM platforms.
- `e2fsck`, `resize2fs`, `tune2fs` are universally available. XFS requires `xfsprogs`.
- The existing spec already specifies ext4.

**Alternatives considered**: XFS — marginally better large sequential throughput on x86_64; not well-validated on RPi CM5 in production; rejected.

---

## 5. RPi CM5 + M.2 HAT Known Issues

**Decision**: Disable PCIe ASPM in `/boot/firmware/cmdline.txt`. Leave PCIe Gen 3 opt-in disabled.

**Rationale**: `pcie_aspm` (Active State Power Management) is the most common cause of NVMe dropouts on CM5 — drives can enter a low-power state from which they fail to wake. This manifests as the device disappearing from `/dev/`. Disabling ASPM prevents this.

PCIe Gen 3 (`dtparam=pciex1_gen=3`) is optional and has reported link instability with some NVMe controllers. Gen 2 (~500 MB/s) is sufficient for Longhorn's random small-I/O workload pattern.

```yaml
- name: Disable PCIe ASPM for NVMe stability on CM5
  ansible.builtin.lineinfile:
    path: /boot/firmware/cmdline.txt
    backrefs: true
    regexp: '^((?!.*pcie_aspm=off).*)$'
    line: '\1 pcie_aspm=off'
  notify: Reboot node
```

**Alternatives considered**: `dtparam=pciex1_gen=3` for Gen 3 throughput — instability risk outweighs marginal benefit for this workload; rejected.

---

## 6. Longhorn Disk Management API (v1.11.x)

### Adding a new disk

**Decision**: `kubectl patch --type merge` on `nodes.longhorn.io`. The map key is chosen by the operator (e.g., `nvme-disk`); Longhorn writes `longhorn-disk.cfg` into the path to record `diskUUID` independently.

Required fields: `path`, `allowScheduling`, `evictionRequested`, `storageReserved`, `diskType`.

```bash
kubectl patch nodes.longhorn.io <node> -n longhorn-system --type merge -p '{
  "spec": {
    "disks": {
      "nvme-disk": {
        "path": "/mnt/nvme",
        "allowScheduling": true,
        "evictionRequested": false,
        "storageReserved": 53687091200,
        "diskType": "filesystem",
        "tags": []
      }
    }
  }
}'
```

`storageReserved` set to ~50Gi (≈5% of 1.7TB) — provides headroom above the 25% `storageMinimalAvailablePercentage` scheduling gate.

### Disabling scheduling on existing disk

```bash
kubectl patch nodes.longhorn.io <node> -n longhorn-system --type merge -p \
  '{"spec":{"disks":{"<OLD_KEY>":{"allowScheduling":false}}}}'
```

Decouples "stop new scheduling" from "evict now" — lets you verify the new disk is healthy before draining.

### Triggering eviction

```bash
kubectl patch nodes.longhorn.io <node> -n longhorn-system --type merge -p \
  '{"spec":{"disks":{"<OLD_KEY>":{"allowScheduling":false,"evictionRequested":true}}}}'
```

Longhorn's Replica Controller creates new replicas on schedulable disks, syncs data, then tears down old replicas. Works on both attached and detached volumes (Longhorn auto-attaches detached volumes for eviction).

### Monitoring progress

```bash
# Count replicas remaining on old disk — reaches 0 when done
kubectl get nodes.longhorn.io <node> -n longhorn-system -o json \
  | jq '.status.diskStatus["<OLD_KEY>"].scheduledReplica | length'
```

### Removing the disk

Only after `scheduledReplica` is empty:

```bash
kubectl patch nodes.longhorn.io <node> -n longhorn-system --type json \
  -p '[{"op":"remove","path":"/spec/disks/<OLD_KEY>"}]'
```

Must use JSON patch `remove` op — merge patch cannot delete a key.

---

## 7. Longhorn Disk Management Gotchas

| Gotcha | Impact | Mitigation |
|--------|--------|------------|
| Filesystem UUID deduplication | Longhorn rejects two disk entries pointing to the same filesystem | Use a distinct partition per disk entry; never bind-mount a subdir of an existing Longhorn disk |
| Disk key is permanent once replicas exist | Renaming a key orphans replicas | Choose the key name upfront; evict fully before removing |
| `storageReserved` defaults to 30% on auto-created disks | Manually-added disks default to 0 if not specified | Always set explicit `storageReserved` |
| Eviction requires a schedulable target | Eviction stalls if no healthy destination exists | Add new disk and wait for `Schedulable: true` before enabling eviction |
| "spec and status of disks are being synced" error | Transient reconciliation delay | Wait 10–30 seconds and retry |

---

## 8. Current Cluster State

- **Longhorn version**: v1.11.1, namespace `longhorn-system`
- **Default replica count**: 2 (set in both `persistence.defaultClassReplicaCount` and `defaultSettings.defaultReplicaCount`)
- **Current disk**: `/var/lib/longhorn` on `mmcblk0p2` (58GB eMMC) per node
- **NVMe**: `nvme0n1` (1.7TB), unmounted, present on nodes 1–6
- **Active PVCs**: mosquitto-data (1Gi), home-assistant (10Gi), influxdb (20Gi), node-red (5Gi) = 36Gi total, all 2-replica
- **Node5**: SSH restored; was cordoned (now uncordoned); same NVMe layout as other nodes
- **Reclaim policy**: `Retain` — PVs are not auto-deleted when PVCs are removed

**Disk key for the existing eMMC disk** must be read at runtime from `kubectl get nodes.longhorn.io <node> -n longhorn-system -o json | jq '.spec.disks | keys'` — it follows the pattern `default-disk-<fsid>` (e.g., `default-disk-ed7af10f5b8356be`) and varies per node.
