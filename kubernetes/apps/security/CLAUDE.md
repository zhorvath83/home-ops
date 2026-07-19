# Identity & Access Management Guide

This guide applies to `kubernetes/apps/security/`. It captures durable guardrails for the cluster IAM platform; for current-state detail (component config, onboarding checklists, known upstream bugs, audit findings) read the Basic Memory area-reference `docs/areas/iam` via the `basic-memory` MCP.

## Scope

This subtree provides the identity platform every other workload authenticates against — it is platform, not app workload:

- `kanidm/` — the OIDC Identity Provider (sole source of truth for users and groups, passkey-first, no password fallback), exposed at `idm.${PUBLIC_DOMAIN}` on both `envoy-external` and `envoy-internal`.

The OIDC gate wiring for consuming apps lives in the shared `kubernetes/components/gateway-oidc/` component, not here.

## Trust Chain (Security Boundary — Do Not Weaken)

For OIDC-gated apps the request path is `User → Envoy Gateway → SecurityPolicy (OIDC) → App`.

- Envoy performs the OIDC authorization-code flow against Kanidm itself: an unauthenticated request is redirected to Kanidm login, and only after a successful token exchange does the request reach the backend (Envoy sets the id-token/access-token cookies).
- Per-app group authorization is enforced at Kanidm (per-client `allowed-groups`, default-deny), not in the SecurityPolicy — the `gateway-oidc` component carries no `authorization` block.
- **Header stripping is a header-injection spoofing guard.** The Envoy Gateway `ClientTrafficPolicy` strips `Remote-User`, `Remote-Email`, `Remote-Groups`, `Remote-Name`, and `Remote-Sub` from inbound requests so those identity headers cannot be supplied by a client. Never remove or narrow that stripping.

## Guardrails For Edits Here

- **Every app must be protected** by either native OIDC (registered as a Kanidm OAuth2 client) or the `gateway-oidc` component. Do not expose a new workload without an IAM policy.
- OIDC client credentials come from a per-app `ExternalSecret` backed by the `onepassword-connect` ClusterSecretStore (1Password item `kanidm`, field `<APP>_client_secret`); never inline `client_id`/`client_secret`. The `gateway-oidc` component ships the ExternalSecret template.
- **OIDC endpoints are always the public issuer** (`https://idm.${PUBLIC_DOMAIN}/...`) — every client, every endpoint (auth/token/userinfo/discovery), per AD-023. Never point token/userinfo at the in-cluster Kanidm Service: discovery-only clients cannot follow a split config, and the split pattern created a two-class rule. The backchannel hairpins through envoy; a client pod that opts out of baseline egress (`egress.home.arpa/custom-egress`) must therefore also carry `egress.home.arpa/allow-gateways`, or its token exchange is dropped by its own CNP posture.
- Administration runs through the `just kanidm` module (ad-hoc `kanidm/tools` client pod in the `security` namespace); the `kanidm/server` image ships no client CLI and there is no macOS package. See `kubernetes/apps/security/kanidm/README.md`.
- Preserve the Kanidm passkey-first posture — do not re-introduce a password fallback.

## Validation

- After edits, verify the app is unreachable without identity and that group-based access is actually enforced — not just that the pod is healthy.
- Public-exposure or trust-boundary changes warrant `.claude/skills/security-review/`.
