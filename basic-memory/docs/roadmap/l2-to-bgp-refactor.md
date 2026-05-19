---
title: l2-to-bgp-refactor
type: roadmap
permalink: home-ops/docs/roadmap/l2-to-bgp-refactor
topic: Cilium L2 announcement → BGP refactor (conditional on multi-node)
status: proposed
scope: If a worker node is ever added to the cluster, refactor LoadBalancer IP announcement
  from Cilium L2 (current — ARP/GARP-based, only one node owns a VIP) to Cilium BGP
  control plane (multiple nodes can announce, ECMP failover). Requires OpenWRT router-side
  BGP config plus cluster-side BGP peering config.
priority: low
rationale: L2 announcement does not scale to multiple nodes per-VIP. Adding a worker
  node makes BGP the right choice; until then, BGP is overkill (no ECMP path benefit
  on a single node, extra router config without any failover advantage). This is a
  known trigger for refactoring rather than an active task.
related_areas:
- networking
- talos-cluster
---

# Cilium L2 announcement → BGP refactor (conditional on multi-node)

## Metadata (observation-form, schema validation)
- [topic] Cilium L2 announcement → BGP refactor (conditional on multi-node)
- [status] proposed
- [priority] low

## Scope
If a worker node is ever added to the cluster, refactor LoadBalancer IP announcement from Cilium L2 (current — ARP/GARP-based, only one node owns a VIP) to Cilium BGP control plane (multiple nodes can announce, ECMP failover). Requires OpenWRT router-side BGP config plus cluster-side BGP peering config.

## Rationale
L2 announcement does not scale to multiple nodes per-VIP. Adding a worker node makes BGP the right choice; until then, BGP is overkill (no ECMP path benefit on a single node, extra router config without any failover advantage). This is a known trigger for refactoring rather than an active task.

## Related
- relates_to [[networking]]
- relates_to [[talos-cluster]]
