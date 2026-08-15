---
title: gateway-guardrails-response-headers
type: roadmap
permalink: home-ops/docs/roadmap/gateway-guardrails-response-headers
topic: 'Gateway guardrails and response headers — admission guardrails for

  routes/SecurityPolicies, connection hardening, extauth-chain resilience, and

  CSP/framing/COOP response headers on the external surface.'
status: in-progress
priority: medium
scope: 'The Envoy Gateway control surface in front of the external routes: the

  reserved-hostname ValidatingAdmissionPolicy, route/SecurityPolicy attach semantics

  (mergeType, Accepted condition), the external proxy connection/timeout settings,
  the

  port-80 https-redirect route, the fail-closed ext_authz chain (CrowdSec bouncer
  +

  AppSec), and the native ClientTrafficPolicy lateResponseHeaders. Carries the

  response-headers-lack-CPS cluster (ids 42, 70).'
rationale: 'These are gateway-plane guardrails that fail silently today: a route-level

  SecurityPolicy that forgets mergeType: StrategicMerge silently detaches the

  Gateway-level CrowdSec gate; a SecurityPolicy that fails to attach leaves the route

  fully ungated; neither is caught by admission, lint, or alert. The external proxy
  is

  a single instance with 30-minute timeouts and no connection limit; the native
  ClientTrafficPolicy lateResponseHeaders

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
- [status] in-progress — Phase 1 delivered + live-verified (2026-08-15); Phases 2-5 proposed
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
- A bouncer restart still 503s every public hostname, but the window is shorter (memory headroom, priorityClass, fast probes) and no longer silent (an unavailability alert fires).
- Unauthenticated public apps get CSP / frame-ancestors / Permissions-Policy / COOP headers, reducing XSS/framing/clickjacking blast radius.
- Path-deny rules are robust to percent-encoding/doubled-slash bypass attempts once explicit path normalization is enabled and re-tested (Phase 5 — currently UNCERTAIN).

## What to do (phased; each phase independently shippable)

### Phase 1 — Admission guardrails for routes and SecurityPolicies ✅ (done 2026-08-15)

- Widen the reserved-hostname ValidatingAdmissionPolicy (validatingadmissionpolicy.yaml): today it matches HTTPRoutes only, while the public listener accepts other route kinds, and it never constrains which Gateway a route may attach to. Extend it to grpcroutes/tlsroutes/tcproutes and add a parentRef/kind constraint so a route cannot attach to an unexpected Gateway.
- Add a VAP requiring spec.mergeType == StrategicMerge on any SecurityPolicy targeting an HTTPRoute (a forgotten mergeType silently detaches the Gateway-level CrowdSec gate).
- Add a PrometheusRule alerting on any SecurityPolicy whose Accepted condition is False or whose ancestorRef is missing (silent attach failure). The alert-wiring coordination target edge-detection-observability is a descoped/lost roadmap item (pending rebuild).

**Delivery (2026-08-15) — Phase 1 implemented, deployed, live-verified.** Commits on `main`: `3f0b1f884` (route + SecurityPolicy admission guardrails), `d2b161f94` (KSM RBAC for SecurityPolicy metrics), `de8ff39e7` (SecurityPolicy-status-vanishing alert).

1. The `httproute-reserved-hostnames` VAP was widened to httproutes/grpcroutes/tlsroutes/tcproutes, plus a parentRef constraint: a non-security route may attach only to the `envoy-external`/`envoy-internal` Gateways (networking namespace, kind Gateway), and an explicit empty `hostnames` list is treated like a missing one (implicit wildcard inheritance on the https listener). The `security` namespace short-circuits and exits before the Gateway constraint applies.
2. New `securitypolicy-route-strategic-merge` VAP: any SecurityPolicy targeting an HTTPRoute must set `spec.mergeType: StrategicMerge` — the default `Merge` silently detaches the Gateway-level CrowdSec/RFC1918 gate.
3. `EnvoyGatewayPolicyNotAccepted` alert. **Decision:** Envoy Gateway exports no per-policy status metric, so the metric comes from kube-state-metrics `custom-resource-state` (`envoy_securitypolicy_info`), following the existing Flux `gotk_resource_info` pattern in the repo — the only viable path to the acceptance criterion.
4. **Blocker found by deploy-check:** the KSM ClusterRole listed only Flux CRDs, not `gateway.envoyproxy.io/securitypolicies` — the metric family registered but produced ZERO samples, so the alert would have stayed silent. Fixed in `d2b161f94` (`rbac.extraRules` list/watch).
5. The blocker's lesson produced `de8ff39e7`: `EnvoyGatewayPolicyStatusMissing` sentinel, `expr: absent(envoy_securitypolicy_info)`, `for: 5m`, `severity: critical` — it watches the guardrail itself, because a silent metric path looks exactly like calm.

**Live verification (2026-08-15):** 12 `envoy_securitypolicy_info` samples, all `accepted="True" reason="Accepted"`; cross-checked against live `kubectl get securitypolicy -A` status (12 policies). The sentinel is not firing. Both VAPs and both alerts are live; Flux reconcile `Ready=True` on the `de8ff39e7` revision.

**Follow-ups (recorded, not implemented):**
- The `httproute-reserved-hostnames` VAP name is now misleading (it covers all route kinds). Rename via delete+create — risk-free.
- The KSM pod template has no checksum annotation, so a CRS config change is hot-reloaded without a pod restart. This was lucky today, but a future CRS config error would silently stand in the same way.

