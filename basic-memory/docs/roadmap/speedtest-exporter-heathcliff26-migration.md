---
title: speedtest-exporter-heathcliff26-migration
type: roadmap
permalink: home-ops/docs/roadmap/speedtest-exporter-heathcliff26-migration
topic: Replace the frozen miguelndecarvalho speedtest-exporter (v3.5.4, 2023) with
  heathcliff26/speedtest-exporter - root-cause fix for recurring measurement errors
  and alert flapping
status: in-progress
priority: medium
scope: 'Single-workload swap in kubernetes/apps/observability/speedtest-exporter:
  image + config plumbing (ConfigMap + explicit -config arg, cache 20m test-inside-scrape),
  PrometheusRule metric rename to Mbit/s plus a NEW SpeedtestMeasurementFailed alert,
  metricRelabelings ip/isp labeldrop, GrafanaDashboard swap to 20115. No PVC, no secrets,
  app-template chart kept.'
rationale: 'v3.5.4 is the last release since 2023-06-28 and bundles an era-old Ookla
  CLI - the recurring measurement errors and speedtest_up flapping trace to it. A
  27-repo community survey (2026-09-19) shows no adopted successor (21/27 frozen on
  the same image), so the choice was made on maintenance signals: heathcliff26 v1.8.0
  (2026-09-16) has steady releases, coverage-gated CI, 3 registries, a published Helm
  chart and Grafana dashboard. Source review 2026-09-19: the scrape model stays test-per-scrape
  (the test runs synchronously inside the scrape when the 20m cache expires), so the
  existing staleness-aware alert windows carry over unchanged in size - only the metric
  names (Mbit/s), a new speedtest_up failure alert, and the dashboard change.'
options:
- 'heathcliff26/speedtest-exporter v1.8.0 (recommended) - best maintenance signals,
  published chart + dashboard; cost: metric rename to Mbit/s, new MeasurementFailed
  alert, dashboard swap'
- tzockt/speedtest-exporter v2.1.2 - metric-compatible minimal diff, but weaker maintenance
  infrastructure than heathcliff26
- 'Stay on miguelndecarvalho v3.5.4 (rejected: image frozen since 2023-06, measurement-error
  flapping is the driving problem)'
related_areas:
- observability
---

# speedtest-exporter migration: miguelndecarvalho -> heathcliff26

## Metadata (observation-form)

- [type] roadmap
- [topic] Replace the frozen 2023 speedtest-exporter image (root cause of recurring measurement errors and alert flapping) with the actively maintained Go exporter
- [status] in-progress - Phase 0 (manifest changes) and Phase 1 (validation gate) executed 2026-09-19; researched 2026-09-19 against the live manifests, the heathcliff26/speedtest-exporter v1.8.0 README + example config, grafana.com dashboard 20115 rev 4, and a 27-repo community survey. Re-reviewed objectively the same day against the upstream SOURCE (cmd/main.go, pkg/collector, pkg/cache, pkg/config, Dockerfile), the pinned app-template 5.1.0 chart tarball, and the live deployment: 6 corrections folded in (scrape model is synchronous test-inside-scrape, NOT background; failure emits speedtest_up=0 with gauges absent -> new MeasurementFailed alert; config file needs an explicit -config arg; ConfigMap+mount mechanics verified against the chart; ip/isp metric labels labeldropped; dashboard datasource resolution verified, no fallback needed). D1-D7 all carry a recommendation, none blocking.
- [priority] medium
- [created] 2026-09-19
- [relates_to] [[home-ops/docs/areas/observability]]

## Context - current deployment facts

App: kubernetes/apps/observability/speedtest-exporter (bjw-s app-template, ks.yaml entry point, no PVC / no VolSync - rollback surface is a git revert only).

