---
title: AD-011-democratic-csi-storage
type: decision
permalink: home-ops/docs/decisions/ad-011-democratic-csi-storage
decision_id: AD-011
topic: Storage unchanged — democratic-csi local-hostpath
status: active
decided_at: '2025-10-01'
decision: The existing `democratic-csi-local-hostpath` storage class carries over
  unchanged to the new cluster.
rationale: On a single-node setup, Longhorn replication is pointless (max 1 replica)
  and Rook-Ceph is anti-pattern democratic-csi local-hostpath driver is established
  and works with Talos `extraMounts` The existing VolSync + Kopia + OVH S3 backup
  pipeline is storage-class-agnostic
tradeoffs: Single point of disk failure — the backup pipeline is critical (this is
  already the case today)
related_areas:
- volsync-backup
- talos-cluster
---

# AD-011 — Storage unchanged — democratic-csi local-hostpath

## Metadata (observation-form, schema validation)

- [decision_id] AD-011
- [status] active
- [decided_at] 2025-10-01
- [topic] Storage unchanged — democratic-csi local-hostpath

## Decision

The existing `democratic-csi-local-hostpath` storage class carries over unchanged to the new cluster.

## Rationale

- On a single-node setup, Longhorn replication is pointless (max 1 replica) and Rook-Ceph is anti-pattern
- democratic-csi local-hostpath driver is established and works with Talos `extraMounts`
- The existing VolSync + Kopia + OVH S3 backup pipeline is storage-class-agnostic

## Tradeoffs

- Single point of disk failure — the backup pipeline is critical (this is already the case today)

## Related

- relates_to [[volsync-backup]]
- relates_to [[talos-cluster]]
