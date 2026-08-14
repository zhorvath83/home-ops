---
title: gateway-guardrails-response-headers
type: roadmap
permalink: home-ops/docs/roadmap/gateway-guardrails-response-headers
topic: 'Gateway guardrails and response headers — admission guardrails for

  routes/SecurityPolicies, connection hardening, extauth-chain resilience, and

  CSP/framing/COOP response headers on the external surface.'
status: proposed
priority: medium
scope: 'The Envoy Gateway control surface in front of the external routes: the

  reserved-hostname ValidatingAdmissionPolicy, route/SecurityPolicy attach semantics

  (mergeType, Accepted condition), the external proxy connection/timeout settings,
  the

  port-80 https-redirect route, the fail-closed ext_authz chain (CrowdSec bouncer
  +

  AppSec, both single-replica), and the response-header Lua filter. Carries the

  response-headers-lack-CPS cluster (ids 42, 70).'
rationale: 'These are gateway-plane guardrails that fail silently today: a route-level

  SecurityPolicy that forgets mergeType: StrategicMerge silently detaches the

  Gateway-level CrowdSec gate; a SecurityPolicy that fails to attach leaves the route

  fully ungated; neither is caught by admission, lint, or alert. The external proxy
  is

  single-replica with 30-minute timeouts and no connection limit, and the response
  Lua

  injects only HSTS/nosniff/Referrer-Policy — no CSP, frame-ancestors, Permissions-Policy,

  or COOP/COEP in front of the unauthenticated public apps. None of this is

  today-exploitable on its own, but each is a silent footgun that an unrelated change

  can trip. Verified against repo file:line (validatingadmissionpolicy.yaml,

  gateway-policies.yaml, envoy.yaml, crowdsec-bouncer helmrelease.yaml,

  security-headers.yaml) and live read-only kubectl.'
related_areas:
- networking
- observability
- iam
options:
- Guard the silent footguns with admission + alerts, not just config — a mergeType
  VAP and a SecurityPolicy-attach-failure alert catch the detach-on-misconfig class
  before it is exploited.
- Default-strict response headers, per-app exceptions — apply CSP / frame-ancestors
  / Permissions-Policy / COOP at the gateway, and carve out per-app exceptions only
  where an app is known to need inline scripts/widgets.
tags:
- roadmap
- security
- networking
- envoy-gateway
- admission-policy
- response-headers
- proposed
---

# gateway-guardrails-response-headers — guardrails + response headers on the external gateway

## Metadata (observation-form, schema validation)

- [topic] Gateway guardrails (admission, attach, connection, extauth resilience) + response headers (CSP/framing/COOP) on the external surface
- [status] proposed
- [priority] medium
- [area] networking / observability / iam
- [created] 2026-08-14

## Verification basis (how this item was built)

- Source: an adversarial audit produced 98 unverified findings; its verification phase did NOT complete. The response-headers-lack-CPS cluster (ids 42, 70) and the individual guardrail findings (reserved-hostname VAP scope, mergeType footgun, slowloris, https-redirect Host reflection, extauth SPOF, path-deny normalization, state-url redirect) were carried here.
- Method: verified against repo file:line (validatingadmissionpolicy.yaml; gateway-policies.yaml timeouts + buffer + redirect route + ClientTrafficPolicies; envoy.yaml replicas; crowdsec-bouncer/app/helmrelease.yaml replicaCount; security-headers.yaml; pocket-id/app/httproute.yaml) and live read-only kubectl. Secret resources were never read; nothing was mutated.
- Carried as explicitly UNCERTAIN (verified config fact, unverifiable consequence):
  - idm path-deny percent-encoding / doubled-slash bypass (id 37) — the denylist uses Gateway API PathPrefix literal matching; bypassability depends on Envoy Gateway's default normalization, which cannot be confirmed from manifests. Fixed by enabling explicit path normalization + re-testing (Phase 5).
  - state-url redirect not domain constrained (id 74) — Envoy's post-login redirect target is not constrained to the gateway's own domains and no knob exists in the installed Envoy Gateway version. Carried as a known upstream limitation, monitor only (Phase 5).

## What we gain

- A route-level SecurityPolicy that forgets mergeType can no longer silently detach the Gateway-level CrowdSec gate, and a SecurityPolicy that fails to attach raises an alert instead of leaving the route ungated.
- The reserved-hostname admission policy covers every route kind the public listener accepts and constrains which Gateway a route may attach to.
- The external proxy resists slowloris / connection exhaustion, and the https-redirect no longer reflects an arbitrary client Host.
- The ext_authz chain is no longer a single restart away from 503ing every public hostname.
- Unauthenticated public apps get CSP / frame-ancestors / Permissions-Policy / COOP headers, reducing XSS/framing/clickjacking blast radius.
- Path-deny rules are robust to percent-encoding/doubled-slash bypass attempts.

## What to do (phased; each phase independently shippable)

### Phase 1 — Admission guardrails for routes and SecurityPolicies

- Widen the reserved-hostname ValidatingAdmissionPolicy (validatingadmissionpolicy.yaml): today it matches HTTPRoutes only, while the public listener accepts other route kinds, and it never constrains which Gateway a route may attach to. Extend it to grpcroutes/tlsroutes/tcproutes and add a parentRef/kind constraint so a route cannot attach to an unexpected Gateway.
- Add a VAP requiring spec.mergeType == StrategicMerge on any SecurityPolicy targeting an HTTPRoute (a forgotten mergeType silently detaches the Gateway-level CrowdSec gate).
- Add a PrometheusRule alerting on any SecurityPolicy whose Accepted condition is False or whose ancestorRef is missing (silent attach failure). The alert-wiring coordination target edge-detection-observability is a descoped/lost roadmap item (pending rebuild).

