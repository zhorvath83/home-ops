---
title: observability
type: area_reference
permalink: home-ops/docs/areas/observability
area: observability
status: current
confidence: high
verified_at: '2026-08-01'
summary: Observability for the cluster splits into NINE workloads under kubernetes/apps/observability/
  — kube-prometheus-stack (operator + Prometheus + Alertmanager + kube-state-metrics
  + node-exporter, minimal single-node configuration), an operator-managed grafana
  (grafana-operator + a Grafana CR, LAN-only on envoy-internal), a speedtest-exporter for
  WAN throughput metrics, victoria-logs (single-node server + per-node collector DaemonSet)
  for the logs plane, plus blackbox-exporter, smartctl-exporter, prometheus-adapter, prometheus-pushgateway and
  silence-operator. Three PrometheusRules and three ScrapeConfigs ARE centralized here now;
  platform subtrees (volsync-system, external-secrets, etc.) still publish their own too. Pushover
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
- kubernetes/apps/observability/grafana/operator/helmrelease.yaml
- kubernetes/apps/observability/grafana/instance/grafana.yaml
- kubernetes/apps/observability/grafana/instance/httproute.yaml
- kubernetes/apps/observability/grafana/instance/externalsecret.yaml
- kubernetes/apps/observability/blackbox-exporter/app/probes.yaml
- kubernetes/apps/observability/blackbox-exporter/app/helmrelease.yaml
- kubernetes/apps/observability/smartctl-exporter/app/prometheusrule.yaml
- kubernetes/apps/observability/prometheus-adapter/app/ocirepository.yaml
- kubernetes/apps/observability/silence-operator/app/ocirepository.yaml
- kubernetes/apps/observability/kube-prometheus-stack/app/alertmanagerconfig.yaml
- kubernetes/apps/observability/kube-prometheus-stack/app/ciliumnetworkpolicy.yaml
- kubernetes/apps/observability/kube-prometheus-stack/app/grafanadatasource.yaml
- kubernetes/apps/observability/kube-prometheus-stack/app/scrapeconfigs/
- kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/
- kubernetes/apps/observability/speedtest-exporter/ks.yaml
- kubernetes/apps/observability/speedtest-exporter/app/helmrelease.yaml
- kubernetes/apps/observability/victoria-logs/app/helmrelease.yaml
- kubernetes/apps/observability/victoria-logs/app/ocirepository.yaml
- kubernetes/apps/observability/victoria-logs/collector/helmrelease.yaml
- kubernetes/apps/observability/victoria-logs/app/ciliumnetworkpolicy.yaml
- kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/dns-exfil.yaml
- kubernetes/apps/kube-system/cilium/app/helmrelease.yaml
- kubernetes/CLAUDE.md ("Current Reality" section)
- kubernetes/apps/observability/prometheus-pushgateway/ks.yaml
- kubernetes/apps/observability/prometheus-pushgateway/app/helmrelease.yaml
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
- [verified_at] 2026-08-03

## Status

Promoted from draft to current on 2026-06-20 after a full manifest verification pass — every sub-Kustomization under `kubernetes/apps/observability/` was read end to end. The logs plane (`victoria-logs`) was added since the previous draft and is now captured, and the metrics/Grafana facts were re-verified with file+line evidence. Remaining gaps are live-state only (see Open Questions).

Re-verified 2026-07-05: the speedtest-exporter public route (speed.${PUBLIC_DOMAIN}) was removed — the HTTPRoute block and the ingress.home.arpa/gateways label were dropped from its HelmRelease, leaving the exporter scrape-only (Prometheus scrapes the in-cluster Service via ServiceMonitor). The ingress.home.arpa/prometheus and egress.home.arpa/allow-world (Ookla servers) labels remain. grafana and victoria-logs exposure is unchanged.


## Summary

The cluster's observability stack lives under `kubernetes/apps/observability/` as NINE sub-Kustomization entries (twelve Flux Kustomizations — grafana, victoria-logs and silence-operator each define two):

- `kube-prometheus-stack` — upstream chart `oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack`, a "minified" single-node homelab variant: most `defaultRules` and the kube-apiserver / kubelet / etcd / kube-controller-manager / scheduler / proxy / coredns exporters are disabled; only the `k8s`, `kubernetesApps`, `kubeStateMetrics`, `prometheusOperator`, and `prometheus` rule groups survive. `cleanPrometheusOperatorObjectNames: true`. Prometheus retention is now explicit: 7d / 4500MB on a 5Gi `democratic-csi-local-hostpath` PVC. Alertmanager is enabled (see update section).
- `grafana` — **operator-managed** (grafana-operator, `operator/`+`instance/` split). Stateless `Grafana` CR (emptyDir DB, no PVC), telemetry off, hardened (read-only rootfs, drop ALL, RuntimeDefault). Datasources (`Prometheus` default, `Alertmanager`), dashboards, and folders are declarative CRs (`GrafanaDatasource`/`GrafanaDashboard`/`GrafanaFolder`) co-located with the owning app; the operator provisions them via the Grafana API using the `grafana-secret` admin creds. **No plugins** (D13) + `preinstall_disabled` — zero grafana.com startup egress; no VictoriaLogs datasource (logs stay in the vmui). **SSO via Pocket ID OIDC** (`auth.generic_oauth`), local login form hidden (`disable_login_form: true`). `root_url = https://grafana.${PUBLIC_DOMAIN}`, internal gateway only. Depends on grafana-operator + kube-prometheus-stack + onepassword-connect.
- `speedtest-exporter` — bjw-s `app-template`, WAN throughput metrics on a 20m scrape interval, hardened (nonRoot 10001, read-only rootfs, drop ALL). No `dependsOn`.
- `victoria-logs` — the logs plane, added since the previous pass. A single-node server (`victoria-logs-single`, 10Gi PVC, 14d retention) plus a per-node collector DaemonSet (`victoria-logs-collector`) that remote-writes to `http://victoria-logs-server.observability.svc.cluster.local:9428`. The collector `dependsOn` the server.

