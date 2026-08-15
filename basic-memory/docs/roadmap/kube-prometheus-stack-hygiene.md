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


## Phase 1 Execution Record (2026-08-15)

**Implementer**: Llama dev subterminal. **Maestro (supervising)**: Claude Code #2.
**Branch**: `main` (GitHub project — direct-to-main is the established pattern; no PR required for this work).
**Status**: DONE — all 9 code commits pushed; this docs commit closes Phase 1.

### Gate evidence (all 9 commits)

Every commit was verified before staging with **per-commit AFTER=0 + KEEP populated** (the
Maestro gate and the reliable cardinality signal), `just k8s test-prom-rules` green, and
pre-commit (yamlfmt/yamllint/gitleaks) green on the touched files. Staging was explicit-pathspec
per file from a clean working tree (`git status` checked before each `git add`).

### Commit-by-commit drop table

| # | SHA | Scope | File(s) | Drop families (metricRelabelings regex) | Measured BEFORE->AFTER |
|---|-----|-------|---------|------------------------------------------|------------------------|
| C1 | `e8c7caf9b` | observability (fix) | `kube-prometheus-stack/app/helmrelease.yaml` | restore chart-default CNI `container_network_*` drop lost to the repo override (P1.1) | CNI-iface series ->0; KEEP eth0=70, non-CNI=259 |
| C2 | `23103d348` | observability | `kube-prometheus-stack/app/helmrelease.yaml` | cAdvisor `container_(memory_failures|last_seen|memory_kernel|failcnt|blkio_device|start_time|threads|ulimits_soft|health_state|processes|sockets).*` + node-exporter `node_network_(flags|device_id|dormant|iface_link_mode|transmit_queue_length|carrier.*|address_assign_type|name_assign_type|net_dev_group|protocol_type)` (P1.7, V3, V4) | health_state/processes/sockets 248->0 each; node_network V4 metadata ->0 |
| C3 | `24cc4c317` | cilium | `cilium/app/helmrelease.yaml` | cilium-agent + cilium-operator latency histograms, **bucket-only** (P1.4, P1.5); chart hooks `prometheus.serviceMonitor.metricRelabelings` / `operator.prometheus.serviceMonitor.metricRelabelings` confirmed by helm template render | 771+456=1227->0; KEEP endpoint_regeneration / policy_implementation / proxy_upstream_reply intact |
| C4 | `66a6b8c95` | envoy-gateway | `networking/envoy-gateway/config/observability.yaml` | envoy-proxy `envoy_cluster_update_duration` / `envoy_sds_update_duration` + upstream cx/rq buckets (P1.2/P1.2b, **bucket-only**) and envoy-gateway `rest_client_*` (**all-parts** _bucket/_sum/_count) (P1.6) | 1400+1100+710=3210->0; KEEP upstream_rq_time, http_downstream_rq_time, watchable/status_update/resource_apply intact |
| C5 | `0b55a82c` | grafana | `observability/grafana/instance/servicemonitor.yaml` | `grafana_.*` + `^go_.*` (P1.3, broadened from the roadmap's specific-bucket list — no dashboard consumes any `grafana_*`) | grafana_* 3705->0; the **separate** `grafana-operator-metrics-service` SM left untouched (controller_runtime_reconcile_total=48, workqueue_depth=4) |
| C6 | `cf8af62eb` | metrics-server | `metrics-server/app/helmrelease.yaml` | `apiserver_response_sizes_bucket|field_validation_request_duration_seconds_bucket|metrics_server_.*_bucket|authentication_duration_seconds_bucket|authorization_duration_seconds_bucket|rest_client_.*_bucket` (P1.9); chart hook + `values.yaml metricRelabelings: []` confirmed | 263->0; KEEP `apiserver_request_{duration,slo,sli}` |
| C7 | `e0c7598e7` | volsync | `volsync/app/helmrelease.yaml` | `controller_runtime_reconcile_time_seconds_bucket|workqueue_(work|queue)_duration_seconds_bucket` (P1.8) via **postRenderers** (chart SM is hardcoded, no metricRelabelings hook) | 268->0; rendered endpoint verified — `interval: 30s` + `tlsConfig.insecureSkipVerify: true` preserved, metricRelabelings added |
| C8 | `50c73a2b9` | observability | `kube-prometheus-stack/app/scrapeconfigs/{nas-node,openwrt}.yaml` | V4 node_network metadata (both) + V1 `node_systemd_unit_state` (nas-node only; OpenWRT exposes 0 systemd, V1 N/A) | nas 946->0 + openwrt 234->0; openwrt exposure confirmed (18 iface x 13 families); node-network traffic families kept |
| C9 | `57bee7df8` | pocket-id | `pocket-id/app/helmrelease.yaml` | IdP HTTP histograms (**all-parts**): `http_server_{request_body_size_bytes,response_body_size_bytes,request_duration_seconds}_(bucket|sum|count)|http_client_request_.*_(bucket|sum|count)` (V2); bjw-s app-template `endpoints[].metricRelabelings` passthrough confirmed via render-test | 1059->0 |

**Dropped total (measured, per-commit sum)**: ~16.9k series across the 9 commits.

### Net head before/after — and a surprise

- **Head start (Phase 1 baseline)**: `prometheus_tsdb_head_series` = **72 234** (the live re-measurement at Phase 1 start; ratified by the Maestro to supersede the roadmap's plan-time 76 965 — recorded here per the RATIFY refinement).
- **Head now**: **77 495** — a **net +5 261** (an *increase*), despite the ~16.9k verified drops.
- **Diagnosis (the surprise)**: the aggregate head gauge is **churn-dominated over the ~45-min implementation window**, not drop-dominated. Evidence: `created_total=238 727`, `removed_total=161 232` (net = head, so the gauge is not lagging/buggy); current `rate(created[5m])=0.59/s` vs `rate(removed[5m])=0/s` — the head is still slowly growing from churn while `metricRelabelings drop` prevents *creation* (it does not cause *removal*; already-ingested stale series evict only after staleness + head GC). Cluster churn during the window (Flux reconciling 9 SMs + normal activity) added roughly the same ~17k the drops removed, leaving the aggregate net ~flat-to-slightly-up versus the roadmap's 76 965 baseline.
- **Why the drops are still confirmed real**: the per-target counts dropped as expected (cilium-agent ~2298->1071, envoy-proxy ~11 000->7790, etc.), and every commit's AFTER=0 + KEEP-populated was verified independently. The **per-commit AFTER=0 + KEEP is the Maestro gate and the reliable signal**; the aggregate head over a 45-min active window is too noisy to be the reduction metric.
- **Recommendation**: re-measure `prometheus_tsdb_head_series` after a stabilization window (no active reconciles, ~15-30 min) — the true net reduction should surface as the dropped stale series evict and churn subsides. Expected steady-state reduction is ~16.9k below the pre-Phase-1 head.

### Implementation decisions worth recording

- **Head offset**: the roadmap's plan-time 76 965 head was superseded by the live 72 234 measurement at Phase 1 start (Maestro RATIFY). Per-commit BEFORE values used live measurements where captured; plan-time roadmap values are marked where the live capture was noisy.
- **V2 (pocket-id) — full histogram, not bucket-only**: the roadmap listed V2 as specific `_bucket` names (~939 series). Implemented as the **full histogram** (all-parts: `_bucket/_sum/_count`, ~1059 series) for a faithful drop with no orphaned `_sum/_count`, consistent with P1.6's all-parts treatment. Human-approved drop — SSO request-latency/body-size is not retained.
- **V4 — three jobs, not one**: the roadmap's "SM node-exporter" V4 location was imprecise. V4 node-network interface metadata was applied on all three jobs that expose it: node-exporter (C2, in the KPS cAdvisor relabeling neighbour), nas-node (C8), and openwrt (C8). OpenWRT exposure confirmed first (18 interfaces x 13 families = 234 series) before applying, per Maestro RATIFY (a). The `carrier.*` regex does not cover `transmit_carrier_total` (transmit-prefixed -> KEPT traffic family).
- **P1.8 (volsync) — postRenderers, not values**: the volsync-perfectra1n chart's ServiceMonitor is hardcoded with no `metricRelabelings` value hook, so the drop is patched via `postRenderers` (kustomize strategic-merge). The patch carries the **full endpoint** (`interval: 30s`, `path: /metrics`, `port: https`, `scheme: https`, `tlsConfig.insecureSkipVerify: true`) for CRD list-merge safety — kustomize merges by the `port: https` key, preserving interval/tlsConfig while adding metricRelabelings. Render verified the merged endpoint.
- **C8/C9 type is perf, not remove** (Maestro RATIFY (c)) — these drop unconsumed metrics from collection; they do not remove code.

### Next

Phase 2 (untapped-value alert gaps + the factual correction) is **not started**; its brief is pending Maestro verification of this Phase 1 record. The dropped metrics have no dashboard/PrometheusRule consumer (verified per-family against the cluster's Grafana dashboards and PrometheusRules), so no consumer breaks.


## Phase 2 In-Progress Checkpoint (2026-08-15)

Context-survival checkpoint (context at 64%; clear+reload expected before Phase 3). Captures ratified decisions + the P2.2 redesign + open follow-ups so a fresh-context session can resume. The authoritative record of completed commits is git; this note is the non-obvious state.

### Ratified + implemented this turn (P2.1 = Commit A, P2.3 = Commit C)
- **P2.1 (Commit A) — TSDB-growth.** Files: kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/tsdb-growth.yaml + tsdb-growth_test.yaml + add ./tsdb-growth.yaml to that dir kustomization.yaml.
  - Trend expr (warning, for: 30m): `max by (job) (predict_linear(prometheus_tsdb_storage_blocks_bytes[3d], 7d)) > 0.9 * max by (job) (prometheus_tsdb_retention_limit_bytes)`. The max by (job) scopes away a stale churned-pod-IP series producing predict=-1.24e11 garbage. Live baseline at deploy: retention_limit=4 718 592 000 (4.5 GB, matches retentionSize: 4500MB), blocks_bytes=~230 MB, predict=2.77 GB, 0.9*limit=4.04 GB, ratio=68.6% (31% headroom, does NOT fire on deploy).
  - Spike expr (warning, for: 5m): `increase(prometheus_tsdb_storage_blocks_bytes[1h]) > 100000000`.
  - Spike step-size CONFIRMED safe (Maestro condition): natural single 2h-block step measured = ~34 MB (increase[2h]=33.7 MB; blocks_bytes 230 MB / blocks_loaded 6 = 38.4 MB/block avg; increase[6h]=85 MB ~ 2.5 blocks). Blocks land every 2h so increase[1h] sees at most one block (~34 MB). 100 MB/h ~ 3x the single-block step; NOT close -> keep 100 MB/h, no widen/raise.
- **P2.3 (Commit C) — VolSync missed-interval.** APPEND to existing kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml (volsync.rules group) + extend prometheusrule_test.yaml.
  - Expr (warning, for: 15m): `increase(volsync_missed_intervals_total[1h]) > 0`.
  - ROADMAP CORRECTION: the identity label is obj_name/obj_namespace/role, NOT $labels.name as the roadmap assumed. Annotation uses {{ $labels.obj_namespace }}/{{ $labels.obj_name }} (matches the existing volsync rule). Does NOT fire on deploy (all volsync_missed_intervals_total = 0, increase[1h] = 0).

### P2.2 (Commit B) — REDESIGNED, HELD for ratify (NOT implemented)
- Premise CORRECTION (record like the Phase 1 head-drift / V4 corrections): the roadmap "soonest ~6d" was a MISREAD. horvathzoltan-me + pocket-id-tls are SHORT-LIVED certs (duration 160h ~ 6.67d, renewBefore 1/3 ~ 53h), healthy Ready=True. A 160h cert is NEVER more than 6.67d from expiry, so an absolute <7d rule is true 100% forever — not a canary and not fixable by tightening. k8tz-tls is 2160h (90d), renewBefore 720h (30d). An absolute day threshold cannot span both.
- Confirmed live metrics: certmanager_certificate_expiration_timestamp_seconds (notAfter), certmanager_certificate_renewal_timestamp_seconds (renewalTime = notAfter - renewBefore; advances ONLY on successful renewal), certmanager_certificate_ready_status{condition=True|False|Unknown} (gauge=1 when current). certmanager_certificate_not_after_seconds ABSENT; no certmanager_certificate_request_* metrics.
- Proposed redesign (relative to each cert own cycle):
  - Rule 1 CertManagerRenewalLate (warning, for: 1h): `time() > certmanager_certificate_renewal_timestamp_seconds`. Fires when renewal is >1h past its scheduled time (relative — no absolute day count). Silent through normal renewal (renewal_timestamp advances on success within minutes; for:1h rides it out). Uniform for 160h and 2160h certs. Current state: time() < renewal_timestamp for all 3 (healthy, mid-cycle) -> does NOT fire on deploy.
  - Rule 2 CertManagerCertificateExpired (critical, for: 5m): `time() > certmanager_certificate_expiration_timestamp_seconds`. Catastrophic backstop (cert actually lapsed). Rule 1 gives ~52h lead for the 160h cert; Rule 2 is the last-resort page.
  - REJECTED: a ready_status{condition=True} != 1 rule (for:15m) — would false-positive on a slow-but-healthy ACME renewal (>15 min DNS propagation); Rule 1 covers the failure mode more cleanly without that noise.
  - Location: kubernetes/apps/cert-manager/cert-manager/app/prometheusrule.yaml + prometheusrule_test.yaml + app/kustomization.yaml (colocated, ACCEPTED). Annotation labels name + exported_namespace render (asserted via exp_annotations).
- AWAITING Maestro ratify of Rule 1+2 (and for:1h vs for:2h tolerance) before implementing Commit B.

### Open follow-ups (survive context clear)
1. P2.1 3-day predict watch (Maestro condition, cannot live in context): measure `predict_linear(prometheus_tsdb_storage_blocks_bytes[3d], 7d)` and the 0.9*retention_limit ratio DAILY on 2026-08-16, 2026-08-17, 2026-08-18. Expect the predict value to DECREASE as the 3d window slides past the Phase-1 drop (decaying high bias). An UPWARD trend once the window is fully post-drop (~3 days out) = real growth, not window pollution -> investigate cardinality. Baseline at deploy: predict=2.77 GB, threshold=4.04 GB, ratio=68.6%.
2. P2.1 spike step-size: confirmed ~34 MB/block, 100 MB/h = ~3x margin (safe).
3. P2.2 ratify pending -> implement Commit B -> FINAL docs commit (append a Phase 2 Completion section to this note + commit all basic-memory/ changes: this checkpoint + the completion).

### Resume state for a fresh-context session
- If A and C are committed (git log shows the feat commits on main) but P2.2 not done: await/implement Commit B per the ratified expression above (check the Maestro ratify message for the final for: value), then the final docs commit. Working tree may carry an unstaged basic-memory/ change (this checkpoint) — it is intentional, committed only in the final docs commit.


## Phase 2 RATIFIED Implementation Plan (2026-08-15) — AUTHORITATIVE

Status (all four decisions ratified by the Maestro on 2026-08-15):
- P2.1 TSDB-growth trend + spike — RATIFIED.
- P2.2 cert-manager redesign (renewal-relative) — RATIFIED. SUPERSEDES the "HELD for ratify" language in the Phase 2 In-Progress Checkpoint section above; read this section, not that one, for P2.2.
- P2.3 VolSync missed-interval — RATIFIED.
- P2.2 location (cert-manager/app/ colocated) — RATIFIED.

Two judgment calls made with the available evidence (Maestro delegated both; will not overrule):
1. **Rule 1 `for: 2h` (not 1h).** A 160h cert (renewBefore 53h) gives lead time = 53h - for. for:1h => 52h; for:2h => 51h. The 1h cost is negligible against 51h, and for:2h rides out a slow-but-healthy ACME DNS-01 renewal (DNS propagation + one retry cycle, up to ~2h) without a false page. Normal renewal completes in minutes; for:2h keeps the alert silent through it. Taken the Maestro's suggestion.
2. **Spike alert uses `delta`, not `increase`.** `prometheus_tsdb_storage_blocks_bytes` is a GAUGE with legitimate DOWN-steps at compaction merges (3 blocks -> 1) and retention evictions. `increase`/`rate` apply counter-reset semantics and inflate on those down-steps, which can false-fire a spike at the next compaction. `delta` (pure net change, no reset handling) catches a genuine runaway-block persist (net up > 100 MB in 1 h) and stays silent on compaction-only movement. The ~34 MB natural per-block step / 3x margin analysis is unchanged (delta[1h] right after a normal persist = ~34 MB, same as the increase measurement, because no down-step was in that window). This is a correctness refinement of the ratified spike alert (same name, same 100 MB threshold, same purpose); document it in the commit body and the docs commit.

### Commit plan (4 commits, all on main, then push)

Each code commit: explicit pathspec staging (`git add <file> ...` per touched file — NEVER `git add -A`/`git add .`), conventional emoji commit. The working tree carries an UNSTAGED `basic-memory/` change (this checkpoint); it is intentionally left unstaged through A/B/C and committed only in the docs commit D.

**Commit A — P2.1 TSDB-growth.** Message: `✨ feat(observability): add TSDB growth-trend and spike alerts`.
- NEW `kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/tsdb-growth.yaml` — PrometheusRule name `tsdb-growth`, group `tsdb.rules`:
  - Alert `PrometheusTSDBGrowthTrend` (severity: warning, for: 30m):
    `expr: max by (job) (predict_linear(prometheus_tsdb_storage_blocks_bytes[3d], 7d)) > 0.9 * max by (job) (prometheus_tsdb_retention_limit_bytes)`
    The `max by (job)` on BOTH sides scopes away a stale churned-pod-IP series whose predict_linear returns a garbage -1.24e11. Annotation names the job via {{ $labels.job }} and states the 90%-of-retention-in-7d condition.
  - Alert `PrometheusTSDBSpike` (severity: warning, for: 5m):
    `expr: max by (job) (delta(prometheus_tsdb_storage_blocks_bytes[1h])) > 100000000`
    (delta, not increase — see judgment call #2.) Annotation names the job and flags possible runaway cardinality.
- NEW `kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/tsdb-growth_test.yaml` (schema json.schemastore.org/prometheus.rules.test.json, `rule_files: [./.extracted_prometheus_rules.yaml]`, `evaluation_interval: 1m`). Run via `just k8s test-prom-rules`.
  - Trend fire: blocks_bytes on a linear ramp so predict_linear(3d,7d) > 0.9*limit. With retention_limit_bytes constant = 4 718 592 000 (4500 MiB), threshold = 4 246 732 800. Use ramp v0=2.5e9 at rate r=200 000/min (v(t)=2.5e9 + 200000*t). predict at T=3d (window full, 4320 samples) = v(3d) + r*10080 = (2.5e9 + 200000*4320) + 200000*10080 = 2.5e9 + 8.64e8 + 2.016e9 = 5.38e9 > 4.246e9. Holds across the 30m `for` (ramp continues) -> fires at eval 3d+30m = 4350m. exp_labels: alertname + severity=warning + job (the prometheus job label, e.g. "kube-prometheus-stack-prometheus"). exp_annotations asserted (job renders).
  - Trend no-fire: blocks_bytes flat at 2.5e9 -> predict 2.5e9 < 4.246e9 -> no fire.
  - Trend boundary pair (proves > strictness, not >=): rate r=120 000/min -> predict = 2.5e9 + 120000*14400 = 4.228e9 (just BELOW 4.246e9) -> NO fire; rate r=122 000/min -> predict = 2.5e9 + 122000*14400 = 4.257e9 (just ABOVE) -> fire. (14400 = 3d+7d in minutes = 4320+10080.) This pair straddles the threshold.
  - Spike fire: blocks_bytes steps up by 150 000 000 in the last 1h (e.g. flat 2.5e9 for a while, then +150e6) so delta[1h] = 150e6 > 100e6. Holds 5m -> fires at the step + 5m. exp_labels + exp_annotations asserted.
  - Spike no-fire: a normal ~34 MB block step (delta[1h]=34e6 < 100e6) -> no fire. Use a +34 000 000 step.
  - Spike no-fire (compaction down-step): blocks_bytes steps DOWN 70e6 (compaction merge) -> delta[1h] negative -> no fire (proves delta does not false-fire on compaction, the increase->delta fix's value).
  - NOTE: the exact promtool `values` strings (e.g. `2500000000+200000x4350`) are derivable from the rates above; model the ramp with `v0+rate x N` notation and the step with flat-then-jump. The retention_limit_bytes input series is a constant `4718592000x N` (or whatever 4500 MiB resolves to — verify: 4500*1024*1024 = 4 718 592 000). Keep eval times past the `for:` (trend eval at 4350m; spike fire at step+5m).

**Commit B — P2.2 cert-manager.** Message: `✨ feat(cert-manager): add renewal-relative certificate expiry alerts`.
- NEW `kubernetes/apps/cert-manager/cert-manager/app/prometheusrule.yaml` — PrometheusRule name `cert-manager`, group `cert-manager.rules`:
  - Alert `CertManagerRenewalLate` (severity: warning, for: 2h):
    `expr: time() > certmanager_certificate_renewal_timestamp_seconds`
    Annotation: `Certificate {{ $labels.name }} in namespace {{ $labels.exported_namespace }} renewal is overdue — cert-manager has not renewed past the scheduled renewal time.`
  - Alert `CertManagerCertificateExpired` (severity: critical, for: 5m):
    `expr: time() > certmanager_certificate_expiration_timestamp_seconds`
    Annotation: `Certificate {{ $labels.name }} in namespace {{ $labels.exported_namespace }} has expired.`
  - Confirmed live metrics (measured this session): both exist. Per-cert label set: name, exported_namespace, issuer_name, issuer_kind. Current healthy state: time() < renewal_timestamp for all 3 certs (horvathzoltan-me renewal=1787109943, pocket-id-tls=1787109889, k8tz-tls=1790452645; now ~1786790430) -> NEITHER alert fires on deploy.
- NEW `kubernetes/apps/cert-manager/cert-manager/app/prometheusrule_test.yaml`:
  - RenewalLate fire: set renewal_timestamp in the PAST relative to eval time (e.g. renewal_ts = eval_time - 3h, so time() > renewal_ts holds) for >2h -> fires at eval past 2h. Model: a constant series `certmanager_certificate_renewal_timestamp_seconds{name="...",exported_namespace="..."}` with a fixed unix value; eval_time chosen so time() at eval > ts + 2h. exp_labels: alertname + severity=warning + name + exported_namespace. exp_annotations asserted (name + exported_namespace render).
  - RenewalLate no-fire: renewal_timestamp in the FUTURE (healthy mid-cycle) -> time() < ts -> no fire.
  - RenewalLate no-fire (brief normal-renewal window): renewal_ts = eval_time - 30m (renewal in progress, just 30m past) -> time() > ts holds but only 30m < for:2h -> NOT yet firing (proves for:2h rides out a normal renewal). This is the key no-spurious-fire case.
  - Expired fire: expiration_timestamp in the past (time() > expiration_ts) for >5m -> fires.
  - Expired no-fire: expiration_timestamp in the future -> no fire.
  - NOTE: promtool cannot call time() arbitrarily; use fixed eval_time values and set the timestamp series to fixed unix seconds so the comparison is deterministic. e.g. eval_time: 2h0m, series value 3600 (1h after epoch) -> time()=7200 > 3600 by 1h... choose values so the for: boundary is clear. The fresh me picks concrete unix-second values and eval_times that make the > and for: semantics unambiguous (the pattern is: renewal_ts = T - delta, eval at T, fire iff delta > for:).
- MODIFY `kubernetes/apps/cert-manager/cert-manager/app/kustomization.yaml` — add `- ./prometheusrule.yaml` to resources (currently lists ocirepository, grafanafolder, grafanadashboard, helmrelease).

**Commit C — P2.3 VolSync missed-interval.** Message: `✨ feat(volsync): add missed-interval alert`.
- MODIFY `kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml` — APPEND a 3rd rule to the existing `volsync.rules` group (after VolSyncVolumeOutOfSync):
  - Alert `VolSyncMissedInterval` (severity: warning, for: 15m):
    `expr: increase(volsync_missed_intervals_total[1h]) > 0`
    Annotation: `VolSync {{ $labels.obj_namespace }}/{{ $labels.obj_name }} missed a scheduled sync interval.`
    (volsync_missed_intervals_total is a COUNTER, so increase is correct here — unlike the TSDB gauge. Identity labels are obj_name/obj_namespace/role, NOT name — see correction #2.)
- MODIFY `kubernetes/apps/volsync-system/volsync/app/prometheusrule_test.yaml` — APPEND test cases following the existing a/b/c pattern:
  - Fire: missed_intervals_total increments by 1 in the last 1h (e.g. `0x10 1x7` -> increase[1h]=1 > 0 at eval 16m, holds 15m) -> fires. exp_labels: alertname + severity=warning + obj_namespace + obj_name. exp_annotations asserted (obj_namespace/obj_name render).
  - No-fire: counter flat at 0 (increase[1h]=0) -> no fire.
  - No-fire: counter flat at a constant 5 (steady, no increase) -> increase[1h]=0 -> no fire (proves it is increase>0, not the absolute value).
- NO new file, NO kustomization change (prometheusrule.yaml already in the volsync app kustomization).

**Commit D — docs.** Message: `📝 docs(progress): record Phase 2 of kube-prometheus-stack-hygiene`.
- First APPEND a "Phase 2 Completion" section to THIS BM note (via edit_note append): commits A/B/C shas, per-commit gate results (test-prom-rules green, pre-commit green, LOADED proof, no-fire proof with the live query values), the 3 roadmap corrections (below), and the spike increase->delta fix rationale.
- Then `git add basic-memory/` (explicit pathspec covering the BM dir) and commit. (This stages BOTH the In-Progress Checkpoint written earlier AND the Phase 2 Completion + this plan — all the unstaged basic-memory changes land together in the docs commit, as intended.)

### Per-commit gates (apply to A, B, C)
1. promtool unit tests for the rule's test file pass: positive/fire case + negative/no-fire case + boundary pair (threshold strictness: > not >=, == not >=) + asserted exp_annotations (a broken {{ $labels.* }} or $value template MUST fail the suite). The bar is BM ADR docs/decisions/promtool-unit-test-bar and kubernetes/CLAUDE.md "PrometheusRule Unit Tests".
2. `just k8s test-prom-rules` green (whole suite — the recipe copies tests + .extracted_prometheus_rules.yaml into a mktemp scratch dir; writes nothing under kubernetes/).
3. pre-commit green on the touched files (`pre-commit run --files <files>` or full run).
4. explicit pathspec staging (`git add <file> ...` per touched file; NEVER `git add -A` / `git add .` — the working tree carries the intentional unstaged basic-memory/ change).
5. AFTER commit + push: reconcile the touched Flux Kustomization (`just k8s flux-reconcile` or wait for auto-reconcile) and verify the rule is LOADED + evaluating + NOT firing against live data:
   - LOADED: `kubectl get --raw '/api/v1/namespaces/observability/services/prometheus-operated:9090/proxy/api/v1/rules'` shows the new rule (filter by rule_name).
   - No spurious firing: evaluate each expr against real data via the prometheus proxy `/api/v1/query?query=<urlenc>` and confirm the result is empty (no firing):
     - P2.1 trend: predict=2.77 GB < 4.04 GB (0.9*4.5GB) -> NOT firing. P2.1 spike: delta[1h] ~0 (no block in the last 1h) or ~34 MB (one block) << 100 MB -> NOT firing.
     - P2.2 RenewalLate: time() < renewal_timestamp for all 3 certs -> NOT firing. Expired: time() < expiration_timestamp for all 3 -> NOT firing.
     - P2.3 missed: increase(volsync_missed_intervals_total[1h]) = 0 for all volsync objects -> NOT firing.
   - This "no spurious firing on deploy" check is THE gate that makes a commit fully verified, not half-verified.
6. The Maestro's stated risk is a commit landing half-verified (auto-compact mid-gate). Do NOT start the next commit until the current one is pushed + reconciled + LOADED + no-fire-verified.

### Three roadmap corrections to record (in the Commit D docs / Phase 2 Completion section)
1. P2.2 short-lived-cert premise MISREAD: the roadmap's "soonest ~6d to expiry" observation was a healthy short-lived cert (horvathzoltan-me + pocket-id-tls, duration 160h ~ 6.67d, renewBefore 1/3 ~ 53h) at rest mid-cycle, NOT a near-expiry cert. A 160h cert is never more than 6.67d from expiry, so an absolute <7d rule is true forever — not a canary. k8tz-tls is 2160h (90d, renewBefore 720h/30d). Absolute day thresholds cannot span both; the ratified redesign is renewal-relative (time() > renewal_timestamp). This corrects the roadmap's P2.2 premise.
2. P2.3 identity labels: the roadmap said `$labels.name`; the live volsync metrics use `obj_name` / `obj_namespace` / `role`. The VolSyncMissedInterval annotation uses {{ $labels.obj_namespace }}/{{ $labels.obj_name }} to match the existing volsync rules.
3. P2.1 spike function: the roadmap said `increase`; corrected to `delta` because prometheus_tsdb_storage_blocks_bytes is a gauge with compaction/retention down-steps that inflate increase's counter-reset logic. (Judgment call #2 above.)

### Open follow-up (dated, survives context)
- P2.1 3-day predict watch (Maestro condition): measure `predict_linear(prometheus_tsdb_storage_blocks_bytes[3d], 7d)` and the ratio to 0.9*retention_limit DAILY on 2026-08-16, 2026-08-17, 2026-08-18. Expect the predict value to DECREASE as the 3d window slides past the Phase-1 metricRelabeling drop (the pre-drop high samples age out of the window — decaying high bias, not real growth). An UPWARD trend once the window is fully post-drop (~3 days out, from ~2026-08-18) = real cardinality growth, not window pollution -> investigate. Baseline at deploy (2026-08-15): predict=2.77 GB, threshold=4.04 GB, ratio=68.6%, 31% headroom. Record each day's value + ratio in this note.

### Resume / signal protocol
- After `/clear` + reload from this BM note: signal the Maestro "Phase 2 context reloaded, implementing".
- Then implement A -> C -> B -> D in order, each with the per-commit gates above (do not start the next until the current is pushed + reconciled + LOADED + no-fire-verified).
- Single completion signal when A+B+C+docs are done, with the gate evidence (commit shas, test-prom-rules green, LOADED + no-fire live query outputs, the 3 corrections recorded).
- If any gate fails or a blocker appears, signal the blocker immediately instead of proceeding.
## Phase 2 Completion (2026-08-15)

**Implementer**: Llama dev subterminal. **Maestro (supervising)**: Claude Code #2.
**Branch**: `main` (direct-to-main, the established pattern). **Status**: DONE — 3 code commits (A, C, B) pushed + reconciled + LOADED + no-fire-verified; this docs commit (D) closes Phase 2.

### Commit-by-commit table

| # | SHA | Scope | Alert(s) added | File(s) |
|---|-----|-------|----------------|---------|
| A | `8723eb295` | observability | PrometheusTSDBGrowthTrend (warning, for:30m), PrometheusTSDBSpike (warning, for:5m) | `kube-prometheus-stack/app/prometheusrules/{tsdb-growth,tsdb-growth_test}.yaml` + kustomization |
| C | `09768366c` | volsync | VolSyncMissedInterval (warning, for:15m) | `volsync-system/volsync/app/{prometheusrule,prometheusrule_test}.yaml` |
| B | `15a7267b1` | cert-manager | CertManagerRenewalLate (warning, for:2h), CertManagerCertificateExpired (critical, for:5m) | `cert-manager/cert-manager/app/{prometheusrule,prometheusrule_test}.yaml` + kustomization |
| D | (this commit) | docs | — | `basic-memory/docs/roadmap/kube-prometheus-stack-hygiene.md` (this checkpoint + completion) |

Implementation order was A → C → B → D (P2.1 and P2.3 were ratified first; P2.2 was redesigned and ratified after). An unrelated renovate commit (`bf9555039`, grafanaDashboards preset repoint) landed between C and B — not part of Phase 2.

### Gate evidence (every code commit)

Each code commit passed the full per-commit gate before the next was started:
1. `just k8s test-prom-rules` green — every `<basename>_test.yaml` pairs with its `.yaml`, `.spec.groups` extracted via yq, `promtool check rules` + `promtool test rules` pass in a mktemp scratch dir. Bar met: positive + negative + boundary + `exp_annotations` (threshold alerts add a boundary pair; the cert-manager RenewalLate adds a brief-renewal case proving the `for:2h` gate).
2. pre-commit green on the touched files (yamlfmt/yamllint/gitleaks/promtool-rule-tests).
3. Explicit-pathspec staging (`git add <file>` per touched file) from a working tree checked with `git status` first — the unstaged BM checkpoint was never staged with A/C/B.
4. Pushed, then the touched Flux Kustomization reconciled (`flux reconcile kustomization <name> --with-source`), confirmed applied at the exact commit sha.
5. **LOADED + no-fire on live data** (the gate that makes a commit fully verified): the new rule group appeared in `prometheus_rule_group_rules`, `prometheus_rule_evaluation_failures_total` = 0 for the group, and the alert condition evaluated false on real cluster data (`ALERTS{alertname=...}` empty). Measured at deploy:

**A — TSDB growth (live, 2026-08-15):**
- Trend: `predict_linear(prometheus_tsdb_storage_blocks_bytes[3d], 7d)` = **2.76 GB** (2 757 987 770 B) < threshold **4.25 GB** (4 246 732 800 B = 0.9 × 4 718 592 000 retention) → NOT firing. Ratio 65.0%, 35% headroom. (Baseline at deploy was 2.77 GB / 68.6%; the predict is decaying as the 3d window slides past the Phase-1 metricRelabeling drop — expected.)
- Spike: `delta(prometheus_tsdb_storage_blocks_bytes[1h])` = **19.5 MB** (19 451 260 B) << 100 MB threshold → NOT firing (a single natural ~2h-block persist, ~3x below threshold).
- ALERTS empty; eval failures 0.

**C — VolSync missed-interval (live, 2026-08-15):**
- `increase(volsync_missed_intervals_total[1h])` = **0** for all 39 VolSync objects (source + destination roles across selfhosted/downloads/media/security) → NOT firing.
- ALERTS empty; eval failures 0.

**B — cert-manager renewal-relative (live, 2026-08-15):**
- RenewalLate: `time() - certmanager_certificate_renewal_timestamp_seconds` negative for all 3 certs → `time() < renewal_ts` → NOT firing. horvathzoltan-me = −317 854 s (~88 h to renewal), pocket-id-tls = −317 800 s, k8tz-tls = −3 660 556 s (~42 d).
- Expired: `time() - certmanager_certificate_expiration_timestamp_seconds` negative for all 3 → NOT expired. horvathzoltan-me = −509 854 s, pocket-id-tls = −509 800 s, k8tz-tls = −6 252 556 s.
- ALERTS empty; eval failures 0. The 3 live certs are `name=horvathzoltan-me` (exported_namespace=networking, 160 h), `name=pocket-id-tls` (security, 160 h), `name=k8tz-tls` (kube-system, 2160 h) — exactly the two-lifetime span the absolute-threshold premise could not cover.

### Three roadmap corrections (recorded as corrections, like the Phase 1 head-drift + V4 findings)

1. **P2.2 premise — short-lived cert misread.** The roadmap's "soonest ~6 d to expiry" was a *healthy* short-lived cert at rest mid-cycle, not a near-expiry cert. horvathzoltan-me + pocket-id-tls are 160 h-duration certs (renewBefore 1/3 ≈ 53 h), so they are *never* more than ~6.67 d from expiry — an absolute `< 7 d` rule is true forever (a constant canary, not a failure canary). k8tz-tls is 2160 h (90 d, renewBefore 720 h). No single absolute day threshold spans both lifetimes. **Corrected** to renewal-relative (`time() > certmanager_certificate_renewal_timestamp_seconds`): the renewal timestamp advances only on a successful renewal, so the condition is true only when cert-manager is actually overdue, regardless of cycle length. `for: 2h` rides out a slow-but-healthy ACME DNS-01 renewal (propagation + one retry, up to ~2 h).

2. **P2.3 identity labels.** The roadmap said `$labels.name`; the live VolSync metrics use `obj_name` / `obj_namespace` / `role` (VolSync sets the RS name as `obj_name`, not `name`). The VolSyncMissedInterval annotation uses `{{ $labels.obj_namespace }}/{{ $labels.obj_name }}` to match the existing VolSyncComponentAbsent / VolSyncVolumeOutOfSync rules.

3. **P2.1 spike function — increase → delta (with the reasoning, not just the expression).** `prometheus_tsdb_storage_blocks_bytes` is a **gauge, not a counter**. It carries legitimate **down-steps**: block-store bytes *decrease* when (a) compaction merges N head-blocks into 1 persisted block, and (b) retention evicts expired blocks. `increase()` and `rate()` apply **counter-reset detection**: on seeing a decrease, they assume the series wrapped (counter reset to 0 then climbed back) and *add* the pre-reset value to the post-reset value, inflating the apparent delta. On a gauge with compaction down-steps (every ~2 h), this manufactures a **false spike** every compaction cycle — a runaway-cardinality alarm that cries wolf on routine maintenance. `delta()` is pure net change (last − first in the range window) with **no counter-reset logic**, so a compaction down-step correctly reads as a *negative* delta and never satisfies `> 100 MB`. The function follows the metric type, not a blanket choice: the companion `volsync_missed_intervals_total` IS a counter (missed intervals only increment), so `increase()` is correct *there* — the opposite choice for the opposite metric type. This is the spike rule's correctness core; the next person must not "simplify" `delta` back to `increase` to "match" the VolSync rule.

### Open follow-up (dated, survives context)

- **P2.1 3-day predict watch** (Maestro condition): measure `predict_linear(prometheus_tsdb_storage_blocks_bytes[3d], 7d)` and the ratio to `0.9 * prometheus_tsdb_retention_limit_bytes` **daily** on 2026-08-16, 2026-08-17, 2026-08-18. Expect the predict value to **decrease** as the 3 d window slides past the Phase-1 metricRelabeling drop (the pre-drop high samples age out of the window — a decaying high bias, not real growth). An **upward** trend once the window is fully post-drop (~3 days out, from ~2026-08-18) = real cardinality growth, not window pollution → investigate. Baseline at deploy (2026-08-15): predict = 2.76 GB, threshold = 4.25 GB, ratio = 65.0%, 35% headroom. Record each day's value + ratio below:
  - 2026-08-16: _(pending)_
  - 2026-08-17: _(pending)_
  - 2026-08-18: _(pending)_

### Next

Phase 2 is **DONE**. Phases 3–6 (scrape-interval tuning, hardening/UX, conditional kubeApiServer scrape, prompp migration) remain as future roadmap items, each pending its own Maestro ratify. The 3-day predict watch above is the only open follow-up from Phase 2.