### Phase 2 — Connection hardening

- Slowloris / connection exhaustion (gateway-policies.yaml timeouts + buffer; envoy.yaml replicas): add connection.connectionLimit, bound maxAcceptPerSocketEvent, and lower requestReceivedTimeout. Blasts: too-low a timeout breaks large uploads (document ingest, book ingest) — calibrate per-route.
- https-redirect reflects client Host (gateway-policies.yaml redirect route): the port-80 redirect route has no hostname filter and no requestRedirect.hostname, so Envoy reflects the client Host into the Location header. Pin the hostnames or set requestRedirect.hostname.

### Phase 3 — ext_authz chain single-point-of-failure

- The chain is fail-closed (failOpen:false, statusOnError:503) plus a single-replica bouncer (128Mi limit) and single-replica AppSec, so one restart 503s every public hostname (gateway-policies.yaml + crowdsec-bouncer/app/helmrelease.yaml replicaCount:1).
- Add a PodDisruptionBudget, raise the bouncer/AppSec resources, and use a RollingUpdate surge (or 2 replicas). Blasts: a second replica changes the ban-state consistency model — verify the bouncer supports HA before scaling.

### Phase 4 — Gateway response headers (CSP / framing / COOP)

- The response Lua injects only HSTS, nosniff, and Referrer-Policy (security-headers.yaml). Add Content-Security-Policy: frame-ancestors 'none', Permissions-Policy, and COOP/COEP (add-if-absent).
- Blasts: a strict CSP can break apps that load inline scripts/widgets — apply per-app where the app is known to need inline, default-strict elsewhere. The dashboard's header is coordinated with [[homepage-recon-exposure]].

### Phase 5 — Path normalization and redirect-target constraints (UNCERTAIN items)

- Path-deny normalization (UNCERTAIN, id 37): enable explicit path normalization (merge slashes, percent-decode) in a ClientTrafficPolicy and re-test the idm deny rules with encoded/doubled-slash variants.
- state-url redirect not domain constrained (UNCERTAIN, id 74): Envoy's post-login redirect target is not constrained to the gateway's own domains and no knob exists in the installed Envoy Gateway version. Carry as a known upstream limitation with a monitor; do not block on it.

## Acceptance criteria

- The VAP rejects a GRPCRoute with a reserved hostname and a route attaching to the wrong Gateway; the mergeType VAP rejects a SecurityPolicy without StrategicMerge.
- A SecurityPolicy set to not-Accepted triggers an alert within the scrape interval.
- connection.connectionLimit is set; requestReceivedTimeout is lowered; a large-upload route still succeeds.
- The redirect route no longer reflects an arbitrary Host.
- A bouncer PDB exists; a RollingUpdate surge is configured (or 2 replicas, after HA verification).
- A CSP / frame-ancestors header is present on external responses.
- Path normalization is on; encoded/doubled-slash deny-rule bypass attempts are blocked.

## Risks / what could break (blast radius per change)

- **Per-route timeouts (Phase 2):** too-low a requestReceivedTimeout breaks large uploads (document/book ingest). Mitigation: calibrate per-route, keep a generous timeout on the ingest routes.
- **extauth HA (Phase 3):** a second bouncer replica changes the ban-state consistency model. Mitigation: verify the envoy-proxy-bouncer supports HA before scaling; otherwise use a PDB + RollingUpdate surge on a single replica.
- **CSP (Phase 4):** a strict CSP breaks apps with inline scripts/widgets. Mitigation: default-strict, carve per-app exceptions where needed; coordinate the dashboard header with [[homepage-recon-exposure]].
- **Path normalization (Phase 5):** enabling normalization can change routing for apps that rely on encoded path segments. Mitigation: test the deny rules AND the app routes with encoded variants before applying.
- **Reserved-hostname VAP widening (Phase 1):** an over-broad parentRef constraint can reject a legitimate cross-Gateway attach. Mitigation: scope the constraint to the external Gateway family.

## Explicitly out of scope

- The non-IP rate-limit dimension → [[client-ip-trust-topology]] (owns the per-route/per-session rate limit).
- The external-surface 4xx/401/429 alerts, brute-force parser, bouncer ticker/reactive-window — edge-detection-observability (roadmap item lost from BM, not git-recoverable; descoped pending rebuild). The attach-failure alert in Phase 1 here is the one guardrail alert that belongs to this item.
- The identity gate for any route → [[app-auth-coverage]].
- The dashboard recon/SA-token exposure → [[homepage-recon-exposure]] (this item only supplies its CSP header).
- The IdP admin-surface path confinement — not carried into this split (dropped from the parent); Phase 5 here is about path-deny NORMALIZATION robustness, not about confining the IdP admin surface.

## Related

- relates_to [[client-ip-trust-topology]] — owns the non-IP rate-limit dimension; both touch the external Gateway.
- (descoped) edge-detection-observability — owned the 4xx/401/429 + brute-force + reactive-window detection; item lost from BM, pending rebuild. The SecurityPolicy-attach-failure alert in Phase 1 is owned here.
- relates_to [[homepage-recon-exposure]] — owns the dashboard data exposure; this item supplies its CSP / frame-ancestors header.
- relates_to [[app-auth-coverage]] — owns the identity gates; the mergeType/attach guardrails here ensure a gate SecurityPolicy cannot silently detach.
- relates_to [[networking]] — Envoy Gateway admission, connection, redirect, response headers.
- relates_to [[observability]] — the SecurityPolicy-attach-failure alert.
- relates_to [[iam]] — the idm path-deny normalization and the OIDC redirect-target constraint.