- Image: ghcr.io/miguelndecarvalho/speedtest-exporter:v3.5.4 - last release 2023-06-28; the bundled Ookla speedtest CLI is from the same era and is the root cause of the recurring measurement errors (user-observed: alert flapping).
- Scrape model: TEST-PER-SCRAPE - every scrape runs a real WAN speedtest, hence the ServiceMonitor uses interval 20m + scrapeTimeout 5m, and the speedtest_* gauges are only fresh ~5m/cycle (staleness trap).
- Alerting: prometheusrule.yaml, 4 alerts (SpeedtestExporterAbsent, SpeedtestSlowInternetDownload < 5e8 bits/s, SpeedtestSlowInternetUpload < 2e8 bits/s, SpeedtestHighPingLatency > 20 ms), engineered around the staleness trap with range aggregation: absent_over_time[30m] for discovery loss, max/min_over_time[40m] = last 2 scrapes for thresholds. Thresholds set below 24h-observed minimums (~528/305 Mbit/s, ~2.75 ms). Unit-tested beside the manifest (prometheusrule_test.yaml; suite gate: just k8s test-prom-rules).
- Dashboard: GrafanaDashboard CR downloading grafana.com id 13665 rev 4 (built for the old metric names) with a DS_PROMETHEUS input mapping.
- Labels: AD-023 vocabulary - ingress.home.arpa/allow-prometheus: "true", egress.home.arpa/allow-world: "true" (unchanged by the migration).
- Live deployment verified 2026-09-19: image v3.5.4; liveness AND readiness probes are tcpSocket:9798 (app-template default - NOT httpGet); securityContext runAsUser/runAsGroup/fsGroup 10001, runAsNonRoot, seccomp RuntimeDefault.
- Chart: app-template 5.1.0 pinned in kubernetes/components/common/repos/app-template (wrapper around the bjw-s common chart). No configMaps: usage anywhere in kubernetes/apps yet (this migration would be the first).

## Why migrate - evidence (2026-09-19)

- v3.5.4 is the final release; recent repo activity is not releases. Recurring measurement errors -> alert flapping.
- Community survey: 27 public Flux home-ops repos deploying a speedtest-exporter - 21/27 run the same v3.5.4 (mostly digest-pinned = untouched for years), 2 archived theirs, the rest each use a different small personal project. There is NO community-adopted successor, so the choice was made on maintenance signals.
- Selected: heathcliff26/speedtest-exporter - v1.8.0 released 2026-09-16, steady release cadence, coverage-gated CI, images on ghcr.io/docker.io/quay.io, published Helm chart (Artifact Hub) and Grafana dashboard (20115, ~585 downloads), server pinning support, at least one foreign production cluster (jfroy/flatops).
- Runner-up tzockt/speedtest-exporter (metric-compatible minimal diff) rejected on weaker maintenance infrastructure; lpicanco/billimek/zakame/ishioni rejected (different metric names / brand-new 2026 / effectively unmaintained).

## Target - heathcliff26/speedtest-exporter v1.8.0 (source-verified facts)

- Go binary, native speedtest.net measurement via speedtest-go (showwin) - no bundled Ookla CLI, no Python runtime. Image: plain vX.Y.Z tag = go-native variant; do NOT use the -cli flavor (external Ookla binary variant). v1.8.0 confirmed on ghcr as an OCI index with amd64+arm64.
- BEHAVIOR (pkg/collector + pkg/cache, verified in source): the test runs SYNCHRONOUSLY INSIDE the scrape when the cache is expired (mutex-guarded; there is NO background scheduler on the scrape path - only the remote_write client runs on its own interval, and remote_write is disabled here). cache == scrape interval therefore still means test-per-scrape: the cache expires ~1m early, so at the next 20m scrape it is always expired and a fresh test runs inside the scrape. A FAILED result is cached for the full TTL - benign while cache <= scrape interval, a blindness amplifier if cache > interval (constraint recorded under D2).
- FAILURE SEMANTICS (collector.Collect): on a failed test ONLY speedtest_up=0 is emitted; the download/upload/ping/jitter/duration gauges are ABSENT that scrape. Sustained measurement failures therefore do NOT fire the threshold alerts (absent series -> empty range result -> no alert); the failure signal rides exclusively on speedtest_up (see D7).
- HTTP server (cmd/main.go): /metrics plus a 200-HTML / root page; 60s WriteTimeout (author-measured test duration 22-24s) - a hung test surfaces as a scrape failure rather than a 5m hang.
- Metrics: speedtest_jitter_latency_milliseconds, speedtest_ping_latency_milliseconds (names UNCHANGED), speedtest_download_megabits_per_second, speedtest_upload_megabits_per_second (MEGIT/S, not bits/s), speedtest_data_used_megabytes, speedtest_duration_milliseconds - all carrying variable labels [ip, isp, instance]; speedtest_up carries NO labels and is always emitted.
- Config: optional YAML file (default paths resolved in pkg/config/config.go - see Phase 0 step 1), keys port/cache/persistCache/instance/logLevel/serverID/remote. Cache file path is HARDCODED to /cache/speedtest-result.json; unwritable /cache degrades gracefully to in-memory (logged).
- Image runs as USER nobody:nobody (Alpine 3.24) - irrelevant under our explicit runAsUser 10001; the /cache emptyDir is fsGroup-writable.

