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

  injected only HSTS/nosniff/Referrer-Policy before Phase 4 — no CSP, frame-ancestors, Permissions-Policy,

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
- Delivered in Phase 4: gateway response headers via native ClientTrafficPolicy lateResponseHeaders — CSP frame-ancestors 'self' (no default-src/script-src, so the gateway 401 page keeps its inline script), Permissions-Policy (WebAuthn at self, sensitive capabilities blocked), COOP same-origin; all addIfAbsent so an app that sets its own header wins.
tags:
- roadmap
- security
- networking
- envoy-gateway
- admission-policy
- response-headers
---

# gateway-guardrails-response-headers — guardrails + response headers on the external gateway

## Metadata (observation-form, schema validation)

- [topic] Gateway guardrails (admission, attach, connection, extauth resilience) + response headers (CSP/framing/COOP) on the external surface
- [status] in-progress — Phase 1-4 delivered + live-verified (2026-08-15); Phase 5 proposed
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
- A bouncer restart still 503s every public hostname and the window is no shorter — the headroom, priorityClass and probe levers were all dropped on evidence — but the failure is no longer silent: an impact-level ext_authz alert fires, and it catches an AppSec outage underneath the bouncer too. The AppSec rollout no longer opens a gap of its own.
- Every app behind both gateways gets CSP (frame-ancestors 'self') / Permissions-Policy / COOP headers, reducing framing/clickjacking blast radius and what a successful XSS can abuse; an app that sets its own header wins (addIfAbsent).
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

### Phase 2 — Connection hardening ✅ (done 2026-08-15)

- Slowloris / connection exhaustion (gateway-policies.yaml timeouts + buffer): add connection.connectionLimit, bound maxAcceptPerSocketEvent, and lower requestReceivedTimeout. Blasts: too-low a timeout breaks large uploads (document ingest, book ingest) — calibrate per-route.
- https-redirect reflects client Host (gateway-policies.yaml redirect route): the port-80 redirect route has no hostname filter and no requestRedirect.hostname, so Envoy reflects the client Host into the Location header. Pin the hostnames or set requestRedirect.hostname.

**Delivery (2026-08-15) — Phase 2 implemented, deployed, live-verified.** Commits on `main`: `355a6af48` (allow a wildcard hostname on the port-80 listener), `39f2b320c` (stop the https-redirect reflecting a client Host), `92f5740a8` (restore the Envoy Gateway accept default), `fc812ab7d` (bound connections on the LAN-exposed gateway).

1. The https-redirect route no longer reflects a client Host: `hostnames: ["*.${PUBLIC_DOMAIN}"]` scopes the port-80 route to our own subdomains. Live test on the internal VIP: own subdomain → 301 to the correct target (path+query preserved), foreign Host → 404, apex → 404.
2. The Phase 1 `httproute-reserved-hostnames` VAP had to be widened first — it rejected our own route because it banned wildcard hostnames. Carve-out: a wildcard is allowed when every parentRef points at `sectionName: http` (the port-80 listener is same-namespace and carries no app hostnames). The idm reservation stays enforced on every listener — the idm check moved out of the conditional branch.
3. `maxAcceptPerSocketEvent: 0 → 1` in both ClientTrafficPolicies. The 0 (unlimited) had no recorded reason (5cf08ffadc, then copied by 27c1c46db8); Envoy Gateway deliberately defaults to 1. EG issue #9652 (a listener-scoped setting silently dropped on a shared address:port) does not affect us — http (10080) and https (10443) are separate ports.
4. `envoy-internal` CTP: `connection.connectionLimit.value: 1024` (blast-radius bound against a runaway client) + new `EnvoyInternalConnectionsHigh` alert (>512, for:10m, warning) + 3 promtool test cases.

**Deviations from the roadmap text (deliberate, with justification):**

A) The `requestReceivedTimeout` reduction was dropped (human decision). Per the live CRD description it covers the WHOLE request reception (headers + body), so lowering it would break the large-upload routes (paperless/docs, calibre-web-automated/books, pingvin-share-x/share, home-gallery/photos, backrest/backup). The classic slow-header (slowloris) vector is already caught by the set `requestHeadersReceivedTimeout: 10s`. What remains is the slow-body (R-U-Dead-Yet) type, where a timeout is the wrong tool by principle: a slowly sent attacker body and a legitimate large upload are indistinguishable in time. The right tool is connection-count limiting, not time.

B) The roadmap's "calibrate per-route" instruction was scope-wrong: a ClientTrafficPolicy is Gateway-level, not route-level. Per-route calibration belongs in Gateway API `HTTPRoute.spec.rules[].timeouts` (request + backendRequest, Extended support), which the installed EG 1.9.0 supports but the repo does not use anywhere today. If ever needed, that is a separate item, not Phase 2.

