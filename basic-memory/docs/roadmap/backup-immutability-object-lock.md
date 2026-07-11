---
title: backup-immutability-object-lock
type: roadmap
permalink: home-ops/docs/roadmap/backup-immutability-object-lock
topic: Immutable, tamper-proof backups — object-lock + delete-restricted keys
status: proposed
priority: high
scope: Add object-lock/versioning to the OVH S3 backup buckets and give the backup
  movers delete-restricted credentials, so backups survive even a full cluster compromise.
rationale: Client-side encryption already protects backup confidentiality; adding
  immutability protects availability and integrity — the combination is what actually
  defeats ransomware and guarantees a trustworthy recovery point.
related_areas:
- volsync-backup
- resticprofile-backup
- ovh-storage
options:
- Governance-mode lock (operator can override) — safer for space reclamation
- Compliance-mode lock (immutable until expiry) — hardest guarantee
---

# Immutable, tamper-proof backups — object-lock + delete-restricted keys

## Metadata (observation-form, schema validation)

- [topic] Immutable, tamper-proof backups — object-lock + delete-restricted keys
- [status] proposed
- [priority] high

## What we gain

- Backups become a true last line of defense — recoverable even if the cluster and its credentials are fully compromised.
- Ransomware or an accidental prune cannot destroy history within the lock/retention window.
- Restore confidence: a known-good, immutable point-in-time always exists.

## What to do

1. Enable OVH object-lock (and/or versioning) on the backup buckets with a lock window aligned to retention.
2. Split credentials: give the mover a write key without DeleteObject/lifecycle; run prune/forget from a separate tightly-scoped identity, or rely on lifecycle expiry under lock.
3. Reconcile Kopia and restic retention with the lock window so maintenance still works.
4. Verify: a delete with the mover key is denied; restore from a locked version succeeds.

## Options

1. Governance-mode lock (operator can override) — safer for space reclamation
2. Compliance-mode lock (immutable until expiry) — hardest guarantee

## Related

- relates_to [[volsync-backup]]
- relates_to [[resticprofile-backup]]
- relates_to [[ovh-storage]]

## Execution plan (research-backed)

### Current state
- OVH backup buckets are plain S3 storage, no lock/versioning: `provision/ovh/buckets.tf` → `resource "ovh_cloud_project_storage" "backup"` (region DE, for_each over `S3_BUCKET_NAMES`), no versioning/object-lock block.
- Single all-powerful credential: `provision/ovh/user.tf:1-33` → one `ovh_cloud_project_user` (role `objectstore_operator`) with an S3 policy of `Action: ["s3:*"]` (includes DeleteObject/DeleteBucket/lifecycle) over all backup buckets. The SAME credential feeds both planes: VolSync/Kopia (`kubernetes/components/volsync/externalsecret.yaml`) and resticprofile (`kubernetes/apps/selfhosted/resticprofile/app/externalsecret.yaml`).
- resticprofile actively deletes: `.../config/profiles.yaml:65-75` → `forget` schedule "Tue 05:00", `prune: true`, keep-hourly 1 / daily 7 / weekly 4 / monthly 12.
- Both planes already use client-side encryption (Kopia/restic passwords from 1Password) — confidentiality is covered; this item is about integrity/availability.

### Target state
- Backups cannot be silently deleted/overwritten within a retention window even with the mover's credentials — a tamper/ransomware-resistant recovery point exists.

### Implementation steps
1. **VERIFY OVH object-lock/versioning support FIRST** (this determines the whole approach). OVH S3-compatible storage support for object-lock (WORM) varies by storage class/region. Check:
   ```bash
   # with the S3 creds (via op run), against the OVH S3 endpoint s3.de.io.cloud.ovh.net
   aws --endpoint-url https://s3.de.io.cloud.ovh.net s3api get-object-lock-configuration --bucket <bucket> || echo "object-lock NOT enabled/supported"
   aws --endpoint-url https://s3.de.io.cloud.ovh.net s3api get-bucket-versioning --bucket <bucket>
   ```
   Also check whether the `ovh_cloud_project_storage` resource exposes a `versioning` argument in the provider version pinned in `provision/ovh/main.tf`.
2. **If object-lock is supported:** enable versioning + default object-lock retention on the buckets. Object-lock generally must be set at/near bucket creation — may require recreating buckets (coordinate: new bucket → re-seed backups → cut over). Prefer **governance mode** first (operator can still reclaim space) unless you want hard compliance-mode immutability.
3. **If object-lock is NOT supported (likely fallback):** enable **versioning** + a **lifecycle policy** (noncurrent-version expiration = your retention), and split credentials:
   - Add a SECOND OVH user (`provision/ovh/user.tf`) with an S3 policy WITHOUT `DeleteObject`/`DeleteObjectVersion`/`PutLifecycleConfiguration` — only `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`. This is the **mover** key used by VolSync/Kopia and resticprofile backup runs.
   - Keep the existing full key for a separate, out-of-band prune/maintenance identity (or rely on lifecycle expiry so no interactive prune is needed).
   - Wire the restricted key into the two ExternalSecrets (`components/volsync/externalsecret.yaml`, `resticprofile/app/externalsecret.yaml`) and store it in a new 1Password field.
4. **Reconcile retention with immutability.** With versioning+lifecycle handling expiry, set resticprofile `forget` to NOT prune from the mover identity (`profiles.yaml:65-75` — either remove `prune: true` or run prune only from the maintenance identity). For Kopia, align its retention policy so maintenance still compacts within the lock window.
5. `just ovh plan` (via op run) to preview, then user-approved `just ovh` apply. Commit: `🔒 feat(ovh): versioning + delete-restricted backup key`.

### Verification
- `aws --endpoint-url ... s3api get-bucket-versioning --bucket <b>` → Enabled; object-lock config present (if used).
- With the MOVER key: `aws --endpoint-url ... s3 rm s3://<b>/<obj>` → AccessDenied (or a delete just creates a delete-marker, prior version retained).
- Restore test: delete/overwrite an object, then restore the prior version / run `just volsync` restore → data recovered.
- Backups still succeed after the credential swap: `kubectl get replicationsource -A` healthy; resticprofile backup log clean.

### Rollback & safety
- Revert TF + ExternalSecret to the single full key and re-apply.
- **Risk:** a too-restrictive mover policy breaks backups (movers need PutObject + multipart: also `s3:AbortMultipartUpload`, `s3:ListMultipartUploadParts`). Test a backup run immediately after the swap. Recreating buckets for object-lock risks orphaning existing backups — keep the old bucket until the new one has a verified full backup.

### Gotchas & dependencies
- OVH object-lock support is the key unknown — step 1 gates everything; do not author TF before confirming.
- Movers need multipart-upload actions, not just PutObject — include them in the restricted policy.
- Would be auto-surfaced by the `ci-secret-and-iac-scanning` trivy job.

### Effort
M–L (~1 day; more if object-lock forces bucket recreation + re-seeding).
