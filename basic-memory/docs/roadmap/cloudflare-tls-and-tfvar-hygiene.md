---
title: cloudflare-tls-and-tfvar-hygiene
type: roadmap
permalink: home-ops/docs/roadmap/cloudflare-tls-and-tfvar-hygiene
topic: Edge TLS floor + sensitive-variable hygiene (Cloudflare)
status: proposed
priority: low
scope: Raise the Cloudflare zone minimum TLS to 1.3 to match the origin, and mark
  the sensitive Cloudflare Terraform variables sensitive=true.
rationale: A consistent TLS 1.3 floor and sensitive-marked variables give a clean,
  uniform edge posture and keep secrets out of plan/CI output.
related_areas:
- cloudflare
---

# Edge TLS floor + sensitive-variable hygiene (Cloudflare)

## Metadata (observation-form, schema validation)

- [topic] Edge TLS floor + sensitive-variable hygiene (Cloudflare)
- [status] proposed
- [priority] low

## What we gain

- Uniform TLS 1.3 from client to origin — no weaker leg.
- Secrets never surface in terraform plan / CI logs.
- Low-effort consistency with the OVH stacks existing hygiene.

## What to do

1. Set the zone min_tls_version to 1.3 (confirm no legacy client needs 1.2).
2. Mark CF_GLOBAL_APIKEY (until the token migration lands), CF_TUNNEL_SECRET, and CF_ACCESS_GOOGLE_CL_SECRET as sensitive=true.
3. Verify: plan output masks the secrets and sites negotiate 1.3.

## Related

- relates_to [[cloudflare]]
- relates_to [[cloudflare-api-token-migration]]

## Execution plan (research-backed)

### Current state
- Zone minimum TLS is below the origin: `provision/cloudflare/zone_settings.tf:14-16` (`cloudflare_zone_setting "min_tls_version"`) is set to 1.2 while the origin ClientTrafficPolicy enforces 1.3; `tls_1_3` is enabled (:26-28).
- Sensitive vars not all marked sensitive: `provision/cloudflare/variables.tf` — `CF_ACCESS_GOOGLE_CL_SECRET` (:121), `CF_GLOBAL_APIKEY` (:136), `CF_TUNNEL_SECRET` (:141) lack `sensitive = true` (only one var at :157 has it). OVH's variables.tf marks its secrets consistently.

### Target state
- Uniform TLS 1.3 floor from client to origin; all secret TF variables marked `sensitive = true` so they never print in plan/CI output.

### Implementation steps
1. **Raise min TLS.** Edit `provision/cloudflare/zone_settings.tf:14-16` → set the `min_tls_version` value to `"1.3"`. Confirm first that no legacy client (old phone, IoT) still needs 1.2 — check Cloudflare Analytics → Traffic → TLS version distribution.
2. **Mark secrets sensitive.** In `provision/cloudflare/variables.tf` add `sensitive = true` to `CF_GLOBAL_APIKEY` (:136), `CF_TUNNEL_SECRET` (:141), `CF_ACCESS_GOOGLE_CL_SECRET` (:121). (If `cloudflare-api-token-migration` lands first, the new `CF_API_TOKEN` var should also be sensitive and `CF_GLOBAL_APIKEY` is removed.)
3. `just cloudflare plan` → expect only the min_tls_version change (marking a var sensitive is not a resource diff). Commit: `🔒 fix(cloudflare): TLS 1.3 floor + sensitive tfvars`.

### Verification
- `just cloudflare plan` output masks the secret var values (shows `(sensitive value)`).
- After apply: `curl -sI --tls-max 1.2 https://<host>` fails the handshake; TLS 1.3 succeeds. Cloudflare dashboard shows min TLS 1.3.

### Rollback & safety
- Revert the value to "1.2" / remove sensitive markers, re-apply. Trivial.
- **Risk:** a legacy client stuck on TLS 1.2 loses access — check the TLS-version analytics before flipping; roll back to 1.2 if something breaks.

### Gotchas & dependencies
- Coordinate with `cloudflare-api-token-migration` (the CF_GLOBAL_APIKEY var may be replaced).

### Effort
S (~30 min + a glance at TLS analytics).
