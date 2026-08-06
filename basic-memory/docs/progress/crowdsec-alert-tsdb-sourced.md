---
title: crowdsec-alert-tsdb-sourced
type: note
permalink: home-ops/docs/progress/crowdsec-alert-tsdb-sourced
---

# crowdsec-alert-tsdb-sourced — execution progress

## Metadata (observation-form)
- [topic] Execution state for the crowdsec-alert-tsdb-sourced roadmap
- [status] DONE — P1+P2+P3 all shipped, deployed, live-verified; orphaned PVC cleanup complete. Roadmap note merged into this note (docs/roadmap note deleted on closure). All four acceptance criteria closed: AC1/AC2/AC3 by code + unit tests + pre-commit green and the post-reconcile live check; AC4 live-verified (Pushgateway restart no longer false-fires, both CrowdSecBlocklistImport* alerts inactive post-reconcile).
- [roadmap] merged into this note — the docs/roadmap/crowdsec-alert-tsdb-sourced note was deleted on closure; all design rationale now lives in the section below
- [area] observability, security
- [created] 2026-08-06
- [closed] 2026-08-06

## Design rationale (merged from roadmap)
## Background — the false fire (2026-08-06)

- [evidence] `CrowdSecBlocklistImportMetricsAbsent` (job=crowdsec-blocklist-import, severity=warning) fired even though the 04:00 importer run had pushed metrics successfully. Job log `[2026-08-06 04:00:19] [INFO] Metrics pushed to Pushgateway at http://prometheus-pushgateway.observability.svc.cluster.local:9091` and `[INFO] Sources: 11 successful, 0 unavailable` — the push SUCCEEDED; the importer did NOT crash before its metrics push and METRICS_ENABLED is on.
- [evidence] The Pushgateway lost the pushed metric on a pod restart. Running process cmdline (`kubectl exec ... /proc/1/cmdline`) is `/bin/pushgateway` with NO arguments; `--persistence.file` defaults to empty → "If empty, metrics are only kept in memory." The PVC is mounted at `/data` but the binary never writes to it. Pod startTime `2026-08-06T06:42:24Z` (08:42 Budapest) is AFTER the 04:00:19 push, so the restart wiped the in-memory metric. The pushgateway `/metrics` endpoint at query time contained zero `blocklist_import` series.
- [evidence] The 04:00 sample had ALREADY been scraped into the Prometheus TSDB before the 08:42 restart. The data was safe in Prometheus; only the relay/cache lost it.

## Decision (settled with the human, 2026-08-06 — do not re-litigate)

- [decision] The Pushgateway is a RELAY/CACHE, not a durable store. Prometheus is the single source of truth. The real defect is NOT that the relay lost the metric — relay loss is an expected property of a cache. The real defect is that BOTH alert expressions are INSTANT queries (`absent(...)` and `max by (source) (...)`), so they depend on the relay continuously re-exposing the series. They should read the Prometheus TSDB instead.
- [decision] The proposed fix "add `--persistence.file` extraArgs to the Pushgateway" is REJECTED. It treats the relay as a durable store and couples alert correctness to relay persistence — the wrong layer. The TSDB already holds the sample.
- [decision] Alerts become range-vector queries over the TSDB. This is immune to Pushgateway restarts by construction and re-establishes Prometheus as SSOT.

## P1 — Alert expressions become range-based

File: `kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml`.

### CrowdSecBlocklistImportMetricsAbsent

- current: `absent(blocklist_import_source_status{job="crowdsec-blocklist-import"})` with `for: 1h`
- target:  `absent_over_time(blocklist_import_source_status{job="crowdsec-blocklist-import"}[26h])`
- `for: 1h` is REMOVED. The 26h range window subsumes the for-debounce: 26h > 24h (one daily-run interval), so it fires only when no sample has been scraped for ~1 missed daily run plus margin.
- `keep_firing_for`: this alert has none today and gets none.
- Semantic note: `absent_over_time(v[26h])` returns 1 when the range vector is empty. If the series NEVER existed (fresh deploy, never pushed) it fires immediately at any eval — same self-firing-on-deploy behaviour as today. The 26h window only debounces the "was pushed, then stopped" case: the alert fires once the last sample ages out of the 26h window. `absent_over_time` carries the matcher labels (job) into the result, so exp_labels are unchanged.

### CrowdSecBlocklistImportSourceFailing

