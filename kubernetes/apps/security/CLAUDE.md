# Identity & Access Management Guide

This guide applies to `kubernetes/apps/security/`. It captures durable guardrails for the cluster IAM platform; for current-state detail (component config, onboarding checklists, known upstream bugs, audit findings) read the Basic Memory area-reference `docs/areas/iam` via the `basic-memory` MCP.

## Scope

This subtree provides the identity platform every other workload authenticates against — it is platform, not app workload:

- `pocket-id/` — the OIDC Identity Provider (sole source of truth for users and groups, passkey-only, no password), exposed at `idm.${PUBLIC_DOMAIN}` on both `envoy-external` and `envoy-internal`.

Two things live outside this subtree: the OIDC gate for apps that do not speak OIDC is the shared `kubernetes/components/gateway-oidc/` component, and the IdP's own clients and groups are Terraform-managed in `provision/pocket-id/`.

## Trust Chain (Security Boundary — Do Not Weaken)

For OIDC-gated apps the request path is `User → Envoy Gateway → SecurityPolicy (OIDC) → App`.

- Envoy performs the OIDC authorization-code flow against Pocket ID itself: an unauthenticated request is redirected to the IdP login, and only after a successful token exchange does the request reach the backend (Envoy sets the id-token/access-token cookies). Envoy always adds PKCE (`code_challenge`/S256); it is not configurable in the `SecurityPolicy`.
- Per-app group authorization is enforced at Pocket ID (per-client `allowed_user_groups`), not in the SecurityPolicy — the `gateway-oidc` component carries no `authorization` block. A client whose group restriction is off admits every account, so that state must never be reachable; the guard lives in `provision/pocket-id` (Terraform precondition + `just pocket-id audit`).
- **Header stripping is a header-injection spoofing guard.** The Envoy Gateway `ClientTrafficPolicy` strips `Remote-User`, `Remote-Email`, `Remote-Groups`, `Remote-Name`, and `Remote-Sub` from inbound requests so those identity headers cannot be supplied by a client. Never remove or narrow that stripping.
- The admin API is deliberately unreachable from the public gateway: the `pocket-id-external` HTTPRoute returns 403 for any request carrying `X-API-KEY`, alongside 403s for the setup/signup and internal paths. Provisioning therefore runs from the LAN through `envoy-internal`.

## Guardrails For Edits Here

- **Every app must be protected** by either native OIDC (registered as a Pocket ID client) or the `gateway-oidc` component. Do not expose a new workload without an IAM policy.
- **Clients and groups are Terraform-managed.** Add an app to `provision/pocket-id/clients.yaml` and run `just pocket-id apply`; never create a client in the admin UI, or it drifts out of the registry and escapes the group-restriction guard. Users and their group membership are the exception — those are managed in the admin UI on purpose.
- OIDC client secrets come from a per-app `ExternalSecret` backed by the `onepassword-connect` ClusterSecretStore (1Password item `pocket-id-clients`, field `<APP>_client_secret`); never inline `client_id`/`client_secret`. The `gateway-oidc` component ships the ExternalSecret template. The `client_id` is not a secret — Terraform sets it to the app name, so manifests carry it as a literal.
- **Pocket ID uses one issuer for every client**: `https://idm.${PUBLIC_DOMAIN}`, with the endpoints resolved through `/.well-known/openid-configuration`. Never point token/userinfo at the in-cluster Service, per AD-023. The backchannel hairpins through envoy; a client pod that opts out of baseline egress (`egress.home.arpa/custom-egress`) must therefore also carry `egress.home.arpa/allow-gateways`, or its token exchange is dropped by its own CNP posture.
- Preserve the passkey-only posture — do not introduce a password fallback.

## Validation

- After edits, verify the app is unreachable without identity and that group-based access is actually enforced — not just that the pod is healthy. The negative case is the one that matters: a user outside the app's group must be refused.
- Public-exposure or trust-boundary changes warrant `.claude/skills/security-review/`.
