# Pocket ID Terraform Guide

This guide applies to `provision/pocket-id/`. It captures durable guardrails for the declarative Pocket ID provisioning area; for current-state detail (client inventory, group taxonomy, cutover history) read the Basic Memory area-reference `docs/areas/iam` via the `basic-memory` MCP.

## Scope

Terraform files here are the source of truth for the identity objects inside the Pocket ID IdP:

- `clients.yaml` — the registry every other file reads: groups, OIDC clients, their subdomains and allowed groups
- `groups.tf` / `clients.tf` — the resources rendered from that registry
- `locals.tf` — registry decoding, callback-URL derivation, `PUBLIC_DOMAIN` lookup from `kubernetes/components/common/vars/cluster-settings.yaml`
- `main.tf` / `variables.tf` / `outputs.tf` — provider, remote state, API token, client-secret outputs
- `lint.sh` — drift check between `clients.yaml` and the `gateway-oidc` consumers in the `ks.yaml` tree

The client secrets produced here are consumed downstream by `kubernetes/components/gateway-oidc/` and by the natively OIDC-speaking apps, through the `HomeOps/pocket-id-clients` 1Password item.

## Operating Rules

- **`clients.yaml` is the only file to edit when adding an app.** The `.tf` files iterate over it; adding a resource block by hand defeats the registry.
- **Never let a client reach the API with an empty group list.** Pocket ID itself is not permissive here: a client marked group-restricted with no groups denies everyone. The gap is in this provider, which does not expose `isGroupRestricted` and instead derives it as "the list is non-empty" — so an empty list arrives as *not restricted* and every account gets in. The `lifecycle.precondition` in `clients.tf` and the matching check in `lint.sh` are both load-bearing; do not weaken either.
- **PKCE stays on.** Envoy Gateway always sends a `code_challenge` (it is not configurable in the `SecurityPolicy`), and Pocket ID only *verifies* the challenge when the client has `pkce_enabled`; with it off, a stolen authorization code can be redeemed without the verifier. `locals.tf` defaults it to `true` — override per client in `clients.yaml` only for an app that provably cannot send a challenge, and say why.
- **Do not enable "skip consent" in the admin UI.** The provider has no `skip_consent` attribute and omits the field from its request body, so Pocket ID resets it to `false` the next time Terraform updates that client — silently, since the field is absent from the schema and never appears in a plan. Enabling it upstream in the provider is the only clean fix.
- Prefer `just pocket-id init|plan|apply` over raw Terraform; use `just pocket-id unlock <id>` for state unlocks and `just pocket-id rotate <app>` to mint a fresh client secret.
- `just pocket-id apply` also syncs the client secrets into the `HomeOps/pocket-id-clients` 1Password item — keep that side effect intact. Raw `terraform apply` skips it and leaves every consuming ExternalSecret stale.
- **A client secret is readable exactly once**, at creation. It lives in Terraform state and in 1Password, nowhere else; losing both means recreating the client (`just pocket-id rotate <app>`).
- The workspace runs in **local execution mode** on purpose: the admin API is reachable only through `envoy-internal`, because the public HTTPRoute returns 403 for any request carrying `X-API-KEY`. A remote-executed plan can never reach it.
- `.env`, `.terraform/`, `.terraform.lock.hcl`, and state files are operational artifacts — do not refactor them as source configuration.

## Validation

- `just pocket-id lint` after any `clients.yaml` or `ks.yaml` change; it is also the first dependency of `plan` and `apply`.
- `just pocket-id audit` queries the running IdP and fails on any client whose group restriction is off — this is what catches a client created in the admin UI behind Terraform's back.
- Use repo-local skills for detailed procedures:
  - shared recipe-runner conventions: `.claude/skills/just/`
  - downstream OIDC gate and trust-boundary impact: `.claude/skills/security-review/`
