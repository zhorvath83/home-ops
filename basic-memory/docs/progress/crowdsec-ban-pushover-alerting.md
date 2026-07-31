---
title: crowdsec-ban-pushover-alerting
type: note
permalink: home-ops/docs/progress/crowdsec-ban-pushover-alerting
---

# crowdsec-ban-pushover-alerting — execution progress

## Metadata (observation-form)
- [topic] Execution state for the crowdsec-ban-pushover-alerting roadmap
- [status] DONE — implemented, deployed, live-verified, all acceptance criteria closed. Roadmap note merged into this note (docs/roadmap note deleted on closure). AC1/AC2/AC3/AC5/AC6/AC7 live-verified by the Maestro independently; AC4 closed by human decision (resolve path wired via sendResolved on the existing alertmanager -> pushover route; the live resolve push was not waited for — the ban was still active at closure with ~8h remaining and repeat-offence doubling).
- [roadmap] merged into this note — the docs/roadmap/crowdsec-ban-pushover-alerting note was deleted on closure; all design rationale now lives in the section below
- [area] observability, security
- [created] 2026-07-31
- [closed] 2026-07-31

## Design rationale (merged from roadmap)

### Decision: Option A (PrometheusRule) over Option B (CrowdSec http-notification plugin)
The human does not value the source IP for ban alerts (stated), and NO cs_* metric carries the source IP as a label (high-cardinality; CrowdSec does not expose IPs) — so Option B's only advantage (per-ban IP in the body) is moot here. Option A reuses the existing Alertmanager -> Pushover route (kubernetes/apps/observability/kube-prometheus-stack/app/alertmanagerconfig.yaml:32-37 matcher + :58-92 receiver; token/userKey from alertmanager-secret) with zero new secrets and no parallel notification plane. Option A's signal is cs_active_decisions non-CAPI, a gauge that fires WHILE a local ban is active — not a per-ban event, but the correct "a local ban exists" signal for an aggregated alert.

### Verified metric inventory (Phase 1, live on prometheus-kube-prometheus-stack-0 via "promtool query instant")
EXISTS:
- cs_active_decisions — gauge, labels {action, origin, reason, machine}. Reset() + repopulated on every /metrics scrape from QueryDecisionCountByScenario. Live: 3 series, ALL origin=CAPI (ssh:bruteforce 8232, http:scan 15563, generic:scan 1383). ZERO local active decisions then (expected — see "Why zero local alerts was NOT a defect").
- cs_bucket_overflowed_total — counter on the AGENT, label name. Only series: name=ltsich/http-w00tw00t = 14. This is overflow->alert, NOT strictly a ban.
- bouncer_lapi_decisions_added_total — exists but includes CAPI bulk -> flood; not a local-ban signal.

DO NOT EXIST (empty results):
- cs_lapi_decisions_total, cs_active_alerts, cs_lapi_alerts_total, cs_decisions_total.

No cs_* metric carries the source IP as a label (confirmed by inspecting all cs_.* series labels).

### Origin enum + DENYLIST (not allowlist) rationale
Origin enum (cscli --origin help; docs.crowdsec.net/cscli/cscli_decisions_list; v1.7.8): cscli, crowdsec, console, cscli-import, lists, CAPI, remediation_sync (+ "..." = non-exhaustive).

Alert expression denylist fragment: origin!~"CAPI|lists(:.*)?"
Prometheus regex is fully anchored, so this excludes EXACTLY "CAPI", "lists", "lists:XXX"; INCLUDES crowdsec, cscli, cscli-import, console, remediation_sync, empty-string (appsec), and ANY future origin. This is fail-loud by design: a future origin the alert does not know about still fires rather than being silently allowlisted. CAPI (community blocklist, ~25k live) and lists/lists:XXX (console-subscribed blocklists) are the noisy set excluded.

