---
title: kube-prometheus-stack-hygiene
type: roadmap
permalink: home-ops/docs/roadmap/kube-prometheus-stack-hygiene
topic: Right-size what kube-prometheus-stack collects (drop unused high-cardinality
  metrics) and fill the alert gaps that the retention miscalculation exposed (TSDB-growth,
  cert-manager expiry, VolSync missed-interval) — a measured-hygiene roadmap, NOT
  a data-loss emergency.
status: proposed
priority: medium
scope: The observability stack around kube-prometheus-stack (KPS, cilium, node-exporter
  HelmReleases + PrometheusRules) on the single-node Talos cluster. Pulled from a
  four-round read-only review (scratchpad/prometheus-review.md). The K-1 "retention
  ~6h / DB ~15GB/day" finding was RETRACTED (outage-confounded); the real retention
  is 7d, storage is NOT binding (headroom ~2.2x cardinality). This item carries hygiene
  + alert-gap work + (per a human decision in Kör 4) a prompp-migration plan as its
  own phase, not a data-loss emergency.
rationale: 'The review measured the live TSDB: 1.80 B/sample, ~290 MB/day, 7d ~2.03
  GB vs retentionSize 4500 MB (4.39 Gi) — storage is not the constraint, so cardinality
  reduction is hygiene, not data-loss prevention. Kör 4 then walked the 15 largest
  series-consuming jobs (per-job topk, measured) and cross-referenced every large
  metric family against all 28 PrometheusRule exprs + all 25 GrafanaDashboard JSONs
  (grafana.com / raw.githubusercontent / inline ConfigMap) to find consumers. Result:
  ~13665 live series (17.8% of the 76965 head) with NO consumer are confirmed DROP-able
  (grafana_* self-metrics 3777 with zero consumers; envoy-proxy unconsumed xDS/cx/listener
  buckets 2520; cilium internal latency histograms 1179; CNI-interface container_network_*
  4768; smaller operator-internal buckets); ~3194 more (4.1%) are VERIFY (human decides:
  nas-node real systemd unit_state, pocket-id IdP HTTP histograms, per-container processes/sockets,
  node-exporter interface metadata). The audit also found three alert gaps the retention
  miscalculation masked (TSDB-growth, cert-manager expiry, VolSync missed-interval)
  — all on ALREADY-COLLECTED data, not new collection. Each phase is independently
  shippable as a separate PR. prompp was re-evaluated in Kör 4 per a human decision
  and is now Phase 6 (status: proposed, gated on memory pressure + an unverified 3.x->2.55
  TSDB-read risk), not a rejected alternative.'
related_areas:
- observability
- flux-gitops
- volsync-backup
- iam
options:
- Phase 1 cardinality drops + Phase 2 alert gaps are the high-ROI core; Phase 3 scrape-interval
  tuning is future-proofing only (engage near the 2.2x headroom).
- Phase 6 (prompp) is a complete plan kept ready; the data says "not yet" today (RSS
  32% of limit, node has ~49 GB free). The cheapest memory-ceiling fix is raising
  the limit, not prompp.
- Long-term metric storage / DR (vmagent -> vmsingle) is a separate architectural
  decision and becomes its OWN ADR (docs/decisions), referenced here as the follow-on
  step — it is NOT a phase of this hygiene roadmap.
tags:
- roadmap
- observability
- kube-prometheus-stack
- prometheus
- cardinality
- alerting
- proposed
---

# kube-prometheus-stack-hygiene — right-size collection + fill the alert gaps the retention miscalc exposed

## Metadata (observation-form, schema validation)

- [topic] Right-size what KPS collects (drop unused high-cardinality metrics) + fill the alert gaps (TSDB-growth, cert-manager expiry, VolSync missed-interval); measured hygiene, not data-loss
- [status] proposed
- [priority] medium
- [area] observability / flux-gitops / volsync-backup / iam
- [created] 2026-08-15

## Verification basis (how this item was built)

