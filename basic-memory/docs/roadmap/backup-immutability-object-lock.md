---
title: backup-immutability-object-lock
type: roadmap
permalink: home-ops/docs/roadmap/backup-immutability-object-lock
topic: Immutable, tamper-proof backups — object-lock + delete-restricted keys
status: proposed
priority: high
scope: 'Assessed 2026-08-03 (control-lane-verified). Object-lock DEFERRED — the perfectra1n-fork
  KopiaMaintenance/ReplicationSource CRDs cannot set retention-mode/period or extend
  locks (CONFIRMED at CRD-schema level), restic cannot use object-lock at all (the
  locks/ problem), and object-lock forces bucket replacement, losing up to 12 months
  of point-in-time history across 19 VolSync apps + the restic repo. Correct primary
  = versioning + delete-restricted mover key + non-current-version lifecycle (in-place,
  no engine breakage). The two planes need different designs.

  '
rationale: 'Client-side encryption covers confidentiality only against OVH-side compromise;
  the Kopia repo password and the restic RESTIC_PASSWORD both live in-cluster via
  ESO, so cluster compromise already loses confidentiality. Object-lock would protect
  availability/integrity only, and versioning + a delete-restricted mover key captures
  most of that with no engine breakage and no re-seed.

  '
related_areas:
- volsync-backup
- resticprofile-backup
- ovh-storage
options:
- Versioning + delete-restricted mover key + non-current-version lifecycle (PRIMARY,
  recommended now — in-place, no engine breakage)
- Object-lock on a NEW Kopia-only bucket, governance mode (DEFERRED — gated on the
  fork blocker below)
- OVH replication to a second region/bucket the cluster key cannot write (UNEVALUATED
  — closes single-region/single-trust residual)
- Do nothing / defer (current state)
---

# Immutable, tamper-proof backups — object-lock + delete-restricted keys

## Metadata (observation-form, schema validation)

- [topic] Immutable, tamper-proof backups — object-lock + delete-restricted keys
- [status] proposed — the schema `status` enum is `[proposed, accepted, in-progress, done, dropped]` (see `schema/roadmap`); `deferred` is not a valid value, so the deferral is expressed in the **Verdict** section below, not in this field
- [priority] high
- [assessed] 2026-08-03 — read-only feasibility re-assessment, control-lane-verified (Maestro independently confirmed the load-bearing facts)

## Verdict — DEFER object-lock as specified; PROCEED-MODIFIED with versioning + delete-restricted mover key + non-current-version lifecycle

- **Object-lock on the existing backup buckets: DEFER.** Three independent blockers (detailed below): the perfectra1n-fork `KopiaMaintenance`/`ReplicationSource` CRDs cannot set retention-mode/period or extend locks (CONFIRMED at CRD-schema level); restic cannot use object-lock at all (the `locks/` problem); and object-lock forces bucket replacement, losing up to 12 months of point-in-time history across 19 VolSync apps + the restic repo.
- **The correct PRIMARY design — which this note previously filed as a "fallback" — is: versioning + a delete-restricted mover key + a non-current-version lifecycle rule.** It is in-place on the existing buckets, breaks neither engine, and captures most of the tamper-resistance object-lock would add.
- **The two planes need DIFFERENT designs.** Kopia can in principle use object-lock (native support) once the fork blocker is closed; restic must never get object-lock and stays on versioning + a `locks/*` DeleteObject carve-out.
- **Recommended next investigation (UNEVALUATED):** the OVH `replication` block — cross-region bucket replication to a bucket the cluster key cannot write to — is the only candidate that also closes the single-region / single-trust-domain residual (§ Value assessment).

## Confirmed facts (cited)

