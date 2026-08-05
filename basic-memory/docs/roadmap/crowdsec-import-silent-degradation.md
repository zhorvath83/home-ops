---
title: crowdsec-import-silent-degradation
type: roadmap
permalink: home-ops/docs/roadmap/crowdsec-import-silent-degradation
topic: Detect silent degradation of the blocklist-import plane
status: proposed
priority: high
scope: The blocklist-import CronJob, its bouncer-key dedup path, and the FQDN egress
  allowlist can each degrade the live decision set without surfacing a job failure,
  an alert, or a network-policy drop. This item packages the six known silent-degradation
  modes into one detection workstream so a near-zero-protection state always raises
  a signal. Feed pruning and Tier B/C promotion decisions stay owned by Phase 4/5
  — out of scope here.
rationale: 'Three of the modes can silently reduce protection to nothing: _run_once
  returns 0 if at least one source succeeds, the bouncer-key path treats 403 as healthy
  and widens max_new to the full cap, and the FQDN allowlist cannot catch an accidental
  Tier B/C enablement for hosts already allowed for Tier A. The Monty C2 dead-feed
  discovery proved the feed-rot mode live. None is caught by KubeJobFailed, the decision-budget
  alert, or the CNP audit today.'
related_areas:
- observability
- networking
options:
- Per-source success/freshness telemetry from the importer (metric or structured log)
  → alert on any source silent for N runs / stale Last-Modified
- 'Bouncer-key 403 detection: treat a 403 from health_check()/get_existing_ips() as
  a run failure, or export a dedicated metric, so a revoked key does not silently
  skip dedup'
- 'Make accidental Tier B/C enablement network-visible: split raw.githubusercontent.com
  egress by path/identity so the ENABLE_* env gates are not the only control'
- 'Recurring frozen-feed decay check: a scheduled job that re-reads each feed Last-Modified
  and alerts on staleness beyond the feed cadence'
- Measure the CronJob pod resource high-water mark (enable METRICS_ENABLED or a one-shot
  resource probe) to validate the 512Mi limit
- Paginate or stream get_existing_ips to bound memory against the growing total decision
  count (upstream contribution; failure mode is ours)
---

# Detect silent degradation of the blocklist-import plane

## Metadata (observation-form, schema validation)

- [topic] Detect silent degradation of the blocklist-import plane
- [status] proposed
- [priority] high
- [created] 2026-08-05 — consolidates the silent-degradation follow-ups logged in [[docs/progress/crowdsec-blocklist-import]]

## The theme

The blocklist-import plane has six known modes in which the live decision set can degrade toward zero protection while every existing health signal (KubeJobFailed, the CrowdSecDecisionBudgetNearCap alert, the FQDN egress CNP audit) stays green. They are unrelated as code paths but identical as failure class: the protection silently drops and nothing raises. This item packages them as one detection workstream; it does not pick fixes for all of them — where the right fix is open, the option is listed with its tradeoff.

## Members

### (a) Feed-rot is structurally invisible — highest value

- [failure] Upstream `_run_once` returns 0 whenever at least ONE source succeeded, so 9 of 10 Tier A feeds failing still yields a successful Job and no alert.
- [evidence] Verified against `blocklist_import.py` (pinned v3.7.1); logged as N2 in [[docs/progress/crowdsec-blocklist-import]]. The Monty Security C2 dead-feed discovery (upstream `data/all.txt` 404) proved the mechanism live — a fully-dead feed was invisible to the job's exit code and was found only by a manual upstream check, not by any job signal (Final-round (b) in the progress note).
- [candidate] Export per-source success/freshness from the importer (a metric or structured log line per source per run) and alert on any source silent for N consecutive runs or with a Last-Modified older than its documented cadence. This subsumes member (d).
- [tradeoff] The importer does not currently emit per-source telemetry, so this needs an importer change or a log parser, not just a new alert on an existing metric.