C) The external gateway's `connectionLimit` is deliberately absent — the Phase 2 acceptance criterion "connection.connectionLimit is set" is therefore NOT met on the external gateway; recorded as an explicit descope, not missing work. Justification: the envoy-external Service is ClusterIP-only (envoy.yaml:41-42), the CiliumNetworkPolicy admits the cloudflared pod as the single ingress source on 10080/10443 (+ prometheus scrape, kubelet), and cloudflared multiplexes with `http2Origin: true` — hence the measured 7-day peak is 1 connection. There is no path from which connections could be exhausted. The internal gateway's measured 7-day peak is 14; the 1024 limit is a blast-radius bound against a runaway client, not attack mitigation.

**Live verification (2026-08-15):** envoy-internal `connectionLimit=1024`, envoy-external no limit, `maxAccept=1` on both; both CTPs `Accepted=True` (no Conflicted/Overridden); both gateways `Accepted=True`/`Programmed=True`; `EnvoyInternalConnectionsHigh` live in the PrometheusRule; internal-gateway traffic unchanged (http 301, https 307 OIDC gate).

**Process lesson:** the Phase 1 VAP rejected the first change written after it immediately, so the VAP modification and the route modification went into TWO separate commits, VAP first — apply order within a Flux Kustomization is not guaranteed, and the reverse order would have caused a transient admission rejection. During validation an out-of-band `kubectl apply` also happened (server-side dry-run always evaluates against the LIVE policy); Flux drift-correction converged it to the committed state. The correct procedure is the two-step commit ordering.

### Phase 3 — ext_authz chain: shrink blast radius and outage window (no replicas) ✅ (done 2026-08-15)
- The chain is fail-closed (failOpen:false, statusOnError:503, gateway-policies.yaml:324-325 external, :298-299 internal) on a single-replica bouncer (replicaCount:1, crowdsec-bouncer/app/helmrelease.yaml:15), so a restart or OOMKill 503s every public hostname; on this single-node cluster the goal is a smaller outage window without replicas.
- Raise the bouncer memory headroom — a 128Mi limit / 64Mi request is tight (crowdsec-bouncer/app/helmrelease.yaml:62-67); an OOMKill is a hard fail-closed outage across every public hostname. Blasts: only node-memory pressure; raise the request first so admission keeps it schedulable.
- Give the bouncer a priorityClass above the workloads it gates, so it is never preempted or evicted first when the single node is under pressure. Blasts: a class ranked below a gated workload re-orders eviction the wrong way — the bouncer must outrank what it gates.
- Tune liveness/readiness so a hung bouncer is detected and restarted fast instead of 503ing through a slow probe window. Blasts: over-aggressive probes restart a healthy bouncer during startup/latency spikes.
- Add a Prometheus alert on bouncer unavailability so the 503 window is visible, not silent. Blasts: only alert noise — calibrate the firing window to ride out a rolling restart.
- No rollout surge on the bouncer: a surge would transiently run 2 pods on this single node, so it is rejected; the restart window is instead bounded by the memory-headroom, priorityClass, probe, and alert levers above.
- No PodDisruptionBudget: a PDB is meaningless at 1 replica on 1 node and is deliberately omitted.

**Delivery (2026-08-15) — Phase 3 implemented, deployed, live-verified.** Commits on `main`: `4a848946e` (close the AppSec rollout gap), `4c439c806` (alert on ext_authz failures, not just a dead bouncer).

1. `EnvoyExtAuthzErrors` alert (envoy-proxy group, networking): `sum by (pod) (increase(envoy_http_ext_authz_error{job="networking/envoy-proxy", namespace="networking"}[5m])) > 0`, `for: 2m`, `severity: critical`, 3 promtool test cases. This is the impact-level signal the roadmap asked for: `CrowdSecBouncerDown` sees only the bouncer pod and `CrowdSecAppsecDown` only the appsec pod — this one measures the failure itself and covers both causes (a bouncer that is up but erroring, or an AppSec outage underneath it). It has never been non-zero, so any occurrence is real.
2. `crowdsec-appsec` Deployment: `Recreate` → `RollingUpdate maxUnavailable:0 / maxSurge:1` via the chart `appsec.strategy` switch, `replicaCount` stays 1. Why: Recreate at 1 replica is a guaranteed outage window on every rollout, and the bouncer WAF branch is hardcoded fail-closed (no failOpen/timeout/skip switch): WAF error → action "error" → gRPC `codes.Unavailable` → `failOpen:false` + `statusOnError:503` → 503 to the client. `exemptIPs` cover only 10.0.0.0/8, so LAN apps are hit too, not just public ones. The Recreate is the chart's inherited blanket default (values.yaml:736-737, present since PR #189 with no recorded reason), contradicted by the chart's own later AppSec HA feature (PR #208); the appsec pod is stateless (no PVC — emptyDir + ConfigMap, no hostPort, per-pod LAPI registration).

**Deviations from the roadmap text (deliberate, with justification):**

A) The memory-headroom lever was dropped: the measured 7-day peak is 46 MiB against the 128 MiB limit (~2.8x headroom), the 64Mi request already sits above the peak, and there were zero OOMKill/restarts in 7 days. The roadmap's "the 128Mi limit is tight" premise was unverified and wrong.