## Decisions

- D1 Chart vs app-template -> RECOMMEND keep app-template 5.1.0, image swap only. The upstream chart's only added value (ServiceMonitor) is already expressed via our conventions; minimal diff wins. Mechanics verified against the pinned chart tarball.
- D2 Test cadence -> RECOMMEND cache: 20m via config.yaml, with the CONSTRAINT cache <= scrape interval (a failed result is cached for the full TTL; cache > interval would blind the window). Behavior stays test-per-scrape, same as today.
- D3 Port -> RECOMMEND keep 9798 via config.yaml port (Service/ServiceMonitor naming unchanged; the SPEEDTEST_PORT env goes away). scrapeTimeout stays 5m (no churn; the server-side 60s WriteTimeout is the real bound).
- D4 Dashboard -> VERIFIED, no fallback needed: dashboard 20115 rev 4 uses a datasource template variable that defaults to the Grafana default datasource - our Prometheus (grafanadatasource.yaml isDefault: true) - and an instance variable querying label_values({job="speedtest-exporter"},instance) which resolves to "speedtest" under our target relabeling. REMOVE the CR's datasources block: 20115 has no grafana.com inputs, that block is 13665's input model.
- D5 Server pin -> auto-select (serverID 0; the author explicitly discourages pinning - pinned servers can retire or degrade).
- D6 instance label -> set instance: "speedtest" in config.yaml so the exporter's own metric label matches the target relabeling replacement (avoids an exported_instance shadow label). AND extend the ServiceMonitor metricRelabelings labeldrop from (pod) to (ip|isp|pod): the exporter's ip/isp labels would create a new series on every WAN IP change and leak into the unit-test exp_labels; the dashboard uses neither. exp_labels in the test suite stay as today (endpoint, instance, job, namespace, service).
- D7 NEW ALERT -> RECOMMEND adding SpeedtestMeasurementFailed: max_over_time(speedtest_up[40m]) == 0 (same 2-sample window gate as the threshold alerts). Reason: on the new exporter measurement failure no longer produces low gauge values - the gauges go absent and the threshold alerts stay silent, so the failure signal the old flapping accidentally provided must become an explicit alert. max (not min) picks the BEST sample in the window, so a single failed test with a healthy one in-window does NOT fire - both must fail. speedtest_up is always emitted on a working scrape, so scrape loss remains the Absent alert's domain, not this one's.

## Execution plan

Phase 0 - single PR, pure GitOps, one HelmRelease rollout:

1. helmrelease.yaml values - ConfigMap plumbing (verified app-template 5.1.0 syntax; first configMaps: user in the repo):
   configMaps: config: {enabled: true, includeInChecksum: true, data: {config.yaml: logLevel "info", port 9798, instance "speedtest", cache "20m", persistCache true}}
   persistence: config: {type: configMap, identifier: config, globalMounts: [{path: /config}]}; cache: {type: emptyDir, globalMounts: [{path: /cache}]} (replaces the /.config emptyDir - cache file path is hardcoded /cache/speedtest-result.json).
   containers.app.args: ["-config", "/config/config.yaml"] - REQUIRED: without the flag the binary looks at /etc/speedtest-exporter/config.yaml (the /config/config.yaml default applies ONLY when an env var named "container" exists, which the image does not set), and a missing config file means SILENT all-defaults (port 8080, cache 5m) - a mis-mount would surface only as scrape-timeout + Absent 30m later. includeInChecksum: true rolls the pod when the config changes.
