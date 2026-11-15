---
title: crowdsec-envoy-local-deny-whitelist
type: roadmap
permalink: home-ops/docs/progress/crowdsec-envoy-local-deny-whitelist
topic: CrowdSec ignores Envoy local denies (geo/RBAC 403, route_not_found) so CrowdSecBanActive
  only fires for sources that reached an application
status: done
priority: medium
scope: s02-enrich parser whitelist in the crowdsec HelmRelease plus a cscli-explain
  fixture suite under tools/crowdsec-whitelist/
related_areas:
- networking
- observability
---

# CrowdSec: skip Envoy local denies

## Metadata (observation-form, schema validation)

- [topic] CrowdSec ignores Envoy local denies so CrowdSecBanActive only fires for sources that reached an application
- [status] done — deployed 2026-11-15 (c6e13bfa7), live-verified the same day

## Problem (evidence, 2026-11-15)

- [observation] After the Cloudflare country rule was removed (a5fb33272, 2026-11-14 23:58) foreign scanners reach envoy-external; the geo gate answers 403 `rbac_access_denied_matched_policy[DENY]`, but the CrowdSec agent still parsed those lines and banned the sources. CrowdSecBanActive (critical, Pushover) fired from 05:28 nearly continuously: 858 firing samples in 12h vs 0 local bans in the previous 6 days.
- [fact] All 285 logged requests of the three banned IPs (IN, US, SG) were RBAC 403s; none reached an upstream.
- [fact] The bans were never consulted: the Envoy bouncer is the only decision consumer (`cscli bouncers list`), and on envoy-external filterOrder runs geoip and RBAC before ext_authz (envoy.yaml:8-13).
- [fact] `crowdsecurity/http-probing` counts 403/404 responses, so the geo gate's own 403 was producing the bans.

## Decision

- [decision] Filter at the parser, not at the alert: `cs_active_decisions` only carries reason/origin/action, so an alert-level exclusion by reason would also silence an allowed (HU) source probing an application — the one signal worth a critical alert.
- [decision] s02-enrich whitelist `home-ops/envoy-local-deny` (HelmRelease `config.parsers.s02-enrich`, chart 0.24.3 mounts it and rolls the agent via the agent-configmap checksum). Expression (since 5163af797): `response_code_details in ["rbac_access_denied_matched_policy[DENY]", "route_not_found"]` (exact match; the first version used `contains`, see the update below), nil-safe via `evt.Unmarshaled.envoy?.… ?? ""`.
- [superseded] (first version, c6e13bfa7) `contains`, not `startsWith`: Envoy occasionally writes a corrupted prefix into response_code_details (e.g. `@EK?Er\u0000\u0000ess_denied_matched_policy[DENY]`, 7 of ~350 RBAC denies, all from the 2026-11-14 port-forward matrix).
- [decision] D1 route_not_found whitelisted: no upstream is reached and no geo check runs there (e.g. flux-webhook host outside /hook/); an allowed scanner is still caught on real routes.
- [decision] D2 envoy-internal RBAC denies (public source on the LAN gateway) whitelisted by the same rule.
- [decision] Kept (not whitelisted): via_upstream responses of any status, `ext_authz_denied` (bouncer ban / AppSec block, keeps the repeat-offender ladder), `local_rate_limited`, `ext_authz_error` (bouncer down, 503).
- [tradeoff] No CAPI signals are shared for foreign scanners the geo gate already rejects; volumetric floods from abroad are not banned (a ban would not apply before RBAC anyway).

## Use case matrix (fixtures: tools/crowdsec-whitelist/fixtures.txt)