- current: `max by (source) (blocklist_import_source_status{job="crowdsec-blocklist-import"}) == 0` with `for: 48h`, `keep_firing_for: 24h`
- target:  `max by (source) (max_over_time(blocklist_import_source_status{job="crowdsec-blocklist-import"}[50h])) == 0`
- `for: 48h` is REMOVED. The 50h range window subsumes the for-debounce: `max_over_time[50h] == 0` holds iff every sample in the last 50h is 0, i.e. ~2 consecutive failed daily runs (50h > 48h) — the same intent as the old for:48h.
- `keep_firing_for: 24h` is RETAINED. Its purpose is orthogonal to the for→range swap: it is a RESOLVE-latch that holds the alert for 24h after the range condition goes false on recovery, so the operator sees the alert across a run boundary before it clears. The range window handles the FIRE-side debounce; keep_firing_for handles the RESOLVE-side visibility. Removing it would let a recovery clear the alert within one scrape, before the operator sees it. The retention is pinned by rewritten test case (11).

### Stale comments to rewrite in the same file

The inline comments at lines 107-130 reference the old `for:48h` / `for:1h` semantics and — critically — assert "the Pushgateway PVC persists metrics across restart so a restart alone does not fire this" (line 130). That PVC-persistence claim is exactly the REJECTED approach and is false in production. Both the comments and the alert `description` annotations (which say "for 1h" / "for ~2 consecutive daily runs") must be updated to the range-window wording in P1, and the unit-test `exp_annotations` must track them verbatim.

## P2 — Rewrite the PromQL unit tests

File: `kubernetes/apps/crowdsec/crowdsec/tests/prometheusrule_test.yaml`.

The task brief estimated ~14 cases built on the for-window semantics. After reading the file, the ACCURATE count is 7: only the two blocklist-import alerts' cases are affected by P1. The other 13 cases — CrowdSecAgentDown (a,b,c), CrowdSecAppsecDown (d,e,f), CrowdSecDecisionBudgetNearCap (1-7) — are on alerts whose expr is UNCHANGED by P1 and need no rewrite. (DecisionBudgetNearCap uses `cs_active_decisions`, not the pushgateway series.)

The 7 cases to rewrite, and how the range-window semantics changes each expectation:

- (8) SourceFailing FIRE: today `0x2882` (0 for 48h2m), eval 48h1m, fires via for:48h. New: `max_over_time[50h]==0` needs ≥50h of all-0 samples; input `0x3001` (0 for 50h1m), eval ~50h1m; fires (no for, fires when the window fills). exp_labels unchanged (alertname + severity + source).
- (9) SourceFailing NO-FIRE healthy: today `1x2882`, eval 48h1m. New: `1x3001`, eval ~50h1m → `max_over_time[50h]=1` → condition false → no-fire.
- (10) SourceFailing NO-FIRE transient: today `0x1440 1x1442` (one 24h failed run then recovery), eval 48h1m, no-fire (condition never held 48h continuously). New: a single 24h failure can NEVER fill a 50h all-0 window — once the recovery `1` enters the window, `max_over_time` is 1. Input `0x1440 1x1561`, eval ~50h1m → no-fire. Pins "1 failed run does not page".
- (11) SourceFailing keep_firing_for pin: today `0x3000 1x1381` (fires at 48h1m, recovers at 50h, eval 73h = 23h after condition false) → still firing because keep_firing_for:24h. New: `0x3000` (50h of 0 → fires when the window fills at ~50h), then `1x...` recovery; the range condition goes false at ~50h (the recovery 1 enters the window); eval at 73h = 23h after false → still firing ONLY because keep_firing_for:24h is RETAINED. This case ENCODES the retention decision: dropping keep_firing_for:24h would return `got:[]` and fail the test.
- (12) MetricsAbsent FIRE: today `input_series: []`, eval 61m (for:1h+1m). New: no series → `absent_over_time[26h]=1`; eval ~26h1m (or fires immediately, since an empty range returns 1 at any eval). exp_labels unchanged (alertname + severity + job — `absent_over_time` carries the matcher labels).
- (13) MetricsAbsent NO-FIRE present: today `1x62`, eval 61m. New: a series present in the 26h window → `absent_over_time` empty → no-fire; `1x1562`, eval ~26h1m.
- (14) MetricsAbsent for-not-met pin: today no series, eval 30m (< for:1h), pending. This pin does NOT survive the rewrite — `for:1h` is gone, so "pending at 30m" no longer applies (with no series, `absent_over_time` fires at 30m too). REPLACE it with a 26h-window-boundary pin: a single sample at t=0 then no further samples; eval at 25h (sample still inside the 26h window) → no-fire; eval at 27h (sample aged out) → fire. This pins the 26h range window — the successor to the for:1h pin.

