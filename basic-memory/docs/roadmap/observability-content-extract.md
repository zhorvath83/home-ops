---
title: observability-content-extract
type: roadmap
permalink: home-ops/docs/roadmap/observability-content-extract
topic: kube-prometheus-stack observability content extract (M1)
status: proposed
scope: 'Refactor `kubernetes/apps/observability/kube-prometheus-stack/app/` toward
  the bjw-s minimalist parity: extract the inline `additionalScrapeConfigs.openwrt`
  block (helmrelease.yaml:363-370) into a `ScrapeConfig` CR under `app/scrapeconfigs/openwrt.yaml`,
  and add a minimum `PrometheusRule` set under `app/prometheusrules/` with at least
  an OOMKilled rule (single-node stability signal). Optional second rule: ZFS health,
  contingent on `node-exporter --collector.zfs` being enabled.'
priority: medium
rationale: 'Inline ScrapeConfig in the HelmRelease is brittle on chart upgrades (Renovate-blocking);
  pulling it out makes it Renovate-neutral and consistent with PodMonitor/ServiceMonitor
  primitives. OOMKilled alert is high-value on a single-node where one runaway pod
  can take out unrelated workloads. Estimated effort: ~1-1.5 hours.'
related_areas:
- observability
- flux-gitops
---

# kube-prometheus-stack observability content extract (M1)

## Metadata (observation-form, schema validation)

- [topic] kube-prometheus-stack observability content extract (M1)
- [status] proposed
- [priority] medium

## Scope

Refactor `kubernetes/apps/observability/kube-prometheus-stack/app/` toward the bjw-s minimalist parity: extract the inline `additionalScrapeConfigs.openwrt` block (helmrelease.yaml:363-370) into a `ScrapeConfig` CR under `app/scrapeconfigs/openwrt.yaml`, and add a minimum `PrometheusRule` set under `app/prometheusrules/` with at least an OOMKilled rule (single-node stability signal). Optional second rule: ZFS health, contingent on `node-exporter --collector.zfs` being enabled.

## Rationale

Inline ScrapeConfig in the HelmRelease is brittle on chart upgrades (Renovate-blocking); pulling it out makes it Renovate-neutral and consistent with PodMonitor/ServiceMonitor primitives. OOMKilled alert is high-value on a single-node where one runaway pod can take out unrelated workloads. Estimated effort: ~1-1.5 hours.

## Explicit scope-bounds (NOT in 16.e)

- AlertmanagerConfig CR — AlertManager is currently disabled (HR `alertmanager.enabled: false`); enabling is its own roadmap item (alertmanager-enable, N1 audit point)
- GrafanaDashboard / GrafanaDatasource CRs — would require Grafana Operator, but we run standalone Grafana with ConfigMap-discovery (`grafana_dashboard: "1"` label) and HR `values.datasources`

## Related

- relates_to [[observability]]
- relates_to [[flux-gitops]]
