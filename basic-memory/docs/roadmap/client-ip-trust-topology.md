---
title: client-ip-trust-topology
type: roadmap
permalink: home-ops/docs/roadmap/client-ip-trust-topology
topic: Add a non-IP rate-limit dimension to the external edge so IP-rotation cannot
  defeat the rate limit, and remediate the filter-order / unrouted-404 gap that the
  IP-keyed bucket does not cover (NOT today-exploitable).
status: proposed
priority: medium
scope: The envoy-external local rate limit (3000 req/min per-source-CIDR Distinct
  bucket, gateway-policies.yaml:26-43), keyed on the same detected client IP that
  the rest of the IP-trust chain keys on. The bucket has no aggregate ceiling and
  no per-route dimension; unrouted-404 floods and IP-rotation are not covered. Collapses
  the rate-limit gaps carried out of the audit (burst 3000/IP, filter-order consequence,
  unrouted-404 not limited).
rationale: 'The config fact is real — the only external rate limit is an IP-keyed
  3000 req/min Distinct bucket, and under the audit premise ("assume Cloudflare provides
  zero protection") IP-rotation defeats it. Today''s reachable state is narrower:
  the origin is a ClusterIP behind the Tunnel and a CNP admits only the cloudflared
  pod, so the spoof is latent on topology drift, not internet-reachable. This item
  carries the one remediation that does NOT depend on the local_ratelimit-vs-ext_authz-vs-oauth2
  filter order and covers the unrouted-404 floods the IP-keyed bucket misses: a non-IP
  (per-route / per-session) rate dimension. It ranks as defence-in-depth / config-drift,
  below the measured data exposures.'
related_areas:
- networking
- observability
options:
- Add a per-route (or per-session) rate limit so IP-rotation cannot defeat the limit
  even if the topology drifts; this is the remediation that does not depend on the
  Envoy Gateway filter order.
tags:
- roadmap
- security
- networking
- envoy-gateway
- rate-limit
- defence-in-depth
- proposed
---

# client-ip-trust-topology — non-IP rate-limit dimension on the external edge

## Metadata (observation-form, schema validation)

- [topic] Add a non-IP rate-limit dimension so IP-rotation cannot defeat the rate limit, and remediate the filter-order / unrouted-404 gap (NOT today-exploitable)
- [status] proposed
- [priority] medium
- [area] networking / observability
- [created] 2026-08-14

## Verification basis (how this item was built)

- Source: an adversarial audit produced 98 unverified findings; its verification phase did NOT complete. The rate-limit gaps carried here are the survivors of that verification.
- Method: verified against repo file:line (gateway-policies.yaml:26-43 rate limit; gateway-policies.yaml:94-97 clientIPDetection; envoy.yaml Service type; ciliumnetworkpolicy-external.yaml) and live read-only kubectl (the ClusterIP origin, the CNP, the CF edge 403 on a client-supplied header). Secret resources were never read; nothing was mutated.
- Refuted by verification (not carried as exploitable):
  - "the rate limit is broken": the audit's own brief established the bucket is a continuously refilling 50 token/s bucket and is NOT broken. Only the real gaps are carried: burst 3000/IP, no aggregate ceiling, filter-order consequence, unrouted-404 not limited.
- Carried as explicitly UNCERTAIN (verified config fact, unverifiable consequence):
  - Rate-limit filter order (local_ratelimit 302 vs ext_authz 5, oauth2 8) and unrouted-404 limiting — Envoy Gateway internal behaviour, not manifest-verifiable. The non-IP per-route limit is the remediation that does NOT depend on the filter order.
- Today's measured reachable state (Maestro lane, trusted over the finders): Cloudflare rejects a client-supplied CF-Connecting-IP header with 403 at the edge; the origin is a ClusterIP behind the Tunnel; the CNP admits only the cloudflared pod. So the spoof is NOT internet-reachable today — it is latent on topology drift.

## What we gain

- A non-IP rate dimension means IP-rotation cannot defeat the rate limit even if the topology drifts.
- A per-route limit covers unrouted-404 floods that the IP-keyed Distinct bucket does not, and does not depend on the local_ratelimit-vs-ext_authz-vs-oauth2 filter order.

## What to do

### Non-IP rate-limit dimension

- Add a per-route (or per-session) rate limit so IP-rotation cannot defeat the limit even if the topology drifts. Today the only limit is the 3000 req/min per-source-CIDR Distinct bucket (gateway-policies.yaml:26-43), keyed on the same detected IP.
- This is also the remediation for the UNCERTAIN filter-order / unrouted-404 gap: a per-route limit does not depend on the local_ratelimit-vs-ext_authz-vs-oauth2 filter order, and it covers unrouted-404 floods that the IP-keyed bucket does not.

## Acceptance criteria

- A per-route rate limit is attached to at least the auth-bearing external routes; an unrouted-404 flood is now limited.

## Risks / what could break (blast radius per change)

- **Per-route rate limit:** a too-tight limit drops legitimate bursts. Mitigation: calibrate against the real per-route traffic (the alert that surfaces a mis-set limit was to live in edge-detection-observability, now a descoped/lost item).

## Explicitly out of scope

- The today-reachable data/admin exposures (home-gallery, IdP admin, kopia, flux-webhook) — not part of this item; the dashboard recon is [[homepage-recon-exposure]].
- The identity gate for any route → [[app-auth-coverage]].
- The reactive-detection window / agent-restart blind spot and the brute-force parser — edge-detection-observability (roadmap item lost from BM, not git-recoverable; descoped pending rebuild from the original audit).
- The mergeType footgun VAP and the SecurityPolicy attach-failure alert → [[gateway-guardrails-response-headers]].
- The "rate limit is broken" claim — refuted; only the real gaps (burst ceiling, filter order, unrouted-404) are carried here.

## Related

- relates_to [[app-auth-coverage]] — owns the identity gates; the IP-trust chain is orthogonal but both must hold.
- relates_to [[gateway-guardrails-response-headers]] — owns the header-strip-adjacent VAPs (mergeType, reserved hostname) and the attach-failure alert; the rate-limit change is independent but both touch the external Gateway.
- (descoped) edge-detection-observability — owned the bouncer ticker/reactive-window work and the brute-force parser; item lost from BM, pending rebuild.
- relates_to [[networking]] — envoy-external rate limit, client-IP detection.
- relates_to [[observability]] — the alert that surfaces a mis-set per-route limit.
