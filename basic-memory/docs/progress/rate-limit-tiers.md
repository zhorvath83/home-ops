---
title: rate-limit-tiers
type: progress
permalink: docs/progress/rate-limit-tiers
topic: Host-based per-client local rate limit tiers (600 default, books 1200, fenykepek
  3000) and the EnvoyRateLimited alert
status: done
priority: medium
area: networking
created: '2026-11-23'
completed: '2026-11-23'
moved_from: docs/roadmap/rate-limit-tiers
related_areas:
- networking
- observability
tags:
- security
- networking
- envoy-gateway
- rate-limit
- completed
---

# Progress — rate-limit-tiers (host-based local rate limit tiers)

Roadmap item researched and completed 2026-11-23, moved from `docs/roadmap/rate-limit-tiers`.
Delivered directly on main as commit 864b167f7, live-verified the same day.

## Metadata (observation-form)

- [status] done — commit 864b167f7 on main, reconciled and live-verified 2026-11-23
- [priority] medium
- [area] networking / observability
- [completed] 2026-11-23
- [moved_from] docs/roadmap/rate-limit-tiers

## Problem

- [observation] Every route allowed 3000 requests/min per client, a value sized only for the home-gallery thumbnail scroll. Login forms, APIs and the IdP backchannel tolerated 50 req/s per IP.
- [observation] The no-selector 30000/min rule was commented as one gateway-wide bucket; the config dump shows it is a per-route `token_bucket`.

## Measured demand (VictoriaLogs envoy access logs, 14 days)

| Host | Gateway | Legitimate peak/min | Minutes above 300 |
|---|---|---|---|
| books (CWA) | external | 1030 (720 /static, 238 /cover; one 6-minute browse) | 3 |
| recipes | external | 472 | 3 |
| fin | internal | 374 | 2 |
| fenykepek | internal | 345 (not a representative scroll) | 1 |
| jellyfin / docs | internal / external | 286 / 285 | 0 |

- [observation] An idm peak of 469/min was a foreign scanner, all 403 at the geo gate; geo-denied requests consume no rate-limit tokens.

## Decisions (with the human, 2026-11-23)

- [decision] Default tier 600/min (human chose 600 over the 300 alternative); books 1200/min; fenykepek 3000/min. recipes and fin fit under 600 and get no special tier.
- [decision] Tier selection by exact `:authority` match (`type: Exact`, `invert` for the default tier), not regex: a variant Host (port, case, unknown) falls into the stricter default tier.
- [decision] No gateway-wide bucket. EG v1.10 ignores `shared` on Local rules; the only route is the Global rate limit (Redis + ratelimit service). Rejected: Cloudflare DDoS, the HU geo gate, CrowdSec and the circuit breaker already cover distributed floods, and a shared bucket is a self-DoS lever. The 30000/min per-route bucket stays with a corrected comment. No follow-up roadmap item.
- [decision] Option A (one gateway BTP, tiers by Host) over Option B (route-level overrides): no merge semantics in the limit model.

## What was done

1. `kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml` — BTP `envoy` rateLimit rewritten into three tiers (v4 + v6 Distinct each) plus the per-route 30000 bucket; comments corrected.
2. `kubernetes/apps/networking/envoy-gateway/config/prometheusrule.yaml` — new `EnvoyRateLimited` warning: `sum by (pod) (increase(envoy_http_local_rate_limit_rate_limited[15m])) > 0`. No new-series guard needed: Envoy creates the counter at 0 on start.
3. `prometheusrule_test.yaml` — three promtool cases (flat-zero boundary, fire on one pod only with asserted annotations, window slid past).
4. `kubernetes/apps/security/pocket-id/app/backendtrafficpolicy.yaml` — header comment records the measured StrategicMerge semantics.

## Phase 0 spike (EG v1.10.0 source)

- [evidence] `headers` + `sourceCIDR: Distinct` in one selector, `invert` and `Exact` are supported for Local limits (header_value_match actions).
- [evidence] `Rule.Shared` is copied into the IR but read only by the Global translator; for Local, the first no-selector rule becomes the route's default `token_bucket`.
- [gap] `egctl x translate` could not be run before deploy (tool download denied); the translation was verified live from the config dump instead.

## Verification

- [verified] flate build of envoy-gateway-config and a server-side dry-run of both BTPs; pre-commit hooks; promtool suite (18 test files) green. flate-test hook skipped at the human's request.
- [verified] Live: BTP envoy Accepted=True (+ Merged=True on envoy-external), pocket-id-external Accepted=True + Merged=True; no Conflicted/Overridden.
- [verified] AC1 — config dump on both gateways: every routed host carries 3000[fenykepek], 1200[books], 600[!fenykepek&!books] (v4+v6) and bucket 30000; external idm additionally 300+300 with bucket 1200.
- [verified] AC2 — 700 requests from the LAN to internal idm `/.well-known/openid-configuration`: 662×200, 38×429 (bucket refill mid-burst explains >600). Envoy stat rate_limited=38, Prometheus counter 38, EnvoyRateLimited fired for envoy-internal, and the description's VictoriaLogs query returned the 38 requests with client and host.
- [evidence] 700 requests to an OIDC-gated host returned 700×302 and no 429: the OIDC filter runs before local_ratelimit, so unauthenticated floods against gated routes are not counted (they hit the IdP redirect, not the backend).
- [open] AC3 — one week without EnvoyRateLimited from a legitimate client (or tiers adjusted). Review on 2026-11-30. The gallery's real scroll profile is still unmeasured; 3000 is unchanged, so this is no regression.

## Relations

- relates_to [[networking]]
- relates_to [[observability]]
- relates_to [[client-ip-trust-topology]]
- relates_to [[security-event-alerting]]