The namespace is `observability` and pulls in the shared `common` component (which carries `alerts/alertmanager` → in-cluster Alertmanager for Flux reconciliation failures, plus `alerts/github` for commit-status). Prometheus-side alerting is on via Alertmanager (pushover default receiver; **Watchdog → a `heartbeat` webhook receiver acting as a dead-man's switch**, InfoInhibitor → `blackhole`); Flux reconciliation failures route through the same Alertmanager. Three PrometheusRules (oomkilled, hubble-policy-deny, dns-exfil) and three ScrapeConfigs (openwrt, nas-node, nas-smartctl) ARE committed under `observability/kube-prometheus-stack/app/`, alongside the flux-system PodMonitor and the per-workload ServiceMonitors/PodMonitors/Probe CRs — platform subtrees additionally publish their own. Exposure: `grafana.${PUBLIC_DOMAIN}` on the **internal gateway ONLY** (decision D6 override: LAN-only permanently, never `envoy-external`); `logs.${PUBLIC_DOMAIN}` on the internal gateway only. The speedtest-exporter is scrape-only (no public route; Prometheus scrapes the in-cluster Service via ServiceMonitor).


## Components

- [component] kube-prometheus-stack — operator + Prometheus + kube-state-metrics + node-exporter; chart, minified homelab tuning, Prometheus 7d/4500MB retention on 5Gi local-hostpath PVC, Alertmanager enabled (internal-gateway route, 1Gi PVC, AlertmanagerConfig with pushover receiver) (kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml)
- [component] grafana — **operator-managed** (grafana-operator chart in `grafana/operator/` + a `Grafana` CR in `grafana/instance/grafana.yaml`), admin/provisioning password from ExternalSecret grafana-secret, telemetry off, hardened, emptyDir (no PVC); datasources are **Prometheus (default) + Alertmanager — NO VictoriaLogs** (logs stay in the vmui); dashboards are declarative `GrafanaDashboard` CRs (the kiwigrid sidecars were removed with the 2026-07-10 operator migration, so there is no sidecar dashboard discovery); exposed `grafana.${PUBLIC_DOMAIN}` on **envoy-internal only** (kubernetes/apps/observability/grafana/)
- [component] speedtest-exporter — bjw-s app-template, WAN throughput metrics, 20m scrape, scrape-only (no public route; Prometheus scrapes the in-cluster Service via ServiceMonitor), AD-023 labels ingress.home.arpa/prometheus + egress.home.arpa/allow-world (kubernetes/apps/observability/speedtest-exporter/)
- [component] victoria-logs server — victoria-logs-single, 10Gi PVC, 14d retention, serviceMonitor on, exposed logs.${PUBLIC_DOMAIN} on the internal gateway only with a / → /select/vmui/ redirect (kubernetes/apps/observability/victoria-logs/app/)
- [component] victoria-logs collector — victoria-logs-collector DaemonSet, PodMonitor on, remote-writes to victoria-logs-server:9428, dependsOn the server (kubernetes/apps/observability/victoria-logs/collector/)
- [component] Namespace marker — namespace.yaml uses the `_` placeholder; real name comes from the Flux Kustomization spec.targetNamespace (kubernetes/apps/observability/namespace.yaml)
- [component] common component — pulled in via kustomization.yaml; carries cluster vars + repos + alerts/alertmanager (Flux type:alertmanager Provider → in-cluster Alertmanager) + alerts/github for this namespace
- [component] flux-system PodMonitor — the only monitor committed under observability/ itself (kubernetes/apps/observability/kube-prometheus-stack/app/podmonitor.yaml)
- [component] Distributed ServiceMonitors/PrometheusRules — enabled chart-side per owning platform (volsync, external-secrets, kopia, victoria-logs), discovered by the operator; no central rules directory here


## Claims (verified against repo)

- [claim] "The observability area deploys NINE sub-Kustomization entries (twelve Flux Kustomizations): kube-prometheus-stack; grafana (grafana-operator + grafana-instance, the instance dependsOn grafana-operator + kube-prometheus-stack + onepassword-connect); speedtest-exporter (no dependsOn); victoria-logs (server + collector DaemonSet, collector dependsOn server); blackbox-exporter, smartctl-exporter, prometheus-adapter, prometheus-pushgateway and silence-operator (all dependOn kube-prometheus-stack; silence-operator-silences dependsOn silence-operator)" (evidence: repo, ref: kubernetes/apps/observability/kustomization.yaml:9-18 + each ks.yaml, verified: 2026-08-06)
- [claim] "kube-prometheus-stack is a minified single-node variant — the kube-apiserver/kubelet/etcd/kube-controller-manager/scheduler/proxy/coreDns exporters are disabled and `cleanPrometheusOperatorObjectNames: true`. The enabled defaultRules set is WIDER than the original minified set: k8s, kubernetesApps, kubeStateMetrics, prometheusOperator, prometheus, plus general, node, nodeExporterAlerting, nodeExporterRecording, kubernetesResources, kubernetesStorage, k8sPodOwner and k8sContainerMemoryCache" (evidence: repo, ref: kube-prometheus-stack/app/helmrelease.yaml:19,23-54, verified: 2026-08-03)
- [claim] "Prometheus retention is explicit: 7d / 4500MB on a 5Gi democratic-csi-local-hostpath PVC" (evidence: repo, ref: kube-prometheus-stack/app/helmrelease.yaml:424-443, verified: 2026-06-20)
- [claim] "Grafana has telemetry disabled (GF_ANALYTICS_* false), admin password from ExternalSecret-backed grafana-secret, read-only rootfs + drop ALL caps + RuntimeDefault, and serves a Prometheus (default) datasource plus an Alertmanager datasource — there is NO VictoriaLogs datasource; logs are read in the vmui" (evidence: repo, ref: grafana/instance/grafana.yaml + kube-prometheus-stack/app/grafanadatasource.yaml, verified: 2026-08-03)
- [claim] "victoria-logs is the logs plane: a victoria-logs-single server (10Gi PVC, 14d retention) plus a victoria-logs-collector DaemonSet that remote-writes to victoria-logs-server:9428; the collector dependsOn the server" (evidence: repo, ref: victoria-logs/app/ + victoria-logs/collector/, verified: 2026-06-20)
- [claim] "Exposure: grafana.${PUBLIC_DOMAIN} attaches to envoy-internal ONLY — decision D6 override, LAN-only permanently, never envoy-external, regardless of SSO state (the rationale is a comment in the HTTPRoute); victoria-logs (logs.${PUBLIC_DOMAIN}) likewise envoy-internal only. The speedtest-exporter has no public route (scrape-only: Prometheus scrapes the in-cluster Service via ServiceMonitor)" (evidence: repo, ref: grafana/instance/httproute.yaml:3-4,16-20 + victoria-logs/app helmrelease.yaml route block + speedtest-exporter/app/helmrelease.yaml, verified: 2026-08-03)
- [claim] "The observability namespace pulls in the shared common component (alerts/alertmanager → Flux type:alertmanager Provider into the in-cluster Alertmanager, plus alerts/github for commit-status); Flux reconciliation failures and Prometheus-rule alerts both route through Alertmanager (pushover default receiver, severity=critical→pushover, InfoInhibitor→blackhole, and Watchdog→a heartbeat webhook receiver that is a real dead-man's switch)" (evidence: repo, ref: kubernetes/apps/observability/kustomization.yaml + kube-prometheus-stack/app/alertmanagerconfig.yaml:16-26,49-57 + components/common/alerts/alertmanager/, verified: 2026-08-03)
- [claim] "PrometheusRules and ScrapeConfigs ARE partly centralized here: `kube-prometheus-stack/app/prometheusrules/` holds oomkilled, hubble-policy-deny and dns-exfil, and `kube-prometheus-stack/app/scrapeconfigs/` holds openwrt, nas-node and nas-smartctl. The flux-system PodMonitor is no longer the only monitor in the subtree. Platform subtrees (volsync-system, external-secrets, …) still publish their own as well" (evidence: repo, ref: kube-prometheus-stack/app/prometheusrules/kustomization.yaml:5-8 + scrapeconfigs/kustomization.yaml:5-8 + app/kustomization.yaml:5-13, verified: 2026-08-03)


## Drift Risk

- [drift] The minified kube-prometheus-stack disables most default alerting rules and exporters — intentional for one node, but a blind spot if the cluster ever scales to multi-node or if a platform needs its own alerts.
- [drift] (Resolved 2026-07-05 by roadmap alertmanager-introduction) Alertmanager is now ENABLED — internal-gateway route alertmanager.${PUBLIC_DOMAIN}, 1Gi local-hostpath PVC, AlertmanagerConfig with pushover receiver, extended default rules (general/node/nodeExporterAlerting/nodeExporterRecording) + custom oom-alert PrometheusRule. Flux reconciliation alerts now route through the Flux type:alertmanager Provider (components/common/alerts/alertmanager) into the same Alertmanager. See the Update section below.
- [drift] Per-platform ServiceMonitors and PrometheusRules are scattered with no inventory — an app that omits its own ServiceMonitor is silently unmonitored.
- [drift] Prometheus (7d/4500MB on 5Gi) and victoria-logs (14d on 10Gi) retention are fixed sizes tuned for current volume; revisit if metric/log volume grows or the local-hostpath PVC fills.
- [drift] Chart tags (kube-prometheus-stack, grafana, victoria-logs server/collector, speedtest-exporter image) are Renovate-tracked OCI refs — a major bump can change CRDs or values schema; review before merging.


## Open Questions / Gaps

- [gap] Live-state validation not performed (Prometheus actually scraping all targets, victoria-logs collector ingesting every namespace, Grafana dashboards rendering) — repo evidence only.
- [gap] Whether the cluster log pipeline indexes security-namespace audit logs (e.g. Pocket ID) into victoria-logs is unconfirmed — cross-reference docs/areas/iam.
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
- podMetadata labels: `ingress.home.arpa/allow-gateway-internal` + `ingress.home.arpa/allow-prometheus` (UI + scrape via cluster CCNPs — renamed from the pre-split `gateways`/`prometheus` labels when the gateways CCNP split per gateway) and `egress.home.arpa/allow-world` (api.pushover.net — observability is NOT free-world under AD-023 V3 baseline; without this label Pushover delivery silently fails).
- defaultRules widened: `general` (Watchdog + InfoInhibitor + TargetDown), `node`, `nodeExporterAlerting`, `nodeExporterRecording` flipped to true. `alertmanager` rule group left false (we ship our own AlertmanagerConfig).
- Custom `oom-alert` PrometheusRule (severity=critical) under `app/prometheusrules/`.

**Secret delivery**: `alertmanager` ExternalSecret → `alertmanager-secret` via the `onepassword-connect` ClusterSecretStore, extracting `PUSHOVER_ALERTMANAGER_TOKEN` + `PUSHOVER_USER_KEY` from the 1Password `pushover` item (token field created manually 2026-07-05 as a hard gate).

**AlertmanagerConfig** (`app/alertmanagerconfig.yaml`): default receiver pushover (rich HTML template, sendResolved, sound gamelan, ttl 86400s); **Watchdog routed to a `heartbeat` webhook receiver** (dead-man's switch — urlSecret `alertmanager-secret`/`watchdog_ping_url`, sendResolved:false, groupInterval 5m, repeatInterval 1m so the cadence is one ping per group_interval); InfoInhibitor routed to `blackhole`; severity=critical routed to pushover; inhibitRules (critical inhibits warning on same alertname+namespace).

**Networking (AD-023)**: a second CiliumNetworkPolicy document appended to `app/ciliumnetworkpolicy.yaml` — `alertmanager` ingress on :9093, now granting THREE sources: flux-system/notification-controller (the Flux→Alertmanager east-west path), observability/grafana (the Alertmanager datasource) and observability/silence-operator. The existing prometheus openwrt-scrape CNP is unchanged. No `metadata.namespace` (ks `targetNamespace: observability` places it).

**Flux alerting unified**: Flux reconciliation errors flow through a native Flux `Provider` `type: alertmanager` (`components/common/alerts/alertmanager/provider.yaml` → `http://alertmanager-operated.observability.svc.cluster.local:9093/api/v2/alerts/`) + `Alert` covering FluxInstance/GitRepository/HelmRelease/HelmRepository/Kustomization/OCIRepository, wired into `components/common/alerts/kustomization.yaml` alongside `github`. Fan-out: 12 namespaces carry the alertmanager Provider+Alert. The GitHub commit-status Provider/Alert (`components/common/alerts/github/`) is unchanged.

**Homepage**: Alertmanager added to the Homepage dashboard Observability group (`alertmanager.svg` icon, pod-selector status) via HTTPRoute annotations on `route.main`.

**Verified live**: ExternalSecret Ready, Alertmanager pod Running 2/2, PVC Bound, HTTPRoute present, CNP VALID, PrometheusRules present (oom-alert + general/node/node-exporter groups), Prometheus auto-wired to Alertmanager (operator-populated spec.alerting.alertmanagers), loaded config shows pushover receiver. End-to-end synthetic alert (amtool, severity=critical) delivered to Pushover. End-to-end Flux error (throwaway Kustomization, bad path → ArtifactFailed) flowed notification-controller → Alertmanager API (`FluxKustomizationArtifactfailed`, severity=error → default pushover receiver) → Pushover. Regression test after relay retirement confirmed Pushover still delivers solely via Alertmanager — no alerting gap.

**Open follow-ups** (not in this roadmap): all three are now DONE — the Grafana Alertmanager datasource landed (grafana is in the alertmanager CNP ingress allowlist), the dead-man's switch landed (Watchdog → `heartbeat` webhook receiver), and the wider default rule groups landed (kubernetesResources/kubernetesStorage/general/node/nodeExporter* are enabled).


## Update — 2026-07-10: Grafana migrated to grafana-operator (roadmap grafana-operator-migration, P0–P6)

- [observation] The standalone Grafana Helm chart (`grafana/app/`, deleted) was replaced by the **grafana-operator** pattern: `kubernetes/apps/observability/grafana/` now splits into `operator/` (HelmRelease, OCIRepository `grafana-operator` 5.24.0, CNP) and `instance/` (Grafana CR, datasource + folder CRs, HTTPRoute, ServiceMonitor, ExternalSecret, CNP). Two Flux Kustomizations: `grafana-operator` (wait) + `grafana-instance` (dependsOn grafana-operator, kube-prometheus-stack, onepassword-connect).
- [observation] 23 dashboards + 8 folders (one per owner namespace, D4) + 2 datasources are `Grafana*` CRs co-located with owning apps (D3). Chart-emitted dashboards (cilium ×2, external-secrets, tuppr, victoria-logs ×2) imported via `configMapRef`; the rest via **pinned URL imports** `url: .../api/dashboards/<id>/revisions/<rev>/download`, auto-updated by the home-operations `grafanaDashboards` Renovate preset (reviewed revision-bump PRs) — bjw-s-aligned; converted from `grafanaCom{id,revision}` on 2026-07-10.
- [observation] kiwigrid sidecars removed → no kube-apiserver egress. No plugins (D13) + `preinstall_disabled: "true"` → no grafana.com startup egress (was previously blocked by CNP → HubblePolicyDeny; now suppressed at source).
- [observation] New `blackbox-exporter` app (P4): Probe CRs for nas.lan ICMP + NFS tcp/2049; kps gained `probeSelectorNilUsesHelmValues: false`. BlackboxProbeFailed → Alertmanager → Pushover.
- [observation] SSO via Pocket ID OIDC — see [[iam]].
- [observation] Grafana DB is ephemeral (emptyDir, D2): the operator re-provisions all dashboards/datasources on each pod start. A pod restart (e.g. `grafana-secret` change → operator `checksum/secrets` pod recreation) briefly empties the UI until the operator re-syncs. No PVC/VolSync by design.

See [[grafana-operator-migration]] (progress) for the full execution log.


## Update — 2026-07-11: victoria-logs CNPs + DNS-exfil detection (AD-023 V5 e/l)

- [observation] **victoria-logs server** (AD-023 V5e, @d37f89f69): now carries `egress.home.arpa/custom-egress` (opt-out → DNS-only sink; the per-app CNP has NO egress section) + `ingress.home.arpa/allow-gateway-internal` + `ingress.home.arpa/allow-prometheus` (set via `server.podLabels`). New per-app CiliumNetworkPolicy (`victoria-logs/app/ciliumnetworkpolicy.yaml`): ingress default-deny, granting the app-unique kubelet health probes + collector remoteWrite on :9428 (`fromEntities: [kube-apiserver, host]` + `fromEndpoints: victoria-logs-collector`); the envoy-internal route + Prometheus scrape arrive via the gateways/prometheus CCNPs. Everything is served on the single port :9428. No grafana→victoria-logs datasource exists (logs stay in the vmui), so no grafana ingress rule.
- [observation] **victoria-logs collector** (V5e, @7bc05ca9a): carries `ingress.home.arpa/prometheus` (top-level `podLabels`) → ingress default-deny except the Prometheus podMonitor scrape (:9429). No per-app CNP (no health probes, no other ingress). Egress stays baseline (server:9428 + apiserver:6443 + DNS, all in-cluster).
- [observation] **DNS-exfil detection** (AD-023 V5l, @d9005e048): the Cilium Hubble `dns` metric gained `labelsContext=source_namespace,source_pod,source_workload` (`kubernetes/apps/kube-system/cilium/app/helmrelease.yaml` — required a manual `kubectl rollout restart ds/cilium` to take effect; the chart does not auto-roll on a hubble-metrics configmap change), so `hubble_dns_queries_total` is now attributable per source pod. New `HubbleDNSExfilSuspected` PrometheusRule (`kube-prometheus-stack/app/prometheusrules/dns-exfil.yaml`, severity warning): per-source-pod DNS query rate >30 q/s for 10m, coredns excluded. NXDOMAIN is NOT the primary signal — baseline NXDOMAIN fraction is ~35% (normal ndots search-domain misses). Starter threshold (~4× the cluster's ~7/s total), to be tightened to a per-pod baseline after a soak.
- [observation] The `prometheusrules/` subtree now holds three rule files: `oomkilled.yaml`, `hubble-policy-deny.yaml`, `dns-exfil.yaml`. `HubblePolicyDeny` remains `> 0` with no `for:` — the rollout-transient tuning was deliberately deferred (per user decision).

See [[cnp-per-app-audit]] (progress) Sessions 19–21 for the execution log.


## Update — 2026-07-11: prometheus-adapter (External Metrics API) + silence-operator (KubeHpaMaxedOut silencing)

Three observability components the Summary/Components above pre-date — all OCIRepository-backed HelmReleases with AD-023 CNPs, dependsOn kube-prometheus-stack:

- [observation] **blackbox-exporter** (`kubernetes/apps/observability/blackbox-exporter/`): THREE Probe CRs — `devices` (jobName devices_probe, module icmp, target nas.lan), `nfs` (jobName nfs_probe, module tcp_connect, target nas.lan:2049) and `idm` (jobName idm_probe, module http_2xx, target https://idm.${PUBLIC_DOMAIN}). prober url `prometheus-blackbox-exporter.observability.svc.cluster.local:9115` (fullnameOverride). Emits `probe_success{job=<jobName>}`. Its PrometheusRule also carries `BlackboxTLSCertExpiringSoon` (job idm_probe, cert expiry < 1d, warning) besides the generic `BlackboxProbeFailed`. Deployed as part of the grafana-operator-migration P4; jobName renamed 2026-07-11 to symmetric `<name>_probe` for the zeroscaler metric selector.
- [observation] **prometheus-adapter** (`kubernetes/apps/observability/prometheus-adapter/`): serves `external.metrics.k8s.io` (APIService v1beta1.external.metrics.k8s.io, Available=True). Chart `oci://ghcr.io/prometheus-community/charts/prometheus-adapter` 5.3.0. values: `rules.default: false` + one external rule mapping `probe_success` with `max_over_time(...[1m])` smoothing, `resources.namespaced: false`. Required so an HPA with `metrics[].type: External` can resolve (unblocks the zeroscaler scale-to-zero pattern — see [[nfs-dependency-zeroscaler]]). No cert-manager (chart default insecureSkipTLSVerify + self-signed cert). End-to-end verified: `kubectl get --raw /apis/external.metrics.k8s.io/v1beta1/.../probe_success?labelSelector=job%3Dnfs_probe` returns value 1; HPA paperless reports ScalingActive=True / ValidMetricFound.
- [observation] **silence-operator** (`kubernetes/apps/observability/silence-operator/`): giantswarm silence-operator (chart `oci://gsoci.azurecr.io/charts/giantswarm/silence-operator` 0.20.1) reconciles `Silence` CRs (CRD `observability.giantswarm.io/v1alpha2`; chart also installs the legacy v1alpha1 `monitoring.giantswarm.io` CRD) into Alertmanager API silences. Two Flux Kustomizations in one ks.yaml: `silence-operator` (app/, healthCheck on HR) + `silence-operator-silences` (silences/, dependsOn silence-operator). values: `alertmanagerAddress: http://alertmanager-operated.observability.svc.cluster.local:9093`, `networkPolicy.enabled: false`. AD-023 CNP restricts egress to kube-apiserver:6443 + alertmanager:9093, ingress prometheus:8080 (chart PodMonitor). silence-operator added to the alertmanager CNP ingress allowlist (functional — the alertmanager CNP is ingress default-deny).
- [observation] **KubeHpaMaxedOut silenced**: the zeroscaler HPAs (maxReplicas:1, minReplicas:0) are permanently "maxed out" while the NFS probe is healthy (desired=1=max); the kubernetes-apps rule guard `max != min` does not exclude them → 11 constant firing warnings. A global `Silence` CR `hpa-maxed-out` (`matchers: [{alertname: KubeHpaMaxedOut}]`) suppresses notifications (perpetual, ends 2126). The alerts stay visible in Alertmanager (state=suppressed); only the Pushover notification is suppressed. Reversible by deleting the Silence CR.
- [decision] Chose the silence-operator approach (bjw-s pattern) over disabling/modifying the default KubeHpaMaxedOut rule: keeps the alert visible in Prometheus, GitOps-managed + reversible (CR delete), reusable for future silences. Cost: a new lightweight operator + two CRDs. Scope caveat: the silence is global (not per-HPA) — acceptable today because no maxReplicas>1 HPA exists; revisit (add horizontalpodautoscaler/namespace matchers) if a real autoscaling HPA is added.

## Relations

- relates_to [[prometheus-adapter]]
- relates_to [[nfs-dependency-zeroscaler]]
- relates_to [[silence-operator]]

## Update — 2026-08-01: ScrapeConfig convention for external scrape targets

- [convention] External Prometheus scrape targets are `ScrapeConfig` CRs under `kubernetes/apps/observability/kube-prometheus-stack/app/scrapeconfigs/`, never inline HelmRelease `additionalScrapeConfigs`. Rationale: inline `additionalScrapeConfigs` is brittle on chart upgrades (Renovate-adjacent — a values-schema change can clobber the block); `ScrapeConfig` CRs are Renovate-neutral and consistent with the ServiceMonitor/PodMonitor/Probe primitives already in use.
- [convention] `scrapeConfigSelectorNilUsesHelmValues: false` on the prometheusSpec (`kube-prometheus-stack/app/helmrelease.yaml:501`) is what makes Prometheus discover `ScrapeConfig` CRs; all selectors (serviceMonitor/podMonitor/probe/rule/scrapeConfig) are `{}` match-all.
- [observation] Current external (non-cluster-service) scrape inventory: `ScrapeConfig/openwrt` (job=openwrt, `${ROUTER_IP}:9100`) and the blackbox-exporter `Probe` CRs `devices` (icmp, nas.lan) + `nfs` (tcp/2049, nas.lan). In-cluster targets (node-exporter, smartctl-exporter, kube-state-metrics, etc.) are scraped via ServiceMonitor/PodMonitor. `prometheus.spec.additionalScrapeConfigs` is empty; the openwrt job is live `up=1`.
- [observation] Execution record: [[prometheus-scrapeconfig-extraction]] (progress, done). The NAS exporters (`nas-smartctl` :9633, `nas-node` :9100) are split into [[nas-host-exporters]] (planned) — out of scope for the convention item.

## Update — 2026-08-01: NAS host exporters live (nas-smartctl, nas-node) + ATA alert group

Supersedes the "NAS exporters are planned / out of scope" line in the ScrapeConfig-convention update above.

- [observation] Two Debian-packaged exporters now run on the OMV NAS host: prometheus-smartctl-exporter 0.14.0-2~bpo13+1 (trixie-backports, :9633) and prometheus-node-exporter 1.9.0-1+b4 (:9100). Installed imperatively; NOT yet codified in Ansible (just omv install still points at a provision/openmediavault/playbooks/site.yml that does not exist).
- [observation] External scrape inventory is now ScrapeConfig/openwrt (${ROUTER_IP}:9100), ScrapeConfig/nas-smartctl (${NAS_IP}:9633), ScrapeConfig/nas-node (${NAS_IP}:9100), plus the blackbox Probe CRs devices (icmp nas.lan) and nfs (tcp/2049 nas.lan). Both NAS jobs relabel instance to nas and drop ^go_.*.
- [observation] The kube-prometheus-stack-prometheus CiliumNetworkPolicy carries a second LAN egress entry: 192.168.1.10/32 on ports 9633 + 9100, alongside the existing 192.168.1.1/32:9100 openwrt grant. AD-023 V3 dropped LAN from the baseline, so each external scrape needs its own grant.
- [observation] smartctl-exporter/app/prometheusrule.yaml now holds TWO groups: the original smartctl-exporter (8 NVMe alerts) and smartctl-exporter-ata (7 alerts scoped job="nas-smartctl"). The two NVMe temperature alerts carry job!="nas-smartctl" so identically named metrics from the two exporters cannot cross-fire. 15 rules total, promtool-tested via just k8s test-prom-rules.
- [observation] The ATA temperature thresholds are 50/55 C, not the NVMe 70/80 — the drive publishes op_limit_max=55, its measured lifetime max is 50, and the host smartd config already uses -W 0,50,55.
- [correction] smartctl_exporter v0.14.0 emits only temperature_type="current" for the NAS SATA disk, NOT one series per temperature JSON key as a source reading had suggested. The temperature_type="current" matcher is kept as a forward guard, not because sibling types exist today.
- [gap] No Grafana panel anywhere renders the ATA attributes (Reallocated_Sector_Ct, Current_Pending_Sector, Offline_Uncorrectable, UDMA_CRC_Error_Count, Helium_Condition) the new alerts are built on. Dashboard 22604 is NVMe/SSD-centric: its temperature, lifetime and health panels work for the NAS disk, its Media Errors, Critical Warnings, Total Data Written and Wear Leveling panels do not. Deferred rather than introducing a self-authored dashboard JSON convention — the repo has no precedent for one.

See [[nas-host-exporters]] (progress) for the execution log and live verification.

## Update 2026-08-03 — staleness re-verification (the audit closes on the note that opened it)

This note is where the `area-reference-staleness-audit` roadmap item came from: on 2026-08-01 it was
caught claiming FOUR workloads while `kustomization.yaml` listed EIGHT. Its `verified_at` was bumped
to 2026-08-01 and dated update sections were appended.

**The original defect was still there.** The frontmatter `summary` still said "splits into four
workloads" today, and `verified_against` still listed two files (`grafana/app/helmrelease.yaml`,
`grafana/app/externalsecret.yaml`) that were DELETED in the 2026-07-10 grafana-operator migration.
Verdict on arrival: MAJOR-DRIFT — 8 wrong, 3 obsolete, 3 incomplete.

- [finding] **`verified_at` is only as good as what was actually re-read.** The 2026-08-01 pass
  appended narrative and bumped the date without reconciling the frontmatter or the Claims section.
  So a fresh `verified_at` is NOT proof a note is correct — which undercuts the roadmap item's own
  premise that `verified_at` is the reliable staleness signal. It is a signal about EFFORT, not
  about CORRECTNESS.
- [correction] Eight workloads (eleven Flux Kustomizations — grafana, victoria-logs and
  silence-operator each define two). Missing everywhere in the note: blackbox-exporter,
  smartctl-exporter, prometheus-adapter, silence-operator.
- [correction] Grafana is **operator-managed** (grafana-operator + a `Grafana` CR), not a standalone
  chart. Its datasources are Prometheus + **Alertmanager** — there is NO VictoriaLogs datasource
  (logs stay in the vmui). The kiwigrid sidecars are gone, so "sidecar dashboard discovery" is wrong
  too; dashboards are declarative `GrafanaDashboard` CRs.
- [correction] **Grafana is `envoy-internal` ONLY**, not "both gateways" — decision D6 override,
  LAN-only permanently, rationale recorded as a comment in the HTTPRoute. The note asserted public
  exposure for the cluster's admin dashboard in three separate places.
- [correction] "PrometheusRules/ServiceMonitors are NOT centralized here" is no longer true: three
  PrometheusRules (oomkilled, hubble-policy-deny, dns-exfil) and three ScrapeConfigs (openwrt,
  nas-node, nas-smartctl) live under `kube-prometheus-stack/app/`.
- [correction] The enabled `defaultRules` set is WIDER than the "minified" description: general,
  node, nodeExporterAlerting, nodeExporterRecording, kubernetesResources, kubernetesStorage,
  k8sPodOwner and k8sContainerMemoryCache are on as well.
- [correction] Watchdog no longer goes to `blackhole` — it routes to a `heartbeat` webhook receiver,
  i.e. the dead-man's switch that the note listed as an open follow-up actually exists. All three of
  that section's "open follow-ups" are done.
- [correction] The alertmanager east-west CNP now admits THREE sources on :9093 (flux
  notification-controller, grafana, silence-operator), not one.
- [correction] Stale label names (`ingress.home.arpa/gateways`, `ingress.home.arpa/prometheus`) in
  the alertmanager and victoria-logs sections — both were renamed by the per-gateway CCNP split to
  `allow-gateway-internal` / `allow-prometheus` (see the networking area audit).
- [correction] prometheus-adapter chart is 5.3.0 (was recorded as 4.12.0); the silence-operator
  registry is `gsoci.azurecr.io` — the note had a typo (`gsci`), which would break a copy-paste.
- [correction] blackbox-exporter has THREE Probe CRs, not two — `idm` (http_2xx) was added — plus a
  `BlackboxTLSCertExpiringSoon` alert.


## Update — 2026-08-06: prometheus-pushgateway (push metrics for blocklist-import freshness)

The ninth observability workload (added in #4129, predates this update). The Summary, frontmatter and inventory [claim] above now reflect NINE; the Components list still predates this workload — this section records the app's specifics.

- [observation] **prometheus-pushgateway** (`kubernetes/apps/observability/prometheus-pushgateway/`): chart `oci://ghcr.io/prometheus-community/charts/prometheus-pushgateway` 3.7.0 from a per-app OCIRepository (app/ocirepository.yaml:13-14). dependsOn kube-prometheus-stack (the ServiceMonitor CRD lives there — ks.yaml:11-13).
- [observation] **StatefulSet + 1Gi PVC** (`democratic-csi-local-hostpath`) via `runAsStatefulSet: true` + `persistentVolume.enabled` (app/helmrelease.yaml:13-20). Rationale: without persistence a pod restart blanks the pushed `blocklist_import_source_status` series and false-fires `CrowdSecBlocklistImportMetricsAbsent` (comment at helmrelease.yaml:14-15).
- [observation] **ServiceMonitor** in the release namespace `observability` with `honorLabels: true` (app/helmrelease.yaml:45-53). The chart defaults `serviceMonitor.namespace` to `monitoring`, which does not exist here — a Helm upgrade would fail without the override. `honorLabels` preserves the pushed `job="crowdsec-blocklist-import"` label so the `CrowdSecBlocklistImport*` PrometheusRule selectors match; without it Prometheus overwrites `job` with the scrape target's and the alerts never fire.
- [observation] **Consumer**: the `crowdsec-blocklist-import` CronJob pushes per-source freshness metrics (`blocklist_import_source_status`) to `http://prometheus-pushgateway.observability.svc.cluster.local:9091` (kubernetes/apps/crowdsec/crowdsec-blocklist-import/app/helmrelease.yaml:89).
- [observation] **CNP** (app/ciliumnetworkpolicy.yaml): ingress default-deny with one allow — push from the crowdsec-namespace `crowdsec-blocklist-import` pod on :9091 (`fromEndpoints` matching `k8s:io.kubernetes.pod.namespace: crowdsec` + `app.kubernetes.io/name: crowdsec-blocklist-import`). The Prometheus scrape ingress is NOT this CNP — it comes from the clusterwide `ingress-from-prometheus` CCNP via the `ingress.home.arpa/allow-prometheus` pod label (helmrelease.yaml:24-25), so the push from crowdsec needs its own allow here.
- [observation] **Name-label caveat** (cross-reference the [[k8s-workloads]] CNP label-selector convention): this is a non-app-template chart, so the pod `app.kubernetes.io/name` label is the CHART name `prometheus-pushgateway`, not the release name — a release rename or `fullnameOverride` change does NOT move it. The app CNP endpointSelector (ciliumnetworkpolicy.yaml:14) matches `app.kubernetes.io/name: prometheus-pushgateway`, which equals both the chart name and (since the #4132 rename) the release name.
