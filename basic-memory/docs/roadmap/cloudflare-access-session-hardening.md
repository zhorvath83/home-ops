---
title: cloudflare-access-session-hardening
type: roadmap
permalink: home-ops/docs/roadmap/cloudflare-access-session-hardening
topic: Tighter Cloudflare Access sessions + step-up for sensitive apps
status: proposed
priority: medium
scope: Shorten the Access session duration for the unrestricted-users policy and layer
  a cluster-side identity gate on sensitive apps, reducing the value of any single
  compromised SSO session.
rationale: Shorter sessions plus an independent second gate mean a single stolen browser
  session or phished IdP account no longer yields long-lived, unrestricted access
  — cheap, config-only hardening on the highest-value access path.
related_areas:
- cloudflare
- iam
options:
- Uniform shorter session
- Per-app session tiers by sensitivity
---

# Tighter Cloudflare Access sessions + step-up for sensitive apps

## Metadata (observation-form, schema validation)

- [topic] Tighter Cloudflare Access sessions + step-up for sensitive apps
- [status] proposed
- [priority] medium

## What we gain

- A compromised session expires quickly instead of lasting weeks.
- Sensitive apps require passing two independent identity systems.
- No new components — configuration-only change on the edge.

## What to do

1. Reduce session_duration on the unrestricted-users Access policy from 720h to a modest value (e.g. 24h).
2. Layer cluster-side forward-auth on the sensitive apps (coordinated with forward-auth-coverage-external-data-apps).
3. Consider WARP/device-posture or shorter re-auth on the most sensitive hostnames.
4. Verify: session expiry is enforced and sensitive apps prompt for the second gate.

## Options

1. Uniform shorter session
2. Per-app session tiers by sensitivity

## Related

- relates_to [[cloudflare]]
- relates_to [[iam]]
- relates_to [[forward-auth-coverage-external-data-apps]]
