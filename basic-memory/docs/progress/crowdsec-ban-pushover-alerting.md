---
title: crowdsec-ban-pushover-alerting
type: note
permalink: home-ops/docs/progress/crowdsec-ban-pushover-alerting
---

# crowdsec-ban-pushover-alerting — execution progress

## Metadata (observation-form)
- [topic] Execution state for the crowdsec-ban-pushover-alerting roadmap
- [status] code committed; AC1/AC2/AC5/AC6/AC7 verified; AC3/AC4 PENDING the human's real-ban test
- [roadmap] [[crowdsec-ban-pushover-alerting]] (docs/roadmap)
- [area] observability, security
- [created] 2026-07-31

## Code state
Committed on main (code commit f55fd6661): adds the CrowdSecBanActive alert to the EXISTING crowdsec PrometheusRule group in kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml (no new file, no AlertmanagerConfig change, no new secret).
- expr: sum by (reason, origin, action) (cs_active_decisions{job="crowdsec-service", namespace="crowdsec", origin!~"CAPI|lists(:.*)?"}) > 0
- for: 1m, keep_firing_for: 5m, severity: critical (routes via the existing critical -> Pushover sub-route; cannot be inhibited by the critical->warning inhibit rule).

## Acceptance criteria (honest status)

VERIFIED:
- AC1 (a locally issued non-CAPI ban makes the alert fire): the expr matchers provably hit real series — verified by the Maestro independently (see verification queries). End-to-end Pushover delivery still pending a real ban (AC3).
- AC2 (alert carries reason/origin/action labels): verified by expr construction "sum by (reason, origin, action)" — labels preserved into the notification body.
- AC5 (no CAPI flood): verified — the denylist excludes origin=CAPI and lists/lists:*; the Maestro's count query confirms CAPI is the only origin present (3 series), so the denylist matches zero rows today.
- AC6 (correct PrometheusRule YAML, loaded by Prometheus): verified by pre-commit (yamlfmt/yamllint/gitleaks Passed) on the touched file; deploy verification (CR exists + Prometheus loaded the rule) in progress.
- AC7 (no new secrets / files / AlertmanagerConfig changes): verified by the diff — only a rule was added to the existing group; the existing Alertmanager -> Pushover route is reused.

PENDING (waiting on the human to produce a real ban):
- AC3 (a real external ban fires the alert end-to-end -> Pushover on the device).
- AC4 (the alert resolves when the ban expires / is deleted -> sendResolved pushes the resolve).

## Maestro's independent verification (verify-don't-trust; re-ran everything, closed a gap the worker left open)

The worker's "live expr returns EMPTY, exit 0" was NOT evidence the rule is correct — a WRONG label matcher returns the same empty result. The Maestro closed that gap with five queries against the live Prometheus:
1. count by (job, namespace, origin) (cs_active_decisions) => {job="crowdsec-service", namespace="crowdsec", origin="CAPI"} = 3 — the job/namespace matchers provably hit real series.
2. cs_active_decisions{origin=~"CAPI|lists(:.*)?"} => 3 — the denylist regex really does match CAPI.
3. Anchoring proof: {job!~"crowdsec-serv"} => 3 — a partial pattern does NOT match, so the full-match anchoring is as claimed.
4. Fail-loud proof: {origin!~"CAP|lists(:.*)?"} => 3 — a near-miss origin value is INCLUDED. Any present-or-future origin that is not exactly CAPI/lists/lists:* alerts. This is the property the human's hard condition demanded, now empirically proven, not just argued.
5. pre-commit on the touched file re-run by the Maestro: all hooks Passed; live git status showed only the two intended paths.
LESSON for next time: when a validation query returns empty, prove the matcher is non-vacuous before calling it validated.

## False-trail history (the most valuable thing in this session)

Two wrong conclusions were built on the same mutable snapshot (cscli alerts list showing only CAPI alerts, zero local). The Maestro hypothesized the source IP was the cloudflared pod IP 10.x (whitelisted by crowdsecurity/whitelists) — refuted by live envoy-external access logs showing downstream_remote_address = a real public IPv6 (CF-Connecting-IP detection rewrites it). The worker then concluded an agent->LAPI alert-delivery defect (the agent logs overflow->alert creation, the LAPI showed zero local alerts) — refuted by the human, who had seen the local alert on the LAPI and DELETED it manually. The missing variable in both cases was the human's own manual action. LESSON: cscli alerts list shows the current state of a MUTABLE store — absence is not proof that something never happened. Ask whether anyone has deleted anything before concluding "never happened". This is recorded in the roadmap note too.