- **OVH Standard S3 (Regions, DE) supports S3 Object Lock + versioning** — governance + compliance + legal hold; object-lock is irreversible; delete-with-version-id → 403, delete-without-version-id → a delete marker. Sources: <https://docs.ovhcloud.com/en/guides/storage-and-backup/object-storage/s3-managing-object-lock>, compliance matrix <https://docs.ovhcloud.com/en/guides/storage-and-backup/object-storage/s3-s3-compliancy>. The cluster's buckets are Standard class in region DE, endpoint `s3.de.io.cloud.ovh.net` (`provision/ovh/buckets.tf:1-15`).
- **OVH Terraform provider `2.18.0` (`provision/ovh/main.tf:13-16`) exposes `versioning` and `object_lock` nested blocks on `ovh_cloud_project_storage`.** Verbatim from the v2.18.0 resource doc (<https://raw.githubusercontent.com/ovh/terraform-provider-ovh/v2.18.0/docs/resources/cloud_project_storage.md>): "Object Lock cannot be disabled once enabled"; removing the `object_lock` block "will destroy and recreate the bucket, deleting all objects permanently"; changing `object_lock.status` "forces bucket replacement. Object Lock must be enabled at bucket creation." `versioning.status` (enabled/disabled/suspended) is an in-place update. Read-only attributes `objects_count` and `objects_size` (bytes) also exist (§ Costing).
- **Kopia has native S3 object-lock support** — `--retention-mode`/`--retention-period` (`kopia repository set-parameters`) plus an `extend-blob-retention-time` maintenance task (`--extend-object-locks`) that renews locks on active blobs during full maintenance; deletes become delete-markers so maintenance "succeeds" while prior versions stay locked; constraint: retention period must exceed the full-maintenance interval. Sources: Kopia PR #2179 (merged) <https://github.com/kopia/kopia/pull/2179>, issue #3427 <https://github.com/kopia/kopia/issues/3427>.
- **restic has NO native object-lock support** (as of 0.18.0). The blocker is the `locks/` directory: restic creates and deletes ephemeral lock files on every `backup`/`forget`/`prune` (`backup` always locks, ignores `--no-lock`); under compliance object-lock they cannot be deleted → stale locks accumulate → the repo appears permanently locked. Upstream issue #5411 ("Add option where to store lock files") is OPEN <https://github.com/restic/restic/issues/5411>; community discussion <https://forum.restic.net/t/any-way-to-get-restic-to-work-with-s3-object-locking-or-a-read-only-key/6858>, <https://forum.restic.net/t/s3-immutable-backups-for-ransomware-recovery/4072>.
- **Live fleet:** 19 `ReplicationSource` objects (verified: `kubectl get replicationsource -A -o name | wc -l` = 19), all `schedule: "0 * * * *"`, `retain: hourly=24 daily=7 weekly=4 monthly=12` (verified on `paperless`). The `KopiaMaintenance/kopia-daily-maintenance` CR runs `trigger.schedule: "30 */6 * * *"` (4×/day; top-level `schedule: "0 2 * * *"`), `activeDeadlineSeconds: 10800`.
- **Single all-powerful credential feeds both planes:** `provision/ovh/user.tf:12-29` — one `ovh_cloud_project_user` (`objectstore_operator`) with `Action: ["s3:*"]` over all buckets. The same `HomeOps/ovh` 1P item feeds VolSync/Kopia (`kubernetes/components/volsync/externalsecret.yaml`) and resticprofile (`kubernetes/apps/selfhosted/resticprofile/app/externalsecret.yaml`).
- **resticprofile actively deletes:** `kubernetes/apps/selfhosted/resticprofile/app/config/profiles.yaml:65-75` — `forget` Tue 05:00, `keep-hourly: 1`/`keep-daily: 7`/`keep-weekly: 4`/`keep-monthly: 12`, `prune: true`.
- **Existing alerting has no bucket-size rule:** only `VolSyncComponentAbsent` and `VolSyncVolumeOutOfSync` exist (`kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml:11,19`).

## The hard gate — Kopia fork blocker (CONFIRMED at CRD-schema level)

The deployed VolSync operator is the **perfectra1n fork** (`ghcr.io/perfectra1n/volsync`, image `v0.17.11`, chart `0.18.5` — `kubernetes/apps/volsync-system/volsync/app/helmrelease.yaml`). The live CRD schemas (verified 2026-08-03 against the cluster) expose **no retention / object-lock / extend field**:

- `KopiaMaintenance.spec` properties: `activeDeadlineSeconds, affinity, cacheAccessModes, cacheCapacity, cachePVC, cacheStorageClassName, containerSecurityContext, contentCacheSizeLimitMB, enabled, failedJobsHistoryLimit, metadataCacheSizeLimitMB, moverPodLabels, moverVolumes, nodeSelector, podSecurityContext, repository, resources, schedule, serviceAccountName, successfulJobsHistoryLimit, suspend, tolerations, trigger` — no `retentionMode`/`retentionPeriod`/`extendObjectLocks`.
- `ReplicationSource.spec.kopia` properties: `accessModes, cacheAccessModes, cacheCapacity, cacheStorageClassName, compression, copyMethod, moverPodLabels, moverSecurityContext, parallelism, repository, retain, storageClassName, volumeSnapshotClassName` — also none.

**Consequence:** even with object-lock enabled on the Kopia bucket, the stack cannot set `--retention-mode`/`--retention-period` and cannot run `extend-blob-retention-time`. Each blob is locked at write-time for the default `period`, but nothing renews active blobs → after `period` elapses blobs become deletable again. The result is a **rolling `period`-deep immutability window**, not "all history is immutable" — weaker than the upstream-intended model and weaker than this roadmap's own goal. This is the single hard gate on any object-lock path for the Kopia plane.

## Why restic must never get object-lock

restic's `locks/` files are created and deleted on every operation. Removing `prune: true` from the mover identity (the old plan's idea) does **not** stop `backup` from writing locks — those locks still need deletion. Without a `locks/*` `DeleteObject` carve-out (or splitting the lock prefix into a separate non-WORM bucket — upstream issue #5411, not available), the restic repo **locks up within days** under object-lock regardless of where `prune` runs. **restic stays on versioning + lifecycle + a delete-restricted key with a `locks/*` carve-out.** The two planes therefore need different designs.

## Object-lock cannot be enabled on the existing buckets — replacement + re-seed

Because an `object_lock.status` change forces bucket replacement (§ Confirmed facts), enabling object-lock on the *current* buckets destroys all existing backups. The only safe path is **new object-lock-enabled buckets + parallel-run cutover**:

- keep the old buckets intact until the new ones hold a verified full backup;
- re-seed: let the 19 hourly VolSync schedules + the nightly resticprofile run repopulate from live data;
- **history loss:** the full retention window (12 monthly snapshots) rebuilds over ~1 year; point-in-time history older than the re-seed is gone. The restic repo's dedup history resets to zero and accrues forward.
- **egress cost is zero** (ingress to OVH is free; the re-seed writes from the cluster, not from the old bucket). The cost is time + history loss + parallel-run operational risk, not bandwidth.
- **the previous effort estimate ("~1 day; more if re-seeding") is wrong by orders of magnitude** — the re-seed is months of parallel running, not a day-plus.

## Value assessment (blunt)

- **Confidentiality already falls on cluster compromise.** The Kopia repo password (`volsync-template` 1P item → ESO) and the restic `RESTIC_PASSWORD` (`resticprofile` 1P item → ESO) **both live in the cluster**. An attacker who owns the cluster can decrypt and read all historical backups. The roadmap's premise that "client-side encryption protects confidentiality" is true **only against OVH-side compromise, not against cluster compromise**.
- **Object-lock therefore protects availability/integrity only, not confidentiality.** Combined with a delete-restricted mover key it moves the trust boundary from "cluster S3 key" to "OVH account" — a real improvement, since the OVH account (long-lived application/consumer keys in 1Password + Terraform Cloud) is not in the cluster.
- **Versioning + a delete-restricted key captures most of that, with no engine breakage and no re-seed.** Versioning defeats overwrite and accidental delete (prior versions survive as non-current); the restricted key removes `DeleteObject`/`PutLifecycleConfiguration` from the mover identity. Object-lock's marginal gain over *versioning alone* is narrow: protection against a *privileged* attacker who holds the full `s3:*` key and deletes non-current versions to cover tracks.
- **Residual surface object-lock does NOT close:**
  - the **OVH account itself** (1Password / Terraform Cloud compromise) — the real root of trust;
  - **single node** — one Talos control plane on one HP box; object-lock does nothing for hardware loss;
  - **single region** — one OVH region (DE); object-lock on one bucket in one region is not off-site diversity.
- **Net:** object-lock is **marginal** here. Versioning + restricted key is load-bearing; object-lock is not.

## Modified scope worth doing now (low-risk, most of the benefit)

1. **Enable `versioning` (status=enabled) on the existing OVH buckets** — in-place, no replacement, no engine breakage.
2. **Add a non-current-version lifecycle rule** (expire non-current versions after ~30–90 days) on each bucket — **set BEFORE or WITH versioning, never after**, so space is bounded from day one.
3. **Split credentials:** add a second `ovh_cloud_project_user` with a write-only S3 policy — `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`, multipart actions (`s3:AbortMultipartUpload`, `s3:ListMultipartUploadParts`, `s3:ListBucketMultipartUploads`); for the **restic** bucket additionally allow `s3:DeleteObject` on a `locks/*` prefix only. Keep the existing full key for a separate, `op`-gated prune/maintenance identity used out-of-band (not delivered to the cluster).
4. **Wire the restricted key into both ExternalSecrets** (`kubernetes/components/volsync/externalsecret.yaml`, `kubernetes/apps/selfhosted/resticprofile/app/externalsecret.yaml`) via a new 1P field; **extend the `just ovh apply` 1P sync** (`provision/ovh/mod.just:26-50`) to write the second access/secret pair — read `mod.just` first; the `jq -er` abort-on-null contract must keep holding.
5. **resticprofile:** move `prune` off the in-cluster mover identity — run `forget --prune` from the out-of-band maintenance identity on a manual/weekly basis (the `locks/*` carve-out keeps `backup` working). Optionally remove `prune: true` from `profiles.yaml:75`.
6. **Verify:** one VolSync app backup + one resticprofile run succeed with the restricted key; `aws s3api get-bucket-versioning` shows Enabled; a `DeleteObject` on a non-`locks/*` object with the mover key is denied (or creates a delete-marker, prior version retained).
7. **Add a bucket-size / object-count PrometheusRule** before enabling versioning (§ Prerequisites).

### Rollback

Revert TF + ExternalSecrets to the single full key and re-apply; set `versioning.status=suspended`. **Versioning is reversible; object-lock is not.** No data is lost on rollback.

### Effort (modified scope)

~1.5–2.5 days hands-on: TF (versioning + second user + lifecycle), `mod.just` 1P-sync extension, two ExternalSecret rewrites, one backup-run verification per plane, one delete-denial test, one rollback drill. **No re-seed, no parallel buckets, no history loss.** The object-lock path, by contrast, is months of parallel running dominated by waiting for 12-month retention to rebuild.

## PROCEED trigger list — what must become true to revisit object-lock

Object-lock (Kopia plane only, governance mode, on NEW buckets) becomes worth revisiting when ALL hold:

- the perfectra1n fork is confirmed (or replaced by upstream VolSync) to support `--retention-mode`/`--retention-period` and `--extend-object-locks` end-to-end through `KopiaMaintenance`/`ReplicationSource`;
- a bucket-size / object-count PrometheusRule is in place and observed stable;
- governance mode (not compliance) is chosen;
- a non-current-version lifecycle rule is set BEFORE lock enable;
- new buckets (not the existing ones) are used, with parallel-run cutover and the old buckets retained until the new ones hold a verified full backup.

## Prerequisites (do before any versioning/lock enable)

- **Bucket-size PrometheusRule** — none exists today (`prometheusrule.yaml:11,19` has only the two volsync alerts). Add one before versioning so the growth the lifecycle rule is meant to bound is observable.
- **Lifecycle rule set BEFORE versioning, not after** — otherwise the bucket grows monotonically from the first versioning enable until the rule is added.
- **`terraform providers schema -json`** run in `provision/ovh/` to confirm the exact v2.18.0 argument names before authoring HCL (the registry web page is JS-only; the raw GitHub doc cited above is authoritative).

## Costing & next investigation

- **Bucket sizes are obtainable WITHOUT S3 credentials.** `ovh_cloud_project_storage` exposes read-only attributes `objects_count` and `objects_size` (bytes). A `terraform output` over those attributes — the existing OVH API credential used by `just ovh` is sufficient, no S3 access key — returns per-bucket size. Smallest next step to size the versioning/lifecycle growth and any re-seed.
- **`replication` block — recommended next investigation (UNEVALUATED).** `ovh_cloud_project_storage` has a `replication` nested block (rules: destination/filter/status/priority/id/delete_marker_replication). OVH-side cross-region bucket replication would put a second copy under a credential the cluster never holds — a low-effort variant of the "second pull-based copy" option and the only candidate that also closes the single-region / single-trust-domain residual from the Value assessment. Not evaluated. Open questions: does OVH replication support cross-region (not just same-region)? does the destination bucket need object-lock/versioning? what is the cost of the replica bytes? does it interact with the source bucket's object-lock/versioning? Investigate before choosing between the modified scope (versioning only) and adding replication.

## Corrections to the previous plan

The previous execution plan (now superseded) had these wrong/outdated steps:

1. **Step 1 ("VERIFY OVH object-lock support FIRST — the key unknown"): outdated.** Object-lock + versioning ARE supported in the cluster's storage class/region. The real gate is the perfectra1n-fork CRD blocker (§ hard gate), not OVH-side support.
2. **Step 2 ("enable versioning + default object-lock retention on the buckets"): wrong for the existing buckets** — object-lock forces replacement, destroying all backups. Must use new buckets, not the existing ones.
3. **Step 3 ("If object-lock is NOT supported — fallback: versioning + lifecycle + split credentials"): this is the correct PRIMARY design for both planes, not a fallback.** It should be the main plan.
4. **Step 4 ("set resticprofile `forget` to NOT prune from the mover identity"): incomplete** — misses the `locks/` files restic creates on every `backup`. Without the `locks/*` DeleteObject carve-out the restic repo locks up regardless of where `prune` runs.
5. **"Effort: M–L (~1 day; more if object-lock forces bucket recreation + re-seeding"): wrong by orders of magnitude** — the re-seed is months, not a day-plus.
6. **Mover-policy gotcha ("movers need multipart-upload actions"): correct — keep, and add `s3:ListBucketMultipartUploads`.**
7. **Implicit assumption that both planes use the same immutability mechanism: wrong** — Kopia can in principle use object-lock (after the fork blocker); restic cannot. The two planes need different designs.

## Relations

- relates_to [[volsync-backup]]
- relates_to [[resticprofile-backup]]
- relates_to [[ovh-storage]]
- relates_to [[schema/roadmap]]
