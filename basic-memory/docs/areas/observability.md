---
title: observability
type: area_reference
permalink: home-ops/docs/areas/observability
area: observability
status: current
confidence: high
verified_at: '2026-07-10'
summary: Observability for the cluster splits into four workloads under kubernetes/apps/observability/
  — kube-prometheus-stack (operator + Prometheus + Alertmanager + kube-state-metrics
  + node-exporter, minimal single-node configuration), a standalone grafana (with
  admin password from ExternalSecret), a speedtest-exporter for WAN throughput metrics,
  and victoria-logs (single-node server + per-node collector DaemonSet) for the logs
  plane. PrometheusRules and ServiceMonitors are scattered across platform subtrees
  (volsync-system, external-secrets, etc.) instead of being centralized here. Pushover
  alerting routes through the in-cluster Alertmanager (pushover default
  receiver); Flux reconciliation failures use a Flux type:alertmanager Provider
  into the same Alertmanager.
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
  (tuned for one node) and ships Alertmanager enabled (pushover default receiver; Flux
  reconciliation failures route through the same Alertmanager via a Flux
  type:alertmanager Provider). Per-platform
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

- `kube-prometheus-stack` — upstream chart `oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack`, a "minified" single-node homelab variant: most `defaultRules` and the kube-apiserver / kubelet / etcd / kube-controller-manager / scheduler / proxy / coredns exporters are disabled; only the `k8s`, `kubernetesApps`, `kubeStateMetrics`, `prometheusOperator`, and `prometheus` rule groups survive. `cleanPrometheusOperatorObjectNames: true`. Prometheus retention is now explicit: 7d / 4500MB on a 5Gi `democratic-csi-local-hostpath` PVC. Alertmanager is enabled (see update section).
- `grafana` — **operator-managed** (grafana-operator, `operator/`+`instance/` split). Stateless `Grafana` CR (emptyDir DB, no PVC), telemetry off, hardened (read-only rootfs, drop ALL, RuntimeDefault). Datasources (`Prometheus` default, `Alertmanager`), dashboards, and folders are declarative CRs (`GrafanaDatasource`/`GrafanaDashboard`/`GrafanaFolder`) co-located with the owning app; the operator provisions them via the Grafana API using the `grafana-secret` admin creds. **No plugins** (D13) + `preinstall_disabled` — zero grafana.com startup egress; no VictoriaLogs datasource (logs stay in the vmui). **SSO via Pocket-ID OIDC** (`auth.generic_oauth`), local login form hidden (`disable_login_form: true`). `root_url = https://grafana.${PUBLIC_DOMAIN}`, internal gateway only. Depends on grafana-operator + kube-prometheus-stack + onepassword-connect.
- `speedtest-exporter` — bjw-s `app-template`, WAN throughput metrics on a 20m scrape interval, hardened (nonRoot 10001, read-only rootfs, drop ALL). No `dependsOn`.
- `victoria-logs` — the logs plane, added since the previous pass. A single-node server (`victoria-logs-single`, 10Gi PVC, 14d retention) plus a per-node collector DaemonSet (`victoria-logs-collector`) that remote-writes to `http://victoria-logs-server.observability.svc.cluster.local:9428`. The collector `dependsOn` the server.

The namespace is `observability` and pulls in the shared `common` component (which carries `alerts/alertmanager` → in-cluster Alertmanager for Flux reconciliation failures, plus `alerts/github` for commit-status). Prometheus-side alerting is on via Alertmanager (pushover default receiver, Watchdog/InfoInhibitor→blackhole); Flux reconciliation failures route through the same Alertmanager. PrometheusRules and ServiceMonitors are NOT centralized here — each platform publishes its own (the only monitor committed in this subtree is a PodMonitor for flux-system). Exposure: `grafana.${PUBLIC_DOMAIN}` on both gateways; `logs.${PUBLIC_DOMAIN}` on the internal gateway only. The speedtest-exporter is scrape-only (no public route; Prometheus scrapes the in-cluster Service via ServiceMonitor).


## Components

