---
title: crowdsec-blocklist-import-v39-alignment
type: roadmap
permalink: home-ops/docs/roadmap/crowdsec-blocklist-import-v39-alignment
topic: crowdsec-blocklist-import v3.9.0 alignment — config posture + new-gauge degradation
  alerting
status: in-progress
priority: medium
scope: Align the blocklist-import env with the upstream v3.9.0 config surface (remove
  the dead Monty switch, BLOCKLISTS_OPT_IN posture to silence the v4.0 defaults-flip
  warning, optional FAIL_ON_DEAD_FEED + reinstated job-failed alert), add PrometheusRules
  on the new per-source gauges (source_entries frozen-feed detection closing the dropped
  mode (d) re-open trigger, source_http_status), plus a first-3.9.0-run verification
  checklist.
rationale: 'The v3.9.0 image is already live (PR #4519) but the release ships a deprecation
  path (v4.0 flips feed defaults), an error-logging dead switch in our env, and four
  per-source health gauges that materialize the re-open trigger of the consciously-dropped
  frozen-feed degradation mode — acting now converts user-accepted risk into covered
  risk at manifest-only cost.'
options:
- BLOCKLISTS_OPT_IN=true (recommended) — future feeds default OFF, matches Tier A
  explicit-allowlist philosophy
- PRESET=max — preserves legacy defaults for future feeds, but a new feed on an already-allowlisted
  FQDN (raw.githubusercontent.com) would silently import
related_areas:
- crowdsec
- observability
- flux-gitops
---

# crowdsec-blocklist-import v3.9.0 alignment — roadmap

## Metadata (observation-form, schema validation)

- [topic] Align the crowdsec-blocklist-import deployment with the upstream v3.9.0 config surface and strengthen the degradation-detection plane with the new per-source gauges
- [status] in-progress (M1+M2 implemented 2026-10-13; M3 pending the first post-merge run)
- [priority] medium
- [area] crowdsec, observability, flux-gitops
- [created] 2026-10-13
- [upstream] v3.9.0 image live in the cluster via Renovate PR #4519 (merged 2026-10-13 19:15Z) — image-only bump, no env change; first 3.9.0 run is 2026-10-14 04:00
- [follows] [[crowdsec-blocklist-import]] (progress, closed) and [[crowdsec-import-silent-degradation]] (progress, closed — residual modes (b)/(d)/(e)/(f) with re-open triggers)

## Current state (evidence)

