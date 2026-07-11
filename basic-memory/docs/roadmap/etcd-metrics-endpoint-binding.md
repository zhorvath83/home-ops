---
title: etcd-metrics-endpoint-binding
type: roadmap
permalink: home-ops/docs/roadmap/etcd-metrics-endpoint-binding
topic: Scope the etcd metrics endpoint to trusted listeners
status: proposed
priority: medium
scope: Bind the etcd metrics listener to loopback or the LAN subnet (and/or require
  auth) so cluster-internal telemetry is not exposed on all interfaces, while preserving
  monitoring.
rationale: Restricting the metrics listener keeps etcd internals visible only to the
  intended scrapers, removing a free reconnaissance signal without losing any monitoring.
related_areas:
- talos-cluster
- observability
---

# Scope the etcd metrics endpoint to trusted listeners

## Metadata (observation-form, schema validation)

- [topic] Scope the etcd metrics endpoint to trusted listeners
- [status] proposed
- [priority] medium

## What we gain

- etcd internals (topology, sizes, leader state) are visible only to intended collectors.
- One fewer unauthenticated information source for anyone on the LAN.
- No monitoring loss — the Prometheus scrape path is preserved.

## What to do

1. Change etcd listen-metrics-urls from 0.0.0.0:2381 to 127.0.0.1 (or the LAN subnet) in the Talos machine config.
2. Confirm the kube-prometheus etcd scrape still reaches the endpoint; adjust the scrape target if needed.
3. Pair with host-firewall-baseline for belt-and-suspenders.
4. Verify: an off-node scrape fails; Prometheus etcd metrics still populate.

## Related

- relates_to [[talos-cluster]]
- relates_to [[observability]]
- relates_to [[host-firewall-baseline]]
