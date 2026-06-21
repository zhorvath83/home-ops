---
title: forward-auth-gep-1494-migration
type: roadmap
permalink: home-ops/docs/roadmap/forward-auth-gep-1494-migration
topic: Adopt GEP-1494 native ExternalAuth HTTPRoute filter for forward-auth (when
  Envoy Gateway GA-supports it)
status: proposed
priority: low
scope: When Envoy Gateway ships GA support for the Gateway API GEP-1494 native ExternalAuth
  HTTPRoute filter, optionally refactor the per-app forward-auth wiring (components/forward-auth
  SecurityPolicy + ${APP} substitution) onto the standard route-attached filter. Purely
  a syntactic/portability cleanup — same TinyAuth + Pocket-ID components, same request
  flow, no functional change.
rationale: Today forward-auth uses the Envoy-Gateway-specific SecurityPolicy.extAuth
  CRD, one generated object per protected HTTPRoute. GEP-1494 standardises the same
  ext_authz delegation as a vendor-neutral Gateway API filter on the HTTPRoute itself.
  The gain is standardisation + one fewer CRD per app; there is NO functional improvement,
  so this is deliberately low priority and gated on upstream GA, not pursued now.
options:
- Adopt when GA — refactor components/forward-auth/ to the native filter once Envoy
  Gateway GA-supports GEP-1494; preserve TinyAuth group ACLs, header-strip trust chain,
  fail-closed, CNP and ReferenceGrant
- Stay on SecurityPolicy.extAuth indefinitely — it already delivers the GEP-1494 target
  behaviour on Envoy Gateway; do nothing if the cleanup never pays for itself
related_areas:
- networking
- iam
---

# Adopt GEP-1494 native ExternalAuth HTTPRoute filter for forward-auth

## Metadata (observation-form, schema validation)

- [topic] Adopt GEP-1494 native ExternalAuth HTTPRoute filter for forward-auth (when Envoy Gateway GA-supports it)
- [status] proposed
- [priority] low

## Goal

- [observation] When Envoy Gateway GA-supports the GEP-1494 ExternalAuth filter, optionally replace the per-app `SecurityPolicy.extAuth` mechanism with the native Gateway-API filter attached directly to each HTTPRoute
- [observation] This is a syntactic/portability refactor only — the auth stack (TinyAuth + Pocket-ID), the request flow, and the security boundary stay identical

## Current state (the GEP-1494 target is already met functionally)

- [observation] Forward-auth runs on Envoy Gateway's native ext_authz via `kubernetes/components/forward-auth/securitypolicy.yaml` (`SecurityPolicy.extAuth` → `tinyauth:3000` `/api/auth/envoy?path=`), `failOpen: false`
- [observation] Per-app opt-in: Flux Kustomization `spec.components: [../../../../components/forward-auth]` + `postBuild.substitute.APP` generates one `<app>-forward-auth` SecurityPolicy targeting the app's HTTPRoute
- [observation] 9 protected apps (echo, bazarr, prowlarr, qbittorrent, subsyncarr, maintainerr, radarr, seerr, sonarr); per-app group ACLs live in TinyAuth (`TINYAUTH_APPS_*_OAUTH_GROUPS`), v5.0.7
- [observation] Pocket-ID is a SHARED OIDC IdP — consumed by TinyAuth AND natively by pingvin-share-x (`kubernetes/apps/selfhosted/pingvin-share-x/app/config/config.yaml`); it is not removable
- [observation] Identity-header strip (anti-spoofing) lives in `envoy-gateway/config/gateway-policies.yaml` ClientTrafficPolicy; cross-namespace ext-auth allowed via `tinyauth/app/referencegrant.yaml`

## What GEP-1494 would add

- [observation] GEP-1494 is the Gateway API standard `ExternalAuth`/`HTTPExtAuthFilter` for north-south HTTP auth, delegating to an external service over Envoy's ext_authz pattern (gRPC mode + HTTP mode; 200 = allow)
- [observation] [gain] Standardisation/portability — config attaches to the HTTPRoute (vendor-neutral) instead of an EG-specific `SecurityPolicy`; survives a future swap to another Gateway API implementation (e.g. Cilium Gateway API)
- [observation] [gain] One fewer moving part per app — the filter is part of the route definition, so `components/forward-auth/` + `${APP}` substitution could be retired
- [observation] [non-gain] Zero functional difference — header forwarding, fail-closed, and the TinyAuth/Pocket-ID flow are identical to today's `SecurityPolicy.extAuth`

## Why not now (blockers / gating)

- [observation] [blocker] GEP-1494 is `Experimental` in the Gateway API spec (experimental channel only) — building durable/public-repo config on an experimental API is a stability/security regression per the repo non-negotiables
- [observation] [blocker] Envoy Gateway does NOT implement the GEP-1494 native filter yet; its documented ext_authz mechanism remains the `SecurityPolicy` CRD
- [observation] [context] devantler/platform#1881 needs GEP-1494 because Cilium Gateway API has no SecurityPolicy.extAuth equivalent (blocked on Cilium >= 1.20). On Envoy Gateway that gap does not exist — we already have the target behaviour, so there is nothing to wait for functionally

## Trigger condition

- [observation] Revisit only when Envoy Gateway announces GA (non-experimental) support for the GEP-1494 ExternalAuth HTTPRoute filter — track EG release notes / Renovate bumps of the Envoy Gateway chart

## Eventual scope (if adopted)

- [observation] Refactor `kubernetes/components/forward-auth/` from `SecurityPolicy.extAuth` to the native HTTPRoute filter; update per-app opt-in if the `${APP}` substitution is no longer needed
- [observation] Preserve: TinyAuth per-app group ACLs, the ClientTrafficPolicy header-strip trust chain, `failOpen: false`, the tinyauth CiliumNetworkPolicy, and the ReferenceGrant (or its filter-era equivalent)
- [observation] [non-goal] Do NOT change TinyAuth or Pocket-ID, and do NOT reduce component count — prior analysis concluded the 3-component design (Envoy Gateway + TinyAuth + shared Pocket-ID) is already optimal

## Related

- relates_to [[networking]]
- relates_to [[iam]]
