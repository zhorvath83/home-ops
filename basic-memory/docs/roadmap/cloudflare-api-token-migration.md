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