- [component] kube-prometheus-stack — operator + Prometheus + kube-state-metrics + node-exporter; chart, minified homelab tuning, Prometheus 7d/4500MB retention on 5Gi local-hostpath PVC, Alertmanager enabled (internal-gateway route, 1Gi PVC, AlertmanagerConfig with pushover receiver) (kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml)
- [component] grafana — standalone chart, admin password from ExternalSecret grafana-secret, telemetry off, hardened; Prometheus + VictoriaLogs datasources, sidecar dashboard discovery, exposed grafana.${PUBLIC_DOMAIN} on both gateways (kubernetes/apps/observability/grafana/)
- [component] speedtest-exporter — bjw-s app-template, WAN throughput metrics, 20m scrape, scrape-only (no public route; Prometheus scrapes the in-cluster Service via ServiceMonitor), AD-023 labels ingress.home.arpa/prometheus + egress.home.arpa/allow-world (kubernetes/apps/observability/speedtest-exporter/)
- [component] victoria-logs server — victoria-logs-single, 10Gi PVC, 14d retention, serviceMonitor on, exposed logs.${PUBLIC_DOMAIN} on the internal gateway only with a / → /select/vmui/ redirect (kubernetes/apps/observability/victoria-logs/app/)
- [component] victoria-logs collector — victoria-logs-collector DaemonSet, PodMonitor on, remote-writes to victoria-logs-server:9428, dependsOn the server (kubernetes/apps/observability/victoria-logs/collector/)
- [component] Namespace marker — namespace.yaml uses the `_` placeholder; real name comes from the Flux Kustomization spec.targetNamespace (kubernetes/apps/observability/namespace.yaml)
- [component] common component — pulled in via kustomization.yaml; carries cluster vars + repos + alerts/alertmanager (Flux type:alertmanager Provider → in-cluster Alertmanager) + alerts/github for this namespace
- [component] flux-system PodMonitor — the only monitor committed under observability/ itself (kubernetes/apps/observability/kube-prometheus-stack/app/podmonitor.yaml)
- [component] Distributed ServiceMonitors/PrometheusRules — enabled chart-side per owning platform (volsync, external-secrets, kopia, victoria-logs), discovered by the operator; no central rules directory here


## Claims (verified against repo)

- [claim] "The observability area now deploys four sub-Kustomizations: kube-prometheus-stack, grafana (dependsOn kube-prometheus-stack + onepassword-connect), speedtest-exporter (no dependsOn), and victoria-logs (server + collector DaemonSet, collector dependsOn server)" (evidence: repo, ref: kubernetes/apps/observability/kustomization.yaml + each ks.yaml, verified: 2026-06-20)
- [claim] "kube-prometheus-stack is a minified single-node variant — chart, most defaultRules + the kube-apiserver/kubelet/etcd/etc. exporters disabled, only k8s/kubernetesApps/kubeStateMetrics/prometheusOperator/prometheus rule groups kept, cleanPrometheusOperatorObjectNames: true" (evidence: repo, ref: kube-prometheus-stack/app/helmrelease.yaml + ocirepository.yaml, verified: 2026-06-20)
- [claim] "Prometheus retention is explicit: 7d / 4500MB on a 5Gi democratic-csi-local-hostpath PVC" (evidence: repo, ref: kube-prometheus-stack/app/helmrelease.yaml:424-443, verified: 2026-06-20)
- [claim] "Grafana has telemetry disabled (GF_ANALYTICS_* false), admin password from existingSecret grafana-secret, read-only rootfs + drop ALL caps + RuntimeDefault, and serves both a Prometheus (default) and a VictoriaLogs datasource" (evidence: repo, ref: grafana/app/helmrelease.yaml, verified: 2026-06-20)
- [claim] "victoria-logs is the logs plane: a victoria-logs-single server (10Gi PVC, 14d retention) plus a victoria-logs-collector DaemonSet that remote-writes to victoria-logs-server:9428; the collector dependsOn the server" (evidence: repo, ref: victoria-logs/app/ + victoria-logs/collector/, verified: 2026-06-20)
- [claim] "Exposure: grafana.${PUBLIC_DOMAIN} attaches to both gateways; victoria-logs (logs.${PUBLIC_DOMAIN}) attaches to envoy-internal only — the logs UI is not published externally. The speedtest-exporter has no public route (scrape-only: Prometheus scrapes the in-cluster Service via ServiceMonitor)" (evidence: repo, ref: grafana + victoria-logs/app helmrelease.yaml route blocks + speedtest-exporter/app/helmrelease.yaml, verified: 2026-07-05)
- [claim] "The observability namespace pulls in the shared common component (alerts/alertmanager → Flux type:alertmanager Provider into the in-cluster Alertmanager, plus alerts/github for commit-status); Flux reconciliation failures and Prometheus-rule alerts both route through Alertmanager (pushover default receiver, Watchdog/InfoInhibitor→blackhole, severity=critical→pushover)" (evidence: repo, ref: kubernetes/apps/observability/kustomization.yaml + kube-prometheus-stack/app/helmrelease.yaml + components/common/alerts/alertmanager/, verified: 2026-07-05)
- [claim] "PrometheusRules/ServiceMonitors are NOT centralized here — the only monitor committed under observability/ is a flux-system PodMonitor; platforms publish their own" (evidence: repo, ref: kube-prometheus-stack/app/podmonitor.yaml + observability subtree listing, verified: 2026-06-20)