Cross-cutting: every `exp_annotations` assertion in (8), (11), (12) must be re-baselined against the updated rule `description` text from P1. The test-group `interval: 1m` must equal the file `evaluation_interval` (already 1m) — still required, because `max_over_time`/`absent_over_time` are evaluated on the evaluation-interval ticks and the range window must be densely sampled.

## P3 — Simplify the Pushgateway back to stateless

File: `kubernetes/apps/observability/prometheus-pushgateway/app/helmrelease.yaml`.

- Remove `runAsStatefulSet: true` (line ~16) and the `persistentVolume` block (lines ~17-20). They exist ONLY to back a `--persistence.file` flag that was NEVER set, so the PVC mount at `/data` is a no-op today (verified: `/data` is empty, the binary runs with no args). This is a net reduction — the relay becomes a plain Deployment with emptyDir, matching its actual role as a stateless cache.
- Remove the now-false comment (lines ~14-15) claiming "StatefulSet + PVC so pushed metrics survive a pod restart — otherwise a restart blanks the blocklist-import freshness signal and false-fires CrowdSecBlocklistImportMetricsAbsent." That claim is the REJECTED persistence approach; with P1 the alerts read the TSDB and a restart no longer false-fires.
- The chart-defaults note about `serviceMonitor.namespace` (lines ~45-46) and the `honorLabels: true` comment (lines ~47-49) STAY — those are still correct and required (the pushed `job=crowdsec-blocklist-import` label must survive scraping).
- Orphaned PVC cleanup: the bound PVC `storage-volume-prometheus-pushgateway-0` (pvc-101fe562-2c61-40c1-91fe-c5355e8ebaf9, 1Gi, democratic-csi-local-hostpath) is NOT deleted automatically when the StatefulSet is removed (the StatefulSet `persistentVolumeClaimRetentionPolicy` is `whenDeleted: Retain`). It must be deleted manually AFTER the StatefulSet→Deployment cutover reconciles, as a documented one-shot ops step (NOT a manifest change). Capture this in the progress note at execution time.

## Verification step — DONE 2026-08-06 (gates P3)

The gate question: does anything OTHER than crowdsec-blocklist-import push to the Pushgateway, and does any Grafana dashboard panel read these series with an INSTANT query (which would go blank during the scrape gap after a restart)? If yes, P3 must be re-evaluated.

- [evidence] Sole pusher: `grep -rn METRICS_PUSHGATEWAY_URL kubernetes/` returns exactly ONE hit — `kubernetes/apps/crowdsec/crowdsec-blocklist-import/app/helmrelease.yaml:89`. No other app pushes to :9091.
- [evidence] No dashboard consumer: `grep -rln blocklist_import` and `grep -rln pushgateway|push_time_seconds` across all GrafanaDashboard CRs (14 dashboards, including the crowdsec-bouncer dashboard) return NONE. No panel reads `blocklist_import_source_status`, `blocklist_import_source_ips`, or any pushgateway metric.
- [verdict] GATE PASSES. No instant-query consumer goes blank during a post-restart scrape gap. P3 (stateless pushgateway) is safe to proceed. The only consumer of these series is the two PrometheusRules, which P1 makes range-based (TSDB-sourced) and thus restart-immune.

## Acceptance criteria

1. P1: both alert expressions in `prometheusrule.yaml` are range-vector queries (`absent_over_time[26h]`, `max_over_time[50h]`); `for:` removed from both; `keep_firing_for:24h` retained on SourceFailing only; inline comments and `description` annotations rewritten (no stale "for 1h" / "PVC persists" claims).
2. P2: the 7 affected test cases (8-14) rewritten per the semantics above; case (14) replaced by the 26h-window-boundary pin; cases (8),(11),(12) `exp_annotations` re-baselined; the other 13 cases unchanged and still green; `just k8s test-prom-rules` green.
3. P3: pushgateway HelmRelease is a stateless Deployment (no `runAsStatefulSet`, no `persistentVolume`); the false persistence comment removed; `serviceMonitor` + `honorLabels` preserved; orphaned PVC deletion recorded as a one-shot ops step.
4. Live: after Flux reconcile, a Pushgateway pod restart does NOT fire `CrowdSecBlocklistImportMetricsAbsent` (the 04:00 sample is read from the TSDB). The alert fires only when a daily run is genuinely missed for ~26h.

## Out of scope / follow-ups