- Source: a four-round read-only review of kube-prometheus-stack (scratchpad/prometheus-review.md, Kör 1-4 — source file no longer present in the repo as of the Kör 4 re-verification; findings are distilled in this note, NEM ELLENŐRIZVE against the original scratchpad). Read-only throughout — no manifest mutation, no commit, no cluster write; all measurements live Prometheus API (`kubectl get --raw` proxy) + `kubectl top` + chart values.yaml (`gh api`).
- Method: Kör 2 retracted the K-1 retention finding (the 8-day node outage confounded `count_over_time(up[7d])` and `blocks_loaded=3`); the real numbers are blocks_bytes=83.65 MB, 1.80 B/sample, ~290 MB/day, 7d ~2.03 GB → retention 7d, storage NOT binding (headroom ~2.2x). Kör 3 audit: top-50 seriesCountByMetricName (status/tsdb, limit=50). Kör 4 audit: per-job topk(25, count by (__name__)({job="X"})) for the 15 largest series consumers (per-job, NOT the rejected full-scan `{}`), cross-referenced against all 28 PrometheusRule exprs + all 25 GrafanaDashboard JSONs (every dashboard fetched: grafana.com download, raw.githubusercontent, or inline ConfigMap via configMapRef) to find consumers. Scrape intervals read from `/api/v1/targets` (active). ALERTS/ALERTS_FOR_STATE and the three alert-metric existence confirmed by live query. Kör 4 re-verified these live this round (prometheus_tsdb_storage_blocks_bytes=1, certmanager_certificate_expiration_timestamp_seconds=3, volsync_missed_intervals_total=38, ALERTS=11, ALERTS_FOR_STATE=11 — all unchanged) and independently confirmed the Phase 5 SLO-chain dependency from the chart source (prometheus-community/helm-charts templates/prometheus/rules-1.14/: kube-apiserver-availability.rules consumes apiserver_request_sli_duration_seconds_bucket; kube-apiserver-slos KubeAPIErrorBudgetBurn depends on the burnrate chain; kubernetes-system-apiserver KubeClientCertificateExpiration uses apiserver_client_certificate_expiration_seconds_bucket/_count). The helmrelease defaultRules (kubeApiserver*=false, kubernetesSystem=false) were verified against the repo file (helmrelease.yaml:33-36, :44).
- Refuted / retracted (carried as closed, not as findings): K-1 (~6h retention, DB ~15GB/day, 7d ~100GB) — ~50x over-estimate, outage-confounded; F-2 (CrowdSecBlocklistImportMetricsAbsent) — resolved by the overnight run, also an outage artifact. Kör 4 also corrected P1.3 (the 920 node_systemd_unit_state series are from nas-node's REAL OMV/Debian systemd, NOT Talos container units — the Kör 3 premise was wrong).
- NOT fully verified (marked, not asserted): PVC-level utilization (kubelet_volume_stats_* reports the HOST fs on local-hostpath, not per-PVC); prompp 3.x->2.55 TSDB read-compatibility (NEM ELLENŐRIZVE — see Phase 6, a blocking risk); per-feature 3.x regression diff (directional only); steady-state node free RAM (single reading).

## What we gain

- ~13665 live series (17.8% of head) removed with no consumer, plus churn reduction (CNI lxc interfaces, cilium/envoy histograms) — less index pressure, ~117 MB/day less storage growth (~819 MB/7d, ~40% of the current 7d footprint), and a proportional head/index-memory reduction (directional ~-65..-95 Mi RSS of the current 646 Mi).
- ~3194 more series (4.1%) flagged VERIFY for the human (nas-node systemd, pocket-id IdP histograms, per-container processes/sockets, node-exporter interface metadata) — not auto-dropped.
- Three alert gaps closed on ALREADY-COLLECTED data (no new scrape targets): TSDB-growth/retentionSize-approach (the exact lesson from Kör 1), cert-manager cert-expiry (silent renewal failure), VolSync backup-missed-interval (DR-plane missed schedule) — ~6 new series total, negligible.
- A complete prompp-migration plan (Phase 6) kept ready per a human decision, with the blocking risk (3.x->2.55 TSDB read-compat, NEM ELLENŐRIZVE) and the cheaper alternatives (raise the memory limit — node has ~49 GB free; apply Phase 1+3 first) spelled out so the decision rests on facts.
- A forward path to long-term metric storage / DR (vmsingle) is marked as the follow-on ADR, not buried inside hygiene work.

## Locked decisions

- This is PLANNING, not implementation. Phases are independently shippable as separate PRs; the human owns commit/merge.
- Storage is NOT binding: do NOT size PVC/retentionSize up as a hygiene action. The 5Gi PVC + 4500MB retentionSize hold 7d with ~2.2x cardinality headroom. Engage PVC sizing only as part of the DR/ADR decision, not here. (Raising the Prometheus MEMORY limit is a separate, cheap option — see Phase 6.)
- Drop recommendations are evidence-backed (no consumer found in rules + dashboards). Uncertain / high-debug-value metrics are NOT hard-dropped — they are VERIFY (human decides): container_pressure_* (KEEP, human-explicit debug value), blocklist_import_errors_total (verify labels), nas-node node_systemd_unit_state, pocket-id http_*, container_processes/sockets, node-exporter interface metadata.
- The bjw-s relabelings are measured, not copied for appearances: today they are no-ops (kubeApiServer N/A — disabled; kubelet labeldrop uid/id|name — 0 independent cardinality; rest_client on kubelet — 0 series). They become a MANDATORY prerequisite of Phase 5, not an optional add-on (see Phase 5).
- No noisy alerts: non-actionable signals (speedtest bandwidth, envoy 5xx on low-traffic home cluster) stay dashboard-only or absent.
- Phase 2 adds NO new scrape target / metric family — all three alerts build on already-collected data (measured, see Phase 2 correction). This corrects the premise behind the Kör 4 human decision B.

## Phases

### Phase 1 — Cardinality hygiene (measured drop-list)

Measured per-job (topk by __name__ per job, live), consumer = GrafanaDashboard panel OR PrometheusRule alert/recording. Verdict categories: DROP (no consumer AND no realistic future/debug value), KEEP (consumer, or real ad-hoc debug value — e.g. container_pressure_*), VERIFY (uncertain / security- or ops-adjacent — human decides). Head series = 76965.

#### Confirmed DROP (no consumer) — ~13665 series, ~117 MB/day

| # | Metric family | Job (scrape object, interval) | Series | MB/day | Consumer check | Verdict |
|---|---|---|---|---|---|---|
| P1.1 | container_network_* on {cali,cilium,cni,lxc,nodelocaldns,tunl} interfaces | kubelet cAdvisor (SM kube-prometheus-stack-kubelet, 10s) | 4768 | 74.1 | k8s-views-pods/namespaces use eth0 (non-host-net pods); lxc/tunl only on host-network pods = host Cilium veth duplication | DROP |
| P1.2 | envoy_cluster_update_duration_bucket + envoy_sds_update_duration_bucket | networking/envoy-proxy (podMonitor envoy-proxy, 1m) | 1400 | 3.6 | envoy-proxy-global uses upstream_rq_time/http_downstream_rq_time, NOT update/sds duration | DROP |
| P1.2b | envoy_cluster_upstream_{rq_per_cx,cx_length_ms,cx_connect_ms,external_upstream_rq_time}_bucket + envoy_listener_{downstream_cx_length_ms,connections_accepted_per_socket_event}_bucket | networking/envoy-proxy (1m) | 1120 | 2.9 | none of these buckets referenced by envoy-proxy-global | DROP |
| P1.3 | grafana_* (all: feature_toggles_info, apiserver_request_*, grpc_authz_*, http_response_size, workqueue, flowcontrol, …) | grafana-service (SM grafana, 1m) | 3777 | 9.8 | NONE — no dashboard/rule references grafana_* (Grafana self-observability; we have no Grafana-internal dashboard) | DROP |
| P1.4 | cilium_hive_jobs_timer_run_duration, cilium_k8s_client_api_latency_time, cilium_agent_api_process_time, cilium_k8s_workqueue_{work,queue}_duration, cilium_node_health_connectivity_latency, cilium_hive_jobs_observer_run_duration, cilium_policy_selector_cache_operation_duration, cilium_datapath_conntrack_gc_duration — all `_seconds_bucket` | cilium-agent (SM cilium-agent, 10s) | 771 | 12.0 | cilium-dashboard uses endpoint_regeneration_time_stats_bucket + proxy_upstream_reply + policy_implementation_delay only; these latency buckets are unconsumed | DROP |
| P1.5 | cilium_operator_k8s_client_api_latency_time, cilium_k8s_workqueue_{work,queue}_duration, cilium_operator_{lbipam,ipam_*}_duration/latency — all `_seconds_bucket` | cilium-operator (SM cilium-operator, 10s) | 408 | 6.3 | cilium-operator-dashboard uses process/ipam gauges + ipam_resync_total, NOT these latency buckets | DROP |
| P1.6 | rest_client_{request_duration,rate_limiter_duration,response_size_bytes,request_size_bytes} (_bucket/_sum/_count) | envoy-gateway (SM envoy-gateway, 1m) | 614 | 1.6 | envoy-gateway-global uses watchable/status_update/resource_apply; rest_client is consumed only by flux dashboards (which filter by flux pods) | DROP |
| P1.7 | container_health_state | kubelet cAdvisor (10s) | 305 | 4.7 | none (no dashboard/rule) | DROP |
| P1.8 | controller_runtime_reconcile_time_seconds_bucket + workqueue_{work,queue}_duration_seconds_bucket | volsync-metrics (SM volsync, 30s) | 268 | 1.4 | volsync dashboard uses volsync_* only; these operator-internal histograms unconsumed | DROP |
| P1.9 | apiserver_response_sizes_bucket, field_validation_request_duration_seconds_bucket, metrics_server_*_bucket, auth{entication,orization}_duration_seconds_bucket, rest_client_*_bucket | metrics-server (SM metrics-server, 1m) | 234 | 0.6 | flux-k8s-api-performance uses apiserver_request_{duration,slo,sli} (KEPT); these others unconsumed | DROP |

Subtotal: 13665 series (17.8% of head), 117.0 MB/day, ~819 MB/7d (~40% of the 2.03 GB 7d footprint).

#### VERIFY (human decides) — ~3194 series, ~16 MB/day

| # | Metric family | Job (scrape object, interval) | Series | MB/day | Why VERIFY (not auto-drop) |
|---|---|---|---|---|---|
| V1 | node_systemd_unit_state | nas-node (scrapeConfig nas-node, 1m) | 920 | 2.4 | CORRECTION: these are nas-node's REAL OMV/Debian systemd units, NOT Talos container units (Kör 3 mis-attributed them). NO rule consumes them (the node-exporter systemd rule filters job="node-exporter" = Talos, where series=0); node-exporter-full uses node_systemd_units/socket, NOT unit_state. Ops-debug value (is a NAS service unit failed?) — human decides. A surgical metricRelabeling drop of `node_systemd_unit_state` (NOT disabling the collector — that would also lose units/socket which ARE consumed) is the precise lever if dropped. |
| V2 | http_server_{request,response}_body_size_bytes_bucket + http_server_request_duration_seconds_bucket + http_client_request_*_bucket | pocket-id (SM pocket-id, 1m) | 1076 | 2.8 | IdP (security-adjacent); no dashboard/rule. Human decides if SSO request-latency / body-size histograms are worth keeping for audit/security debug. |
| V3 | container_processes + container_sockets | kubelet cAdvisor (10s) | 610 | 9.5 | per-container process/socket debug; no dashboard. Like container_pressure_* but lower debug value for a home cluster (human: keep for debug, or drop?). |
| V4 | node_network_{address_assign_type,name_assign_type,net_dev_group,protocol_type,device_id,dormant,flags,carrier_changes_total} | node-exporter (SM …node-exporter, 1m) | ~588 | 1.5 | interface metadata; node-exporter-full uses the traffic/info/mtu/iface_link families, NOT these. Low value, but per-interface — confirm no panel uses them before dropping. |

VERIFY subtotal: 3194 series (4.1%), 16.2 MB/day, ~113 MB/7d. Grand total (DROP + VERIFY): 16859 series (21.9%), ~133 MB/day, ~932 MB/7d (~46% of 7d footprint).

#### KEEP (consumed or explicit debug value) — representative large families

container_pressure_* (2440, human-explicit KEEP — cgroup pressure debug); kube_pod/deployment/replicaset/persistentvolume/hpa_* (KSM, consumed by k8s-views); apiserver_request_{duration,slo,sli}_seconds_bucket (metrics-server, consumed by flux-k8s-api-performance); volsync_* (volsync dashboard + the P2.3 alert); envoy_cluster_upstream_rq_time + envoy_http_downstream_rq_time (envoy-proxy-global); cilium_endpoint_regeneration_time_stats / cilium_proxy_upstream_reply / cilium_policy_implementation_delay (cilium-dashboard); hubble_* (hubble rules + flow visibility); node_cpu/node_filesystem/node_network traffic families (node-exporter-full, k8s-views-nodes, openwrt); certmanager_certificate_expiration_timestamp_seconds (3, the P2.2 alert source).

#### bjw-s relabelings — measured verdict (not copied for appearances)

- kubeApiServer drops (apiserver/etcd/rest_client duration buckets, response_sizes, watch_events_sizes): **N/A today** (kubeApiServer.enabled: false → 0 series). They are a **MANDATORY prerequisite of Phase 5**, not an optional add-on — see Phase 5.
- kubelet labeldrop uid/id|name: **0 independent cardinality** (uid/gid label values are constant per pod → no series multiplication). No-op, not worth adding.
- rest_client drop on the kubelet job: **0 series** (kubelet does not expose rest_client). No-op.

#### Planned end-state YAML (NOT applied — implementation is copy + verify)

The KPS kubelet cAdvisor block (P1.1 re-adds the chart-default CNI drop that our override lost — Helm arrays do not merge; P1.7 adds container_health_state):

```yaml
kubelet:
  serviceMonitor:
    # cAdvisorInterval: 60s   # Phase 3 (optional, future-proofing only)
    cAdvisorMetricRelabelings:
      # P1.1 — re-add the chart-default CNI-interface drop (lost when our override
      # replaced the chart default). -4768 live series. Safe: non-host-network
      # pods report eth0; lxc*/tunl* appear only on host-network pods (duplication).
      - sourceLabels: [__name__, interface]
        separator: ';'
        regex: container_network_.*;(cali|cilium|cni|lxc|nodelocaldns|tunl).*
        action: drop
      # P1.7 — container_health_state has no dashboard/rule consumer. -305.
      - sourceLabels: [__name__]
        regex: container_health_state
        action: drop
      # …existing override entries kept…
```

Drop regex per scrape object for the other DROP rows (attach as `metricRelabelings` on the named ServiceMonitor / PodMonitor / ScrapeConfig; `action: drop`, `sourceLabels: [__name__]`):

| Scrape object (ns/name) | Drop regex (by __name__) | Series |
|---|---|---|
| podMonitor networking/envoy-proxy | `envoy_(cluster_update_duration|sds_update_duration|cluster_upstream_rq_per_cx|cluster_upstream_cx_length_ms|cluster_upstream_cx_connect_ms|cluster_external_upstream_rq_time|listener_downstream_cx_length_ms|listener_connections_accepted_per_socket_event)_bucket` | 2520 |
| SM observability/grafana | `grafana_.*` (or disable the grafana scrape) | 3777 |
| SM kube-system/cilium-agent | `cilium_(hive_jobs_timer_run_duration|k8s_client_api_latency_time|agent_api_process_time|k8s_workqueue_work_duration|k8s_workqueue_queue_duration|node_health_connectivity_latency|hive_jobs_observer_run_duration|policy_selector_cache_operation_duration|datapath_conntrack_gc_duration)_seconds_bucket` | 771 |
| SM kube-system/cilium-operator | `cilium_operator_k8s_client_api_latency_time_seconds_bucket\|cilium_k8s_workqueue_(work\|queue)_duration_seconds_bucket\|cilium_operator_(lbipam_event_processing_time\|ipam_resync_latency\|ipam_resync_duration\|ipam_k8s_sync_latency\|ipam_k8s_sync_duration\|ipam_deficit_resolver_latency\|ipam_deficit_resolver_duration\|hive_jobs_observer_run_duration)_seconds_bucket` | 408 |
| SM networking/envoy-gateway | `rest_client_(request_duration\|rate_limiter_duration\|response_size_bytes\|request_size_bytes)(_bucket\|_sum\|_count)?` | 614 |
| SM volsync-system/volsync | `controller_runtime_reconcile_time_seconds_bucket\|workqueue_(work\|queue)_duration_seconds_bucket` | 268 |
| SM kube-system/metrics-server | `apiserver_response_sizes_bucket\|field_validation_request_duration_seconds_bucket\|metrics_server_.*_bucket\|authentication_duration_seconds_bucket\|authorization_duration_seconds_bucket\|rest_client_(request_duration\|rate_limiter_duration)_seconds_bucket` | 234 |

(Regexes are illustrative for the drop __name__ set; the implementer verifies each against a live `count(metric)` before/after and runs `just k8s test-prom-rules`.)

### Phase 2 — Untapped-value alert gaps (high-value, low-noise) + a factual correction

**Correction (Kör 4, factual — not argument):** the human decision to "switch to prompp because of the resource cost of introducing many new metrics" rests on a misread of Phase 2. Phase 2 introduces NO new metric / scrape target — all three alerts are rules over ALREADY-COLLECTED data. Measured:
- `prometheus_tsdb_storage_blocks_bytes` exists now (count=1, our Prometheus instance).
- `certmanager_certificate_expiration_timestamp_seconds` exists now (count=3: pocket-id-tls, k8tz-tls, horvathzoltan-me).
- `volsync_missed_intervals_total` exists now (count=38, one per replication source).
- A new alert rule adds ~1-2 ALERTS + ~1-2 ALERTS_FOR_STATE series when firing/pending; a dashboard adds 0. Today ALERTS=11, ALERTS_FOR_STATE=11. Three new alert rules ≈ +6 series worst case = +0.008% of the 76965 head. Negligible — this is alerting on existing data, not new collection.

**Net Phase 1 + Phase 2 balance:** Phase 1 confirmed DROP = -13665 series / -117 MB/day; Phase 2 = +6 series / ~0 storage. Net = **-13659 series (-17.8%)**, and a directional head/index-memory reduction of ~-65..-95 Mi RSS (memory-per-series is workload-dependent — NEM ELLENŐRIZVE precisely, but the direction is sound: fewer head series → smaller postings/index). Prometheus RSS today 646 Mi / 2 Gi (32%); after Phase 1, directionally ~560-580 Mi (~28% of 2 Gi). So Phase 1+2 together LOWER resource use, they do not raise it.

- **P2.1 TSDB-growth / retentionSize-approach alert.** New PrometheusRule: `predict_linear(prometheus_tsdb_storage_blocks_bytes[3d], 7d) > 0.9 * prometheus_tsdb_retention_limit_bytes` plus a growth-spike rule. Direct automation of the Kör 1 lesson. Low noise (trend-based).
- **P2.2 cert-manager cert-expiry alert.** New PrometheusRule: `certmanager_certificate_expiration_timestamp_seconds - time() < 7d` (3 certs, soonest ~6d). Covers silent renewal failure; the blackbox `probe_ssl_earliest_cert_expiry{job="idm_probe"} < 1d` only covers external idm TLS, not internal cert-manager certs.
- **P2.3 VolSync backup-missed-interval alert.** New PrometheusRule: `increase(volsync_missed_intervals_total[1h]) > 0`. Existing volsync rules cover exporter-down + out-of-sync, not a missed schedule. `volsync_missed_intervals_total` has dashboard 21356 but no alert. Currently 0 (healthy).

### Phase 3 — Scrape-interval tuning (future-proofing, NOT urgent)

10s -> 60s on the cilium ServiceMonitors (`hubble.metrics.serviceMonitor.interval`, `operator.prometheus.serviceMonitor.interval`, `prometheus.serviceMonitor.interval` in the cilium HelmRelease; chart defaults of 10s we do not override) and on the KPS cAdvisor endpoint (`kubelet.serviceMonitor.cAdvisorInterval: 60s`). Storage is NOT binding (~15.5d headroom), so this is hygiene/future-proofing, not data-loss prevention. Cuts samples 6x on those targets. Engage only when cardinality approaches the ~2.2x headroom or when index pressure shows in Prometheus memory. The `dns-exfil` rule uses `rate(...[5m])` — works at 60s, lower resolution (acceptable for a home cluster).

### Phase 4 — Hardening / UX (low priority)

- **P4.1 Prometheus UI exposure** on `envoy-internal` (LAN-only, behind the OIDC gate) via an HTTPRoute — currently debug is `kubectl get --raw` only.
- **P4.2 Explicit `prometheusSpec.securityContext`** (runAsNonRoot, 64535, fsGroup) — chart-default is already non-root, explicit hardens per repo policy.
- **P4.3 Explicit `prometheusConfigReloader.resources`** (5m/32M) — consistency with repo resource policy.
- **P4.4 Pushover `.Annotations.message` fallback** in the alertmanagerconfig template (description -> summary -> message -> default; today message is missing).


### Phase 5 (CONDITIONAL) — kubeApiServer scrape + measured drop-list (NOT recommended now)

Enabling `kubeApiServer.enabled: true` is the **single largest growth item in the entire roadmap** — an order of magnitude bigger than anything else. A fresh read-only measurement (`kubectl get --raw /metrics` on the apiserver endpoint, nothing enabled):

- The apiserver `/metrics` endpoint alone exposes **55 198 series** — **+72%** over the current 76 965 head (it would nearly double the TSDB).
- Top families (measured): apiserver_request_duration_seconds_bucket 12 144; etcd_request_duration_seconds_bucket 9 984; apiserver_request_sli_duration_seconds_bucket 5 742; apiserver_request_body_size_bytes_bucket 4 672; apiserver_watch_list_duration_seconds_bucket 3 384; apiserver_watch_cache_read_wait_seconds_bucket 2 422; apiserver_response_sizes_bucket 1 712; apiserver_watch_events_sizes_bucket 1 575.

**bjw-s relabelings — measured verdict, not copied for appearances.** Today they are no-ops (kubeApiServer.enabled: false → 0 series; kubelet labeldrop uid/id|name → 0 independent cardinality; rest_client on kubelet → 0 series). They become a **MANDATORY prerequisite** of Phase 5, not an optional add-on — the apiserver families they target are exactly the ones that appear once the scrape is on.

**⚠️ CRITICAL INTERDEPENDENCY — chart-verified this round (Kör 4).** The bjw-s apiserver drop regex is `(apiserver|etcd|rest_client)_request(|_sli|_slo)_duration_seconds_bucket` (Maestro-measured at the bjw-s config, line 52; the bjw-s repo is private/not publicly fetchable — NEM ELLENŐRIZVE from the bjw-s source directly, but the chart half below is independently verified). The `(|_sli|_slo)` alternation **includes the `_sli` variant**, so the regex matches `apiserver_request_sli_duration_seconds_bucket`. That metric is the INPUT to the entire SLO recording chain:

- `kube-apiserver-availability.rules` (recording) builds `cluster_verb_scope_le:apiserver_request_sli_duration_seconds_bucket:increase1h` and the 30d aggregation directly from `apiserver_request_sli_duration_seconds_bucket` — **VERIFIED** from chart source (`prometheus-community/helm-charts`, `templates/prometheus/rules-1.14/kube-apiserver-availability.rules.yaml`); it does NOT reference the non-sli `apiserver_request_duration_seconds_bucket`.
- `kube-apiserver-slos.yaml` alert `KubeAPIErrorBudgetBurn` (4 severities) fires on `apiserver_request:burnrate*` recording rules, which derive from that availability chain — **VERIFIED** from chart source. `kube-apiserver-burnrate.rules` + `kube-apiserver-histogram.rules` feed the same chain.

**Consequence:** enabling the bjw-s relabelings AND the SLO rule groups (`kubeApiserverAvailability: true` + `kubeApiserverSlos: true`) together produces **silently dead rules** — the input metric is dropped, the recording rules evaluate to empty, the burn-rate alerts never fire, and nothing signals the absence. This is the single most dangerous footgun in Phase 5. The bjw-s relabelings and the SLO rule groups are NOT composable as-is; the `_sli` variant MUST be excluded from the drop regex.

**Canonical Phase 5 drop-list (replaces the bjw-s copy — cuts MORE and keeps the SLO chain alive).** Built from the chart rule files (every alert/recording rule's metric usage checked) + the measured per-family series:

KEEP (the SLO chain + the genuinely useful single-node alerts consume these):
- `apiserver_request_sli_duration_seconds_bucket` (5 742) — SLO-chain input (availability/burnrate/histogram). MUST NOT be dropped.
- `apiserver_request_sli_duration_seconds_count` — availability chain.
- `apiserver_request_total` (633) — availability + terminated-requests alert.
- `apiserver_client_certificate_expiration_seconds_bucket` + `_count` — `KubeClientCertificateExpiration` alert (Talos client-cert rotation; the real-value alert — see per-alert eval below).
- `aggregator_unavailable_apiservice*` — `KubeAggregatedAPIDown`/`Errors` alerts.
- `apiserver_request_terminations_total` — `KubeAPITerminatedRequests` alert.

DROP (no rule in any enabled group consumes these) — **-35 893**:

| Metric family | Series |
|---|---|
| apiserver_request_duration_seconds_bucket | 12 144 |
| etcd_request_duration_seconds_bucket | 9 984 |
| apiserver_request_body_size_bytes_bucket | 4 672 |
| apiserver_watch_list_duration_seconds_bucket | 3 384 |
| apiserver_watch_cache_read_wait_seconds_bucket | 2 422 |
| apiserver_response_sizes_bucket | 1 712 |
| apiserver_watch_events_sizes_bucket | 1 575 |
| **Total DROP** | **-35 893** |

Net: 55 198 - 35 893 = **+19 305 series (+25% over the 76 965 head)**. This is BETTER than the bjw-s-only drops (bjw-s: -31 287 → +23 911; this list: -35 893 → +19 305) — it cuts ~4 600 MORE series AND leaves the SLO chain working. The remaining ~19 305 long tail should get a dedicated measurement pass (which other families are unused for a single-node cluster) before Phase 5 is ever engaged; the +19 305 is the floor with this drop-list alone.

**Per-alert evaluation for a single-node cluster (do NOT enable everything automatically).** Our `defaultRules` disable all apiserver groups today (helmrelease.yaml:33-36 `kubeApiserver`/`kubeApiserverAvailability`/`kubeApiserverError`/`kubeApiserverSlos` = false, :44 `kubernetesSystem` = false — **VERIFIED** against the repo file). If Phase 5 is engaged, enable selectively:

- **KubeClientCertificateExpiration** — **REAL value on single-node**: it watches the client certs the apiserver sees (Talos/control-plane cert rotation); a silent rotation failure is exactly the class of bug that bites a single-node cluster with no redundancy. KEEP — this is the headline reason to enable the apiserver scrape at all. Uses `apiserver_client_certificate_expiration_seconds_*` — NEW data, only present with the apiserver scrape on; distinct from the P2.2 `certmanager_*` alert (cert-manager-issued certs).
- **KubeAPIDown / KubeAPIInstanceUnreachable** — **LIMITED value on single-node**: if the apiserver is down, Prometheus runs on the same node and most likely cannot scrape or fire either; the existing dead-man's-switch / heartbeat (Pushover/Watchtower-style) covers this better than an in-cluster alert that depends on the very target that died. Dashboard-only or skip.
- **KubeAPITerminatedRequests / KubeAggregatedAPIDown / KubeAggregatedAPIErrors** — low traffic on a home cluster; evaluate per noise-tolerance. `KubeAggregatedAPIDown` has real value if aggregated APIs (custom resources) are used.
- **KubeAPIErrorBudgetBurn (SLO)** — only enable together with the availability/burnrate/histogram recording groups AND the corrected (sli-preserving) drop-list; otherwise it is the silently-dead footgun above.

**Conclusion.** Phase 5 is the roadmap's largest growth item (+19 305 floor with the aggressive drop-list, +25% head; +23 911 with the bjw-s-only drops) for a single-node home cluster whose apiserver SLO is low-value (one node, no redundancy) — vs Phase 1 which SAVES -13 665 (confirmed DROP). It stays CONDITIONAL and is NOT recommended now. If ever engaged: (1) a dedicated measurement pass on the remaining ~19 305 long tail FIRST; (2) the sli-preserving drop-list above (NOT the bjw-s `_sli`-dropping regex); (3) selective alert enablement weighted to KubeClientCertificateExpiration; (4) measure and accept the net head impact before merge.
### Phase 6 — prompp migration (status: proposed, gated; per a Kör 4 human decision)

**Factual correction carried into the plan (not an argument):** the decision's stated rationale — "switch to prompp because introducing many new metrics would blow up resource use" — rests on the Phase 2 misread corrected above. Phase 2 adds ~6 series on already-collected data; Phase 1 is net negative (-13 665). The decision is respected and the plan is complete regardless; the facts are recorded so the trigger is judged on real pressure, not a misread.

**prompp recap (from Kör 3, unchanged):** C++ storage engine, ~10x memory optimization, on-disk block format IDENTICAL to Prometheus (so it optimizes MEMORY, NOT disk/storage), 2.55-based with 3.0 backports, remote-write supported, `enable_block_manager` feature-flag (v0.8.1) for block compression, ~450★, weekly cadence, v0.8.9 (2026-08-14), Docker Hub, NO cosign/SBOM/provenance.

**Steps:**
1. Override the Prometheus image in the KPS HelmRelease: `prometheusSpec.image: { registry: docker.io, repository: <prompp-repo>, tag: <v0.8.9> }` AND `prometheusSpec.version: <v0.8.9 or a recognized Prometheus version string>` — the operator rejects an unrecognized image as "unsupported version" unless `version` is overridden. NEM ELLENŐRIZVE: confirm the exact override the operator accepts, and the exact prompp image registry/repository/tag (verify against the prompp release + the prometheus-operator docs).
2. Flux/HelmRelease: a `values` change on the existing KPS HelmRelease (no new resource); reconcile; the operator recreates the Prometheus pod with the new image.
3. Version pair: prompp v0.8.x is Prometheus-2.55-based; our current image is Prometheus 3.13.2-distroless. This is a DOWNGRADE in the Prometheus lineage (3.x -> 2.55-base).

**Migration risk — THE critical point (blocking):** our existing TSDB blocks were written by Prometheus 3.13.2; prompp is 2.55-based. Prometheus 3.0 changed TSDB internals (new chunk encodings, native-histogram storage). Whether a 2.55-based reader can open 3.x-written blocks is **NEM ELLENŐRIZVE** — not confirmable from the prompp "identical block format" claim, which is about prompp-vs-Prometheus-2.55 parity, NOT 3.x-backward-read. If 3.x blocks are unreadable by the 2.55-based binary, the migration forces a TSDB wipe / re-initialization (all historical metrics lost) or an export/import path. **This must be verified FIRST** (test on a COPY of the PVC, or confirm in the prompp + Prometheus 3.0 release notes / issue tracker) before any attempt. Do NOT proceed on the assumption that the format is compatible in the 3.x->2.x direction.

**Feature regression (3.x -> 2.55-base):** 3.0/3.x added UTF-8 label values, native histograms (off by default for us), OTLP receiver (we don't use it), remote-write 2.0 (we don't remote-write), UI changes. For this stack we use none of UTF-8 labels / OTLP / native histograms / remote-write, so the regression is mainly UI differences + losing 3.x-only bugfixes. NEM ELLENŐRIZVE per-feature (would need a release-notes diff); directionally low-impact for this stack.

**Supply-chain:** the prompp image is on Docker Hub (Deckhouse/Ozon), NO cosign signature, NO SBOM, NO provenance — unaudited vs the distroless Prometheus image we run (known supply chain). For a home cluster this is a judgment call; for any security-sensitive context it is a blocker.

**Rollback:** revert the HelmRelease `values` (git revert + reconcile) — the operator recreates the pod with the Prometheus 3.x image. Data: if prompp kept the 3.x blocks readable (the open question), no loss; if it rewrote them, the 2.55-format blocks may or may not be 3.x-readable (the SAME NEM ELLENŐRIZVE caveat in reverse). Safest rollback preserves a pre-migration PVC snapshot.

**VERDICT + conditions:** prompp is justified only when memory is ACTUALLY under sustained pressure — Prometheus RSS sustainably > 70-80% of the 2 Gi limit (>= ~1.4-1.6 Gi) for days — AND Phase 1 drops + Phase 3 scrape-interval tuning have been applied and did not solve it. Today RSS = 646 Mi / 2 Gi = 32%, far below any trigger. The data-driven answer today is "not yet" — but the plan is complete so the human decides on facts.

**Cheaper alternatives (measured):**
1. Phase 1 drops alone remove ~17.8% of head series -> proportional index-memory reduction (~-65..-95 Mi RSS, directional).
2. Phase 3 scrape-interval tuning (10s -> 60s on cilium/cAdvisor) cuts samples 6x -> storage + head-churn reduction.
3. **Simply raise the memory limit** — the node has ~49 GB free RAM (MemAvailable 48.9 Gi on k8s-cp0, 23% used at the reading). Raising `prometheusSpec.resources.limits.memory` 2 Gi -> 4 Gi costs nothing here and removes the ceiling entirely at the current scale. This is by far the cheapest path to "keep the memory ceiling" and makes prompp unnecessary until cardinality grows ~5-10x. NEM ELLENŐRIZVE: confirm the node's steady-state free RAM under full cluster load (the 49 GB is a single reading; verify it is not transiently high).

**Known risks (the former rejection reasons, kept inside this phase):** on-disk format identical to Prometheus -> storage NOT reduced (prompp optimizes memory, not disk); downgrade direction (3.x -> 2.55); supply-chain unaudited (no cosign/SBOM); young project (~450★, weekly cadence). These do not block the decision but must be accepted. Re-evaluation triggers (no need to re-research from scratch): (1) `enable_block_manager` matures AND also compresses on-disk blocks; (2) memory pressure actually appears (series 5-10x, RSS near the limit); (3) the image gains cosign + SBOM; (4) the 3.x->2.55 read-compat is verified.

## Follow-on (NOT a phase of this roadmap)

- **Long-term metric storage / DR — separate ADR.** Single Prometheus, 5Gi PVC, no remoteWrite: if the node/PVC is lost, all metrics are lost. vmsingle (we already run VictoriaLogs — same vendor, 5-10x compression) is the strongest mid-term option. This is an architectural decision (new component, separate storage) with its own trade-offs and becomes its OWN ADR in `docs/decisions`, linked here as the next step — NOT a phase of this hygiene roadmap.

## Closed / explained (not findings)

- **K-1 VISSZAVONVA** — the "~6h retention, DB ~15GB/day, 7d ~100GB" ~50x over-estimate; the 8-day node outage confounded the evidence. Real: 7d retention, storage NOT binding (headroom ~2.2x). Documented so the reasoning is not lost.
- **F-2 MEGOLDÓDOTT** — CrowdSecBlocklistImportMetricsAbsent resolved by the overnight run; also an outage artifact (the CronJob had not run since the node came back). The freshness alert is now green.
- **P1.3 (Kör 3) corrected in Kör 4** — the 920 node_systemd_unit_state series are nas-node's REAL OMV/Debian systemd, NOT Talos container units. Disabling the Talos node-exporter systemd collector is a no-op (Talos has no systemd). nas-node unit_state is now VERIFY V1, not a blanket drop.

## Acceptance criteria (per phase, observable)

- **P1.1:** `count(container_network_receive_bytes_total{interface=~"lxc.*"})` == 0 (live) AND the k8s-views-pods per-pod eth0 network panels still show data. Test: `just k8s test-prom-rules` green; reconcile; verify query.
- **P1.2/P1.2b:** `count(envoy_cluster_update_duration_bucket)` == 0 AND `count(envoy_sds_update_duration_bucket)` == 0 (and the other listed envoy buckets); envoy-proxy-global panels (upstream_rq, membership) still show data.
- **P1.3:** `count(grafana_feature_toggles_info)` == 0 (grafana_* gone) — if dropped via metricRelabeling; OR the grafana ServiceMonitor is disabled. No other dashboard breaks (none used grafana_*).
- **P1.4/P1.5:** `count(cilium_hive_jobs_timer_run_duration_seconds_bucket)` == 0 (and the other listed cilium buckets); cilium-dashboard panels (endpoint_regeneration, proxy_upstream_reply, policy, bpf) still show data.
- **P1.6:** `count(rest_client_request_duration_seconds_bucket{job="envoy-gateway"})` == 0; envoy-gateway-global panels (watchable/status_update/resource_apply) still show data.
- **P1.7:** `count(container_health_state)` == 0.
- **P1.8/P1.9:** the listed volsync/metrics-server operator-internal buckets == 0; volsync dashboard + flux-k8s-api-performance still show data.
- **P2.1:** the TSDB-growth rule unit-tested (promtool, fire on a synthetic 7d-to-cap series + no-fire on flat); `prometheus_tsdb_storage_blocks_bytes` queryable.
- **P2.2:** the cert-expiry rule unit-tested (fire <7d, no-fire >7d, boundary at 7d); `count(certmanager_certificate_expiration_timestamp_seconds)` == 3; the `{{ $labels.name }}` template renders (asserted via test exp_annotations).
- **P2.3:** the missed-interval rule unit-tested (fire on increase>0, no-fire at 0); `volsync_missed_intervals_total` queryable.
- **P3:** after change, cilium/hubble/kubelet-cAdvisor targets show `interval=60s` in `/api/v1/targets`; `dns-exfil` rule still unit-tests green; `rate(hubble_dns_queries_total[5m])` still returns data.
- **P4.1:** `curl -k https://prometheus.<internal-domain>/api/v1/status/config` returns 200 from the LAN (OIDC-gated); blocked from outside.
- **P4.2-4.4:** manifest diff shows the explicit fields; no behavioral regression.
- **Phase 5:** only proceed if `kubeApiServer.enabled` flips to true; THEN the bjw-s relabelings are applied as a MANDATORY part of the same change; a dedicated measurement pass + aggressive drop-list is run first; `count(apiserver_request_duration_seconds_bucket)` is bounded by the adopted drops and the chosen apiserver-SLO dashboard shows data. Net head impact is measured and accepted before merge.
- **Phase 6:** NOT executed unless RSS sustainably > 70-80% of limit after Phase 1+3; the 3.x->2.55 TSDB read-compat is verified on a PVC copy FIRST (blocking gate); the image supply chain is accepted; a pre-migration PVC snapshot exists for rollback.

## Non-goals

- Do NOT size PVC/retentionSize up as a hygiene action (storage not binding). Raising the MEMORY limit is a separate cheap option (Phase 6 alternatives) and may be chosen independently.
- Do NOT enable etcd/apiserver/scheduler default rule groups or the kubeApiServer scrape except as the conditional, measured Phase 5.
- Do NOT hard-drop uncertain metrics (container_pressure_*, blocklist_import_errors_total, nas-node node_systemd_unit_state, pocket-id http_*, container_processes/sockets, node-exporter interface metadata) — VERIFY / keep for debug.
- Do NOT adopt prompp before verifying the 3.x -> 2.55 TSDB read-compatibility (blocking risk) and before confirming the cheaper alternatives (raise the limit, Phase 1, Phase 3) are insufficient.
- Do NOT introduce noisy alerts (speedtest bandwidth, envoy 5xx on home-cluster traffic) — dashboard-only where not actionable.
