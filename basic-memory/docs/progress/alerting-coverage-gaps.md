---
title: alerting-coverage-gaps
type: progress
permalink: home-ops/docs/progress/alerting-coverage-gaps
topic: Consolidated alerting-coverage-gaps roadmap+progress — three PrometheusRule
  coverage gaps shipped (Kopia maintenance staleness, ExternalSecret sync-error, speedtest-exporter)
  with promtool unit tests; Phase 4 (Docker Hub rate-limit) dropped after live verification
  found its metric basis absent. Roadmap note merged into this progress note 2026-08-16.
status: done
priority: medium
area: volsync-backup / external-secrets / observability
created: '2026-08-15'
completed: '2026-08-16'
scope: Three PrometheusRule additions shipped (Kopia maintenance staleness, ExternalSecret
  sync-error, speedtest-exporter); Phase 4 (Docker Hub rate-limit) dropped — metric
  basis absent.
rationale: Built on metrics verified live in Prometheus per phase before any expression
  was written; the roadmap premise (metrics already scraped, no new exporter) held
  for Phases 1-3 and failed for Phase 4.
related_areas:
- volsync-backup
- external-secrets
- observability
tags:
- progress
- observability
- alerting
- volsync-backup
- external-secrets
- prometheus
- roadmap
origin: roadmap note docs/roadmap/alerting-coverage-gaps merged into this progress
  note 2026-08-16 (spec + execution consolidated; roadmap note deleted)
---

# alerting-coverage-gaps — execution progress

## Metadata (observation-form)

- [topic] Three PrometheusRule coverage gaps shipped (Kopia maintenance staleness, ExternalSecret sync-error, speedtest-exporter); Phase 4 (Docker Hub rate-limit) dropped — metric basis absent
- [status] DONE — implemented, promtool-verified, committed to main
- [area] volsync-backup / external-secrets / observability
- [created] 2026-08-16
- [implements] roadmap merged into this note 2026-08-16 (Phase 1-3 delivered, Phase 4 dropped)

## Live verification basis (built with no guessing)

Every phase was checked against live Prometheus metrics (pod `prometheus-kube-prometheus-stack-0`, observability ns) BEFORE writing any expression. The roadmap premise — "metrics already scraped, no new exporter required" — was tested per phase: held for 1-3, failed for 4.

