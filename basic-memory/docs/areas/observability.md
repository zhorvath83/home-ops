---
title: observability
type: area_reference
permalink: home-ops/docs/areas/observability
area: observability
status: current
confidence: high
verified_at: '2026-07-05'
summary: Observability for the cluster splits into four workloads under kubernetes/apps/observability/
  — kube-prometheus-stack (operator + Prometheus + Alertmanager + kube-state-metrics
  + node-exporter, minimal single-node configuration), a standalone grafana (with
  admin password from ExternalSecret), a speedtest-exporter for WAN throughput metrics,
  and victoria-logs (single-node server + per-node collector DaemonSet) for the logs
  plane. PrometheusRules and ServiceMonitors are scattered across platform subtrees
  (volsync-system, external-secrets, etc.) instead of being centralized here. Pushover
  alerting goes through Flux's flux-alerts component, not Alertmanager.
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
- kubernetes/apps/observability/victoria-logs/app/helmrelease.yaml
- kubernetes/apps/observability/victoria-logs/app/ocirepository.yaml
- kubernetes/apps/observability/victoria-logs/collector/helmrelease.yaml
- kubernetes/CLAUDE.md ("Current Reality" section)
drift_risk: The minified kube-prometheus-stack disables most default rules and exporters
  (tuned for one node) and ships Alertmanager disabled, so Prometheus-rule alerting
  is effectively off — only Flux failures page via Pushover (flux-alerts). Per-platform
  ServiceMonitors/PrometheusRules are scattered with no inventory. Prometheus (7d/4500MB)
  and victoria-logs (14d) retention are fixed sizes that need revisiting as volume
  grows; chart OCI tags are Renovate-tracked and a major bump can shift CRDs or values
  schema.
tags:
- area-reference
- observability
- platform
---

# observability — current state

## Metadata (observation-form, schema validation)

- [area] observability
- [status] current
- [confidence] high
- [verified_at] 2026-07-05

## Status

Promoted from draft to current on 2026-06-20 after a full manifest verification pass — every sub-Kustomization under `kubernetes/apps/observability/` was read end to end. The logs plane (`victoria-logs`) was added since the previous draft and is now captured, and the metrics/Grafana facts were re-verified with file+line evidence. Remaining gaps are live-state only (see Open Questions).

Re-verified 2026-07-05: the speedtest-exporter public route (speed.${PUBLIC_DOMAIN}) was removed — the HTTPRoute block and the ingress.home.arpa/gateways label were dropped from its HelmRelease, leaving the exporter scrape-only (Prometheus scrapes the in-cluster Service via ServiceMonitor). The ingress.home.arpa/prometheus and egress.home.arpa/allow-world (Ookla servers) labels remain. grafana and victoria-logs exposure is unchanged.


## Summary

The cluster's observability stack lives under `kubernetes/apps/observability/` as four sub-Kustomizations:

- `kube-prometheus-stack` — upstream chart `oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack` (v86.3.2), a "minified" single-node homelab variant: most `defaultRules` and the kube-apiserver / kubelet / etcd / kube-controller-manager / scheduler / proxy / coredns exporters are disabled; only the `k8s`, `kubernetesApps`, `kubeStateMetrics`, `prometheusOperator`, and `prometheus` rule groups survive. `cleanPrometheusOperatorObjectNames: true`. Prometheus retention is now explicit: 7d / 4500MB on a 5Gi `democratic-csi-local-hostpath` PVC. Alertmanager is shipped by the chart but disabled.
- `grafana` — standalone chart (v12.4.8), admin password from ExternalSecret `grafana-secret`, telemetry off (`GF_ANALYTICS_*` false), hardened (read-only rootfs, drop ALL caps, RuntimeDefault). Datasources: Prometheus (default) plus a VictoriaLogs datasource (plugin preinstalled). Dashboards auto-discovered via the sidecar (`grafana_dashboard` label, all namespaces). `GF_SERVER_ROOT_URL = https://grafana.${PUBLIC_DOMAIN}`. Depends on kube-prometheus-stack + onepassword-connect.
- `speedtest-exporter` — bjw-s `app-template` (image v3.5.4), WAN throughput metrics on a 20m scrape interval, hardened (nonRoot 10001, read-only rootfs, drop ALL). No `dependsOn`.
- `victoria-logs` — the logs plane, added since the previous pass. A single-node server (`victoria-logs-single` v0.13.8, 10Gi PVC, 14d retention) plus a per-node collector DaemonSet (`victoria-logs-collector` v0.3.6) that remote-writes to `http://victoria-logs-server.observability.svc.cluster.local:9428`. The collector `dependsOn` the server.

