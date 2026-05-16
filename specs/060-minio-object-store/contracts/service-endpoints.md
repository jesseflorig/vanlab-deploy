# Contract — MinIO Service Endpoints

**Feature**: 060-minio-object-store
**Audience**: Future in-cluster consumers of the MinIO S3 API (spec 061 Longhorn, future Loki/Authentik/Velero).

This contract defines the cluster-internal interface that 060 commits to. Consumers (subsequent specs) MAY rely on the values here as stable.

## In-cluster S3 API endpoint

| Property | Value |
|---|---|
| Service DNS | `minio.minio.svc.cluster.local` |
| Port | `9000` |
| Protocol | `http` (plaintext within cluster overlay — see Constitution VI exemption for intra-cluster) |
| Path style | Path-style addressing (`http://host:port/<bucket>/<key>`) — virtual-host style is not configured |
| AWS region label | Consumers MUST supply `us-east-1` when their SDK requires a region; MinIO ignores the value, but absent regions break some SDKs |

Full URL form for AWS-style consumers: `http://minio.minio.svc.cluster.local:9000`.

## Admin console endpoint

| Property | Value |
|---|---|
| Hostname | `minio.fleet1.lan` |
| Port | `443` |
| Protocol | `https` (TLS via fleet1.lan wildcard cert, spec 054) |
| Reachability | LAN + Tailscale only; **not** publicly exposed |
| Auth | MinIO root user (from `minio-root` Secret) — direct login, no SSO integration in 060 |

## Buckets

| Bucket | Purpose | Stable name? |
|---|---|---|
| `longhorn-backups` | Sole consumer = Longhorn `BackupTarget` (spec 061). Other writers MUST NOT use this bucket. | Yes |
| `vanlab-archive` | General-purpose; consumers may write here at standup but production consumers SHOULD provision their own consumer-named bucket. | Yes |

## Credentials handling

- Root credentials live in `Secret/minio-root` in the `minio` namespace. Decrypted by Sealed Secrets controller. Consumers MUST NOT use root credentials.
- Per-consumer credentials MUST be scoped to a single bucket via a custom MinIO policy. Pattern established by the `longhorn-backups-rw` policy created at 060 standup.
- Per-consumer credentials are sealed in the *consumer's* spec, not in 060.

## Stability commitments

| Property | Stable across 060-onwards? | Notes |
|---|---|---|
| Service DNS name | Yes | Helm release name `minio` in namespace `minio` |
| S3 API port `9000` | Yes | Chart default; not overridden |
| Console hostname `minio.fleet1.lan` | Yes | Subject to wildcard cert continuing to exist |
| Bucket name `longhorn-backups` | Yes | Hardcoded in spec 061 |
| Bucket name `vanlab-archive` | Yes | Reserved; renaming requires migration |
| HTTPS for S3 API (in-cluster) | **No** | Currently HTTP. May change in a future spec; consumers SHOULD construct endpoint URLs from a configurable variable rather than hardcoding the scheme. |
| MinIO chart version | **No** | Pinned to a specific 5.x release; upgrades go through the Helm-bump review pattern. |

## Negative contract assertions

- The S3 API endpoint is **not reachable via `IngressRoute`**. Any consumer attempting to reach it via a `*.fleet1.lan` hostname will fail. This is intentional per FR-012.
- MinIO does **not** speak SSO/OIDC in 060. Console login uses the root credential. (Authentik integration is out of scope until at least spec 064; even then, MinIO console likely stays on Tier 0 native auth as a break-glass tool — TBD.)
- No bucket lifecycle policies are applied. Object retention is owned by each consumer (Longhorn `RecurringJob.retain` for spec 061; not yet decided for other future consumers).
