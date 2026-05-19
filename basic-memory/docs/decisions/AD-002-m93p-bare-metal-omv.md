---
title: AD-002-m93p-bare-metal-omv
type: decision
permalink: home-ops/docs/decisions/ad-002-m93p-bare-metal-omv
decision_id: AD-002
topic: M93p stays bare-metal OMV — preserve physical separation
status: active
decided_at: '2025-10-01'
decision: Replace the M93p Proxmox + OMV VM setup with bare-metal OMV; do NOT consolidate
  it into the HP.
rationale: Physical separation has DR value — if the HP dies, the NAS and local backup
  target stay alive Beyond VolSync OVH S3 backup, the local NFS mount and a potential
  Kopia local repo retain value M93p idles at ~12 W — yearly extra cost ~8,000 Ft,
  well covered by the DR value Proxmox layer is unnecessary on the M93p if only OMV
  runs there — bare-metal is simpler and removes a patch cycle
tradeoffs: 'Extra cutover step: M93p Proxmox tear-down + bare-metal OMV install USB
  DAS passthrough config goes away (works now, but direct USB access on bare-metal
  makes it unnecessary)'
related_areas:
- ovh-storage
- resticprofile-backup
---

# AD-002 — M93p stays bare-metal OMV — preserve physical separation

## Metadata (observation-form, schema validation)
- [decision_id] AD-002
- [status] active
- [decided_at] 2025-10-01
- [topic] M93p stays bare-metal OMV — preserve physical separation

## Decision
Replace the M93p Proxmox + OMV VM setup with bare-metal OMV; do NOT consolidate it into the HP.

## Rationale
- Physical separation has DR value — if the HP dies, the NAS and local backup target stay alive
- Beyond VolSync OVH S3 backup, the local NFS mount and a potential Kopia local repo retain value
- M93p idles at ~12 W — yearly extra cost ~8,000 Ft, well covered by the DR value
- Proxmox layer is unnecessary on the M93p if only OMV runs there — bare-metal is simpler and removes a patch cycle

## Tradeoffs
- Extra cutover step: M93p Proxmox tear-down + bare-metal OMV install
- USB DAS passthrough config goes away (works now, but direct USB access on bare-metal makes it unnecessary)

## Related
- relates_to [[ovh-storage]]
- relates_to [[resticprofile-backup]]
