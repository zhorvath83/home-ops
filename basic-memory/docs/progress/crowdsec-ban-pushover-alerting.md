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