- The 4 residual degradation modes dropped in [[crowdsec-import-silent-degradation]] (bouncer-key 403, frozen-mirror-200-stale, pod-resource, unpaginated get_existing_ips) remain open and are NOT addressed here.
- Per-source Last-Modified telemetry (the frozen-mirror case) is still an upstream gap.
- The node-level event that recreated the pushgateway pod (and all crowdsec pods) at 08:42 on 2026-08-06 was not root-caused (k8s events expired); immaterial to this roadmap, which makes the alerts restart-immune regardless.


## Delivery — P1 + P2 (2026-08-06)

- [delivered] Branch `fix/crowdsec-alert-tsdb-sourced` off `main`; code commit `aa487864f` (signed, "Good git" signature) — `🐛 fix(crowdsec): source blocklist-import alerts from TSDB range windows`, 2 files changed, 80 insertions(+), 67 deletions(-).
- [delivered] P1 (`kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml`):
  - CrowdSecBlocklistImportMetricsAbsent expr → `absent_over_time(blocklist_import_source_status{job="crowdsec-blocklist-import"}[26h])`; `for: 1h` removed; no `keep_firing_for`.
  - CrowdSecBlocklistImportSourceFailing expr → `max by (source) (max_over_time(blocklist_import_source_status{job="crowdsec-blocklist-import"}[50h])) == 0`; `for: 48h` removed; `keep_firing_for: 24h` retained.
  - Inline comments (lines 107-122) rewritten to the TSDB-sourced rationale; the false "Pushgateway PVC persists metrics across restart" claim at the old line ~130 is GONE; both `description` annotations rewritten to name the range window.
- [delivered] P2 (`kubernetes/apps/crowdsec/crowdsec/tests/prometheusrule_test.yaml`): the 7 affected cases (8)-(14) rewritten; case (14) replaced by the 26h-window-boundary pin (single sample at t=0; eval 25h → no-fire, eval 27h → fire); `exp_annotations` of (8), (11), (12), and (14-fire) re-baselined against the new P1 `description` text; the other 13 cases (Agent/Appsec a-f, DecisionBudgetNearCap 1-7) untouched.
- [delivered] GREEN GATE: `just k8s test-prom-rules` → "All promtool rule tests passed" (crowdsec module: "SUCCESS: 8 rules found" / "SUCCESS"); pre-commit on the 2 files (yamlfmt, yamllint, gitleaks, promtool-rule-tests) all Passed, no reformatting.
- [not-delivered] P3 (stateless Pushgateway) + orphaned PVC cleanup are OUT OF SCOPE for this branch — the user handles the PVC cleanup later. P3 stays tracked here, gated by the verification step above (GATE PASSES).
- [status] proposed → in-progress. P1+P2 done; P3 pending separate work.


## Delivery — P3 (2026-08-06)

