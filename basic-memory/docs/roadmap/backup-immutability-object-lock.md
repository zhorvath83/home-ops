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
