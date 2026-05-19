---
title: observability
type: area_reference
permalink: home-ops/docs/areas/observability
area: observability
status: draft
confidence: low
verified_at: '2026-05-20'
summary: Draft stub. Observability for the cluster splits into three workloads under
  kubernetes/apps/observability/ — kube-prometheus-stack (operator + Prometheus +
  Alertmanager + kube-state-metrics + node-exporter, minimal single-node configuration),
  a standalone grafana (with admin password from ExternalSecret), and a speedtest-exporter
  for WAN throughput metrics. PrometheusRules and ServiceMonitors are scattered across
  platform subtrees (volsync-system, external-secrets, etc.) instead of being centralized
  here. Pushover alerting goes through Flux's flux-alerts component, not Alertmanager.
verified_against:
- kubernetes/apps/observability/kustomization.yaml
- kubernetes/apps/observability/namespace.yaml
- kubernetes/apps/observability/kube-prometheus-stack/ks.yaml
- kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml
- kubernetes/apps/observability/kube-prometheus-stack/app/podmonitor.yaml
- kubernetes/apps/observability/grafana/ks.yaml
- kubernetes/apps/observability/grafana/app/helmrelease.yaml
- kubernetes/apps/observability/grafana/app/externalsecret.yaml
- kubernetes/apps/observability/speedtest-exporter/ks.yaml
- kubernetes/apps/observability/speedtest-exporter/app/helmrelease.yaml
- kubernetes/CLAUDE.md ("Current Reality" section)
drift_risk: This note is a draft stub — only the high-level shape is captured, not
  the per-component configuration, retention policy, scrape targets, or alerting routing.
  The chart's minimal-config approach (most defaultRules disabled) was tuned for a
  single-node homelab and will produce blind spots if multi-node is ever introduced.
  Alertmanager is deployed by the kube-prometheus-stack chart but the primary alerting
  channel is Flux-side Pushover via flux-alerts; the relationship between the two
  paths is not documented and risks duplicated or missing alerts.
tags:
- area-reference
- observability
- draft
- platform
---

# observability — current state (DRAFT)

## Metadata (observation-form, schema validation)
- [area] observability
- [status] draft
- [confidence] low
- [verified_at] 2026-05-20

## Status
This note is intentionally a stub. Only the high-level shape of the observability area is captured. A future pass should expand the per-component configuration (Prometheus retention, scrape configs, default rule set selection, Grafana dashboards, Alertmanager routing).

## Summary
The cluster's observability stack lives under `kubernetes/apps/observability/` and consists of three sub-Kustomizations:

- `kube-prometheus-stack` — the upstream kube-prometheus-stack Helm chart, configured as a "minified" single-node homelab variant per Eirik Albrigtsen's pattern (referenced as a comment in the HelmRelease values). Most of the chart's heavy default rule groups are disabled (`alertmanager: false`, `etcd: false`, `general: false`, the kube-apiserver group, kubeControllerManager, kubelet, kubePrometheusGeneral, etc.); the surviving rules are the `k8s` core plus a few container/pod-level memory rules. `cleanPrometheusOperatorObjectNames: true`.
- `grafana` — standalone HelmRelease using the upstream Grafana chart, admin password supplied from a 1Password-backed Secret `grafana-secret`, hardened container security context (readOnlyRootFilesystem, RuntimeDefault seccomp, drop all caps), telemetry disabled (`GF_ANALYTICS_*` env vars). Depends on `kube-prometheus-stack` + `onepassword-connect`.
- `speedtest-exporter` — small workload exposing WAN throughput metrics for Prometheus scraping; no external dependency.

The namespace is `observability`. The shared `flux-alerts` component is attached to this namespace too — Flux reconciliation failures here surface via Pushover, the same channel the rest of the cluster uses. PrometheusRules and ServiceMonitors are intentionally **not** centralized in this area — each platform subtree publishes its own (e.g. `kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml` for VolSync, the external-secrets chart values enable a chart-side ServiceMonitor + Grafana dashboard).

