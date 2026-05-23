---
title: AD-012-nvme-split-os-vs-data
type: decision
permalink: home-ops/docs/decisions/ad-012-nvme-split-os-vs-data
decision_id: AD-012
topic: NVMe split — PC801 for OS+etcd, PC711 for data PVCs
status: active
decided_at: '2025-10-01'
decision: Of the two SK hynix NVMe drives, the PC801 (Gen4) is the Talos OS install
  disk (etcd + EPHEMERAL volume); the PC711 (Gen3) is the democratic-csi data disk
  (`/var/mnt/local-hostpath`).
rationale: Both M.2 slots on the HP ProDesk 600 G6 DM are PCIe Gen3 — the PC801 Gen4
  sequential-throughput advantage does NOT materialize However, etcd fsync latency
  is sensitive to random-write IOPS and controller quality. etcd is the critical write
  path of the cluster — slow etcd disk slows the whole cluster reconcile and causes
  "request timeout" errors under heavy load PC801 (1.3M IOPS random write) gives a
  real advantage to the etcd workload that PC711 cannot match for media PVCs democratic-csi
  PVCs (Plex DB, Paperless, Sonarr config) generate lower average write throughput
  than the PC711 (570K IOPS, 1 GB DRAM cache) can sustain Talos `EPHEMERAL` volume
  (container images, runtime state) also lives on the OS disk — faster image pulls
  and container starts
tradeoffs: In practice the speed difference is marginal (Gen3 ceiling on both), but
  the controller-level difference (PC801 vs PC711) is measurable on etcd If a future
  heavy-write PVC appears (e.g., a PG database doing 1000+ TPS), the data disk allocation
  may want to be reconsidered — not needed today
related_areas:
- talos-cluster
---

# AD-012 — NVMe split — PC801 for OS+etcd, PC711 for data PVCs

## Metadata (observation-form, schema validation)

- [decision_id] AD-012
- [status] active
- [decided_at] 2025-10-01
- [topic] NVMe split — PC801 for OS+etcd, PC711 for data PVCs

## Decision

Of the two SK hynix NVMe drives, the PC801 (Gen4) is the Talos OS install disk (etcd + EPHEMERAL volume); the PC711 (Gen3) is the democratic-csi data disk (`/var/mnt/local-hostpath`).

## Rationale

- Both M.2 slots on the HP ProDesk 600 G6 DM are PCIe Gen3 — the PC801 Gen4 sequential-throughput advantage does NOT materialize
- However, etcd fsync latency is sensitive to random-write IOPS and controller quality. etcd is the critical write path of the cluster — slow etcd disk slows the whole cluster reconcile and causes "request timeout" errors under heavy load
- PC801 (1.3M IOPS random write) gives a real advantage to the etcd workload that PC711 cannot match for media PVCs
- democratic-csi PVCs (Plex DB, Paperless, Sonarr config) generate lower average write throughput than the PC711 (570K IOPS, 1 GB DRAM cache) can sustain
- Talos `EPHEMERAL` volume (container images, runtime state) also lives on the OS disk — faster image pulls and container starts

## Tradeoffs

- In practice the speed difference is marginal (Gen3 ceiling on both), but the controller-level difference (PC801 vs PC711) is measurable on etcd
- If a future heavy-write PVC appears (e.g., a PG database doing 1000+ TPS), the data disk allocation may want to be reconsidered — not needed today

## Related

- relates_to [[talos-cluster]]
