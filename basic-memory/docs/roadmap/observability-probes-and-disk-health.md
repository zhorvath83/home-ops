---
title: observability-probes-and-disk-health
type: roadmap
permalink: home-ops/docs/roadmap/observability-probes-and-disk-health
topic: Add blackbox-exporter (active probes) and smartctl-exporter (disk health)
status: proposed
priority: medium
scope: 'Extend observability with two exporters present in all three reference clusters:
  blackbox-exporter for active HTTP/TCP/DNS/ICMP probes (external + LAN routes, Cloudflare
  Tunnel health), and smartctl-exporter for SMART attribute scraping on the PC801/PC711
  NVMe pair (wear, reallocated sectors, temperature). Includes ServiceMonitor wiring,
  PrometheusRule additions (NVMe wear, disk temp, probe failure), and Grafana dashboards.'
rationale: No active HTTP probing today — silent 5xx on cloudflared/HTTPRoute/chart
  misconfiguration only surfaces via user reports. node-exporter default does not
  cover SMART attributes deeply; the PC801/PC711 NVMe pair is the single hardware
  failure boundary (etcd + every PVC), so SMART degradation lead time (wear, reallocated
  sectors) is the only early-warning signal we have. Both have low operational cost
  and are present in all three reference clusters.
options:
- Deploy both at once
- smartctl-exporter first (highest signal on single-node), blackbox-exporter second
  (after Pushover/Alertmanager routing is clarified)
related_areas:
- observability
- talos-cluster
---

# Add blackbox-exporter (active probes) and smartctl-exporter (disk health)

## Metadata (observation-form, schema validation)
- [topic] Add blackbox-exporter (active probes) and smartctl-exporter (disk health)
- [status] proposed
- [priority] medium

## Scope
Extend the `observability` namespace with two missing exporters that the three reference clusters (bjw-s, onedr0p, buroa) all run:

1. **blackbox-exporter** — active HTTP / HTTPS / TCP / DNS / ICMP probes. Targets defined as Prometheus `Probe` CRs or scrape config. Useful for: external endpoint uptime (e.g. paperless, plex public routes), Cloudflare Tunnel health from inside the cluster, LAN service reachability.
2. **smartctl-exporter** — SMART attribute scraper for SSD/NVMe health. Targets the two NVMe disks (PC801 OS+etcd, PC711 data PVCs) declared in the Talos machineconfig. Exposes wear-level, reallocated sectors, temperature, total bytes written.

Both come from `kube-prometheus-stack` adjacent ecosystem and integrate via `ServiceMonitor` (auto-scraped) and shipping Grafana dashboards.

The work:
- `kubernetes/apps/observability/blackbox-exporter/` — new app folder
- `kubernetes/apps/observability/smartctl-exporter/` — new app folder; needs privileged access to the host device nodes for SMART reads (`hostPID` or device mount)
- PrometheusRule additions: NVMe wear threshold alert, disk temperature alert, probe failure alert
- Grafana dashboards: blackbox SLO board + smartctl per-device board (chart-shipped or community)

## Rationale
- **blackbox-exporter**: today there is no active probing of any HTTP path; if cloudflared, an HTTPRoute, or an upstream chart misconfiguration silently 5xx's, only user-reported failure surfaces it. Single-node lab means external probes (UptimeRobot etc.) only catch internet-facing endpoints; LAN routes are invisible.
- **smartctl-exporter**: the PC801/PC711 NVMe pair is the single hardware failure boundary for the cluster (etcd + every PVC). SMART degradation lead time (reallocated sectors, wear%) is the only early signal we have before a disk drop takes the cluster down. Currently we get nothing — `node-exporter` default doesn't cover SMART attributes deeply.

Both have low operational cost; both are present in all three reference clusters' observability stacks.

## Options
The two exporters are independent; either could be deployed first if the work needs to be split. Recommended order: **smartctl-exporter first** (highest signal on a single-node cluster), **blackbox-exporter second** (after the Pushover/Alertmanager routing model is clarified — see [[pushover-provider-model-unify]], [[alertmanager-enable]]).

## Related
- relates_to [[observability]]
- relates_to [[talos-cluster]]
- relates_to [[pushover-provider-model-unify]]
- relates_to [[alertmanager-enable]]
