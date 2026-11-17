# Networking Platform Guide

This guide applies to `kubernetes/apps/networking/`. It captures durable guardrails for the ingress + edge exposure chain; for current-state detail (components, gateways, policies, claims, drift risk) read the Basic Memory area-reference `docs/areas/networking` via the `basic-memory` MCP.

## Scope

Platform networking, not user applications:

- ingress and edge routing through Envoy Gateway
- external exposure through Cloudflare Tunnel
- DNS synchronization through ExternalDNS (public) and `k8s-gateway` (LAN split DNS)

L2 and service IP allocation lives in `kubernetes/apps/kube-system/cilium/` (Cilium LB-IPAM + L2 announcement); this subtree consumes those VIPs but does not own them.

## Structural Guardrails

Do not assume one app equals one Flux Kustomization here:

- `envoy-gateway/` is split into separate Kustomizations (certificate, controller, config) — inspect the parent `ks.yaml` for multi-stage ordering before changing any child file.
- App manifests may include explicit `CiliumNetworkPolicy` or `SecurityPolicy` resources.
- Config manifests often live outside `app/` in dedicated `config/` directories.
- Do not collapse split Kustomizations into one unless explicitly asked.

## Envoy Gateway Conventions

`envoy-external` and `envoy-internal` are the shared Gateway API entrypoints; both live in namespace `networking`.

Rules:

- User-facing app routes should usually attach to both `envoy-external` and `envoy-internal`.
- Technical / internet-only routes can stay `envoy-external`-only when no LAN reach is needed.
- Gateway-level traffic policy (`BackendTrafficPolicy`, `ClientTrafficPolicy`, `EnvoyPatchPolicy`, `SecurityPolicy`) belongs here, not scattered into application trees.
- One BackendTrafficPolicy and one EnvoyExtensionPolicy per Gateway target — EG rejects a second as `Conflicted` (neither attaches). To add a feature, extend the existing `envoy` BTP rather than creating a new policy.
- There is no `EnvoyExtensionPolicy`, and adding one should be a last resort: Lua policies are disabled by default since EG v1.9.0, and the security response headers they used to carry are now native `ClientTrafficPolicy.headers.lateResponseHeaders`. Look for a native ClientTrafficPolicy/BackendTrafficPolicy field before reaching for Lua.
- The same applies to `SecurityPolicy` at Gateway level: a second one on the same target loses the contest and sits inert, so `envoy-internal-rfc1918` carries both the RFC1918 `authorization` and the CrowdSec `extAuth`, and `envoy-external-edge` carries both the HU-only geo `authorization` and the CrowdSec `extAuth`.
- A **route**-level `SecurityPolicy` must set `mergeType: StrategicMerge`, or it replaces the Gateway-level policy for that route instead of combining with it. The parent reports `Overridden`, the child keeps working, and the parent's protections are lost silently — this is how the RFC1918 allowlist skipped every OIDC-gated route until 2026-07-28. The shared `components/gateway-oidc` sets it.
- Every route hostname must be owned in `provision/pocket-id/clients.yaml` (client or `exempt`); the route auth guard (`provision/pocket-id/lint.sh`, rules in `provision/pocket-id/CLAUDE.md`) enforces it in pre-commit and CI.
- Even under StrategicMerge, a route-level `authorization` block **replaces** the parent's rules (no list merge) and an omitted `defaultAction` becomes Deny. On an `envoy-external` route that silently drops the HU-only geo gate; on an `envoy-internal` route, the RFC1918 allowlist. No admission check can see this. Only `flux-system/github-webhook` does it on purpose (GitHub hooks ranges). Any other route policy carrying `authorization` must restate the parent's rules, and the change needs security review.
- `envoy-external` client IP uses `numTrustedHops: 1`, not `trustedCIDRs`: EG rejects geo authorization with trustedCIDRs (envoyproxy/gateway#9935), and an invalid geo policy 500s every external route. Do not switch back before #9935 ships. The trust anchor is `CiliumNetworkPolicy/envoy-external` (cloudflared-only ingress); never widen its ingress.
- The HU-only country gate lives only in `envoy-external-edge`; the Cloudflare WAF country rule was removed on 2026-11-14. Granting access from abroad means an extra Allow rule there (e.g. `clientCIDRs` or another country), or a route policy per the rule above. Do not reintroduce a Cloudflare-side country rule. Hosts behind the Cloudflare Access wildcard are still gated by Access first.
- Do not add a `responseOverride` (EG 1.10 / Envoy 1.40.2): EG always sets `preserve_response_code_details`, and that custom_response path (envoyproxy/envoy#46600) rebuilds `response_code_details` from a view of the string it destroys — a use-after-free that wrote heap bytes into the access log for RBAC denies. The 403 override was reverted on 2026-11-14 (f3f1f4989) and the 401 OIDC-failure page on 2026-11-15, as the path does not depend on the status code. Lift this only once an Envoy release fixes the path.
- Never set `extAuth.bodyToExtAuth`: Envoy returns 413 once a body exceeds `maxRequestBytes` rather than buffering partially, and that outranks `failOpen` — it caps every upload behind the gateway.
- After any gateway-policy change, verify the live policy is `Accepted=True` with no `Conflicted` or `Overridden` condition — both fail silently.
- If changing listener behavior, inspect related policy and certificate manifests together.
- `envoy-internal` is protected by an RFC1918-only `SecurityPolicy`; do not weaken that without explicit security review.

## Cloudflare Edge Conventions

Cloudflare Tunnel and ExternalDNS are part of the same exposure chain:

- `cloudflare-tunnel` forwards the public domain to `envoy-external.networking.svc.cluster.local`; tunnel config comes from a ConfigMap, credentials from an ExternalSecret.
- ExternalDNS watches Gateway and HTTPRoute sources for the public path.
- LAN clients reach the same hostnames via router-side conditional forwarding to `k8s-gateway`, not through Cloudflare Tunnel.

Rules:

- If public hostnames or gateway targets change, inspect both Cloudflare Tunnel and ExternalDNS.
- If LAN hostname behavior changes, inspect `k8s-gateway` and the internal Gateway attachment model.
- Preserve Cloudflare-specific hardening and transport flags unless there is a concrete reason to change them.
- Keep secret names aligned between `externalsecret.yaml` and chart `envFrom` / `secretKeyRef` usage.

## Validation

See `.claude/skills/networking-platform/references/validation.md`.
