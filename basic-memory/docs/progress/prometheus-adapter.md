---
title: prometheus-adapter
type: progress
permalink: home-ops/docs/progress/prometheus-adapter
topic: Execution state for the prometheus-adapter roadmap (External Metrics API deploy
  + verify)
status: done
roadmap: '[[prometheus-adapter]]'
related_areas:
- observability
tags:
- progress
- observability
- prometheus-adapter
- external-metrics
- hpa
priority: medium
---

# prometheus-adapter

## Metadata

- [topic] Add prometheus-adapter to expose Prometheus metrics as the External Metrics API (deployed + verified)
- [status] done
- [priority] medium

## Scope

Deploy `prometheus-adapter` into the `observability` namespace, following the bjw-s reference shape (`kubernetes/apps/observability/prometheus-adapter/`):

- `ks.yaml` Flux Kustomization with `targetNamespace: observability`
- `app/helmrelease.yaml` referencing the `prometheus-adapter` chart via `OCIRepository` + minimal `values`
- `values.prometheus.url: http://prometheus-operated.observability.svc.cluster.local`, `port: 9090`
- `values.rules.default: false` — disable the chart's default rules
- One initial external rule for `probe_success` wrapped with `max_over_time(...[1m])` smoothing to avoid HPA flapping

bjw-s reference excerpt:

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

Future rules (custom HPA on app-specific Prometheus metrics) are added under the same `external:` list incrementally.

## Rationale

The cluster had no External Metrics API provider. Any `HorizontalPodAutoscaler` using `metrics[].type: External` could not resolve because the API server had no backend for `external.metrics.k8s.io`. This blocked the scale-to-zero-on-dependency pattern (see [[nfs-dependency-zeroscaler]]) and any future custom-metric HPA.

`prometheus-adapter` is the canonical bridge: it serves `external.metrics.k8s.io` by translating Prometheus queries into K8s metric values. Bjw-s, onedr0p, and buroa all run it for the same reason. The minimal-values pattern (only `default: false` + one rule) keeps the install footprint tiny and avoids exposing unneeded chart-default rules.

## Options

1. **bjw-s minimal pattern** — `default: false` + only the rules we actively use; lowest noise and memory footprint *(chosen)*
2. **Chart defaults enabled** — broader set of resource/custom/external rules out of the box; more memory, more noise, no direct benefit unless we discover a need

## Session 1 — deploy + verify (2026-07-11)

### Done

- Created [file] kubernetes/apps/observability/prometheus-adapter/{ks,app/kustomization,app/ocirepository,app/helmrelease}.yaml — Flux Kustomization (targetNamespace observability, dependsOn kube-prometheus-stack, interval 1h, wait false) + OCIRepository (oci://ghcr.io/prometheus-community/charts/prometheus-adapter tag 4.12.0) + minimal-spec HelmRelease.
- HelmRelease values: prometheus.url=http://prometheus-operated.observability.svc.cluster.local:9090, rules.default: false, one external rule (seriesQuery `{__name__="probe_success"}`, resources.namespaced false, name.as probe_success, metricsQuery `max_over_time(<<.Series>>{<<.LabelMatchers>>}[1m])`). resources 10m/64Mi req, 256Mi limit.
- Modified [file] kubernetes/apps/observability/kustomization.yaml — added `- ./prometheus-adapter/ks.yaml` after blackbox-exporter.
- Code commit 05e123e29 on main: `✨ feat(observability): add prometheus-adapter External Metrics API`. Pushed to origin/main. Pre-commit all Passed.
- [decision] No cert-manager and no CNP for the adapter — chart default insecureSkipTLSVerify + self-signed cert (matches bjw-s, which ships no CNP for the adapter). Added resources limit and dependsOn kube-prometheus-stack as deliberate policy choices beyond the bjw-s minimal pattern.

### Verify (live, post-deploy) — ALL PASS

- [observation] flux get ks -n observability prometheus-adapter → Ready, ReconciliationSucceeded. All 12 sibling observability KS Ready at the same revision.
- [observation] HelmRelease prometheus-adapter → ready=True, InstallSucceeded, version=1.
- [observation] APIService v1beta1.external.metrics.k8s.io → Available=True, Passed (adapter is the backend).
- [observation] prometheus-adapter pod Running 1/1.
- [observation] End-to-end external metric query: `kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/selfhosted/probe_success?labelSelector=job%3Dnfs_probe"` → returns ExternalMetricValueList, metricName probe_success, labels {instance: nas.lan:2049, job: nfs_probe, namespace: observability}, value "1". Proves the full chain adapter → external.metrics.k8s.io serves the blackbox probe metric.

### Follow-up

- [follow-up] Stale probe_success series with old job labels (nas, nfs) still appear in Prometheus instant queries — leftover samples from before the Probe rename, will age out within the ~5min staleness window. No action needed.

## Relations

- relates_to [[nfs-dependency-zeroscaler]]
- relates_to [[observability]]
- relates_to [[observability-probes-and-disk-health]]