B) The priorityClass lever was dropped (human decision): the repo uses priorityClassName nowhere, only the system-* classes exist, and on a single-node cluster the effect is limited to eviction-order/preemption. It would be a new convention without reference points.

C) The probe-tuning lever was dropped: the chart defaults give ~20s detection (initialDelay 5s, period 5s, failureThreshold 3), but the outage window is dominated by pod restart time, so tightening buys little and adds flapping risk.

D) The roadmap's requested "unavailability alert" already existed: `CrowdSecBouncerDown`, live since 2026-07-27 (cd7ab20c2). What was missing was the impact-level signal — `EnvoyExtAuthzErrors` supplies that.

**Honest limitation:** the "Recreate is a real outage source" conclusion rests on SOURCE-CODE evidence, not live observation. `bouncer_waf_errors_total` has been 0 for 90 days, and neither of the two AppSec pod swaps landed in a measurable-traffic window.

**Side benefit:** `CrowdSecAppsecDown` saw a zero-target window on every rollout under Recreate (false-positive risk); RollingUpdate 0/1 removes that too.

**Live verification (2026-08-15):** live PrometheusRule `envoy-proxy` group carries the 6th rule `EnvoyExtAuthzErrors`; the alert is loaded in Prometheus with health ok, state inactive (metric 0 on all 4 series — 2 gateways × http-10080/https-10443); `bouncer_waf_requests_total` increasing and `bouncer_waf_errors_total` 0; appsec deployment strategy RollingUpdate maxUnavailable=0/maxSurge=1, pod Ready 1/1.

### Phase 4 — Gateway response headers (native lateResponseHeaders: CSP / framing / COOP) ✅ (done 2026-08-15)
- The baseline is already native: ClientTrafficPolicy headers.lateResponseHeaders injects HSTS and nosniff (set) plus Referrer-Policy (addIfAbsent) on both gateways (gateway-policies.yaml:123-131 external, :180-188 internal). Missing: Content-Security-Policy frame-ancestors 'none', Permissions-Policy, COOP/COEP.
- Add the missing headers to the SAME lateResponseHeaders lists, using addIfAbsent so an app that sets its own header wins. Blasts: a set() would silently override a stricter app value — addIfAbsent keeps app sovereignty.
- CSP default-strict at the gateway (frame-ancestors 'none'), with per-app carve-outs for apps known to need inline scripts/widgets. Blasts: a strict CSP breaks inline-script/widget apps — carve per-app, never gateway-wide.
- Coordinate the dashboard header with [[homepage-recon-exposure]] — that item owns the dashboard exposure surface; this one only supplies its frame-ancestors / CSP baseline.
- Permissions-Policy and COOP/COEP are additive and low-risk, but verify COEP (cross-origin-isolate) against widget-bearing apps first. Blasts: COEP breaks cross-origin embeds — leave it off until the carve-out list is known.
**Delivery (2026-08-15) — Phase 4 implemented, deployed, live-verified.** Commit on `main`: `f3d89a847` (feat(networking): add framing, permissions and COOP response headers).

1. Three response headers were added to BOTH ClientTrafficPolicy `lateResponseHeaders` blocks (gateway-policies.yaml, envoy-external + envoy-internal), each `addIfAbsent` so an app that sets its own header always wins:
   - `content-security-policy: frame-ancestors 'self'` — this single directive only, no default-src/script-src.
   - `permissions-policy` — blocked (empty allowlist): camera, microphone, geolocation, usb, midi, payment, display-capture, serial, bluetooth; at `(self)`: publickey-credentials-get, publickey-credentials-create, fullscreen, autoplay, picture-in-picture.
   - `cross-origin-opener-policy: same-origin`.

**Deviations from the roadmap text (deliberate, with justification):**

A) `frame-ancestors` is `self`, not the roadmap's `none`. Paperless sends its own `x-frame-options: SAMEORIGIN` — it relies on same-origin embedding (its document preview) — and a CSP `frame-ancestors` overrides X-Frame-Options in browsers, so `none` would have broken that preview. `self` blocks the same threat (a foreign page framing our apps) while leaving same-origin embedding intact.