## Components
- [component] kube-prometheus-stack — operator, Prometheus, Alertmanager, kube-state-metrics, node-exporter; minimal homelab tuning (kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml)
- [component] grafana — standalone HelmRelease, admin password from `grafana-secret` (1Password-backed ExternalSecret), depends on kube-prometheus-stack + onepassword-connect (kubernetes/apps/observability/grafana/)
- [component] speedtest-exporter — WAN throughput metrics for Prometheus (kubernetes/apps/observability/speedtest-exporter/)
- [component] Namespace marker — `kubernetes/apps/observability/namespace.yaml` (placeholder; actual name from Flux `spec.targetNamespace`)
- [component] flux-alerts component — pulled in via `kubernetes/apps/observability/kustomization.yaml` (Pushover alerting on this namespace)
- [component] Distributed PrometheusRules — published per platform (notably `kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml`); no central rules directory under `observability/` itself
- [component] Distributed ServiceMonitors — enabled chart-side by individual platform apps (external-secrets, volsync, kopia browser); discovered by the kube-prometheus-stack operator

## Claims (verified against repo)
- [claim] "The observability area deploys three sub-Kustomizations: `kube-prometheus-stack`, `grafana` (depends on kube-prometheus-stack + onepassword-connect), and `speedtest-exporter` (no explicit dependsOn)" (evidence: repo, ref: kubernetes/apps/observability/kustomization.yaml + each ks.yaml, verified: 2026-05-20)
- [claim] "The kube-prometheus-stack HelmRelease is configured as a minified single-node homelab variant — most upstream defaultRules are disabled (alertmanager, etcd, general, kube-apiserver group, kubelet, kubePrometheusGeneral); only the k8s core plus a couple of container memory rules remain" (evidence: repo, ref: kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml:21-40, verified: 2026-05-20)
- [claim] "Grafana telemetry is explicitly disabled (`GF_ANALYTICS_CHECK_FOR_UPDATES`, `GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES`, `GF_ANALYTICS_REPORTING_ENABLED` all false), admin password comes from `grafana-secret` (existingSecret), container runs read-only with drop ALL caps and RuntimeDefault seccomp" (evidence: repo, ref: kubernetes/apps/observability/grafana/app/helmrelease.yaml:12-32, verified: 2026-05-20)
- [claim] "The observability namespace also pulls in the shared `flux-alerts` component — Flux reconciliation failures here go to Pushover, same as the rest of the cluster" (evidence: repo, ref: kubernetes/apps/observability/kustomization.yaml:11-12, verified: 2026-05-20)
- [claim] "PrometheusRules are NOT centralized in the observability subtree — they live next to their owning platform (e.g. VolSync's PrometheusRule lives in `kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml`)" (evidence: repo, ref: kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml + observability subtree listing, verified: 2026-05-20)

## Drift Risk
- [drift] Most of kube-prometheus-stack's default alerting rules are disabled — this is intentional for a single-node homelab but creates blind spots if the cluster ever scales to multi-node or if platform components need their own alerts.
- [drift] Alertmanager is deployed by the chart but the primary cluster-wide alerting path is Flux-side Pushover via the `flux-alerts` component. The relationship between the two paths is not documented — alerts could be duplicated or missing depending on where they are defined.
- [drift] Per-platform ServiceMonitors and PrometheusRules are scattered across subtrees with no inventory. An app that fails to enable its own ServiceMonitor is invisible.
- [drift] Storage strategy for Prometheus (retention, PVC vs emptyDir) was not inspected in this draft pass.
- [drift] Grafana dashboard provisioning was not inspected — the chart supports sidecar-based dashboard discovery via ConfigMap labels, but whether any dashboards are committed to repo or only created at runtime is unknown.

## Open Questions / Gaps
- [gap] Per-component configuration (Prometheus retention, scrape configs, Alertmanager routing, Grafana data sources, dashboard provisioning, exposure model) — all deferred to a future expansion pass.
- [gap] Exact list of ServiceMonitors and PrometheusRules across the cluster — needs a manifest sweep `grep -r 'kind: PrometheusRule\|kind: ServiceMonitor' kubernetes/`.
- [gap] Whether Alertmanager is actually receiving alerts and to where (Pushover via flux-alerts handles **Flux** events, but Prometheus alerts go through Alertmanager) — needs live-state validation.
- [gap] No `.claude/skills/observability/` exists today; documentation for the area lives only in this draft + per-component manifest comments.
- [gap] Speedtest-exporter scrape target and Grafana dashboard wiring not inspected.

## Relations
- depends_on [[external-secrets]]
- relates_to [[k8s-workloads]]
- relates_to [[flux-gitops]]
- relates_to [[volsync-backup]]
- part_of [[home-ops-platform]]