- [delivered] P3 landed on branch `refactor/pushgateway-stateless` (off main after #4133 merge commit `8f510f653`). Code commit `33944e7ee` (signed, "Good git" signature) — `♻️ refactor(observability): drop pushgateway StatefulSet+PVC, alerts are TSDB-sourced`, 1 file changed, 7 deletions(-).
- [delivered] Removed from `kubernetes/apps/observability/prometheus-pushgateway/app/helmrelease.yaml`: `runAsStatefulSet: true`, the whole `persistentVolume` block (enabled/size/storageClass), and the false 2-line comment claiming "StatefulSet + PVC so pushed metrics survive a pod restart". Kept: serviceMonitor (namespace + honorLabels: true), securityContext, containerSecurityContext, resources, podLabels, automountServiceAccountToken, serviceAccount. No `extraArgs` / `--persistence.file` added (the relay-not-store fix is rejected; Prometheus is SSOT).
- [delivered] PRE-FLIGHT writable-filesystem finding (verified against chart 3.7.0 templates): with `runAsStatefulSet: false` + `persistentVolume.enabled: false` (chart defaults once the overrides are removed), `templates/_helpers.tpl` renders the `storage-volume` as `emptyDir: {}` mounted at `/data` (the `$storageVolumeAsPVCTemplate := and .Values.runAsStatefulSet .Values.persistentVolume.enabled` guard is false, so the `else` branch emits emptyDir). `readOnlyRootFilesystem: true` therefore still has a writable mount — no CrashLoopBackOff. The pushgateway binary with no `--persistence.file` writes nothing at runtime (confirmed in Task 1: /data empty, cmdline `/bin/pushgateway` no args), so the emptyDir is harmless.
- [delivered] Service name unchanged: `templates/service.yaml` uses `prometheus-pushgateway.fullname` regardless of `runAsStatefulSet`; only the `clusterIP: None` (Headless) line is dropped when `runAsStatefulSet=false`, giving a normal ClusterIP Service. The importer target `prometheus-pushgateway.observability.svc.cluster.local:9091` resolves either way. `templates/statefulset.yaml` is gated on `if .Values.runAsStatefulSet` so it no longer renders; `templates/deployment.yaml` renders instead.
- [delivered] GREEN GATE: `just k8s test-prom-rules` -> "All promtool rule tests passed" (crowdsec 8 rules SUCCESS — untouched, as expected); pre-commit on the touched file (yamlfmt, yamllint, gitleaks, end-of-file-fixer, etc.) all Passed, no auto-fix.
- [not-delivered] Orphaned PVC `storage-volume-prometheus-pushgateway-0` (bound, 1Gi, democratic-csi-local-hostpath; PV pvc-101fe562-2c61-40c1-91fe-c5355e8ebaf9 reclaimPolicy=Delete) is NOT deleted by this change — the StatefulSet removal does not garbage-collect it. It is a separate manual ops step for the Maestro, AFTER the HelmRelease reconciles to the Deployment.
- [status] in-progress -> done. P1+P2+P3 all shipped; the only remaining item is the one-shot PVC cleanup (Maestro ops step, not a manifest change).


## Cleanup — DONE (2026-08-06)

- [done] PR #4134 merged as 608528ac1; Flux reconciled ks observability/prometheus-pushgateway to revision 608528ac1. StatefulSet gone; Deployment prometheus-pushgateway 1/1 Running, 0 restarts (pod prometheus-pushgateway-65b7764b85-zwggm). The emptyDir pre-flight held — no CrashLoopBackOff. Prometheus target prometheus-pushgateway up at http://10.244.0.4:9091/metrics; both CrowdSecBlocklistImport* alerts inactive.
- [done] Orphaned PVC cleanup executed (human pre-authorized). Pre-delete safety re-confirm: PVC storage-volume-prometheus-pushgateway-0 Bound to PV pvc-101fe562-2c61-40c1-91fe-c5355e8ebaf9 (1Gi, democratic-csi-local-hostpath); PV persistentVolumeReclaimPolicy=Delete; no pod in observability mounted it (match count 0 over all pod specs).
- [done] kubectl delete pvc -n observability storage-volume-prometheus-pushgateway-0 — PVC deleted; the PV pvc-101fe562-2c61-40c1-91fe-c5355e8ebaf9 was reaped immediately (NotFound right after delete, Delete policy). No Released/Failed linger, so no separate PV deletion and no node-level hostpath cleanup was needed — deleting the PVC cascaded to the PV and the on-disk hostpath automatically.
- [done] Post-delete verify: pod prometheus-pushgateway-65b7764b85-zwggm still 1/1 Running, 0 restarts; Service endpoints 10.244.0.4:9091 still ready (Prometheus target up); no PV matching 101fe562/pushgateway remains; no pushgateway PVC in observability. No other kubectl mutations were run.
- [correction] My P3 Delivery bullet above recorded the PV reclaim policy as "Retain" — that was wrong. I conflated the StatefulSet persistentVolumeClaimRetentionPolicy (whenDeleted: Retain, which is why the PVC was not garbage-collected on StatefulSet removal — still correct) with the live PV persistentVolumeReclaimPolicy, which is Delete. Corrected in the bullet above (PV reclaimPolicy=Delete). Consequence captured: PVC deletion cascades to PV + on-disk hostpath, so no separate PV/node step.
- [status] done — unchanged. The roadmap is now fully closed: P1+P2+P3 shipped via PRs #4133 (merge 8f510f653) and #4134 (merge 608528ac1), and the orphan PVC cleanup is complete. No further work.

## Roadmap closure (2026-08-06)
The crowdsec-alert-tsdb-sourced roadmap item is CLOSED. The roadmap note (docs/roadmap/crowdsec-alert-tsdb-sourced) was merged into this progress note (Design rationale section above) and deleted — everything now lives under docs/progress per the roadmap -> progress lifecycle. All four acceptance criteria are closed. P1+P2 shipped via PR #4133 (merge 8f510f653), P3 shipped via PR #4134 (merge 608528ac1), and the orphaned PVC cleanup is complete. The Pushgateway is now a stateless Deployment (emptyDir, no PVC); both CrowdSecBlocklistImport* alerts are TSDB-sourced range-vector queries (absent_over_time[26h], max_over_time[50h]) and were inactive post-reconcile; a Pushgateway pod restart no longer false-fires the freshness alert. No further work.

## Relations
- relates_to [[crowdsec-blocklist-import]]
