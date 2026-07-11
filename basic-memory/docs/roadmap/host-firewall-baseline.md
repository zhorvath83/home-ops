---
title: host-firewall-baseline
type: roadmap
permalink: home-ops/docs/roadmap/host-firewall-baseline
topic: Node-level firewall — a network floor for the control-plane host
status: proposed
priority: medium
scope: Add a Talos network.ingressFirewall (default-drop, allow LAN-scoped management)
  and/or enable the Cilium host firewall, so the nodes sensitive ports have a network-layer
  allow-list in addition to their existing authentication.
rationale: 'A host firewall adds defense-in-depth at the node boundary: management
  and control-plane ports become reachable only from intended sources, so authentication
  is no longer the only thing between the LAN and the Talos/kubelet/etcd APIs.'
related_areas:
- talos-cluster
- networking
options:
- Talos ingressFirewall — OS-level, simplest
- Cilium host firewall — policy-as-CCNP, unified with the existing model
- Both — layered
---

# Node-level firewall — a network floor for the control-plane host

## Metadata (observation-form, schema validation)

- [topic] Node-level firewall — a network floor for the control-plane host
- [status] proposed
- [priority] medium

## What we gain

- The nodes sensitive surfaces (Talos API, kubelet, etcd, metrics) get a network allow-list, not just credential gating.
- A compromised LAN device or a stray port-forward can no longer even reach these ports.
- An explicit, reviewable definition of who may talk to the control plane.

## What to do

1. Define Talos network.ingressFirewall: default-drop, allow the LAN CIDR to the ports actually needed (6443/50000/10250), drop off-LAN sources.
2. Or enable the Cilium host firewall with CCNPs selecting reserved:host.
3. Bind purely-internal endpoints (etcd metrics) to loopback/LAN — see etcd-metrics-endpoint-binding.
4. Verify: off-scope sources are filtered; cluster operation and upgrades still function.

## Options

1. Talos ingressFirewall — OS-level, simplest
2. Cilium host firewall — policy-as-CCNP, unified with the existing model
3. Both — layered

## Related

- relates_to [[talos-cluster]]
- relates_to [[networking]]
- relates_to [[etcd-metrics-endpoint-binding]]
