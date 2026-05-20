---
title: prometheus-adapter
type: roadmap
permalink: home-ops/docs/roadmap/prometheus-adapter
topic: Add prometheus-adapter to expose Prometheus metrics as External Metrics API
status: proposed
priority: medium
scope: 'Deploy prometheus-adapter into observability namespace following the bjw-s
  reference shape. Minimal values: default rules disabled, single external rule for
  probe_success wrapped with max_over_time(...[1m]) smoothing. OCIRepository-backed
  HelmRelease. Future custom-metric HPA rules added under the same external: list
  incrementally.'
rationale: 'Cluster has no External Metrics API provider today; any HPA with metrics[].type:
  External cannot resolve. This blocks scale-to-zero-on-dependency (nfs-dependency-zeroscaler)
  and any future custom-metric HPA. prometheus-adapter is the canonical bridge that
  translates Prometheus queries into external.metrics.k8s.io values. Same approach
  in bjw-s, onedr0p, buroa.'
options:
- 'bjw-s minimal pattern — default: false + only actively-used rules; smallest footprint'
- Chart defaults enabled — broader rule set out of the box; more memory and noise,
  no direct benefit
related_areas:
- observability
---

# Add prometheus-adapter to expose Prometheus metrics as External Metrics API

## Metadata (observation-form, schema validation)
- [topic] Add prometheus-adapter to expose Prometheus metrics as External Metrics API
- [status] proposed
- [priority] medium

## Scope
Deploy `prometheus-adapter` into the `observability` namespace, following the bjw-s reference shape (`kubernetes/apps/observability/prometheus-adapter/`):

- `ks.yaml` Flux Kustomization with `targetNamespace: observability`
- `app/helmrelease.yaml` referencing the `prometheus-adapter` chart via `OCIRepository` + minimal `values`
- `values.prometheus.url: http://prometheus-operated.observability.svc.cluster.local`, `port: 9090`
- `values.rules.default: false` — disable the chart's default rules (none of them are wanted today)
- One initial external rule for `probe_success` (the metric blackbox-exporter emits), wrapped with `max_over_time(<<.Series>>{<<.LabelMatchers>>}[1m])` smoothing to avoid HPA flapping

Bjw-s reference excerpt:

```yaml
rules:
  default: false
  external:
    - seriesQuery: '{__name__="probe_success"}'
      resources:
        namespaced: false
      name:
        as: probe_success
      metricsQuery: max_over_time(<<.Series>>{<<.LabelMatchers>>}[1m])
```

Future rules (custom HPA on app-specific Prometheus metrics) can be added under the same `external:` list incrementally.

## Rationale
The cluster has no External Metrics API provider today. Any `HorizontalPodAutoscaler` using `metrics[].type: External` cannot resolve because the API server has no backend for `external.metrics.k8s.io`. This blocks the entire scale-to-zero-on-dependency pattern (see [[nfs-dependency-zeroscaler]]) and any future custom-metric HPA.

`prometheus-adapter` is the canonical bridge: it serves the `external.metrics.k8s.io` API by translating Prometheus queries into K8s metric values. Bjw-s, onedr0p, and buroa all run it for the same reason.

The minimal-values pattern (only `default: false` + one rule) keeps the install footprint tiny and avoids exposing unneeded chart-default rules.

## Options
1. **bjw-s minimal pattern** — `default: false` + only the rules we actively use; lowest noise and memory footprint
2. **Chart defaults enabled** — exposes a broader set of resource/custom/external rules out of the box; more memory, more noise, no direct benefit unless we discover a need

## Related
- relates_to [[observability]]
- relates_to [[observability-probes-and-disk-health]]