### (b) Bouncer-key path fails silently — highest value

- [failure] `health_check()` returns `response.status_code in (200, 403)` (True for 403 — "200 = OK, 403 = unauthorized but reachable") and `get_existing_ips()` logs an error on 403 and returns `[]`. An invalid or revoked BOUNCER key does not fail the run — it silently skips dedup, and `max_new` widens to the full `MAX_DECISIONS`.
- [evidence] Verified against `blocklist_import.py` main; logged as Closing (C4) in [[docs/progress/crowdsec-blocklist-import]]. The write-path gate validated in the live manual Job `bli-live-1` covers only the MACHINE credential, not the bouncer key.
- [candidate] Treat a 403 from the bouncer-key path as a run failure (exit non-zero), or export a dedicated metric for bouncer-key 403s, so a revoked key cannot silently disable dedup.
- [tradeoff] Changing the exit-code contract is a behaviour change; a metric-only signal preserves the exit-0 path but still needs an alert to be useful. Which is preferable is open.

### (c) FQDN allowlist blind to accidental Tier B/C enablement

- [failure] `raw.githubusercontent.com` is already allowed for Tier A (`cybercrime.ipset` + `vxvault.ipset`), so it also serves four disabled high-volume Tier B/C gates (ABUSE_IPDB, FIREHOL, IPSUM, maltrail under SCANNERS) with no CNP change. An accidental `ENABLE_*=true` for those is invisible to the network policy — the env gates are the only control.
- [evidence] Logged as N5 and the Cap+alert-round egress-policy observation in [[docs/progress/crowdsec-blocklist-import]].
- [candidate] Make Tier B/C enablement network-visible: split the `raw.githubusercontent.com` egress by path or by source identity so the env flags are not the sole control.
- [tradeoff] toFQDNs cannot split by URL path; a path-level split needs an L7 policy (Envoy/Cilium L7) or per-feed distinct hosts where they exist. Genuinely open — listed as an option, not a decision.

### (d) Frozen-mirror feed decay (recurring, not one-off)

- [failure] A feed can freeze (stale Last-Modified against a documented cadence) and remain "enabled" forever; Cybercrime Tracker was a 28-day-stale mirror (`Source File Date: Tue Jul 7` against a 12h cadence).
- [evidence] Recorded in the R3 pruning-decision section of [[docs/roadmap/crowdsec-blocklist-import]] as a 30-day review trigger, not a one-off — a recurring decay check is needed.
- [candidate] A scheduled job that re-reads each feed Last-Modified and alerts on staleness beyond the feed cadence. Subsumed by member (a)'s freshness telemetry if that emits Last-Modified per source.
- [tradeoff] Some feeds do not expose a reliable Last-Modified; the check needs a per-feed cadence table.

### (e) Job-pod resource usage UNVERIFIED (slow-burn)

- [failure] The CronJob pod is scaled to 0 between runs and `METRICS_ENABLED=false`, so the 512Mi limit is a reasoned estimate (the unpaginated decision fetch), not a measured high-water mark.
- [evidence] Logged as Final-round (c) in [[docs/progress/crowdsec-blocklist-import]].
- [candidate] Enable METRICS_ENABLED or run a one-shot resource probe on the next non-dry-run run to record the actual high-water mark and validate the 512Mi limit.
- [tradeoff] Low cost; the only risk is discovering the limit is too low, which is itself the point.

### (f) get_existing_ips unpaginated (slow-burn, partly upstream)

- [failure] `get_existing_ips` issues a single unpaginated `GET /v1/decisions` and `response.json()`s the whole body; it grows with the LAPI's total decision count and will eventually exceed memory.
- [evidence] ~33.8k decisions ≈ ~6.8 MB JSON today; logged as Final-round (a) in [[docs/progress/crowdsec-blocklist-import]] and the rationale for the 512Mi limit.
- [candidate] Paginate or stream `get_existing_ips` to bound memory against the total decision count.
- [tradeoff] This is an upstream `blocklist_import.py` change; the failure mode is ours but the fix is contributed upstream or carried as a patch.

