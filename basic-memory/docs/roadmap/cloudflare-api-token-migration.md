---
title: cloudflare-api-token-migration
type: roadmap
permalink: home-ops/docs/roadmap/cloudflare-api-token-migration
topic: Cloudflare Terraform provider auth hardening — Global API Key → scoped API
  Token
status: proposed
priority: medium
scope: 'Migrate provision/cloudflare Terraform provider authentication from the account
  Global API Key (var.CF_GLOBAL_APIKEY + var.CF_USERNAME) to a scoped API Token whose
  permissions cover exactly the managed surface: Zone DNS/settings/WAF/Rulesets, Workers
  + KV + Routes, R2, Zero Trust Access apps/groups/service-tokens, Tunnel, account
  resources, notifications.'
rationale: A scoped token limits the provider credential to exactly the resources
  this repo manages, so the blast radius of that credential shrinks from the whole
  Cloudflare account to just the home-ops surface — and a scoped token used elsewhere
  (delete_stale_tunnels.sh) already proves the pattern works here.
options:
- Single all-in-one token — lowest churn, one rotation point (recommended)
- Split per-product tokens — smaller per-token blast radius but needs aliased provider
  blocks and per-resource provider= references
related_areas:
- cloudflare
---

# Cloudflare Terraform provider auth hardening — Global API Key → scoped API Token

## Metadata (observation-form, schema validation)

- [topic] Cloudflare Terraform provider auth hardening — Global API Key → scoped API Token
- [status] proposed
- [priority] medium

## What we gain

- The Terraform credential can touch only what home-ops manages — unrelated zones, Workers, and Access apps are out of its reach.
- The token is independently rotatable and revocable without disturbing the account key.
- Aligns with Cloudflares documented best practice and with the scoped token already in use by delete_stale_tunnels.sh.

## What to do

1. Replace the provider api_key + api_user_service_key with api_token in provision/cloudflare/main.tf.
2. Create a scoped token covering the full managed permission set (list above); add it to the 1Password cloudflare item; swap the .env vars injected via op run.
3. Reproduce a clean just cloudflare plan, then retire CF_GLOBAL_APIKEY + CF_USERNAME.
4. Verify: just cloudflare plan/apply succeeds with the scoped token and no permission gaps.

## Options

1. Single all-in-one token — lowest churn, one rotation point (recommended)
2. Split per-product tokens — smaller per-token blast radius but needs aliased provider blocks and per-resource provider= references

## Related

- relates_to [[cloudflare]]
- relates_to [[cloudflare-tls-and-tfvar-hygiene]]

## Execution plan (research-backed)

### Current state
- Provider authenticates with the account Global API Key: `provision/cloudflare/main.tf:46-49` → `provider "cloudflare" { ... api_key = var.CF_GLOBAL_APIKEY }` (+ email/`CF_USERNAME`). Provider is `cloudflare/cloudflare` **v5.22.0** (main.tf:19-21) — resources are v5 (`cloudflare_zone_setting`, `cloudflare_zero_trust_access_*`).
- A scoped token already exists and is proven: used as a Bearer by `delete_stale_tunnels.sh` (`op://HomeOps/cloudflare/apitoken_1`).
- Vars in `provision/cloudflare/variables.tf`: `CF_GLOBAL_APIKEY` (:136), `CF_USERNAME` (:131). TF runs via `op run --env-file=./.env -- terraform` (`provision/cloudflare/mod.just`).

### Target state
- The Terraform provider uses a scoped API Token limited to exactly the managed surface; the Global API Key is retired from this stack.

### Implementation steps
1. **Enumerate required permissions from the actual resources** in `provision/cloudflare/*.tf`:
   - Zone → DNS: Edit (`dns_records.tf`)
   - Zone → Zone Settings: Edit (`zone_settings.tf`)
   - Zone → Zone WAF / Config Rules / Rulesets: Edit (`firewall_rules.tf`)
   - Account → Cloudflare Tunnel: Edit (`tunnel.tf`)
   - Account → Access: Apps and Policies + Access: Service Tokens: Edit (`access.tf`)
   - Account → Workers Scripts + Workers KV Storage + Zone → Workers Routes: Edit (`workers.tf`)
   - Account → Workers R2 Storage: Edit (if R2 managed)
   - Account → Notifications: Edit (`notification.tf`)
   - Zone → Zone: Read (baseline)
   Create the token in the Cloudflare dashboard (My Profile → API Tokens → Create Custom Token) scoped to the home-ops zone + account only.
2. **Add the token to 1Password** (`op://HomeOps/cloudflare` item, e.g. field `TF_VAR_CF_API_TOKEN`) and reference it in `provision/cloudflare/.env`.
3. **Edit the provider block** `provision/cloudflare/main.tf:46-49`:
   ```hcl
   provider "cloudflare" {
     api_token = var.CF_API_TOKEN
   }
   ```
   Add `variable "CF_API_TOKEN" { type = string, sensitive = true }` to variables.tf; remove the `api_key`/email lines once the plan is clean.
4. **Reproduce a clean plan:** `just cloudflare plan` (via op run) → must show **no changes** (auth swap only, not resource changes). Fix token scope until plan is clean.
5. **Retire** `CF_GLOBAL_APIKEY` + `CF_USERNAME` from .env and variables.tf. Commit: `🔒 refactor(cloudflare): scoped API token for TF provider`.

### Verification
- `just cloudflare plan` → "No changes" with the token.
- A deliberately out-of-scope action (e.g. touching an unrelated zone) would be denied — confirms scoping.

### Rollback & safety
- Revert main.tf/variables.tf/.env to the Global API Key. State is unaffected (auth method change only).
- **Risk:** a missing permission makes `terraform apply` fail mid-run (partial apply). Do a full `plan` + a no-op `apply` first; keep the Global API Key available until the token is proven across a real apply.

### Gotchas & dependencies
- v5 provider: confirm attribute name is `api_token` (it is in cloudflare/cloudflare v5).
- Enable `sensitive=true` on the new var (see `cloudflare-tls-and-tfvar-hygiene`).
- Token needs BOTH zone-scoped and account-scoped permissions (Access/Tunnel/Workers/R2 are account-level).

### Effort
M (~3–4h, mostly getting the permission scope exactly right).