### Phase 2 — Connection hardening

- Slowloris / connection exhaustion (gateway-policies.yaml timeouts + buffer): add connection.connectionLimit, bound maxAcceptPerSocketEvent, and lower requestReceivedTimeout. Blasts: too-low a timeout breaks large uploads (document ingest, book ingest) — calibrate per-route.
- https-redirect reflects client Host (gateway-policies.yaml redirect route): the port-80 redirect route has no hostname filter and no requestRedirect.hostname, so Envoy reflects the client Host into the Location header. Pin the hostnames or set requestRedirect.hostname.

### Phase 3 — ext_authz chain: shrink blast radius and outage window (no replicas)
- The chain is fail-closed (failOpen:false, statusOnError:503, gateway-policies.yaml:324-325 external, :298-299 internal) on a single-replica bouncer (replicaCount:1, crowdsec-bouncer/app/helmrelease.yaml:15), so a restart or OOMKill 503s every public hostname; on this single-node cluster the goal is a smaller outage window without replicas.
- Raise the bouncer memory headroom — a 128Mi limit / 64Mi request is tight (crowdsec-bouncer/app/helmrelease.yaml:62-67); an OOMKill is a hard fail-closed outage across every public hostname. Blasts: only node-memory pressure; raise the request first so admission keeps it schedulable.
- Give the bouncer a priorityClass above the workloads it gates, so it is never preempted or evicted first when the single node is under pressure. Blasts: a class ranked below a gated workload re-orders eviction the wrong way — the bouncer must outrank what it gates.
- Tune liveness/readiness so a hung bouncer is detected and restarted fast instead of 503ing through a slow probe window. Blasts: over-aggressive probes restart a healthy bouncer during startup/latency spikes.
- Add a Prometheus alert on bouncer unavailability so the 503 window is visible, not silent. Blasts: only alert noise — calibrate the firing window to ride out a rolling restart.
- No rollout surge on the bouncer: a surge would transiently run 2 pods on this single node, so it is rejected; the restart window is instead bounded by the memory-headroom, priorityClass, probe, and alert levers above.
- No PodDisruptionBudget: a PDB is meaningless at 1 replica on 1 node and is deliberately omitted.
### Phase 4 — Gateway response headers (native lateResponseHeaders: CSP / framing / COOP)
- The baseline is already native: ClientTrafficPolicy headers.lateResponseHeaders injects HSTS and nosniff (set) plus Referrer-Policy (addIfAbsent) on both gateways (gateway-policies.yaml:123-131 external, :180-188 internal). Missing: Content-Security-Policy frame-ancestors 'none', Permissions-Policy, COOP/COEP.
- Add the missing headers to the SAME lateResponseHeaders lists, using addIfAbsent so an app that sets its own header wins. Blasts: a set() would silently override a stricter app value — addIfAbsent keeps app sovereignty.
- CSP default-strict at the gateway (frame-ancestors 'none'), with per-app carve-outs for apps known to need inline scripts/widgets. Blasts: a strict CSP breaks inline-script/widget apps — carve per-app, never gateway-wide.
- Coordinate the dashboard header with [[homepage-recon-exposure]] — that item owns the dashboard exposure surface; this one only supplies its frame-ancestors / CSP baseline.
- Permissions-Policy and COOP/COEP are additive and low-risk, but verify COEP (cross-origin-isolate) against widget-bearing apps first. Blasts: COEP breaks cross-origin embeds — leave it off until the carve-out list is known.
### Phase 5 — Path normalization and redirect-target constraints (UNCERTAIN items)

- Path-deny normalization (UNCERTAIN, id 37): enable explicit path normalization (merge slashes, percent-decode) in a ClientTrafficPolicy and re-test the idm deny rules with encoded/doubled-slash variants.
- state-url redirect not domain constrained (UNCERTAIN, id 74): Envoy's post-login redirect target is not constrained to the gateway's own domains and no knob exists in the installed Envoy Gateway version. Carry as a known upstream limitation with a monitor; do not block on it.

## Acceptance criteria

- The VAP rejects a GRPCRoute with a reserved hostname and a route attaching to the wrong Gateway; the mergeType VAP rejects a SecurityPolicy without StrategicMerge.
- A SecurityPolicy set to not-Accepted triggers an alert within the scrape interval.
- connection.connectionLimit is set; requestReceivedTimeout is lowered; a large-upload route still succeeds.
- The redirect route no longer reflects an arbitrary Host.
- The bouncer memory limit is raised and a priorityClass is set; a bouncer-unavailability alert fires within the scrape interval. No PDB, no added replicas.
- A CSP / frame-ancestors header is present on external responses, injected via ClientTrafficPolicy lateResponseHeaders (addIfAbsent).
- Path normalization is on; encoded/doubled-slash deny-rule bypass attempts are blocked.

## Risks / what could break (blast radius per change)

- **Per-route timeouts (Phase 2):** too-low a requestReceivedTimeout breaks large uploads (document/book ingest). Mitigation: calibrate per-route, keep a generous timeout on the ingest routes.
- **extauth restart window (Phase 3):** the chain is fail-closed, so any bouncer restart 503s every public hostname. Mitigation: memory headroom + priorityClass + fast probes + an unavailability alert. Replicas, HA, and a PDB are explicitly out of scope on this single-node cluster.
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
