---
title: crowdsec-ban-pushover-alerting
type: note
permalink: home-ops/docs/roadmap/crowdsec-ban-pushover-alerting
---

# crowdsec-ban-pushover-alerting — roadmap

## Status
planning — Phase 1 complete and Maestro-ratified; Phase 2 implementation in progress. The rule is correct, future-proof, and WILL fire on a real local ban — an external attacker can be banned today (AC3 achievable; the human can produce a ban).

## Decision: Option A (PrometheusRule) over Option B (CrowdSec http-notification plugin)
The human does not value the source IP for ban alerts (stated), and NO cs_* metric carries the source IP as a label (high-cardinality; CrowdSec does not expose IPs) — so Option B's only advantage (per-ban IP in the body) is moot here. Option A reuses the existing Alertmanager -> Pushover route (kubernetes/apps/observability/kube-prometheus-stack/app/alertmanagerconfig.yaml:32-37 matcher + :58-92 receiver; token/userKey from alertmanager-secret) with zero new secrets and no parallel notification plane. Option A's signal is cs_active_decisions non-CAPI, a gauge that fires WHILE a local ban is active — not a per-ban event, but the correct "a local ban exists" signal for an aggregated alert.

## Verified metric inventory (Phase 1, live on prometheus-kube-prometheus-stack-0 via "promtool query instant")
EXISTS:
- cs_active_decisions — gauge, labels {action, origin, reason, machine}. Reset() + repopulated on every /metrics scrape from QueryDecisionCountByScenario. Live: 3 series, ALL origin=CAPI (ssh:bruteforce 8232, http:scan 15563, generic:scan 1383). ZERO local active decisions now (expected — see "Why zero local alerts was NOT a defect").
- cs_bucket_overflowed_total — counter on the AGENT, label name. Only series: name=ltsich/http-w00tw00t = 14. This is overflow->alert, NOT strictly a ban.
- bouncer_lapi_decisions_added_total — exists but includes CAPI bulk -> flood; not a local-ban signal.

DO NOT EXIST (empty results):
- cs_lapi_decisions_total, cs_active_alerts, cs_lapi_alerts_total, cs_decisions_total.

No cs_* metric carries the source IP as a label (confirmed by inspecting all cs_.* series labels).

## Origin enum + DENYLIST (not allowlist) rationale
Origin enum (cscli --origin help; docs.crowdsec.net/cscli/cscli_decisions_list; v1.7.8): cscli, crowdsec, console, cscli-import, lists, CAPI, remediation_sync (+ "..." = non-exhaustive).

Alert expression denylist fragment: origin!~"CAPI|lists(:.*)?"
Prometheus regex is fully anchored, so this excludes EXACTLY "CAPI", "lists", "lists:XXX"; INCLUDES crowdsec, cscli, cscli-import, console, remediation_sync, empty-string (appsec), and ANY future origin. This is fail-loud by design: a future origin the alert does not know about still fires rather than being silently allowlisted. CAPI (community blocklist, ~25k live) and lists/lists:XXX (console-subscribed blocklists) are the noisy set excluded.

## Coverage proof (by construction; two v1.7.8 source citations, both re-verified verbatim by the Maestro)
- Metric: cmd/crowdsec/metrics.go @ v1.7.8 — GlobalActiveDecisions.Reset() then repopulated from dbClient.QueryDecisionCountByScenario on every /metrics scrape; labels {reason=d.Scenario, origin=d.Origin, action=d.Type}.
- Query: pkg/database/decisions.go @ v1.7.8 (Ent ORM) — Decision.Query().Where(decision.UntilGT(now)).GroupBy(scenario, origin, type).Aggregate(Count) — counts EVERY non-expired LAPI decisions-table row, no other filter.
=> every active decision row is covered regardless of which path created it. Per path: agent scenario overflow -> origin "crowdsec"; appsec in-band match -> alert.Source.Origin unset -> empty/LAPI-default (NOT CAPI/lists) -> included; cscli -> "cscli"; console -> "console"; bouncer consumes decisions, creates no LAPI rows (covered transitively).
Honest caveat: appsec OUT-OF-BAND matches reset SendAlert=false by default -> no alert -> no decision -> not a "ban"; in-band virtual-patching matches DO create decisions. The metric covers every actual BAN (a decision row); OOB-only detections are not bans.

## Agreed alert shape (to add to the EXISTING group in kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml — no new file, no AlertmanagerConfig change, no secret)
- expr: sum by (reason, origin, action) (cs_active_decisions{job="crowdsec-service", namespace="crowdsec", origin!~"CAPI|lists(:.*)?"}) > 0
- severity: critical (routes via the dedicated pushover sub-route; CANNOT be inhibited by the existing critical->warning inhibit rule, alertmanagerconfig.yaml:37-48, which targets warning only; the global priority template :64-65 already gives all firing alerts Pushover priority 1, so critical adds no extra noise).
- for: 1m + keep_firing_for: 5m (debounce a transient scrape-gap resolve->refire since the gauge is Reset() each scrape; a 4h ban means a 5m lag on genuine resolve is negligible). One terse WHY comment, matching the file's existing style.

## Option B — documented fallback (NOT chosen; trigger condition + two Maestro corrections)
Trigger condition: if a future requirement values the per-ban source IP in the notification body, switch to B (the CrowdSec-native http-notification plugin). B is the only path that reports the source IP.
Correction 1: the http-notification plugin payload key is "format", NOT "body".
Correction 2: any runtime ${VAR} in a manifest under kubernetes/ must be escaped as $${VAR} because the root cluster-apps Kustomization applies postBuild substitution (live pattern: helmrelease.yaml:31 — "$${REGISTRATION_TOKEN}"). An unescaped ${VAR} is consumed by Flux postBuild and never reaches the container env.

## Why zero local alerts was NOT a defect (false trail, closed)

The earlier "zero local alerts on the LAPI" observation is fully explained WITHOUT any delivery defect:
- the local alert DID exist on the LAPI; the human saw it there and DELETED it manually (confirmed by the human). So the agent -> LAPI -> alert -> decision path works end to end.
- the 14 w00tw00t overflows (cs_bucket_overflowed_total=14) are consistent with ONE alert for one repeat source IP: CrowdSec deduplicates / extends rather than creating 14 alert rows.
- any resulting 4h ban (default_ip_remediation profile) has since expired; cs_active_decisions counts only non-expired rows (decision.UntilGT(now), verified in decisions.go @ v1.7.8) — empty now is correct, not a defect.

LESSON (nearly cost a wrong roadmap note): cscli alerts list shows the current state of a MUTABLE store — absence is not proof that something never happened. Both the Maestro (10.x whitelist hypothesis) and the worker (delivery-defect conclusion) over-read the same snapshot; the missing variable was the human's own manual delete. Ask whether anyone has deleted anything before concluding "never happened".

## Relations
- relates_to [[envoy-crowdsec-bouncer]]
