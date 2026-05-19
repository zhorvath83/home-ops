---
title: AD-018-volsync-ovh-data-migration
type: decision
permalink: home-ops/docs/decisions/ad-018-volsync-ovh-data-migration
decision_id: AD-018
topic: Data migration via VolSync OVH round-trip for every PVC
status: active
decided_at: '2025-10-01'
decision: Data migration uses the existing VolSync + OVH S3 backup pipeline with a
  fresh Kopia repo pointer. Old cluster final snapshot → new cluster ReplicationDestination
  restore.
rationale: The Kopia repo stays the same — OVH bucket unchanged, password unchanged;
  only `purpose` / `hostname` changes per cluster The `kubernetes/components/volsync/replicationdestination.yaml`
  template already exists in the repo (currently commented for "new-cluster recreate")
  App-level export (e.g., Plex DB dump) is only needed where data is not on a PVC
  or the PVC content is not self-consistent (e.g., open SQLite WAL)
tradeoffs: 17 PVCs = ~17 RD jobs. Time depends on PVC size, but OVH↔HP download on
  1 GbE caps at ~100 MB/s Network traffic depends on snapshot size (Plex DB can be
  large)
related_areas:
- volsync-backup
- ovh-storage
---

# AD-018 — Data migration via VolSync OVH round-trip for every PVC

## Metadata (observation-form, schema validation)
- [decision_id] AD-018
- [status] active
- [decided_at] 2025-10-01
- [topic] Data migration via VolSync OVH round-trip for every PVC

## Decision
Data migration uses the existing VolSync + OVH S3 backup pipeline with a fresh Kopia repo pointer. Old cluster final snapshot → new cluster ReplicationDestination restore.

## Rationale
- The Kopia repo stays the same — OVH bucket unchanged, password unchanged; only `purpose` / `hostname` changes per cluster
- The `kubernetes/components/volsync/replicationdestination.yaml` template already exists in the repo (currently commented for "new-cluster recreate")
- App-level export (e.g., Plex DB dump) is only needed where data is not on a PVC or the PVC content is not self-consistent (e.g., open SQLite WAL)

## Tradeoffs
- 17 PVCs = ~17 RD jobs. Time depends on PVC size, but OVH↔HP download on 1 GbE caps at ~100 MB/s
- Network traffic depends on snapshot size (Plex DB can be large)

## Related
- relates_to [[volsync-backup]]
- relates_to [[ovh-storage]]
