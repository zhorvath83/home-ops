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
