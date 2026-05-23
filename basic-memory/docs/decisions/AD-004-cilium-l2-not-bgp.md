---
title: AD-004-cilium-l2-not-bgp
type: decision
permalink: home-ops/docs/decisions/ad-004-cilium-l2-not-bgp
decision_id: AD-004
topic: L2 announcement instead of BGP
status: active
decided_at: '2025-10-01'
decision: Use Cilium L2 announcement policy for service IPs; do NOT enable the BGP
  control plane.
rationale: Single-node setup makes BGP overkill — no ECMP, no failover to another
  node OpenWRT router could speak BGP but would need config on both sides with no
  real benefit L2 ARP/GARP broadcast fits a single 1 GbE NIC cleanly onedr0p reference
  uses L2 announcement — ready-made template
tradeoffs: If a multi-node setup arrives later (worker nodes), L2 announcement does
  not scale per-VIP (only one node owns a VIP) — BGP switch is a small refactor at
  that point
related_areas:
- networking
---

# AD-004 — L2 announcement instead of BGP

## Metadata (observation-form, schema validation)

- [decision_id] AD-004
- [status] active
- [decided_at] 2025-10-01
- [topic] L2 announcement instead of BGP

## Decision

Use Cilium L2 announcement policy for service IPs; do NOT enable the BGP control plane.

## Rationale

- Single-node setup makes BGP overkill — no ECMP, no failover to another node
- OpenWRT router could speak BGP but would need config on both sides with no real benefit
- L2 ARP/GARP broadcast fits a single 1 GbE NIC cleanly
- onedr0p reference uses L2 announcement — ready-made template

## Tradeoffs

- If a multi-node setup arrives later (worker nodes), L2 announcement does not scale per-VIP (only one node owns a VIP) — BGP switch is a small refactor at that point

## Related

- relates_to [[networking]]