## What the human must do to close AC3/AC4

From a public WAN IP (NOT LAN — crowdsecurity/whitelists whitelists 10/172.16/192.168/127/::1, so a LAN source will NOT trigger):
  curl -A "sqlmap/1.6.7" https://<public-domain>/
trips crowdsecurity/http-bad-user-agent -> agent overflow -> LAPI alert + decision (4h ban, origin=crowdsec). WARNING: this bans the human's own WAN IP for 4h (default_ip_remediation profile), blocking their own external access for that window. Rollback: "cscli decisions delete <ip>" (run on the LAPI pod). Then watch for the Pushover notification (AC3) and, after the ban expires or is deleted, the resolve notification (AC4).

## Relations
- implements [[crowdsec-ban-pushover-alerting]]
- relates_to [[envoy-crowdsec-bouncer]]
## Deploy verification (final, post-rebase)

The earlier shas f55fd6661/b76adf958 (and the re-created a74b911a7/6c3a10884) are DEAD — superseded by a rebase onto e9bcac529 (an unrelated Renovate pocket-id image bump that landed on origin/main during this session, after the first push was rejected as non-fast-forward). The FINAL post-rebase shas are:
- CODE: 5ec31c912 ✨ feat(crowdsec): alert on locally issued bans
- DOCS: 6d9244f7e 📝 docs(crowdsec): record the ban-alerting rollout and its verification

Push: confirmed `e9bcac529..6d9244f7e main -> main`; `git rev-list --left-right --count origin/main...main` = 0/0 (level); remote tip = 6d9244f7e237dad71aa78e92c28109563a569116.

Flux: the crowdsec/crowdsec Kustomization reconciled at Applied revision refs/heads/main@sha1:6d9244f7e237dad71aa78e92c28109563a569116 — the PrometheusRule CR on the cluster carries the CrowdSecBanActive entry (kubectl get prometheusrule -n crowdsec crowdsec -o yaml).

Prometheus LOADED the rule (not merely CR present) — proven via the rules API (/api/v1/rules, fetched by port-forward + curl since the distroless prometheus container has no curl/wget/ls/sh, only prometheus+promtool):
- group=crowdsec, name=CrowdSecBanActive, state=inactive, health=ok, type=alerting
- query / duration=60 / keepFiringFor=300 / severity=critical all loaded from the committed YAML
- lastEvaluation fresh (2026-07-31T17:29:05Z) — the rule is evaluating, not stale

Caveat on method (LESSON): the ALERTS metric is NOT a valid loaded-proof here. Prometheus only emits an ALERTS{alertstate="inactive"} series for a rule that has PREVIOUSLY fired; a never-fired rule (CrowdSecBanActive today, or the pre-existing CrowdSecLAPIDown) does NOT appear in ALERTS at all — count(ALERTS) showed only Watchdog + KubeHpaMaxedOut, both firing. The same empty ALERTS result that "proved not loaded" for CrowdSecBanActive was equally empty for the pre-existing CrowdSecLAPIDown — the non-vacuous control that exposed the method, not the rule. The rules API is the correct loaded-proof because it lists every loaded rule regardless of firing history.

Status: committed + pushed + deploy-verified. AC1/AC2/AC5/AC6/AC7 verified; AC3/AC4 still PENDING the human's real-ban test (see "What the human must do to close AC3/AC4" above).
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
- AC3 (end-to-end -> Pushover on the device): VERIFIED — the human confirmed the Pushover notification arrived on their phone. (The new description text goes out on Alertmanager's next repeat/flush now that Prometheus reloaded it.)
- AC4 (resolved push when the ban expires/is deleted): still PENDING until the ban is cleared (`cscli decisions delete <ip>`) or expires (4h, doubling for repeats).

Status: committed + pushed + deploy-verified + live-fired. AC1/AC2/AC3/AC5/AC6/AC7 VERIFIED; AC4 PENDING.
