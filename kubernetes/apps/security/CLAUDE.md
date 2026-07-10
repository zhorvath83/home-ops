# Identity & Access Management Guide

This guide applies to `kubernetes/apps/security/`. It captures durable guardrails for the cluster IAM platform; for current-state detail (component config, onboarding checklists, known upstream bugs, audit findings) read the Basic Memory area-reference `docs/areas/iam` via the `basic-memory` MCP.

## Scope

This subtree provides the identity platform every other workload authenticates against — it is platform, not app workload:

- `pocket-id/` — the OIDC Identity Provider (sole source of truth for users and groups, passkey-first, no password fallback), exposed at `id.${PUBLIC_DOMAIN}`
- `tinyauth/` — the forward-auth Policy Enforcement Point: an OIDC client to Pocket-ID that gives Envoy a forward-auth interface for workloads that cannot speak OIDC natively

The forward-auth wiring for consuming apps lives in the shared `kubernetes/components/forward-auth/` component, not here.

## Trust Chain (Security Boundary — Do Not Weaken)

For OIDC-less apps the request path is `User → Envoy Gateway → SecurityPolicy (ExtAuthz) → TinyAuth → App`.

- **Header stripping is the security boundary.** The Envoy Gateway `ClientTrafficPolicy` strips `Remote-User`, `Remote-Email`, `Remote-Groups`, `Remote-Name`, and `Remote-Sub` from inbound requests so those identity headers can ONLY be set by the auth provider. Never remove or narrow that stripping — it is what prevents header-injection identity spoofing.
- ExtAuthz calls TinyAuth synchronously; a 401/403 drops the request at Envoy before it reaches the backend.
- TinyAuth injects the validated identity headers only after successful auth.

## Guardrails For Edits Here

- **Every app must be protected** by either native OIDC (registered in Pocket-ID) or the `forward-auth` component. Do not expose a new workload without an IAM policy.
- **TinyAuth nil-ACL trap**: define the per-app `TINYAUTH_APPS_<NAME>_OAUTH_GROUPS` ACL **before** attaching `forward-auth` to an app. The pinned TinyAuth release defaults to *allow* when no per-app ACL exists, so a missing ACL silently grants access to every authenticated user. (See the BM note for the exact version and upstream fix status.)
- **ReferenceGrant coverage**: a forward-auth app in a new namespace needs that namespace added to the `tinyauth-extauth` `ReferenceGrant` in the `security` namespace first, or Envoy Gateway rejects the `SecurityPolicy`.
- OIDC client credentials come from a per-app `ExternalSecret` backed by the `onepassword-connect` ClusterSecretStore (see `kubernetes/apps/external-secrets/CLAUDE.md`); never inline `client_id`/`client_secret`.
- **OIDC endpoints are always the public issuer** (`https://id.${PUBLIC_DOMAIN}/...`) — every client, every endpoint (auth/token/userinfo/discovery), per AD-023 rev4. Never point token/userinfo at the in-cluster Pocket-ID Service: discovery-only clients cannot follow a split config, and the split pattern created a two-class rule. The backchannel hairpins through envoy; a client pod that opts out of baseline egress (`egress.home.arpa/custom-egress`) must therefore also carry `egress.home.arpa/allow-gateways`, or its token exchange is dropped by its own CNP posture.
- Preserve the Pocket-ID passkey-first posture — do not re-introduce a password fallback.

## Validation

- After edits, verify the app is unreachable without identity and that group-based access is actually enforced — not just that the pod is healthy.
- Public-exposure or trust-boundary changes warrant `.claude/skills/security-review/`.