### Coverage proof (by construction; two v1.7.8 source citations, both re-verified verbatim by the Maestro)
- Metric: cmd/crowdsec/metrics.go @ v1.7.8 — GlobalActiveDecisions.Reset() then repopulated from dbClient.QueryDecisionCountByScenario on every /metrics scrape; labels {reason=d.Scenario, origin=d.Origin, action=d.Type}.
- Query: pkg/database/decisions.go @ v1.7.8 (Ent ORM) — Decision.Query().Where(decision.UntilGT(now)).GroupBy(scenario, origin, type).Aggregate(Count) — counts EVERY non-expired LAPI decisions-table row, no other filter.
=> every active decision row is covered regardless of which path created it. Per path: agent scenario overflow -> origin "crowdsec"; appsec in-band match -> alert.Source.Origin unset -> empty/LAPI-default (NOT CAPI/lists) -> included; cscli -> "cscli"; console -> "console"; bouncer consumes decisions, creates no LAPI rows (covered transitively).
Honest caveat: appsec OUT-OF-BAND matches reset SendAlert=false by default -> no alert -> no decision -> not a "ban"; in-band virtual-patching matches DO create decisions. The metric covers every actual BAN (a decision row); OOB-only detections are not bans.

### Agreed alert shape (added to the EXISTING group in kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml — no new file, no AlertmanagerConfig change, no secret)
- expr: sum by (reason, origin, action) (cs_active_decisions{job="crowdsec-service", namespace="crowdsec", origin!~"CAPI|lists(:.*)?"}) > 0
- severity: critical (routes via the dedicated pushover sub-route; CANNOT be inhibited by the existing critical->warning inhibit rule, alertmanagerconfig.yaml:37-48, which targets warning only; the global priority template :64-65 already gives all firing alerts Pushover priority 1, so critical adds no extra noise).
- for: 1m + keep_firing_for: 5m (debounce a transient scrape-gap resolve->refire since the gauge is Reset() each scrape; a 4h ban means a 5m lag on genuine resolve is negligible). One terse WHY comment, matching the file's existing style.

### Option B — documented fallback (NOT chosen; trigger condition + two Maestro corrections)
Trigger condition: if a future requirement values the per-ban source IP in the notification body, switch to B (the CrowdSec-native http-notification plugin). B is the only path that reports the source IP.
Correction 1: the http-notification plugin payload key is "format", NOT "body".
Correction 2: any runtime $${VAR} in a manifest under kubernetes/ must be escaped as $$${VAR} because the root cluster-apps Kustomization applies postBuild substitution (live pattern: helmrelease.yaml:31 — "$$${REGISTRATION_TOKEN}"). An unescaped $${VAR} is consumed by Flux postBuild and never reaches the container env.

### Why zero local alerts was NOT a defect (false trail, closed)
The earlier "zero local alerts on the LAPI" observation is fully explained WITHOUT any delivery defect:
- the local alert DID exist on the LAPI; the human saw it there and DELETED it manually (confirmed by the human). So the agent -> LAPI -> alert -> decision path works end to end.
- the 14 w00tw00t overflows (cs_bucket_overflowed_total=14) are consistent with ONE alert for one repeat source IP: CrowdSec deduplicates / extends rather than creating 14 alert rows.
- any resulting 4h ban (default_ip_remediation profile) has since expired; cs_active_decisions counts only non-expired rows (decision.UntilGT(now), verified in decisions.go @ v1.7.8) — empty now is correct, not a defect.

LESSON (nearly cost a wrong roadmap note): cscli alerts list shows the current state of a MUTABLE store — absence is not proof that something never happened. Both the Maestro (10.x whitelist hypothesis) and the worker (delivery-defect conclusion) over-read the same snapshot; the missing variable was the human's own manual delete. Ask whether anyone has deleted anything before concluding "never happened".

## Code state
Committed on main (code commit 5ec31c912): adds the CrowdSecBanActive alert to the EXISTING crowdsec PrometheusRule group in kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml (no new file, no AlertmanagerConfig change, no new secret).
- expr: sum by (reason, origin, action) (cs_active_decisions{job="crowdsec-service", namespace="crowdsec", origin!~"CAPI|lists(:.*)?"}) > 0
- for: 1m, keep_firing_for: 5m, severity: critical (routes via the existing critical -> Pushover sub-route; cannot be inhibited by the critical->warning inhibit rule).

