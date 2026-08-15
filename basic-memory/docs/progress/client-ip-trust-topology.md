---
title: client-ip-trust-topology
type: progress
permalink: home-ops/docs/progress/client-ip-trust-topology
topic: Add a non-IP rate-limit dimension to the external edge so IP-rotation cannot
  defeat the rate limit, and remediate the filter-order / unrouted-404 gap
status: done
priority: medium
area: networking
created: '2026-08-14'
completed: '2026-08-15'
branch: feat/client-ip-trust-topology-rate-limit
moved_from: docs/roadmap/client-ip-trust-topology
related_areas:
- networking
- observability
tags:
- roadmap
- security
- networking
- envoy-gateway
- rate-limit
- defence-in-depth
- completed
---

# Progress — client-ip-trust-topology (non-IP rate-limit dimension)

Roadmap item completed 2026-08-15 and moved from `docs/roadmap/client-ip-trust-topology`;
merged into this progress note. Executed as PR #4183 and verified live.

## Metadata (observation-form)

- [status] done — merged in PR #4183 and verified live
- [priority] medium
- [area] networking / observability
- [created] 2026-08-14
- [completed] 2026-08-15
- [branch] feat/client-ip-trust-topology-rate-limit
- [moved_from] docs/roadmap/client-ip-trust-topology

## Background (roadmap item)

The only external rate limit was an IP-keyed 3000 req/min per-source-CIDR Distinct bucket
(`gateway-policies.yaml:26-43`), with no aggregate ceiling and no per-route dimension;
unrouted-404 floods and IP-rotation were not covered. This item carried the one remediation
that does NOT depend on the local_ratelimit-vs-ext_authz-vs-oauth2 filter order and covers
the unrouted-404 floods the IP-keyed bucket misses: a non-IP (per-route / per-session) rate
dimension. It ranks as defence-in-depth / config-drift, below the measured data exposures.

Today's reachable state (measured, Maestro lane): Cloudflare rejects a client-supplied
CF-Connecting-IP header with 403 at the edge; the origin is a ClusterIP behind the Tunnel;
a CNP admits only the cloudflared pod. The spoof is NOT internet-reachable today — it is
latent on topology drift. The gaps carried here were the survivors of an adversarial audit
verification (burst 3000/IP, no aggregate ceiling, filter-order consequence, unrouted-404
not limited); the "rate limit is broken" claim itself was refuted.

## What was done

1. `kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml` — the `envoy`
   BackendTrafficPolicy gained a third local rate-limit rule with **no clientSelectors**:
   an aggregate 30000 req/min bucket. A rule without clientSelectors is one shared bucket
   per gateway, so IP rotation cannot buy extra budget, and it covers unrouted-404 floods
   that the per-source-CIDR Distinct buckets never see. It also does not depend on the
   local_ratelimit-vs-ext_authz-vs-oauth2 filter order (the UNCERTAIN item in the roadmap).

2. `kubernetes/apps/security/pocket-id/app/backendtrafficpolicy.yaml` (new) — a route-level
   BackendTrafficPolicy on `pocket-id-external`, the public IdP surface: 300 req/min per
   source IP (v4 + v6 Distinct) plus a 1200 req/min shared bucket with no clientSelectors.
   `mergeType: StrategicMerge` is mandatory — without it the route-level policy REPLACES the
   Gateway-level `envoy` policy for that route and silently drops its circuit breaker,
   compression, 401 response override, retry and timeouts. Wired into the app kustomization.

## Verification basis

- `kubectl explain backendtrafficpolicy.spec.mergeType`: field exists, "can only be set when
  targeting xRoute resources" — our target is an HTTPRoute, so it is legal here.
- `pre-commit run --files ...` on all three touched files: all hooks passed, no reformat.
- `kustomize build kubernetes/apps/security/pocket-id/app`: OK.
- `kubectl apply --dry-run=server` on both the new route-level policy and the modified
  `envoy` BackendTrafficPolicy: accepted by the API server.
- Live (post-merge, PR #4183): both BackendTrafficPolicies report `Accepted=True`; the
  parent `envoy` policy reports `Merged=True` (never `Overridden`) on the envoy-external
  ancestor; envoy proxy pods stable with 0 restarts; the IdP login page still returns 200
  through the external edge.

## Chosen values and why

- Gateway aggregate 30000/min (500 rps): far above real home-cluster traffic, low enough to
  blunt a rotation flood. Per-gateway, so the internal gateway keeps its own bucket.
- IdP route 300/min per IP + 1200/min shared: a login flow is tens of requests, so both
  ceilings are generous for legitimate use while capping credential-stuffing volume
  regardless of how many source IPs the attacker rotates through.

## Risk

A too-tight limit 429s legitimate bursts. The shared IdP bucket is the self-lockout vector:
one abusive client can consume up to 300/min of the 1200/min route budget. Accepted for a
single-household IdP; calibrate against real per-route traffic if 429s appear.

## Explicitly out of scope

- The today-reachable data/admin exposures (home-gallery, IdP admin, kopia, flux-webhook) —
  not part of this item; the dashboard recon is [[homepage-recon-exposure]].
- The identity gate for any route → [[app-auth-coverage]].
- The reactive-detection window / agent-restart blind spot and the brute-force parser —
  edge-detection-observability (roadmap item lost from BM, descoped pending rebuild).
- The mergeType footgun VAP and the SecurityPolicy attach-failure alert →
  [[gateway-guardrails-response-headers]].
- The "rate limit is broken" claim — refuted; only the real gaps (burst ceiling, filter
  order, unrouted-404) were carried.

## Relations

- relates_to [[networking]] — envoy-external rate limit, client-IP detection
- relates_to [[observability]] — the alert that surfaces a mis-set per-route limit
- relates_to [[app-auth-coverage]] — identity gates; the IP-trust chain is orthogonal but both must hold
- relates_to [[gateway-guardrails-response-headers]] — mergeType VAP / attach-failure alert; independent but both touch the external Gateway