| Case | Envoy reply | Whitelisted |
|---|---|---|
| A1 foreign source, geo-gated host | 403 rbac deny | yes |
| A2 geo DB miss / reserved IP | 403 rbac deny | yes |
| A3 corrupted details prefix | 403 `…ess_denied_matched_policy[DENY]` | no (since 5163af797; fail-safe extra ban) |
| A4 non-GitHub source on flux-webhook /hook/* | 403 rbac deny (route policy) | yes |
| A5 GitHub source, bad token | 404 via_upstream | no |
| A6 any source, no route | 404 route_not_found | yes |
| A7 allowed source probes an app | 404 via_upstream | no |
| A8 banned allowed source | 403 ext_authz_denied | no |
| A10 login brute force | 401 via_upstream | no |
| A11 flood over local rate limit | 429 local_rate_limited | no |
| A13 bouncer down | 503 ext_authz_error | no |
| A0 normal request | 200 via_upstream | no |
| B2 public source on envoy-internal | 403 rbac deny | yes |
| C1 non-access-log line | parser failure at s01 | no |
| C2 Envoy text-format line (no JSON, Unmarshaled nil) | reaches s02 | no, no expr error |
| A16 oauth2 state injection (`…_x_denied_matched_policy[DENY]`) | 401 local | no |
| A17 oauth2 state injection (`…_route_not_found`) | 401 local | no |

## Verification (2026-11-15)

- [verified] TDD: `tools/crowdsec-whitelist/testWhitelist.sh candidate` (scratch config in the agent pod's /tmp, no credentials copied) was red before the change (8/14, every wl case failing) and green after (15/15); `live` mode 15/15 after the Flux rollout.
- [verified] Negative live test: 15 probe paths via envoy-external port-forward with a TEST-NET XFF source → 15× 403 rbac, `cs_node_wl_hits_ok_total{name="home-ops/envoy-local-deny",source=envoy-external}` = 15, no decision, no alert.
- [verified] Positive live test (own HU IP, user-approved): 15 probe paths → 10× 404 via_upstream + 2× 403 ext_authz_denied (AppSec vpatch) → decisions appsec-vpatch, http-probing, http-admin-interface-probing; CrowdSecBanActive active for appsec-vpatch and http-probing at 10:04:05Z. Decisions deleted afterwards (`cscli decisions delete --ip`), next requests 302 again. Side effect: the test alerts were pushed to CAPI for the own IP.
- [verified] Agent restart clean (only pre-existing warnings); `cscli parsers list` shows home-ops/envoy-local-deny enabled,local.
- [note] Test design: 8.8.8.8 and other public resolvers are dropped by `crowdsecurity/public-dns-allowlist` and do not exercise scenarios; use TEST-NET sources.

## Follow-ups

- [open] Watch 24h: no foreign local bans; CrowdSecAcquisitionStalled stays quiet (cs_parser_hits_ok_total should still count whitelisted events).
- [resolved-elsewhere] The corrupted response_code_details prefix is the known Envoy use-after-free from the 403 responseOverride (reverted in f3f1f4989; upstream report declined by user decision, see [[onprem-geoip-country-filter]]). All 14 corrupted lines fall in 2026-11-14 22:28:39–55Z, none in ~5300 later requests. Root cause (2026-11-15 upstream read): envoyproxy/envoy#46600 (merged 2026-08-24, in v1.40.x) resolves `details` as a string_view into StreamInfo's own response_code_details when preserve_response_code_details is set; sendLocalReply → setResponseCodeDetails → `response_code_details_.emplace(view)` destroys the string before copying from it (stream_info_impl.h, v1.40.2). Envoy Gateway always sets PreserveResponseCodeDetails: true for responseOverride (internal/xds/translator/custom_response.go). No upstream issue or fix found as of 2026-11-15 (v1.40.2 latest). The source:Local 401 override (BTP envoy) used the same path and was removed on 2026-11-15 (64beaed28), see the update below.
- [open] 17 stale bouncer and machine registrations in LAPI (old envoy@ / blocklist_import@ pod IPs).
- [open] envoy-internal has no explicit filterOrder (ext_authz vs RBAC order is the EG default).
- [open] CrowdSecBanActive description says the ban "doubles"; profiles.yaml grows it linearly (4h → 8h → 12h …).

## Relations

- relates_to [[onprem-geoip-country-filter]]
- relates_to [[networking]]
- relates_to [[cloudflare-tunnel-to-towonel]]

## Update — 2026-11-15: exact match, 401 override removed

- [finding] The 401 OIDC-failure responseOverride triggered the same use-after-free: 5 of 5 bogus `/oauth2/callback` requests on envoy-external logged `@7K?Er\u0000\u0000ery_param_is_not_a_valid_JSON:_` (heap bytes over `State_qu`). The networking guide's claim that the 401 override was unaffected was wrong. Any client that passes the gate can trigger it.
- [done] 64beaed28 removed the 401 responseOverride (BTP envoy) and generalised the networking guide rule to "no responseOverride until Envoy fixes envoyproxy/envoy#46600". Live: BTP Accepted/Merged on both gateways; after the change 5/5 external and 3/3 internal callback 401s log intact details and Envoy's plain "OAuth flow failed." body.
- [finding] The oauth2 filter echoes the base64url-decoded `state` into response_code_details, so the first `contains` whitelist was spoofable: `state=base64url("x_denied_matched_policy[DENY]")` produced `State_query_param_is_not_a_valid_JSON:_x_denied_matched_policy[DENY]` and the event was whitelisted (verified live). Impact was limited to hiding those crafted 401 callback requests themselves (local replies, no upstream).
- [done] 5163af797: exact match on the two values. TDD: red 15/17 (A3, A16), green 17/17 candidate and live; the captured real bypass line is no longer whitelisted; 5 live TEST-NET geo-denied probes → 5 whitelist hits, no decision.
- [fact] Every local 403 RBAC deny in 24h of logs on envoy-external (all routes, incl. github-webhook and https-redirect) is exactly `rbac_access_denied_matched_policy[DENY]`, so the exact match misses no real variant.
- [note] Deploy gotcha: `flux reconcile hr crowdsec --with-source` refreshes only the chart OCIRepository; the values change needs `flux reconcile ks crowdsec`. A live fixture run during the agent rollout reports spurious keeps (exec into the terminating pod).
