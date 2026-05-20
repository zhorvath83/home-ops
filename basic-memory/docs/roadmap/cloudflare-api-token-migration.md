---
title: cloudflare-api-token-migration
type: roadmap
permalink: home-ops/docs/roadmap/cloudflare-api-token-migration
topic: Cloudflare Terraform provider auth hardening — Global API Key → scoped API
  Token
status: proposed
priority: medium
scope: 'Migrate provision/cloudflare/ Terraform provider authentication from Global
  API Key + account email (var.CF_GLOBAL_APIKEY + var.CF_USERNAME) to a scoped API
  Token. Touchpoints: provider block, 1Password ''cloudflare'' item, .env via op run,
  and the token permission set covering DNS/WAF/Workers/R2/Access/Tunnel/notifications.'
rationale: Global API Key has full-account blast radius. The cloudflare area-reference
  explicitly flags this as a 'hardening follow-up rather than current blocker'. Scoped
  API Tokens limit blast radius and are Cloudflare's recommended Terraform pattern.
options:
- Single all-in-one token — lowest churn, one rotation point
- Split per-product tokens — smaller blast radius per token but requires multiple
  aliased provider blocks and per-resource provider= references
related_areas:
- cloudflare
---

# Cloudflare Terraform provider auth hardening — Global API Key → scoped API Token

## Metadata (observation-form, schema validation)
- [topic] Cloudflare Terraform provider auth hardening — Global API Key → scoped API Token
- [status] proposed
- [priority] medium

## Scope
Migrate the `provision/cloudflare/` Terraform provider authentication from Cloudflare's Global API Key + account email model (`var.CF_GLOBAL_APIKEY` + `var.CF_USERNAME`, provision/cloudflare/main.tf:46-49, variables.tf:131-139) to a scoped API Token model.

Touchpoints:
1. `provision/cloudflare/main.tf` provider block — replace `api_key` + `api_user_service_key` with `api_token`
2. 1Password `cloudflare` item — add the new token field; retire `CF_GLOBAL_APIKEY` + `CF_USERNAME` once a clean `just cloudflare plan` is reproduced
3. `.env` template injected via `op run --no-masking --env-file=./.env -- terraform ...` — swap the variables
4. Token permission set must cover every resource type currently in the stack: Zone DNS edit, Zone settings + WAF + Rulesets, Workers + Workers KV + Workers Routes, R2 + R2 custom domain, Zero Trust Access apps + groups + service tokens, Cloudflare Tunnel, Account-level resources, notification policies

## Rationale
The Global API Key has full-account blast radius; a leaked token destroys the entire Cloudflare account, including any unrelated zones, Workers, and Access apps not managed by this repo. The `docs/areas/cloudflare` area-reference flags this as **"a hardening follow-up rather than current blocker"** — explicit deferred work, not a drift risk. Scoped API Tokens narrow the blast radius to the actual managed surface and are Cloudflare's documented best practice for Terraform.

The migration is not a current blocker because the home-ops account is single-tenant and the credential is held only in 1Password + Terraform Cloud. The cost of the migration is reproducing the right permission scope on the new token without breaking `just cloudflare apply`.

## Options
1. **Single all-in-one token** — one token with the union of all permissions; lowest operational cost; one secret rotation point
2. **Split per-product tokens** — separate tokens for DNS, Workers, R2, Access; smaller blast radius per token, but the Terraform provider only accepts one `api_token` value so this would require multiple aliased provider blocks and resource-level `provider =` references — significantly more churn

## Related
- relates_to [[cloudflare]]