2. helmrelease.yaml: image -> ghcr.io/heathcliff26/speedtest-exporter:v1.8.0 (plain tag); drop the SPEEDTEST_PORT env; probes and securityContext UNCHANGED (live probes are tcpSocket:9798 and the exporter binds the port at start; even / serves 200).
3. prometheusrule.yaml: rename the two throughput metrics to *_megabits_per_second with thresholds 5e8 -> 500, 2e8 -> 200 (numerically identical); ping expression and SpeedtestExporterAbsent unchanged; ADD SpeedtestMeasurementFailed (D7). KEEP the range-agg windows and their sizing (40m = 2 scrapes = 2 real tests - the test-inside-scrape model keeps the existing staleness analysis valid). Rewrite the design comment: correct the model attribution (test runs inside the scrape when the 20m cache has expired; on failure the gauges are absent, only speedtest_up=0 is served) and document the new alert's max-not-min direction.
4. prometheusrule_test.yaml: rewrite threshold values and annotations to the Mbit/s forms (6e8->600, 4e8->400 etc.); ADD SpeedtestMeasurementFailed cases (positive/negative/boundary - max_over_time keeps the best sample, so a single 0 beside a 1 must NOT fire); exp_labels unchanged thanks to the D6 labeldrop.
5. helmrelease.yaml serviceMonitor metricRelabelings: labeldrop regex (pod) -> (ip|isp|pod).
6. grafanadashboard.yaml: URL -> https://grafana.com/api/dashboards/20115/revisions/4/download; REMOVE the datasources block (D4).
7. Threshold recalibration stays a FOLLOW-UP, not a blocker: the 24h-observed minimums were measured by the old CLI; after migration observe >=24h and re-check the distance to 500/200 Mbit/s.

Phase 1 - validation gate (before commit): just k8s test-prom-rules green (updated suite incl. the new alert); pre-commit green; diff review - nothing outside the migration.

Phase 2 - rollout + live verification (after push + flux reconcile): pod image v1.8.0 Running; /metrics serves the new metric names and speedtest_up 1 within one cycle (<=20m); Prometheus target up; dashboard 20115 renders with data (datasource + instance variables resolved); >=2 scrape cycles (~40m) observed with no alert firing; record measured minimums for the recalibration check.

Rollback: git revert the migration commit - Flux restores v3.5.4 + old rule/dashboard. Series continuity breaks either way (the old *_bits_per_second series are already stale).

## Acceptance criteria

1. Pod runs ghcr.io/heathcliff26/speedtest-exporter:v1.8.0 (verified live).
2. up{job="speedtest-exporter"} == 1 sustained across >=2 scrape cycles.
3. speedtest_download_megabits_per_second / speedtest_upload_megabits_per_second / speedtest_ping_latency_milliseconds series present with NO ip/isp labels; speedtest_up == 1 on a healthy test.
4. promtool suite green: renamed metric expressions with Mbit/s boundary pairs AND the new SpeedtestMeasurementFailed alert (single failed test beside a healthy one does not fire).
5. No speedtest alert fires in steady state over a >=40m observation window.
6. Grafana dashboard 20115 rev 4 renders current data with resolved variables.
7. AD-023 labels unchanged, no PVC introduced, no secret touched.
8. Config actually loaded: metrics served on port 9798 with a ~20m test cadence (proves the -config arg + ConfigMap mount, not silent defaults).

## Risks / verify at execution