- Live: HelmRelease crowdsec-blocklist-import upgraded to 3.9.0@sha256:71e36b47858f8f91f6dd92b5e6dbbc583775c7568b0459761127ce81f1944a08 (verified live 2026-10-13, upgrade succeeded); the last completed job ran 3.8.0.
- Env (kubernetes/apps/crowdsec/crowdsec-blocklist-import/app/helmrelease.yaml): all 22 feed switches of the upstream registry are set explicitly (verified against upstream docs/config-reference.md) — 9 Tier A feeds true, the rest false. Neither PRESET nor BLOCKLISTS_OPT_IN is set. ENABLE_MONTY_SECURITY_C2 is still set to false although the feed was REMOVED upstream (#80) — v3.9.0 logs an ERROR for it on every run.
- Metric surface verified live in the pushgateway (3.8.0 run): source_status, source_ips (NEW unique IPs per run — not the feed size), source_refreshed_ips, source_duration_seconds, errors_total{error_type=fetch|parse|import|encoding,source,message} (sanitized categories), sources_enabled/successful/failed, total_ips, new_ips, refreshed_ips, existing_decisions, last_run_timestamp, encoding_errors_total, duration_seconds histogram. v3.9.0 adds four per-source gauges: source_last_success_timestamp, source_entries (RAW entry count — the feed size), source_unique_contribution, source_http_status (fetch HTTP code; 0 = connection failure, -1 = no request made). delete_from_gateway(job=...) wipes every series of the job before each push — no stale accumulation (design unchanged since v3.7.1, measured).
- Alert topology today: CrowdSecBlocklistImportSourceFailing (max_over_time[50h]==0, keep_firing_for 24h), CrowdSecBlocklistImportMetricsAbsent (absent_over_time[26h]), CrowdSecDecisionBudgetNearCap. CrowdSecBlocklistImportFailed (kube_job_status_failed) was REMOVED in the freshness rework because the importer exits 0 while >=1 source succeeds — so today a failed job has NO alert.
- Confidence re-tiering (VXVault 75->35, URLhaus 75->90, etc.) is consumer-visible ONLY in SCENARIO_FORMAT=structured (verified from upstream docs/scenario-format.md); we run the legacy default, so it changes nothing for us until/unless structured mode is adopted.

## What we gain

- v4.0-proof posture with no deprecation warning: v4.0.0 flips the no-config fallback to PRESET=server, which would silently change the feed set; pinning the posture now makes the intent explicit.
- Frozen-feed detection: source_entries makes the consciously-dropped mode (d) frozen-mirror-200-stale directly alertable (the recorded re-open trigger was "a feed's IP count stays unchanged for a long period"). Botvrij is the documented suspect (feed Last-Modified 2026-02-03, ~182 days at drop time).
- Failure-reason visibility: source_http_status separates a dead feed (404/410) from a provider outage (5xx) from a connection failure (0); errors_total already separates parse failures that leave source_status at 1.
- Immediate dead-feed signal (FAIL_ON_DEAD_FEED + a reinstated job-failed alert) complementing the deliberately 2-run-debounced SourceFailing rule.

## What to do (members)

### M1 — env alignment (helmrelease.yaml, manifest-only)

1. Remove ENABLE_MONTY_SECURITY_C2 (feed removed upstream; the stale env logs an ERROR each run).
2. Add BLOCKLISTS_OPT_IN: "true" — silences the v4.0 defaults-flip warning and fixes the opt-in posture for future feeds (see Options).
3. (recommended) Add FAIL_ON_DEAD_FEED: "true" paired with M2.3; decide backoffLimit (see Options).

### M2 — alerting on the new signals (prometheusrule.yaml + prometheusrule_test.yaml)

1. CrowdSecBlocklistImportFeedFrozen: source_entries unchanged across ~8 consecutive daily runs (max_over_time == min_over_time over ~8d window on the TSDB) while source_status stays 1 — the frozen-mirror half of mode (d). Include the entries==0 while status==1 case (empty/garbage body parsed successfully). Botvrij is the expected first firing. Promtool tests per the repo bar (positive, negative, boundary pair, latch if keep_firing_for is used).
2. http_status enrichment: prefer extending CrowdSecBlocklistImportSourceFailing annotations or a low-noise separate rule on http_status >= 400 — decide in dev after confirming the gauge is pushed for healthy sources too (see Risks); net-reduction test applies.
3. CrowdSecBlocklistImportJobFailed on kube_job_status_failed{namespace="crowdsec", job_name=~"crowdsec-blocklist-import-.*"} > 0 — reinstate the rule removed in the freshness rework, but only if FAIL_ON_DEAD_FEED is adopted (otherwise it stays dead code, as it was).

### M3 — first-3.9.0-run verification (observability checklist, no code change)

After the 2026-10-14 04:00 run: (i) the four new gauge families are pushed with job label crowdsec-blocklist-import and scraped; (ii) logs show the defaults-flip warning and the Monty error (both disappear once M1 merges); (iii) no new egress attempts from the importer pod — Autopilot primitives are report-only and TELEMETRY_ENABLED=false, so any drop in Cilium flows for the run window is a finding, not noise; (iv) verify in upstream source whether FAIL_ON_DEAD_FEED still imports the surviving feeds before exiting non-zero (main loop was not fully readable at review); (v) sources_enabled sanity == 9.

### M4 — explicitly deferred / rejected

- SCENARIO_FORMAT=structured (per-feed scenario names, per-feed consolidated alerts, confidence ranking): deferred — only then does the confidence re-tiering matter; requires checking no consumer matches legacy scenario names. CrowdSecBanActive excludes by origin, so it is unaffected.
- Data-Shield IPv4 feed: REJECTED — GPL-3.0, ~96K entries exceeds the 75000 MAX_DECISIONS cap, not Tier A confirmed-malicious-infrastructure class, and would need a new CNP FQDN entry. Re-open only by explicit human decision.
- Autopilot planning primitives: report-only, no collector/enforcement connected — ignore until upstream connects enforcement, then re-evaluate the telemetry posture.

## Options

1. BLOCKLISTS_OPT_IN=true (recommended) vs PRESET=max — behavior-identical TODAY because all 22 registry switches are already explicit; they differ only for feeds added in future releases: PRESET=max defaults them ON (and a future feed hosted on raw.githubusercontent.com — already allowlisted in the CNP — would silently import), BLOCKLISTS_OPT_IN keeps them OFF pending evidence-gated Tier promotion. Opt-in matches the repo's Tier A explicit-allowlist philosophy and the CNP fail-closed design.
2. FAIL_ON_DEAD_FEED now vs metrics-only — a single transient feed failure fails the job (vs the deliberate 2-run debounce of SourceFailing); acceptable as a warning-severity signal. Interplay: backoffLimit 3 gives up to 4 attempts, each a full partial run — idempotent via LAPI dedup but wasteful; consider backoffLimit 0 for a deterministic single attempt.

## Residual-mode ledger (silent-degradation follow-up)

- (b) bouncer-key 403: NOT covered by v3.9.0 — source_http_status is the FEED-fetch status; LAPI auth failure is still log-only (verified in upstream v3.9.0 source: no metric is recorded on get_existing_ips 403). Re-open triggers unchanged (CrowdSecDecisionBudgetNearCap or a 403 in pod logs).
- (d) frozen-mirror-200-stale: the dropped half becomes closable by M2.1 — source_entries is exactly the missing per-source freshness telemetry the drop decision named as the fix requirement. The unreachable half stays covered by SourceFailing.
- (e) 512Mi resource / (f) unpaginated get_existing_ips: untouched by this release; slow-burn, re-open triggers unchanged.

## Risks / open questions

- FAIL_ON_DEAD_FEED ordering (import-then-exit vs abort) unverified — the upstream main loop was truncated in review; confirm before enabling (M3.iv).
- source_http_status push semantics: failure default 0, no-request -1 — confirm it is pushed for every enabled source (healthy ones too) before writing a !=200 alert, otherwise gate on source_status==0 AND http_status>0.
- Frozen threshold: healthy feed sizes fluctuate, but 7-8 identical daily values is a strong frozen signal; Botvrij's legitimate cadence is unknown — treat the first firing as investigate-first, not page.
- BLOCKLISTS_OPT_IN + zero-feed guardrail: our explicit set is non-empty (9 feeds), so the guardrail cannot fire from this change; sources_enabled==9 is the post-merge assertion.

## Verification (success criteria)

- kustomize build green for the crowdsec app; just k8s test-prom-rules green including the new rule tests (positive/negative/boundary/latch per the promtool bar).
- pre-commit green on all touched files.
- Post-merge first run: warning-free and error-free logs, sources_enabled==9, new gauges present in the pushgateway and scraped, all new rules loaded in Prometheus.

## Review outcome (2026-10-13)

Verified against upstream v3.9.0 `blocklist_import.py` and the repo; the plan was corrected before implementation.

- [resolved] FAIL_ON_DEAD_FEED ordering (M3.iv): import-then-exit — the run imports every surviving feed and pushes metrics, then `_run_once` returns 1 (source L3627). Not an abort.
- [resolved] source_http_status push semantics: set for EVERY enabled source — success = real status code (200), failure = HTTPError code or 0 (connection failure); -1 only when a success carries no response code (source L1446-1480).
- [resolved] Empty 200 body = success with entry_count=0 (fetch path L2183-2193) — the entries==0 && status==1 case is real, so it got its own immediate rule instead of waiting for the frozen window.
- [resolved] ENABLE_MONTY_SECURITY_C2 is in REMOVED_ENABLE_VARS: logs an ERROR, does not exit.
- [correction] M2.1 window: Prometheus retention is 7d (kube-prometheus-stack helmrelease `retention: 7d`), so the planned ~8d window is impossible. Implemented as [6d] plus a `present_over_time([1d] offset 5d)` age gate, so a new feed or the first post-upgrade runs cannot fire on a short constant window.
- [correction] M2.3 is redundant: kube-prometheus-stack `defaultRules.rules.kubernetesApps: true` already ships KubeJobFailed. No custom JobFailed rule is needed in any variant.
- [decision] FAIL_ON_DEAD_FEED NOT adopted (human decision 2026-10-13): KubeJobFailed keeps firing while a failed Job object exists (failedJobsHistory 3), and backoffLimit 3 + OnFailure would re-run a dead feed up to 4 times. SourceFailing (2-run debounce) + the http_status cause guidance cover the dead-feed case without that noise.
- [decision] M2.2 implemented as annotation guidance on CrowdSecBlocklistImportSourceFailing (404/410 dead, 5xx outage, 0 connection) — no new rule (net-reduction).

### Implemented

- helmrelease.yaml: ENABLE_MONTY_SECURITY_C2 removed; BLOCKLISTS_OPT_IN: "true" added.
- prometheusrule.yaml: CrowdSecBlocklistImportFeedEmpty (max(source_entries)==0 and max(source_status)==1, no for) and CrowdSecBlocklistImportFeedFrozen (min_over_time[6d] > 0 and max_over_time[6d] == min_over_time[6d] and present_over_time[1d] offset 5d), both warning; SourceFailing description extended.
- prometheusrule_test.yaml: cases 27-33 (FeedEmpty fire / status-gate no-fire / boundary 1; FeedFrozen fire / changed / min>0 gate / age-gate pin); SourceFailing exp_annotations updated. `just k8s test-prom-rules` all green; age-gate and status-gate mutation-verified (removing either makes exactly its pin case fail).
- Frozen-rule caveat: slow-moving lists (e.g. Spamhaus DROP) may legitimately hold a constant size for 6 days — first firings are investigate-first. Earliest possible firing: ~2026-10-19/20 (5d of 3.9.0 history needed). Botvrij is the expected first firing.

### Still open (M3)

After the 2026-10-14 04:00 run: new gauge families present in the pushgateway and scraped; no Monty ERROR and no defaults-flip DEPRECATION in logs (once this change is live); sources_enabled == 9; no unexpected Cilium drops for the importer pod; all three new/changed rules loaded in Prometheus.

## Related

- relates_to [[crowdsec-blocklist-import]]
- relates_to [[crowdsec-import-silent-degradation]]