The namespace is `observability` and pulls in the shared `common` component (which carries `flux-alerts` → Pushover for Flux reconciliation failures). Prometheus-side alerting via Alertmanager is intentionally off; only Flux-level failures page. PrometheusRules and ServiceMonitors are NOT centralized here — each platform publishes its own (the only monitor committed in this subtree is a PodMonitor for flux-system). Exposure: `grafana.${PUBLIC_DOMAIN}` on both gateways; `logs.${PUBLIC_DOMAIN}` on the internal gateway only. The speedtest-exporter is scrape-only (no public route; Prometheus scrapes the in-cluster Service via ServiceMonitor).


## Components

- [component] kube-prometheus-stack — operator + Prometheus + kube-state-metrics + node-exporter; chart v86.3.2, minified homelab tuning, Prometheus 7d/4500MB retention on 5Gi local-hostpath PVC, Alertmanager disabled (kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml)
- [component] grafana — standalone chart v12.4.8, admin password from ExternalSecret grafana-secret, telemetry off, hardened; Prometheus + VictoriaLogs datasources, sidecar dashboard discovery, exposed grafana.${PUBLIC_DOMAIN} on both gateways (kubernetes/apps/observability/grafana/)
- [component] speedtest-exporter — bjw-s app-template, WAN throughput metrics, 20m scrape, scrape-only (no public route; Prometheus scrapes the in-cluster Service via ServiceMonitor), AD-023 labels ingress.home.arpa/prometheus + egress.home.arpa/allow-world (kubernetes/apps/observability/speedtest-exporter/)
- [component] victoria-logs server — victoria-logs-single v0.13.8, 10Gi PVC, 14d retention, serviceMonitor on, exposed logs.${PUBLIC_DOMAIN} on the internal gateway only with a / → /select/vmui/ redirect (kubernetes/apps/observability/victoria-logs/app/)
- [component] victoria-logs collector — victoria-logs-collector v0.3.6 DaemonSet, PodMonitor on, remote-writes to victoria-logs-server:9428, dependsOn the server (kubernetes/apps/observability/victoria-logs/collector/)
- [component] Namespace marker — namespace.yaml uses the `_` placeholder; real name comes from the Flux Kustomization spec.targetNamespace (kubernetes/apps/observability/namespace.yaml)
- [component] common component — pulled in via kustomization.yaml; carries cluster vars + repos + flux-alerts (Pushover) for this namespace
- [component] flux-system PodMonitor — the only monitor committed under observability/ itself (kubernetes/apps/observability/kube-prometheus-stack/app/podmonitor.yaml)
- [component] Distributed ServiceMonitors/PrometheusRules — enabled chart-side per owning platform (volsync, external-secrets, kopia, victoria-logs), discovered by the operator; no central rules directory here


## Claims (verified against repo)