- **Phase 1**: `kube_job_status_completion_time` (kube-state-metrics) confirmed present; live Job-name pattern `kopia-maint-kopia-daily-maintenance-<hash>-<ts>` (single job type, NOT billimek's quick/full split). CronJob `successfulJobsHistoryLimit=3`, no TTL; schedule `30 */6 * * *` = 4 runs/day (6h cadence). kube-state-metrics does NOT surface the Job's own `volsync.backube/kopia-maintenance` label on this metric, so the job_name regex is the selector. No existing kopia alert (no overlap).
- **Phase 2**: `externalsecret_status_condition` confirmed (134 series); labels `condition`, `status`, `name`, `exported_namespace` (real ES ns), `namespace` (controller ns). The ESO app dir had a grafana dashboard/folder but no PrometheusRule — first one.
- **Phase 3**: metrics flow (`up{job="speedtest-exporter"}=>1`; 20m interval / 5m scrapeTimeout — a real speedtest per scrape). The roadmap/billimek metric names (`speedtest_download_bandwidth_bytes`, `speedtest_ping_latency_seconds`) DO NOT EXIST in exporter v3.5.4. Real names: `speedtest_download_bits_per_second`, `speedtest_upload_bits_per_second`, `speedtest_ping_latency_milliseconds`, `speedtest_up`. Single series (one server). 24h-observed: download min ~528 Mbit/s, upload min ~305 Mbit/s, ping max ~2.75 ms. Thresholds (500/200 Mbit/s, 20 ms) set by human below the observed minimums so normal operation does not fire.
- **Phase 4**: `container_last_seen` (billimek metric) absent; `kube_pod_container_status_waiting_reason` (ImagePullBackOff alternative) also absent from kube-state-metrics (only the reason-less `..._waiting` and `..._terminated_reason` exist). docker.io footprint is 3 explicit images (busybox, grafana:13.0.1, prompp) + many opaque `sha256:` digests; crowdsec is NOT on docker.io now. The roadmap inventory premise was stale.

## What was done

### Phase 1 — KopiaMaintenanceStale (volsync-system)

Added to the existing `kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml` (`volsync.rules` group), beside the VolSync* sync-plane alerts:

```
expr: time() - max(max_over_time(kube_job_status_completion_time{namespace="volsync-system",job_name=~"kopia-maint-kopia-daily-maintenance-.*"}[2d])) > 43200
for: 30m, severity: warning
```

- `max_over_time[2d]` holds the last completion past Job history GC; the outer `max()` drops job_name/namespace labels, so the summary carries no `$labels` (intentional, unlike the VolSync* alerts).
- 43200 = 12h = 2 missed 6-hourly runs (derived from the verified schedule, not copied from billimek's 12h/48h which matched a different cadence).
- Test extended in `prometheusrule_test.yaml` using the pod-garbage-collector "track time() − age" pattern (`values: '-43201+60x32'`): fire (age 43201) / no-fire boundary (43200, strict >) / absent (no series).

### Phase 2 — ExternalSecretNotReady (external-secrets)

New `kubernetes/apps/external-secrets/external-secrets/app/prometheusrule.yaml`:

```
expr: externalsecret_status_condition{condition="Ready",status="False"} == 1
for: 5m, severity: warning
```

- `== 1` keeps all input labels; summary renders `$labels.exported_namespace/$labels.name` (exported_namespace is the real ES ns; namespace is the controller's).
- Registered in `kustomization.yaml` resources; test file is fire(1)/no-fire(0)/boundary(2) with the full live label set asserted.

### Phase 3 — speedtest-exporter alert set (observability)

New `kubernetes/apps/observability/speedtest-exporter/app/prometheusrule.yaml` with four alerts (billimek names kept, expr + thresholds rebuilt on real metrics):

- `SpeedtestExporterAbsent`: `absent(up{job="speedtest-exporter"})`, for:15m, critical.
- `SpeedtestSlowInternetDownload`: `speedtest_download_bits_per_second < 500000000`, for:25m, warning.
- `SpeedtestSlowInternetUpload`: `speedtest_upload_bits_per_second < 200000000`, for:25m, warning.
- `SpeedtestHighPingLatency`: `speedtest_ping_latency_milliseconds > 20`, for:25m, warning.
- `for:25m` requires a slow value to survive a re-scrape (2 consecutive slow scrapes at the 20m cadence), not a single transient one.
- Registered in `kustomization.yaml`; test covers fire/no-fire-boundary/sanity per alert + the absent fire/no-fire pair.

### Phase 4 — Docker Hub rate-limit: DROPPED

Dropped before implementation — the metric basis is absent (see verification basis above). To implement it properly would require a separate kube-state-metrics metric-allowlist change (KPS HelmRelease) to enable `kube_pod_container_status_waiting_reason`, then a real pull-failure alert — out of scope for "add a PrometheusRule with already-flowing metrics". Recorded as an optional follow-up.

## Verification

- `just k8s test-prom-rules`: all 15 test files green (3 new/extended: volsync now 4 rules, external-secrets 1, speedtest 4).
- pre-commit: yamlfmt, yamllint, promtool-rule-tests, gitleaks, secret-scan all pass on the 8 touched files.
- No cluster impact pre-push — local-only files until GitOps reconcile (kubernetes/CLAUDE.md apply boundary).

## Next

- After push + Flux reconcile: confirm the three PrometheusRules are loaded (`promtool query instant http://localhost:9090 'ALERTS{alertname=~"KopiaMaintenanceStale|ExternalSecretNotReady|Speedtest.*"}'`) and that none are spuriously firing on normal operation.
- Optional follow-up (own issue/MR): enable `kube_pod_container_status_waiting_reason` in kube-state-metrics and ship a real `ImagePullBackOff`/pull-failure alert (the Phase 4 replacement) — separate prerequisite change, not part of this roadmap item.
- Threshold tuning after a few weeks of live data: the speedtest 500/200 Mbit/s and the Kopia 12h windows may want adjusting based on observed variance.


## Post-ship verification & fix (2026-08-16) — supersedes the Phase 3 description above

A live cluster verification (the human requested "ellenőrizd" after the push) confirmed all three rules reconciled via Flux and were loaded by Prometheus with the correct alert names, but it **caught a real defect in the speedtest alerts** that the promtool unit tests had NOT caught.

**Finding (live):** `SpeedtestExporterAbsent` sat `pending` constantly. Root cause: the speedtest-exporter ServiceMonitor scrapes every 20m (verified: `count_over_time(up{job="speedtest-exporter"}[1h]) = 3`; scrapeTimeout 5m — a real speedtest per scrape). The `speedtest_*` gauges and `up` are fresh only ~5m after each scrape and stale for the remaining ~15m of the cycle. The instant form shipped in cca897803 was therefore broken:
- `absent(up{job="speedtest-exporter"})` returned 1 for ~15m of every 20m cycle (the `up` series goes stale between scrapes) → the alert flapped pending permanently.
- `speedtest_* < threshold for:25m` — the comparison was active only ~5m/cycle (stale the other 15m), so the `for:25m` window could never accumulate → the threshold alerts would NEVER fire.

**Not affected (verified live):** `KopiaMaintenanceStale` keys off `kube_job_status_completion_time` (kube-state-metrics, scraped ~every 30s-1m) and `ExternalSecretNotReady` off `externalsecret_status_condition` (ESO controller metrics, frequent scrape) — both gauges stay fresh, so the instant comparison + `for:` form is correct for them. The defect was localized to the uniquely-slow 20m speedtest scrape.

**Fix (commit b40b33ab0):** rebuilt the four speedtest alerts with range aggregation over windows sized to the 20m cadence, matching the repo's own crowdsec blocklist idiom (`absent_over_time`/`max_over_time` for infrequent metrics):
- `SpeedtestExporterAbsent`: `absent_over_time(up{job="speedtest-exporter"}[30m])` — 30m > 20m interval + jitter, no `for:` (the window is the gate); fires ~30m after the target truly disappears, one missed scrape cannot fire.
- `SpeedtestSlowInternetDownload`/`Upload`: `max_over_time(speedtest_*_bits_per_second[40m]) < threshold` — 40m = 2x interval (last 2 scrapes); `max` means both scrapes must be below, so a single transient slow scrape cannot fire. No `for:`.
- `SpeedtestHighPingLatency`: `min_over_time(speedtest_ping_latency_milliseconds[40m]) > 20` — `min` means both scrapes must be high; a single low-latency scrape keeps it quiet. No `for:`.

**Test rewrite:** the promtool tests were rewritten to the crowdsec dense-sample healthy-prefix-then-degradation idiom (15 cases: absent fire/no-fire/30m-boundary; per threshold alert fire/healthy/transient/boundary). NOTE: promtool does NOT model the 5m Prometheus staleness (samples placed via `values:` are present at their timestamps), so the unit tests validate the range-window LOGIC, not the live staleness-robustness — the staleness-robustness is a property of the range functions reading the TSDB. This is why the original instant-form tests passed green while the alerts were broken live. `just k8s test-prom-rules` green; pre-commit green.

**Lesson:** for any alert on a slow-scrape metric (interval approaching or exceeding the 5m staleness window), instant comparisons + `for:` are broken by design — use range aggregation (`absent_over_time`/`max_over_time`/`min_over_time`) with a window sized to the scrape interval, and verify LIVE, not just with promtool (which does not model staleness).


---

## Roadmap (merged 2026-08-16 from docs/roadmap/alerting-coverage-gaps)

The roadmap note that specified this work was merged into this progress note and deleted; this section preserves its spec-side content. The execution detail above remains the source of truth for what shipped.

### Origin

A GitHub code search over billimek/k8s-gitops (21 PrometheusRule manifests) was cross-checked against our 13 existing PrometheusRules. Four gaps were found where we run the component and scrape its metrics but carry no alert. Items where the component/metric does not exist in this stack (Ceph, OPNsense/Unbound, NFS+KEDA, CloudNativePG, Gatus, UPS/NUT) and items already covered by the kube-prometheus-stack defaultRules (node-exporter host alerts) were discarded as not-applicable or redundant.

### Scope (premise: metrics already scraped, no new exporter)

Four independently-shippable PrometheusRule additions: KopiaMaintenance staleness (volsync-system), ExternalSecret sync-error (external-secrets), speedtest-exporter (observability), and Docker Hub rate-limit risk (observability). The central premise was tested per phase against live Prometheus before any expression was written — it held for Phases 1-3 and failed for Phase 4.

### What we gain

- A silent Kopia maintenance failure (compaction/GC never running) surfaces before it becomes a slow-motion backup-integrity problem; the existing VolSync sync alerts watch sync, not maintenance.
- An ExternalSecret stuck Ready=False (e.g. after a 1Password Connect credential rotation) alerts instead of being discovered only when a dependent app breaks.
- Internet-link degradation (slow speedtest, high ping, exporter gone dark) becomes visible instead of living only in an unwatched Grafana dashboard.
- Phase 4 (Docker Hub rate-limit) was dropped — see execution.

### Acceptance criteria and outcomes

- Kopia staleness alert fires on a deliberately stale fixture and not on a normal run — MET (Phase 1 shipped; promtool fire/no-fire/absent cases green; live 2026-08-16: most recent completion 5.6h ago, alert inactive).
- ExternalSecret Ready=False fires within 5m; healthy does not — MET (Phase 2 shipped; fire(1)/no-fire(0)/boundary(2) green).
- speedtest set has a passing promtool suite with recalibrated thresholds plus positive/negative/boundary per alert — MET (Phase 3 shipped, then rebuilt for the 20m staleness trap; 15-case suite green; thresholds 500/200 Mbit/s and 20 ms set below 24h-observed minimums).
- Docker Hub alert rebuilt (not copied) against our actual container count/pull cadence with a documented threshold — NOT MET / DROPPED (Phase 4: metric basis absent — neither container_last_seen nor kube_pod_container_status_waiting_reason exists; recorded as an optional follow-up requiring a kube-state-metrics allowlist change).
- All shipped rules carry sibling _test.yaml fixtures and pass just k8s test-prom-rules — MET (suite green, re-verified 2026-08-16).

### Out of scope (do not reopen here)

- Node-exporter host-level alerts — already covered by kube-prometheus-stack defaultRules (node/nodeExporterAlerting/nodeExporterRecording enabled).
- Ceph, OPNsense/Unbound, NFS+KEDA, CloudNativePG, Gatus, UPS/NUT alerts — components do not exist in this stack.
- Alertmanager meta-alerting (MassiveAlertStorm etc.) — low priority at current alert volume.
- Envoy Gateway alert expansion beyond the existing EnvoyProxyDown — tracked separately in [[gateway-guardrails-response-headers]].
- A real Docker Hub pull-failure alert — separate issue/MR; needs kube_pod_container_status_waiting_reason enabled in kube-state-metrics first (a KPS HelmRelease allowlist change), not a metrics-already-flowing PrometheusRule.

### Risks: roadmap vs. realized

- Phase 1 Job-name regex guessing -> mitigated: verified live (single job type, not billimek quick/full split).
- Phase 2 ESO metric rename -> mitigated: externalsecret_status_condition confirmed (134 series) before writing the expr.
- Phase 3 uncalibrated thresholds -> mitigated: set from 24h-observed minimums, not billimek link. A non-roadmap risk — the 20m scrape staleness breaking instant comparisons — was caught only by live verification, not promtool (see the post-ship fix above).
- Phase 4 threshold meaningless at single-node scale -> moot: the metric basis was absent, so the alert was dropped, not shipped inert.
