# Pocket ID Terraform Guide

This guide applies to `provision/pocket-id/`. It captures durable guardrails for the declarative Pocket ID provisioning area; for current-state detail (client inventory, group taxonomy, cutover history) read the Basic Memory area-reference `docs/areas/iam` via the `basic-memory` MCP.

## Scope

Terraform files here are the source of truth for the identity objects inside the Pocket ID IdP:

- `clients.yaml` — the registry every other file reads: groups, OIDC clients, their subdomains and allowed groups
- `groups.tf` / `clients.tf` — the resources rendered from that registry
- `locals.tf` — registry decoding, callback-URL derivation, `PUBLIC_DOMAIN` lookup from `kubernetes/components/common/vars/cluster-settings.yaml`
- `main.tf` / `variables.tf` / `outputs.tf` — provider, remote state, API token, client-secret outputs
- `lint.sh` — route auth guard layer 1 (static): every hostname under `kubernetes/` is owned by a client or an exemption, and gate envoy clients are wired to `gateway-oidc`
- `lint-rendered.sh` — route auth guard layer 2 (CI): checks a `flate build all -o json` render against layer 1 and proves each gate envoy route carries its OIDC `SecurityPolicy`
- `tests/run.sh` — fixture tests for both layers (`tests/fixtures/base` plus one mutation per case)

The client secrets produced here are consumed downstream by `kubernetes/components/gateway-oidc/` and by the natively OIDC-speaking apps, through the `HomeOps/pocket-id-clients` 1Password item.

## Operating Rules

- **`clients.yaml` is the only file to edit when adding an app.** The `.tf` files iterate over it; adding a resource block by hand defeats the registry.
- **The map key is load-bearing, `friendly_name` is not.** The key becomes the `client_id`, the `<app>_client_secret` field in 1Password, and the `property` an `ExternalSecret` reads — renaming it replaces the client, mints a new secret and orphans the old 1Password field. `friendly_name` is only the label the IdP shows and is safe to change at any time.
- **Never let a client reach the API with an empty group list.** Pocket ID itself is not permissive here: a client marked group-restricted with no groups denies everyone. The gap is in this provider, which does not expose `isGroupRestricted` and instead derives it as "the list is non-empty" — so an empty list arrives as *not restricted* and every account gets in. The `lifecycle.precondition` in `clients.tf` and the matching check in `lint.sh` are both load-bearing; do not weaken either.
- **PKCE stays on.** Envoy Gateway always sends a `code_challenge` (it is not configurable in the `SecurityPolicy`), and Pocket ID only *verifies* the challenge when the client has `pkce_enabled`; with it off, a stolen authorization code can be redeemed without the verifier. `locals.tf` defaults it to `true` — override per client in `clients.yaml` only for an app that provably cannot send a challenge, and say why.
- **Do not enable "skip consent" in the admin UI.** The provider has no `skip_consent` attribute and omits the field from its request body, so Pocket ID resets it to `false` the next time Terraform updates that client — silently, since the field is absent from the schema and never appears in a plan. Enabling it upstream in the provider is the only clean fix.
- Prefer `just pocket-id init|plan|apply` over raw Terraform; use `just pocket-id unlock <id>` for state unlocks and `just pocket-id rotate <app>` to mint a fresh client secret.
- `just pocket-id apply` also syncs the client secrets into the `HomeOps/pocket-id-clients` 1Password item — keep that side effect intact. Raw `terraform apply` skips it and leaves every consuming ExternalSecret stale.
- **A client secret is readable exactly once**, at creation. It lives in Terraform state and in 1Password, nowhere else; losing both means recreating the client (`just pocket-id rotate <app>`).
- The workspace runs in **local execution mode** on purpose: the admin API is reachable only through `envoy-internal`, because the public HTTPRoute returns 403 for any request carrying `X-API-KEY`. A remote-executed plan can never reach it.
- `.env`, `.terraform/`, `.terraform.lock.hcl`, and state files are operational artifacts — do not refactor them as source configuration.

## Route Auth Guard

`clients.yaml` is also the coverage registry: every hostname published under `kubernetes/` must be a `clients` subdomain or an `exempt` key, never both. `exempt.<sub>` needs `reason`, `control` (the compensating control) and `gateways` (where it may attach); `redirect_only: true` allows only backend-less routes on the `http` listener; `temporary: true` needs `tracking: <BM permalink>` and prints a warning on every run.

Layer 1 rules (offline; pre-commit, `just pocket-id lint`, CI):

- **R1** after the owner Kustomization's `postBuild.substitute`, each hostname is `<sub>.${PUBLIC_DOMAIN}` or `*.${PUBLIC_DOMAIN}`; **OWN** each route file lies under some Flux Kustomization `spec.path`.
- **R2** each `<sub>` is claimed by a client or an exemption.
- **R3** a gate envoy host is published by exactly one route with exactly one hostname (the `gateway-oidc` redirectURL is single-host), and its Kustomization includes `components/gateway-oidc` with `APP` = client key and `APP_SUBDOMAIN` (or `APP`) = subdomain.
- **R4** a gate native host has no `gateway-oidc` in front of it.
- **R5** an exempt host attaches only to its listed gateways.
- **R6** no client or exemption is left without a route.
- **R7** a route without hostnames attaches only to `http` listeners.
- **REG / PARSE** registry consistency (empty or undefined groups, mandatory exemption fields) and unparsable YAML, both fail closed.

Discovery keys on any map with a `hostnames` list or `parentRefs`, in any document kind, so chart-specific route paths (`server.route`, a flat `route:`) are covered. Layer 2 additionally catches routes that only a render shows (chart defaults, `valuesFrom`) and a dropped or partial render (per-subdomain route-count parity). When `components/gateway-oidc` changes its redirect or target contract, update R3 and L2.3 with it.

The guard proves that a gate is declared and wired, not that the app enforces it: a native app with a local password path still passes.

## Validation

- `just pocket-id lint` after any `clients.yaml` or `ks.yaml` change; it is also the first dependency of `plan` and `apply`.
- `provision/pocket-id/tests/run.sh` after changing `lint.sh` or `lint-rendered.sh` (pre-commit runs it too).
- `just pocket-id audit` queries the running IdP and fails on any client whose group restriction is off — this is what catches a client created in the admin UI behind Terraform's back.
- Use repo-local skills for detailed procedures:
  - shared recipe-runner conventions: `.claude/skills/just/`
  - downstream OIDC gate and trust-boundary impact: `.claude/skills/security-review/`