## Drift Risk

- [drift] The minified kube-prometheus-stack disables most default alerting rules and exporters — intentional for one node, but a blind spot if the cluster ever scales to multi-node or if a platform needs its own alerts.
- [drift] (Resolved 2026-07-05 by roadmap alertmanager-introduction) Alertmanager is now ENABLED — internal-gateway route alertmanager.${PUBLIC_DOMAIN}, 1Gi local-hostpath PVC, AlertmanagerConfig with pushover receiver, extended default rules (general/node/nodeExporterAlerting/nodeExporterRecording) + custom oom-alert PrometheusRule. Flux reconciliation alerts now route through the Flux type:alertmanager Provider (components/common/alerts/alertmanager) into the same Alertmanager. See the Update section below.
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

## Update — 2026-07-05 (Alertmanager enablement + Flux alert unification)

Implemented via `docs/progress/alertmanager-introduction` (status: done). Re-verified against the cluster after each phase.

**Alertmanager now ENABLED** in kube-prometheus-stack:
- `alertmanager.enabled: true` with `route.main` on `envoy-internal` (networking/https), host `alertmanager.${PUBLIC_DOMAIN}` — LAN-only UI like grafana/logs.
- `alertmanagerSpec.alertmanagerConfiguration.name: alertmanager`, `externalUrl: https://alertmanager.${PUBLIC_DOMAIN}`, 1Gi `democratic-csi-local-hostpath` PVC.
- podMetadata labels: `ingress.home.arpa/gateways` + `ingress.home.arpa/prometheus` (UI + scrape via cluster CCNPs) and `egress.home.arpa/allow-world` (api.pushover.net — observability is NOT free-world under AD-023 V3 baseline; without this label Pushover delivery silently fails).
- defaultRules widened: `general` (Watchdog + InfoInhibitor + TargetDown), `node`, `nodeExporterAlerting`, `nodeExporterRecording` flipped to true. `alertmanager` rule group left false (we ship our own AlertmanagerConfig).
- Custom `oom-alert` PrometheusRule (severity=critical) under `app/prometheusrules/`.

**Secret delivery**: `alertmanager` ExternalSecret → `alertmanager-secret` via the `onepassword-connect` ClusterSecretStore, extracting `PUSHOVER_ALERTMANAGER_TOKEN` + `PUSHOVER_USER_KEY` from the 1Password `pushover` item (token field created manually 2026-07-05 as a hard gate).

**AlertmanagerConfig** (`app/alertmanagerconfig.yaml`): default receiver pushover (rich HTML template, sendResolved, sound gamelan, ttl 86400s); Watchdog + InfoInhibitor routed to a `blackhole` receiver (no external heartbeat monitor yet — follow-up if gatus/Uptime-Kuma/healthchecks.io is added); severity=critical routed to pushover; inhibitRules (critical inhibits warning on same alertname+namespace).

**Networking (AD-023)**: a second CiliumNetworkPolicy document appended to `app/ciliumnetworkpolicy.yaml` — `alertmanager` ingress granting flux-system/notification-controller → :9093 (the Flux→Alertmanager east-west path). The existing prometheus openwrt-scrape CNP is unchanged. No `metadata.namespace` (ks `targetNamespace: observability` places it).

