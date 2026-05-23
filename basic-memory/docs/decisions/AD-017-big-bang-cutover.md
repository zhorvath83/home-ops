---
title: AD-017-big-bang-cutover
type: decision
permalink: home-ops/docs/decisions/ad-017-big-bang-cutover
decision_id: AD-017
topic: Big-bang cutover with K3s shut down during testing
status: active
decided_at: '2025-10-01'
decision: 'Big-bang cutover model: the old K3s VM is SHUT DOWN during new-cluster
  testing. The two clusters do NOT run in parallel.'
rationale: 'The two clusters cannot run together on the LAN (IP pool collision, single
  Cloudflare Tunnel connector) Workflow: snapshot → K3s VM shutdown → new cluster
  boot → restore + validation → if OK: keep; if not: HP power-down + K3s VM power-on
  VolSync restore happens per-app but all 17 PVCs can be triggered in parallel'
tradeoffs: NAS NFS share stays unchanged (M93p remains up), but apps are unavailable
  for 1-3 hours during the switchover Rollback = HP power-down + K3s VM power-on (~5-10
  minutes)
related_areas:
- volsync-backup
- talos-cluster
---

# AD-017 — Big-bang cutover with K3s shut down during testing

## Metadata (observation-form, schema validation)

- [decision_id] AD-017
- [status] active
- [decided_at] 2025-10-01
- [topic] Big-bang cutover with K3s shut down during testing

## Decision

Big-bang cutover model: the old K3s VM is SHUT DOWN during new-cluster testing. The two clusters do NOT run in parallel.

## Rationale

- The two clusters cannot run together on the LAN (IP pool collision, single Cloudflare Tunnel connector)
- Workflow: snapshot → K3s VM shutdown → new cluster boot → restore + validation → if OK: keep; if not: HP power-down + K3s VM power-on
- VolSync restore happens per-app but all 17 PVCs can be triggered in parallel

## Tradeoffs

- NAS NFS share stays unchanged (M93p remains up), but apps are unavailable for 1-3 hours during the switchover
- Rollback = HP power-down + K3s VM power-on (~5-10 minutes)

## Related

- relates_to [[volsync-backup]]
- relates_to [[talos-cluster]]