Annotation rewrite (commit f0d92b32d): summary/description rewritten after the human called the original wording out — the description IS the Pushover message body the recipient reads on their phone, but it was written as an internal design note. New text:
- summary: "CrowdSec banned a source"
- description: "CrowdSec banned a source after the scenario below tripped. The ban lasts 4h and doubles for each repeat offence; no action is needed. If it was you, clear it with `cscli decisions delete <ip>`."

## Acceptance criteria (final status)

VERIFIED (live, by the Maestro independently):
- AC1 (a locally issued non-CAPI ban makes the alert fire): verified against the live firing alert's labels, not just the expr — a real local ban is active (origin=crowdsec, reason=ltsich/http-w00tw00t, action=ban), the alert is firing (activeAt 2026-07-31T17:34:05Z), Alertmanager has it active (not inhibited/silenced), routed to the pushover receiver.
- AC2 (alert carries reason/origin/action labels): verified by expr construction "sum by (reason, origin, action)" — labels preserved into the notification body.
- AC3 (a real external ban fires the alert end-to-end -> Pushover on the device): VERIFIED — the human confirmed the Pushover notification arrived on their phone (see "Annotation rewrite + live end-to-end verification").
- AC5 (no CAPI flood): verified — the denylist excludes origin=CAPI and lists/lists:*; the Maestro's count query confirms CAPI is the only origin present, so the denylist matches zero rows.
- AC6 (correct PrometheusRule YAML, loaded by Prometheus): verified by pre-commit (yamlfmt/yamllint/gitleaks Passed) on the touched file; deploy verification (CR exists + Prometheus loaded the rule via the rules API) confirmed.
- AC7 (no new secrets / files / AlertmanagerConfig changes): verified by the diff — only a rule was added to the existing group; the existing Alertmanager -> Pushover route is reused.

CLOSED (human decision, 2026-07-31):
- AC4 (the alert resolves when the ban expires / is deleted -> sendResolved pushes the resolve): the resolve path is wired through the existing alertmanager -> pushover receiver (sendResolved=true). The live resolve push was NOT waited for, because at closure the ban was still active (~8h remaining, repeat-offence doubling). The human chose to close the item without waiting for the natural expiry/tombstone push. The wiring is proven; the live resolve notification is deferred to the ban's natural lifecycle, not tracked further here.

## Maestro's independent verification (verify-don't-trust; re-ran everything, closed a gap the worker left open)

The worker's "live expr returns EMPTY, exit 0" was NOT evidence the rule is correct — a WRONG label matcher returns the same empty result. The Maestro closed that gap with five queries against the live Prometheus:
1. count by (job, namespace, origin) (cs_active_decisions) => {job="crowdsec-service", namespace="crowdsec", origin="CAPI"} = 3 — the job/namespace matchers provably hit real series.
2. cs_active_decisions{origin=~"CAPI|lists(:.*)?"} => 3 — the denylist regex really does match CAPI.
3. Anchoring proof: {job!~"crowdsec-serv"} => 3 — a partial pattern does NOT match, so the full-match anchoring is as claimed.
4. Fail-loud proof: {origin!~"CAP|lists(:.*)?"} => 3 — a near-miss origin value is INCLUDED. Any present-or-future origin that is not exactly CAPI/lists/lists:* alerts. This is the property the human's hard condition demanded, now empirically proven, not just argued.
5. pre-commit on the touched file re-run by the Maestro: all hooks Passed; live git status showed only the two intended paths.
LESSON for next time: when a validation query returns empty, prove the matcher is non-vacuous before calling it validated.

## False-trail history (the most valuable thing in this session)

