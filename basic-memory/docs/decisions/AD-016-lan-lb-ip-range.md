---
title: AD-016-lan-lb-ip-range
type: decision
permalink: home-ops/docs/decisions/ad-016-lan-lb-ip-range
decision_id: AD-016
topic: LAN LoadBalancer IP range `192.168.1.15-25`
status: active
decided_at: '2025-10-01'
decision: The new cluster L2 announcement IP pool is `192.168.1.15-25` (11 IPs). The
  current MetalLB service IPs (`.18`, `.19`, `.20`) fall in this range and are preserved
  unchanged.
rationale: 'During testing the old K3s cluster is shut down — no IP conflict DNS records
  and router/dnsmasq configs remain untouched (`LB_K8S_GATEWAY_IP=192.168.1.19` etc.)
  Rollback path: HP power-down → K3s VM power-on → IPs automatically restore'
tradeoffs: The two clusters cannot run simultaneously on the LAN (IP collision). The
  "shut down K3s during testing" workflow resolves this Cloudflare Tunnel cannot connect
  to both clusters simultaneously (single tunnel-token connector pod) — but with K3s
  shut down this is not a problem
related_areas:
- networking
---

# AD-016 — LAN LoadBalancer IP range `192.168.1.15-25`

## Metadata (observation-form, schema validation)
- [decision_id] AD-016
- [status] active
- [decided_at] 2025-10-01
- [topic] LAN LoadBalancer IP range `192.168.1.15-25`

## Decision
The new cluster L2 announcement IP pool is `${d}{LB_IP_POOL_START}–${d}{LB_IP_POOL_STOP}` (11 IPs). The current MetalLB service IPs (`.18`, `.19`, `.20`) fall in this range and are preserved unchanged. These values are now defined in the `cluster-settings` ConfigMap.

## Rationale
- During testing the old K3s cluster is shut down — no IP conflict
- DNS records and router/dnsmasq configs remain untouched (`K8S_GATEWAY_IP` now from `cluster-settings`)
- Rollback path: HP power-down → K3s VM power-on → IPs automatically restore

## Tradeoffs
- The two clusters cannot run simultaneously on the LAN (IP collision). The "shut down K3s during testing" workflow resolves this
- Cloudflare Tunnel cannot connect to both clusters simultaneously (single tunnel-token connector pod) — but with K3s shut down this is not a problem

## Related
- relates_to [[networking]]