## Priority argument

(a) and (b) are the sharp ones — either can silently reduce the protection to nothing (all feeds dead but job green; revoked bouncer key but job green and max_new widened to the full cap). (c) is a control-bypass that needs operator error to trigger, so it is second. (d) is a recurrence of (a)'s class and is subsumed by (a)'s freshness telemetry. (e) and (f) are slow-burn capacity limits, not protection drops — real but lower urgency. Hence priority: high (driven by (a)+(b)), and (a)/(b) should land first.

## Out of scope

- Phase 4 owns the 3-week observation window (decision volume, feed health, alert noise) — feed pruning decisions belong there, not here.
- Phase 5 owns Tier B/C feed promotion (evidence-gated) — which feeds to enable is a Phase 5 decision; this item only covers detecting accidental/unguarded enablement (member c).
- The keep_firing_for latch test gap on CrowdSecBanActive / CrowdSecAcquisitionStalled is a unit-test-coverage gap, not a silent-degradation mode — tracked in [[prometheusrule-unit-test-coverage]].

## Resumption state

This section is the single pick-up point for this item — a future session should resume from here without replaying the delivery history in [[docs/progress/crowdsec-blocklist-import]]. It is expected to be kept current: whoever closes one of the entries below updates or removes it here rather than leaving a stale line. A resumption section that rots is worse than none, because it is trusted.

- **Phase 4 observation window — OPEN.** Opened 2026-08-05, review due ~2026-08-26 (3 weeks). Data source: the per-source DEBUG log lines the importer emits (`LOG_LEVEL: DEBUG` was enabled for this), retained in VictoriaLogs. Hit attribution CANNOT come from metrics — already measured: the bouncer exposes 15 metric families; `bouncer_requests_total` is labelled by `action` only with NO `origin` label, and `bouncer_decision_cache_size{origin=...}` counts CACHE, not hits. The VictoriaLogs correlation path (bouncer-denied 403s cross-referenced against `cscli decisions list --origin blocklist-import -o json`) is MANDATORY, not a fallback. Baseline: over 30 days the whole plane measured 19 bans vs 52,630 allows (0.036%), all 19 predating blocklist-import. The decision rule and the full measurement list live in the Phase 4 section of [[docs/roadmap/crowdsec-blocklist-import]] — point there, do not duplicate.
- **F6 acceptance — UNPROVEN.** `BATCH_SIZE: "5000"` is live (verified in the running CronJob) but its effect is not yet demonstrated. Gate, stated so it cannot be faked: a run only proves F6 if it imported MORE than 500 IPs — a low-phase run (~288 net-new) produces 1 alert record at the old `BATCH_SIZE=500` too, so it proves nothing. Check: read the newest blocklist-import Job log for `Imported N new IPs into CrowdSec`; if N > 500, confirm that run's timestamp bucket has exactly ONE alert record (`cscli alerts list --limit 200 -o json`, group by `created_at` minute). Older buckets from pre-merge runs persist until LAPI flush retention prunes them, so do NOT expect a grand total of 1. WHY this gate is worded so carefully: the original acceptance ("next run yields 1 record instead of 11") was invalid because the 11-record figure was two runs' total, not one — a low-phase run would have passed it trivially. That is already corrected in [[docs/progress/crowdsec-blocklist-import]]; the point here is that the replacement gate must not repeat it.
- **Trivial leftover:** the manual Job `bli-live-1` still exists in the crowdsec namespace (its log is saved at `/tmp/claude-501/bli-live-1.log`, which is ephemeral). Deleting it is pending the human's word.

## Related

- relates_to [[docs/roadmap/crowdsec-blocklist-import]]
- relates_to [[docs/progress/crowdsec-blocklist-import]]
- relates_to [[observability]]
- relates_to [[networking]]
