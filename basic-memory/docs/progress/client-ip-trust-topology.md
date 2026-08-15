---
title: client-ip-trust-topology
type: progress_note
permalink: home-ops/docs/progress/client-ip-trust-topology
---

# Progress — client-ip-trust-topology (non-IP rate-limit dimension)

Roadmap: [[client-ip-trust-topology]].

## Metadata (observation-form)

- [status] done — merged in PR #4183 and verified live
- [area] networking
- [branch] feat/client-ip-trust-topology-rate-limit

## Session 2026-08-15 — aggregate + per-route rate limit

### What was done

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

### Verification basis

- `kubectl explain backendtrafficpolicy.spec.mergeType`: field exists, "can only be set when
  targeting xRoute resources" — our target is an HTTPRoute, so it is legal here.
- `pre-commit run --files ...` on all three touched files: all hooks passed, no reformat.
- `kustomize build kubernetes/apps/security/pocket-id/app`: OK.
- `kubectl apply --dry-run=server` on both the new route-level policy and the modified
  `envoy` BackendTrafficPolicy: accepted by the API server.

### Chosen values and why

- Gateway aggregate 30000/min (500 rps): far above real home-cluster traffic, low enough to
  blunt a rotation flood. Per-gateway, so the internal gateway keeps its own bucket.
- IdP route 300/min per IP + 1200/min shared: a login flow is tens of requests, so both
  ceilings are generous for legitimate use while capping credential-stuffing volume
  regardless of how many source IPs the attacker rotates through.

### Risk

A too-tight limit 429s legitimate bursts. The shared IdP bucket is the self-lockout vector:
one abusive client can consume up to 300/min of the 1200/min route budget. Accepted for a
single-household IdP; calibrate against real per-route traffic if 429s appear.

### Next

- Merge the PR, then verify live: both BackendTrafficPolicies report Accepted, the parent
  `envoy` policy is NOT reported Overridden on the pocket-id-external route, and the IdP
  login still works.
- Then flip the roadmap note status from proposed to done.

## Relations

- implements [[client-ip-trust-topology]]
- relates_to [[networking]]