**Flux alerting unified**: Flux reconciliation errors flow through a native Flux `Provider` `type: alertmanager` (`components/common/alerts/alertmanager/provider.yaml` → `http://alertmanager-operated.observability.svc.cluster.local:9093/api/v2/alerts/`) + `Alert` covering FluxInstance/GitRepository/HelmRelease/HelmRepository/Kustomization/OCIRepository, wired into `components/common/alerts/kustomization.yaml` alongside `github`. Fan-out: 12 namespaces carry the alertmanager Provider+Alert. The GitHub commit-status Provider/Alert (`components/common/alerts/github/`) is unchanged.

**Homepage**: Alertmanager added to the Homepage dashboard Observability group (`alertmanager.svg` icon, pod-selector status) via HTTPRoute annotations on `route.main`.

**Verified live**: ExternalSecret Ready, Alertmanager pod Running 2/2, PVC Bound, HTTPRoute present, CNP VALID, PrometheusRules present (oom-alert + general/node/node-exporter groups), Prometheus auto-wired to Alertmanager (operator-populated spec.alerting.alertmanagers), loaded config shows pushover receiver. End-to-end synthetic alert (amtool, severity=critical) delivered to Pushover. End-to-end Flux error (throwaway Kustomization, bad path → ArtifactFailed) flowed notification-controller → Alertmanager API (`FluxKustomizationArtifactfailed`, severity=error → default pushover receiver) → Pushover. Regression test after relay retirement confirmed Pushover still delivers solely via Alertmanager — no alerting gap.

**Open follow-ups** (not in this roadmap): Grafana Alertmanager datasource (needs a grafana→AM:9093 east-west CNP entry); dead-man's-switch (replace Watchdog→blackhole with a heartbeat webhook receiver if an uptime monitor lands); consider `kubernetesResources`/`kubernetesStorage` default rule groups once node/general rules prove stable.


## Update — 2026-07-10: Grafana migrated to grafana-operator (roadmap grafana-operator-migration, P0–P6)

- [observation] The standalone Grafana Helm chart (`grafana/app/`, deleted) was replaced by the **grafana-operator** pattern: `kubernetes/apps/observability/grafana/` now splits into `operator/` (HelmRelease, OCIRepository `grafana-operator` 5.24.0, CNP) and `instance/` (Grafana CR, datasource + folder CRs, HTTPRoute, ServiceMonitor, ExternalSecret, CNP). Two Flux Kustomizations: `grafana-operator` (wait) + `grafana-instance` (dependsOn grafana-operator, kube-prometheus-stack, onepassword-connect).
- [observation] 23 dashboards + 8 folders (one per owner namespace, D4) + 2 datasources are `Grafana*` CRs co-located with owning apps (D3). Chart-emitted dashboards (cilium ×2, external-secrets, tuppr, victoria-logs ×2) imported via `configMapRef`; the rest via **pinned URL imports** `url: .../api/dashboards/<id>/revisions/<rev>/download`, auto-updated by the home-operations `grafanaDashboards` Renovate preset (reviewed revision-bump PRs) — bjw-s-aligned; converted from `grafanaCom{id,revision}` on 2026-07-10.
- [observation] kiwigrid sidecars removed → no kube-apiserver egress. No plugins (D13) + `preinstall_disabled: "true"` → no grafana.com startup egress (was previously blocked by CNP → HubblePolicyDeny; now suppressed at source).
- [observation] New `blackbox-exporter` app (P4): Probe CRs for nas.lan ICMP + NFS tcp/2049; kps gained `probeSelectorNilUsesHelmValues: false`. BlackboxProbeFailed → Alertmanager → Pushover.
- [observation] SSO via Pocket-ID OIDC (P5) — see [[iam]].
- [observation] Grafana DB is ephemeral (emptyDir, D2): the operator re-provisions all dashboards/datasources on each pod start. A pod restart (e.g. `grafana-secret` change → operator `checksum/secrets` pod recreation) briefly empties the UI until the operator re-syncs. No PVC/VolSync by design.

See [[grafana-operator-migration]] (progress) for the full execution log.