- speedtest-go auto-selection may pick different servers than the old CLI did - measured minimums may shift; the 24h recalibration follow-up covers this.
- Grafana history continuity breaks at the migration commit (old *_bits_per_second series end) - accepted.
- Upstream is small (~13 stars) - accepted with eyes open: chosen on maintenance-signal evidence over non-existent adoption; Renovate keeps the image tag current afterwards (no .renovate change needed - standard docker datasource, no speedtest customManagers exist today).
- The 60s server WriteTimeout means a pathologically slow test surfaces as a failed scrape - acceptable: sustained loss is the Absent alert's domain, single failures are the MeasurementFailed alert's (both 2-sample gated).
- VERIFIED-FORMERLY-RISKY items (review closed them): image UID (overridden by our runAsUser/fsGroup 10001, /cache emptyDir group-writable, graceful degrade if not), config default path (explicit -config arg), dashboard variable resolution (default datasource is our Prometheus), probe paths (tcp probes, and / serves 200 anyway).

## Execution record

### Phase 0 + Phase 1 - implemented 2026-09-19, branch feat/speedtest-exporter-heathcliff26-migration

All six execution-plan steps applied verbatim on
kubernetes/apps/observability/speedtest-exporter/app/, zero deviation from the plan:

1. helmrelease.yaml: configMaps.config enabled+includeInChecksum with config.yaml (logLevel info,
   port 9798, instance speedtest, cache 20m, persistCache true); persistence config -> configMap
   (identifier config, mounted /config) + cache emptyDir at /cache; args ["-config",
   "/config/config.yaml"]; SPEEDTEST_PORT env dropped (service port now a literal 9798, the
   &port anchor went with it). Chart syntax verified directly against the pinned app-template
   5.1.0 tarball (oci://ghcr.io/bjw-s-labs/helm/app-template): configMaps.<id>.enabled /
   includeInChecksum / data exist, and persistence type configMap resolves identifier via
   bjw-s.common.lib.configMap.getByIdentifier - enabled: true is mandatory (the template fails
   the render otherwise).
2. Image -> ghcr.io/heathcliff26/speedtest-exporter:v1.8.0; probes and securityContext untouched.
3. prometheusrule.yaml: download/upload expressions renamed to *_megabits_per_second with
   thresholds 500/200; NEW SpeedtestMeasurementFailed max_over_time(speedtest_up[40m]) == 0,
   severity warning, placed after SpeedtestExporterAbsent; Absent and ping unchanged; design
   comment rewritten per the corrected model attribution.
4. prometheusrule_test.yaml: values 600/400/500 (download), 300/100/200 (upload); annotations
   rewritten; three new SpeedtestMeasurementFailed cases (fire 1x40->0x42, healthy 1x82,
   transient 1x40 0x20 1x22 - single failed test beside a healthy one does not fire; the ==
   boundary is the fire case's exact 0); exp_labels carry the five target labels (endpoint,
   instance, job, namespace, service) for speedtest_up.
5. serviceMonitor metricRelabelings regex (pod) -> (ip|isp|pod).
6. grafanadashboard.yaml: URL -> grafana.com 20115 rev 4; datasources block removed.

Validation (Phase 1 gate):

- promtool: check rules + test rules GREEN (5 rules found; suite incl. the new alert cases
  passes, exit 0). Run via the recipe's exact steps (yq ea extraction -> promtool check ->
  promtool test). The official just k8s test-prom-rules wrapper was re-run GREEN on 2026-09-19 after
  reinstalling gum (mise install --force aqua:charmbracelet/gum@2.0.1; the old aqua install
  dir held a stale payload): all 15 suites pass, speedtest suite reports 5 rules SUCCESS.
  The Phase 1 gate is therefore closed with the wrapper, not just the manual promtool steps.
- pre-commit: all hooks green on the four touched files (yamlfmt, yamllint, gitleaks, secrets
  scan, whitespace/eof fixes) including promtool-rule-tests - fully green on the 2026-09-19 re-run after the gum fix.
- diff review: 4 files, 168 insertions / 74 deletions, every hunk traces to a plan step;
  nothing outside the migration; AD-023 labels untouched; no PVC, no secret, no .renovate change.

Pending (Phase 2, after push + flux reconcile): live verification per the acceptance criteria -
pod image v1.8.0, new metric names with speedtest_up 1, no ip/isp labels, Prometheus target up,
dashboard 20115 rendering, >=40m no-alert observation, measured minimums for the 24h threshold
recalibration follow-up. Close-out: move this note to docs/progress/ + status done.
