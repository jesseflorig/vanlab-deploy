# Feature Spec: NVMe Migration for Longhorn Storage

**Branch**: `037-nvme-migration` | **Date**: 2026-04-04

## Overview

Longhorn is currently backed by `/var/lib/longhorn` on each node's eMMC SD card (58GB).
Each node has a 1.7TB NVMe drive (`nvme0n1`) that is unmounted and unused.
This feature prepares the NVMe drives, migrates all Longhorn replica data off the eMMC,
and removes the eMMC disk from Longhorn scheduling.

## User Stories

### P1 — NVMe Preparation
As a cluster operator, I want every node's NVMe drive (`nvme0n1`) formatted and persistently
mounted at `/mnt/nvme` so that Longhorn can use it as a storage backend.

**Acceptance criteria**:
- `nvme0n1` partitioned with a single ext4 partition on every cluster node (nodes 1–6)
- Partition mounted at `/mnt/nvme` and persisted in `/etc/fstab` via UUID (not device name)
- Ansible task is idempotent: re-running does not re-format an already-formatted drive
- Node5 is unreachable via SSH — task must succeed on nodes 1–4, 6 and gracefully skip node5

### P2 — Longhorn Disk Registration
As a cluster operator, I want Longhorn to recognise `/mnt/nvme` as an additional disk on each
node so that new volume replicas are placed on NVMe storage.

**Acceptance criteria**:
- `/mnt/nvme` added to each Longhorn node's disk list with `allowScheduling: true`
- Existing eMMC disk (`/var/lib/longhorn`) set to `allowScheduling: false` (no new replicas)
- Both disks remain present during migration (no data loss)

### P3 — Replica Migration
As a cluster operator, I want all existing Longhorn volume replicas moved from the eMMC disk
to the NVMe disk so that persistent data lives on fast, high-capacity storage.

**Acceptance criteria**:
- All PVC replicas report healthy status on NVMe disks after migration
- No PVC enters a degraded state that does not self-heal
- Migration is observable (progress can be checked with `kubectl` or Longhorn UI)

### P4 — eMMC Disk Removal
As a cluster operator, I want the eMMC disk entry removed from Longhorn once all replicas
have migrated, so that Longhorn no longer attempts to use SD card storage.

**Acceptance criteria**:
- eMMC disk entry removed from every Longhorn node CRD
- Longhorn reports 0 replicas on eMMC paths after removal
- `/var/lib/longhorn` on the eMMC continues to exist but is no longer a Longhorn disk