Two wrong conclusions were built on the same mutable snapshot (cscli alerts list showing only CAPI alerts, zero local). The Maestro hypothesized the source IP was the cloudflared pod IP 10.x (whitelisted by crowdsecurity/whitelists) — refuted by live envoy-external access logs showing downstream_remote_address = a real public IPv6 (CF-Connecting-IP detection rewrites it). The worker then concluded an agent->LAPI alert-delivery defect (the agent logs overflow->alert creation, the LAPI showed zero local alerts) — refuted by the human, who had seen the local alert on the LAPI and DELETED it manually. The missing variable in both cases was the human's own manual action. LESSON: cscli alerts list shows the current state of a MUTABLE store — absence is not proof that something never happened. Ask whether anyone has deleted anything before concluding "never happened". This is recorded in the Design rationale section above too.

## Re-test procedure (retained for reference — AC3/AC4 already closed)

From a public WAN IP (NOT LAN — crowdsecurity/whitelists whitelists 10/172.16/192.168/127/::1, so a LAN source will NOT trigger):
  curl -A "sqlmap/1.6.7" https://<public-domain>/
trips crowdsecurity/http-bad-user-agent -> agent overflow -> LAPI alert + decision (4h ban, origin=crowdsec). WARNING: this bans the human's own WAN IP for 4h (default_ip_remediation profile), blocking their own external access for that window. Rollback: "cscli decisions delete <ip>" (run on the LAPI pod). Then watch for the Pushover notification (AC3, already verified live) and, after the ban expires or is deleted, the resolve notification (AC4, closed by human decision — wiring proven, live push not waited for).

## Relations
- relates_to [[envoy-crowdsec-bouncer]]

## Deploy verification (final, post-rebase)

The shas were re-created twice during this session (a human soft-reset, then a rebase onto the Renovate commit e9bcac529 that landed on origin/main mid-push), so any dead predecessor found in git history is the same logical commit, not separate work. The FINAL shas are:
- CODE: 5ec31c912 ✨ feat(crowdsec): alert on locally issued bans
- DOCS: 6d9244f7e 📝 docs(crowdsec): record the ban-alerting rollout and its verification

Push: confirmed `e9bcac529..6d9244f7e main -> main`; `git rev-list --left-right --count origin/main...main` = 0/0 (level); remote tip = 6d9244f7e237dad71aa78e92c28109563a569116.

Flux: the crowdsec/crowdsec Kustomization reconciled at Applied revision refs/heads/main@sha1:6d9244f7e237dad71aa78e92c28109563a569116 — the PrometheusRule CR on the cluster carries the CrowdSecBanActive entry (kubectl get prometheusrule -n crowdsec crowdsec -o yaml).

Prometheus LOADED the rule (not merely CR present) — proven via the rules API (/api/v1/rules, fetched by port-forward + curl since the distroless prometheus container has no curl/wget/ls/sh, only prometheus+promtool):
- group=crowdsec, name=CrowdSecBanActive, state=inactive, health=ok, type=alerting
- query / duration=60 / keepFiringFor=300 / severity=critical all loaded from the committed YAML
- lastEvaluation fresh (2026-07-31T17:29:05Z) — the rule is evaluating, not stale

Caveat on method (LESSON): the ALERTS metric is NOT a valid loaded-proof here. Prometheus only emits an ALERTS{alertstate="inactive"} series for a rule that has PREVIOUSLY fired; a never-fired rule (CrowdSecBanActive at first load, or the pre-existing CrowdSecLAPIDown) does NOT appear in ALERTS at all — count(ALERTS) showed only Watchdog + KubeHpaMaxedOut, both firing. The same empty ALERTS result that "proved not loaded" for CrowdSecBanActive was equally empty for the pre-existing CrowdSecLAPIDown — the non-vacuous control that exposed the method, not the rule. The rules API is the correct loaded-proof because it lists every loaded rule regardless of firing history.

## Annotation rewrite + live end-to-end verification

