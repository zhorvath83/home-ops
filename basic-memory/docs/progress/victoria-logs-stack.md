---
title: victoria-logs-stack
type: roadmap
permalink: home-ops/docs/roadmap/victoria-logs-stack
topic: Adopt VictoriaLogs as the cluster log-aggregation stack
status: implemented
priority: medium
scope: Add a log-aggregation layer to the observability namespace. Today there is
  no log platform — diagnostics rely on kubectl logs per pod and flux events; logs
  are lost across Pod restarts. Adopt VictoriaLogs (common to bjw-s, onedr0p, buroa)
  with a victoria-logs-collector (vlagent) DaemonSet, Grafana data source wiring,
  retention sized for the single-node disk budget.
rationale: Log loss across Pod restarts is the largest current observability blind
  spot. kube-prometheus-stack covers metrics + Flux Alerts covers reconciliation events,
  but neither persists application logs. VictoriaLogs is the homelab consensus pick
  across all three reference clusters. Also prerequisite for future log-pattern alerting.
options:
- VictoriaLogs + victoria-logs-collector — matches bjw-s/onedr0p/buroa current implementation
- VictoriaLogs + fluent-bit — lower-footprint collector alternative
- Loki + Promtail — Grafana-native, heavier; rejected unless a Loki-only feature is
  needed
related_areas:
- observability
---

# Adopt VictoriaLogs as the cluster log-aggregation stack

## Metadata (observation-form, schema validation)

- [topic] Adopt VictoriaLogs as the cluster log-aggregation stack
- [status] implemented
- [priority] medium

## Scope

Add a log-aggregation layer to the observability namespace. Today the home-ops cluster has **no log platform at all** — diagnostics rely on `kubectl logs` per pod and on `flux events` for reconciliation traces. Once a Pod restarts or is rescheduled, logs from previous runs are lost.

VictoriaLogs is the choice common to all three reference clusters (bjw-s, onedr0p, buroa) under their observability namespace. The adoption work:

1. New `kubernetes/apps/observability/victoria-logs/` app folder following the canonical `ks.yaml` + `app/` shape
2. Log collector — `victoria-logs-collector` (vlagent) DaemonSet feeding into VictoriaLogs; all three reference clusters now use this instead of vector/fluent-bit
3. Storage strategy — 10Gi PVC with 14d retention, aligned with single-node disk budget
4. Grafana data source — wired as inline datasource with `victoriametrics-logs-datasource` plugin in the Grafana HelmRelease
5. Exposure model — internal-only HTTPRoute via `envoy-internal` with root redirect to `/select/vmui/`; Homepage integration with pod-selector

## Rationale

Log loss across Pod restarts is the largest current observability blind spot. `kube-prometheus-stack` covers metrics + Flux Alerts covers reconciliation events, but neither persists application logs. VictoriaLogs is lightweight (single binary, low memory, no Elastic/Loki operator overhead) and is the homelab consensus pick in the three reference clusters.

This roadmap item is also a prerequisite for any future alerting that needs log-pattern matching (e.g. "alert on X log messages per minute in app Y").

## Options

1. **VictoriaLogs + victoria-logs-collector** — single-binary log store + purpose-built vlagent collector; matches bjw-s/onedr0p/buroa current implementations
2. **VictoriaLogs + fluent-bit** — same store, lower-footprint collector; alternative used by some homelab repos (goochs, chr1sd, ahgraber)
3. **Loki + Promtail** — Grafana-native alternative; more components, heavier; rejected in advance unless a specific Loki-only feature is needed

## Related

- relates_to [[observability]]
