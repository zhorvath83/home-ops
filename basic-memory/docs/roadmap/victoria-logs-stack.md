---
title: victoria-logs-stack
type: roadmap
permalink: home-ops/docs/roadmap/victoria-logs-stack
topic: Adopt VictoriaLogs as the cluster log-aggregation stack
status: proposed
priority: medium
scope: Add a log-aggregation layer to the observability namespace. Today there is
  no log platform — diagnostics rely on kubectl logs per pod and flux events; logs
  are lost across Pod restarts. Adopt VictoriaLogs (common to bjw-s, onedr0p, buroa)
  with a vector or fluent-bit collector, Grafana data source wiring, retention sized
  for the single-node disk budget.
rationale: Log loss across Pod restarts is the largest current observability blind
  spot. kube-prometheus-stack covers metrics + Flux Alerts covers reconciliation events,
  but neither persists application logs. VictoriaLogs is the homelab consensus pick
  across all three reference clusters. Also prerequisite for future log-pattern alerting.
options:
- VictoriaLogs + vector — matches bjw-s/onedr0p/buroa pattern
- VictoriaLogs + fluent-bit — lower-footprint collector alternative
- Loki + Promtail — Grafana-native, heavier; rejected unless a Loki-only feature is
  needed
related_areas:
- observability
---

# Adopt VictoriaLogs as the cluster log-aggregation stack

## Metadata (observation-form, schema validation)
- [topic] Adopt VictoriaLogs as the cluster log-aggregation stack
- [status] proposed
- [priority] medium

## Scope
Add a log-aggregation layer to the observability namespace. Today the home-ops cluster has **no log platform at all** — diagnostics rely on `kubectl logs` per pod and on `flux events` for reconciliation traces. Once a Pod restarts or is rescheduled, logs from previous runs are lost.

VictoriaLogs is the choice common to all three reference clusters (bjw-s, onedr0p, buroa) under their observability namespace. The adoption work:

1. New `kubernetes/apps/observability/victoria-logs/` app folder following the canonical `ks.yaml` + `app/` shape
2. Log collector — `vector` or `fluent-bit` DaemonSet feeding into VictoriaLogs (the references all use `vector` as collector; confirm before committing)
3. Storage strategy — PVC vs S3-backed retention; size and retention values to align with the single-node disk budget
4. Grafana data source — wire VictoriaLogs as an additional Grafana data source, no AlertManager dependency
5. Exposure model — internal-only HTTPRoute via `envoy-internal` if a UI is desired, or kubectl port-forward only

## Rationale
Log loss across Pod restarts is the largest current observability blind spot. `kube-prometheus-stack` covers metrics + Flux Alerts covers reconciliation events, but neither persists application logs. VictoriaLogs is lightweight (single binary, low memory, no Elastic/Loki operator overhead) and is the homelab consensus pick in the three reference clusters.

This roadmap item is also a prerequisite for any future alerting that needs log-pattern matching (e.g. "alert on X log messages per minute in app Y").

## Options
1. **VictoriaLogs + vector** — single-binary log store + universal collector; matches the bjw-s/onedr0p/buroa pattern
2. **VictoriaLogs + fluent-bit** — same store, lower-footprint collector; alternative if vector resource use proves too high on the single node
3. **Loki + Promtail** — Grafana-native alternative; more components, heavier; rejected in advance unless a specific Loki-only feature is needed

## Related
- relates_to [[observability]]