Commit f0d92b32d (♻️ refactor(crowdsec): make the ban alert readable in the notification, pushed 5787529e7..f0d92b32d) rewrote the CrowdSecBanActive summary/description after the human called the original wording out — and they were right: the description IS the Pushover message body the recipient reads on their phone, but it was written as an internal design note ("routed to Pushover via the critical sub-route" — the medium announcing itself; "carries reason/origin/action labels for the notification body" — meta-commentary restating labels the Alertmanager template already renders in a <small> block). New text:
- summary: "CrowdSec banned a source" (plainer, past tense — matches what happened)
- description: "CrowdSec banned a source after the scenario below tripped. The ban lasts 4h and doubles for each repeat offence; no action is needed. If it was you, clear it with `cscli decisions delete <ip>`." (what happened -> how long -> whether to act -> how to undo; "the scenario below" points at the label block instead of duplicating it)

LESSON (reusable — annotation-wording): annotations are the product surface. `description` is written FOR THE RECIPIENT — what happened, what it means, what (if anything) to do. Never about the alerting pipeline, and never restating labels the template already renders. The CODE comment above the rule (WHY the denylist is non-CAPI, the gauge Reset/keep_firing_for debounce) stays — that one is for maintainers, the right audience for a code comment.

Deploy verification of the rewrite:
- Flux reconciled crowdsec/crowdsec at Applied revision refs/heads/main@sha1:f0d92b32; the in-cluster PrometheusRule CR carries the new summary/description (kubectl jsonpath).
- Prometheus reloaded it (rules API /api/v1/rules via port-forward): CrowdSecBanActive health=ok, state=firing, annotations = new text, lastEvaluation fresh. The operator->config-reloader->/-/reload chain lagged ~30s behind the CR update (old text was still served briefly); confirmed loaded only by re-querying the rules API until the new summary appeared.

Live end-to-end verification (AC1/AC2/AC3 now VERIFIED — Maestro confirmed independently):
- A REAL local ban is active: origin=crowdsec, reason=ltsich/http-w00tw00t, action=ban, severity=critical — the alert is firing (activeAt 2026-07-31T17:34:05Z), Alertmanager has it active (not inhibited/silenced), routed to the pushover receiver. AC1 (non-CAPI ban fires) + AC2 (labels carried) verified against the live firing alert's labels, not just the expr.
- AC3 (end-to-end -> Pushover on the device): VERIFIED — the human confirmed the Pushover notification arrived on their phone. (The new description text goes out on Alertmanager's next 12h repeat (root route repeatInterval=12h, critical->pushover sub-route does not override), not minutes from now.)
- AC4 (resolved push when the ban expires/is deleted): CLOSED by human decision (see Acceptance criteria). At closure the ban was still active with ~8h remaining (repeat-offence doubling).

## Alertmanager independent verification (Maestro direct API check — stronger than rules API alone)

The Alertmanager API directly holds the NEW annotation text (summary "CrowdSec banned a source", the rewritten description), updatedAt 2026-07-31T17:43:05Z, state active, receivers ["observability/alertmanager/pushover"]. That proves Prometheus is evaluating the reloaded rule AND propagating the new annotations downstream — the whole chain, not just the CR or the rules API.

repeatInterval correction (Maestro accepted): the rewritten BODY only reaches the phone on the next 12h repeat (root route repeatInterval=12h; the critical->pushover sub-route does not override it), so anyone re-testing the wording must clear and re-trigger the ban (cscli decisions delete <ip>, then a fresh ban) rather than wait for a repeat. The human already received the OLD-text notification (the AC3 end-to-end delivery proof); the NEW text goes out on the next 12h repeat or on a fresh firing.

## Roadmap closure (2026-07-31)
The crowdsec-ban-pushover-alerting roadmap item is CLOSED. The roadmap note (docs/roadmap/crowdsec-ban-pushover-alerting) was merged into this progress note (Design rationale section above) and deleted — everything now lives under docs/progress per the roadmap -> progress lifecycle. All acceptance criteria are closed: AC1/AC2/AC3/AC5/AC6/AC7 live-verified by the Maestro independently; AC4 closed by human decision (resolve path wired via sendResolved, live resolve push not waited for — the ban was still active at closure). The feature is live in production: the CrowdSecBanActive alert is firing on a real local ban (origin=crowdsec, reason=ltsich/http-w00tw00t, action=ban), routed to Pushover, and confirmed delivered to the device.
