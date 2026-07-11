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

## Execution plan (research-backed)

### Current state
- etcd metrics listen on all interfaces, unauthenticated: `kubernetes/talos/machineconfig.yaml.j2:147` → `etcd.extraArgs.listen-metrics-urls: http://0.0.0.0:2381`. etcd advertises client traffic only on `192.168.1.0/24` (line 139-140) and requires mTLS on 2379.
- On this single-NIC node, `0.0.0.0` and `192.168.1.11` are nearly the same exposure; the meaningful reduction is (a) not exposing it off-LAN, and (b) not exposing it to arbitrary pods.

### Target state
- The :2381 metrics endpoint is reachable only by the intended scraper, not by any LAN host or arbitrary pod, without losing etcd monitoring.

### Implementation steps
1. **Determine HOW etcd is scraped first** — this decides the correct fix:
   ```bash
   kubectl -n observability get servicemonitor,scrapeconfig -o name | grep -i etcd
   kubectl -n observability get prometheus -o yaml | grep -iA3 etcd
   ```
   kube-prometheus-stack's `kubeEtcd` typically scrapes the node IP:2381 from the Prometheus pod. If so, rebinding to 127.0.0.1 **breaks the scrape** — do NOT naively set loopback.
2. **Preferred: gate it with the host firewall** (see `host-firewall-baseline`) — keep `listen-metrics-urls` on the node IP but restrict :2381 to the POD/SVC CIDR only, so LAN hosts can't scrape it but Prometheus can. This is the correct fix if scraping uses the node IP.
   - Add `2381` to the `NetworkRuleConfig` that allows the pod/svc CIDRs, and DROP it for the LAN range (or omit :2381 from the LAN allow rule).
3. **Alternative: bind to loopback** `http://127.0.0.1:2381` **only if** you also relocate scraping (e.g. a host-network exporter/sidecar on the node) — more work; usually not worth it here.
4. Whichever path: dry-run `just talos render-config k8s-cp0`, then user-approved `just talos apply-node k8s-cp0` (networking-phase, no reboot).

### Verification
- From a LAN host (not a pod): `curl -s http://192.168.1.11:2381/metrics` → connection refused/filtered.
- Prometheus etcd target stays Up: `kubectl -n observability exec <prometheus-pod> -- wget -qO- localhost:9090/api/v1/targets | grep etcd` (or the Grafana etcd dashboard keeps populating).

### Rollback & safety
- Revert the arg / firewall rule and re-apply. Networking-phase, no reboot.
- Risk: losing the etcd scrape if you rebind without moving the scraper — hence step 1 gating.

### Gotchas & dependencies
- Best implemented together with `host-firewall-baseline` (the firewall is the clean gate).

### Effort
S (~1–2h, mostly verifying the scrape path; folds into the host-firewall work).