- [claim] "The observability area now deploys four sub-Kustomizations: kube-prometheus-stack, grafana (dependsOn kube-prometheus-stack + onepassword-connect), speedtest-exporter (no dependsOn), and victoria-logs (server + collector DaemonSet, collector dependsOn server)" (evidence: repo, ref: kubernetes/apps/observability/kustomization.yaml + each ks.yaml, verified: 2026-06-20)
- [claim] "kube-prometheus-stack is a minified single-node variant — chart v86.3.2, most defaultRules + the kube-apiserver/kubelet/etcd/etc. exporters disabled, only k8s/kubernetesApps/kubeStateMetrics/prometheusOperator/prometheus rule groups kept, cleanPrometheusOperatorObjectNames: true" (evidence: repo, ref: kube-prometheus-stack/app/helmrelease.yaml + ocirepository.yaml, verified: 2026-06-20)
- [claim] "Prometheus retention is explicit: 7d / 4500MB on a 5Gi democratic-csi-local-hostpath PVC" (evidence: repo, ref: kube-prometheus-stack/app/helmrelease.yaml:424-443, verified: 2026-06-20)
- [claim] "Grafana (chart v12.4.8) has telemetry disabled (GF_ANALYTICS_* false), admin password from existingSecret grafana-secret, read-only rootfs + drop ALL caps + RuntimeDefault, and serves both a Prometheus (default) and a VictoriaLogs datasource" (evidence: repo, ref: grafana/app/helmrelease.yaml, verified: 2026-06-20)
- [claim] "victoria-logs is the logs plane: a victoria-logs-single server (v0.13.8, 10Gi PVC, 14d retention) plus a victoria-logs-collector DaemonSet (v0.3.6) that remote-writes to victoria-logs-server:9428; the collector dependsOn the server" (evidence: repo, ref: victoria-logs/app/ + victoria-logs/collector/, verified: 2026-06-20)
- [claim] "Exposure: grafana.${PUBLIC_DOMAIN} attaches to both gateways; victoria-logs (logs.${PUBLIC_DOMAIN}) attaches to envoy-internal only — the logs UI is not published externally. The speedtest-exporter has no public route (scrape-only: Prometheus scrapes the in-cluster Service via ServiceMonitor)" (evidence: repo, ref: grafana + victoria-logs/app helmrelease.yaml route blocks + speedtest-exporter/app/helmrelease.yaml, verified: 2026-07-05)
- [claim] "The observability namespace pulls in the shared common component (flux-alerts → Pushover); Flux reconciliation failures page, but Prometheus Alertmanager is disabled so Prometheus-rule alerting is effectively off" (evidence: repo, ref: kubernetes/apps/observability/kustomization.yaml + kube-prometheus-stack/app/helmrelease.yaml, verified: 2026-06-20)
- [claim] "PrometheusRules/ServiceMonitors are NOT centralized here — the only monitor committed under observability/ is a flux-system PodMonitor; platforms publish their own" (evidence: repo, ref: kube-prometheus-stack/app/podmonitor.yaml + observability subtree listing, verified: 2026-06-20)


## Drift Risk

- [drift] The minified kube-prometheus-stack disables most default alerting rules and exporters — intentional for one node, but a blind spot if the cluster ever scales to multi-node or if a platform needs its own alerts.
- [drift] Alertmanager is shipped by the chart but disabled; Flux failures page via Pushover (flux-alerts) while Prometheus-rule alerting is effectively off. Closing that gap needs an explicit Alertmanager route or an alternative rule sink.
- [drift] Per-platform ServiceMonitors and PrometheusRules are scattered with no inventory — an app that omits its own ServiceMonitor is silently unmonitored.
- [drift] Prometheus (7d/4500MB on 5Gi) and victoria-logs (14d on 10Gi) retention are fixed sizes tuned for current volume; revisit if metric/log volume grows or the local-hostpath PVC fills.
- [drift] Chart tags (kube-prometheus-stack, grafana, victoria-logs server/collector, speedtest-exporter image) are Renovate-tracked OCI refs — a major bump can change CRDs or values schema; review before merging.


## Open Questions / Gaps

- [gap] Live-state validation not performed (Prometheus actually scraping all targets, victoria-logs collector ingesting every namespace, Grafana dashboards rendering) — repo evidence only.
- [gap] Whether the cluster log pipeline indexes security-namespace audit logs (e.g. TinyAuth) into victoria-logs is unconfirmed — cross-reference docs/areas/iam.
- [gap] No .claude/skills/observability/ exists; procedural guidance lives only in this note + per-component manifest comments.


## Relations

- depends_on [[external-secrets]]
- relates_to [[k8s-workloads]]
- relates_to [[flux-gitops]]
- relates_to [[volsync-backup]]
- part_of [[home-ops-platform]]