B) The CSP deliberately carries `frame-ancestors` ALONE — no default-src/script-src — so the gateway's own 401 responseOverride page keeps its inline script. The "no CSP on the gateway" comment (gateway-policies.yaml:51) explains that script's existence; it is NOT a ban on adding a CSP. Live-proven: the full OIDC flow ends with the 401 override page served intact, inline script in the body.

C) COEP was left out, deliberately. It breaks cross-origin embeds and adds nothing in this cluster; the roadmap's requested pre-check verdict is: not worth it.

D) Permissions-Policy does NOT block WebAuthn. Pocket ID is passkey-based (no password), so `publickey-credentials-get` and `publickey-credentials-create` stay at `(self)`; empty allowlists there would break every login in the cluster.

**Syntactic lesson (two standards, two syntaxes in one commit):** in CSP the `self` keyword must be QUOTED (`frame-ancestors 'self'`) — unquoted it parses as a host-source named "self" and the protection silently does nothing; in Permissions-Policy the `(self)` allowlist is correct UNQUOTED.

**Live verification (2026-08-15):** all three headers appear on the internal gateway (192.168.1.18, `--resolve`) for recipes/photos/dash/echo and on the external surface through the Cloudflare Tunnel; paperless (docs) keeps its own `referrer-policy: same-origin` and `x-frame-options: SAMEORIGIN` (addIfAbsent app sovereignty proven live) while receiving our CSP + permissions-policy; the 401 override page loads intact with its inline script (callback with `error=access_denied`); both CTPs `Accepted=True` (no Conflicted/Overridden), both gateways `Accepted=True`/`Programmed=True`; the envoy pods took the reload with 0 restarts, no traffic disruption.

### Phase 5 — Path normalization and redirect-target constraints (UNCERTAIN items)

- Path-deny normalization (UNCERTAIN, id 37): enable explicit path normalization (merge slashes, percent-decode) in a ClientTrafficPolicy and re-test the idm deny rules with encoded/doubled-slash variants.
- state-url redirect not domain constrained (UNCERTAIN, id 74): Envoy's post-login redirect target is not constrained to the gateway's own domains and no knob exists in the installed Envoy Gateway version. Carry as a known upstream limitation with a monitor; do not block on it.

## Acceptance criteria

- The VAP rejects a GRPCRoute with a reserved hostname and a route attaching to the wrong Gateway; the mergeType VAP rejects a SecurityPolicy without StrategicMerge.
- A SecurityPolicy set to not-Accepted triggers an alert within the scrape interval.
- connection.connectionLimit is set on the internal gateway (1024, half-cap alert); the external gateway is deliberately uncapped (no exhaustion path: ClusterIP-only + CiliumNetworkPolicy admits only the cloudflared pod, measured 7-day peak 1). requestReceivedTimeout lowering deliberately dropped — it covers the whole request reception (headers+body) and would break the large-upload routes; the slow-header vector is already bound by requestHeadersReceivedTimeout: 10s (Delivery deviation A).
- The redirect route no longer reflects an arbitrary Host.
- The bouncer memory-limit raise and priorityClass were deliberately dropped (Delivery deviations A-B: measured 7-day peak 46 MiB vs the 128 MiB limit is ~2.8x headroom with zero OOM in 7 days; no repo priorityClass convention on a single node); the impact-level EnvoyExtAuthzErrors alert covers bouncer and AppSec outages within the scrape interval. No PDB, no added replicas.
- A CSP / frame-ancestors 'self' header is present on external responses, injected via ClientTrafficPolicy lateResponseHeaders (addIfAbsent).
- Path normalization is on; encoded/doubled-slash deny-rule bypass attempts are blocked.

## Risks / what could break (blast radius per change)

- **Per-route timeouts (Phase 2):** too-low a requestReceivedTimeout breaks large uploads (document/book ingest). Mitigation: calibrate per-route, keep a generous timeout on the ingest routes.
- **extauth restart window (Phase 3):** the chain is fail-closed, so any bouncer restart 503s every public hostname. Mitigation: memory headroom + priorityClass + fast probes + an unavailability alert. Replicas, HA, and a PDB are explicitly out of scope on this single-node cluster.
- **CSP (Phase 4):** a strict CSP — one with default-src or script-src — would break the gateway own 401 responseOverride page, which carries an inline script, along with any app that inlines scripts. That is why the delivered CSP carries frame-ancestors alone. Widening it later is not a config tweak: it needs a per-app audit, starting with that 401 page. frame-ancestors is self rather than none because paperless frames its own document preview and sends SAMEORIGIN itself.
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
