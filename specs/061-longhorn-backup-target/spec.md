# Feature Specification: Longhorn Backup Target (MinIO)

**Feature Branch**: `061-longhorn-backup-target`
**Created**: 2026-05-11
**Status**: Clarified — ready for `/speckit.plan`
**Input**: User description: "Wire Longhorn to MinIO as its off-cluster backup target; establish recurring snapshot + backup defaults on critical PVCs."

---

> ✅ **STATUS: READY FOR `/speckit.clarify`**
>
> Spec 060 (MinIO object storage) has been implemented and is ready for deployment (branch `060-minio-object-store` — merge before starting 061). The upstream contract is current: see `specs/060-minio-object-store/contracts/longhorn-backup-target.md`.
>
> Before invoking `/speckit.plan`, run `/speckit.clarify` and revalidate:
> - Are the "critical PVCs" listed below still the right set? (Authentik specs 063–065 are not yet deployed; exclude their PVCs until they exist.)
> - Is the recurring schedule (nightly snapshot, weekly backup) still appropriate given current data churn?
> - Confirm the `longhorn-minio-credentials-source` SealedSecret values from spec 060 are available in `group_vars/all.yml` before re-sealing for `longhorn-system`.

---

## Clarifications

### Session 2026-05-16

- Q: Should there be a periodic automated restore-test job? → A: Out of scope for v1 — document as a future spec (e.g., 062).
- Q: Uniform retention or tiered per PVC class? → A: Two tiers — full policy (7-day snapshot / 4-week backup) for data PVCs; lighter (3-day snapshot / 2-week backup) for monitoring stack PVCs.
- Q: Should Gitea get a higher-frequency backup (e.g., 6-hourly)? → A: No — standard Tier A nightly is sufficient; Gitea is already mirrored to GitHub on every merge.
- Q: Explicit PrometheusRules for backup/snapshot failures, or rely on kube-prometheus-stack defaults? → A: Explicit PrometheusRule resources defined in this spec — default bundle does not cover backup job failures.

## Captured Design Summary

**Purpose**: Configure Longhorn to use the MinIO bucket from spec 060 as its `BackupTarget`, and apply default `RecurringJob` policies to existing critical PVCs across the cluster.

**Dependencies**:
- **Hard**: Spec 060 (MinIO) must be deployed first — the backup bucket and S3 credentials must exist.
- **Soft**: None. This can land independently of any SSO work.

**Scope**:
1. Configure Longhorn `BackupTarget` resource pointing at MinIO S3 endpoint + Sealed Secret credentials.
2. Define two-tier `RecurringJob` CRDs:
   - **Tier A (data PVCs)**: Nightly snapshot (kept 7 days) + weekly backup to MinIO (kept 4 weeks). Applies to: Gitea, Loki, Home Automation stack, Frigate clips.
   - **Tier B (monitoring PVCs)**: Nightly snapshot (kept 3 days) + weekly backup to MinIO (kept 2 weeks). Applies to: Prometheus, Grafana, Alertmanager.
3. Apply via labels (`recurring-job.longhorn.io/...`) to critical PVCs.

**Critical PVCs identified as of 2026-05-11** (re-verify when planning):
- Gitea data PVC (source of truth for GitOps).
- Loki PVC (log retention, spec 014).
- Home automation stack PVCs (Mosquitto, Home Assistant, Node-RED, InfluxDB — spec 016).
- Monitoring stack PVCs (Prometheus 20Gi, Grafana 5Gi, Alertmanager 5Gi — spec 009).
- Frigate clips RWX PVC (spec 041/049).
- Future: Authentik Postgres (spec 063) — add when 063 lands.

**Explicitly excluded**:
- Frigate continuous-recording local NVMe storage (not a PVC; ephemeral by design).
- MinIO's own PVC (must not back up to itself).
- etcd state (handled separately via spec 008's mechanisms, not Longhorn).
- Automated restore-test/verification job (out of scope for v1 — reserved for a future spec, e.g., 062).

**Operational expectations**:
- A nightly snapshot for *any* PVC marked critical.
- A weekly off-cluster backup for the same.
- Snapshot/backup metrics scraped by Prometheus (spec 009) — alert on failures.
- Explicit `PrometheusRule` resources defined in this spec for backup and snapshot job failures (kube-prometheus-stack defaults do not cover these failure modes).

## Open Questions to Revalidate

1. ~~**Retention**: Is "nightly × 7 days + weekly × 4 weeks" the right policy?~~ Resolved: two tiers — Tier A (data PVCs) 7-day/4-week; Tier B (monitoring PVCs) 3-day/2-week.
2. ~~**Per-PVC overrides**: Should databases get more frequent backups?~~ Resolved: no — Gitea is mirrored to GitHub on every merge; Authentik deferred until spec 063.
3. ~~**Backup verification**: Should there be a periodic automated restore-test job?~~ Resolved: out of scope for v1; future spec 062.
4. ~~**Alerting wiring**: Are Longhorn backup failure alerts covered by kube-prometheus-stack defaults?~~ Resolved: explicit `PrometheusRule` resources required in this spec.
5. **Migration of existing PVCs**: Does applying `RecurringJob` labels to *existing* PVCs cause any disruption? (Should be metadata-only, but verify.)

## Open Decisions Locked from 2026-05-11 Design Session

- MinIO is the backup target (not external S3, not NFS, not a USB drive on a node).
- GitOps-managed via ArgoCD; recurring job definitions live in Git alongside the rest of the vanlab stack.
- Sealed Secret holds the MinIO S3 access credential for Longhorn.
- This work is a **prerequisite** for spec 063 (Authentik IdP) — Authentik should not deploy until its PVC has a real backup story.

## Assumptions (revalidate)

- MinIO (spec 060) is healthy and reachable from Longhorn manager pods.
- Longhorn version is current (v1.11.1 per spec 006 — verify, may have upgraded since).
- ArgoCD + Sealed Secrets remain the deployment pattern.
- No off-site (off-LAN) backup tier is in scope for v1. This spec produces *off-cluster* backups (in MinIO), not *off-site*. A future spec may add S3 replication or rsync-to-NAS for true off-site.
