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

## Execution plan (research-backed)

### Current state
- The wildcard "Private Cloud" Access app (`provision/cloudflare/access.tf:135-149`, `domain = "*.${var.CF_DOMAIN_NAME}"`) has `session_duration = "720h"` (30 days) and attaches the `unrestricted_users_policy` (precedence 2) + the `service_token_auth` non-identity policy (precedence 1). "Private Cloud Photos" (:156-159) also `session_duration = "720h"`.
- Single IdP: "Sign in with Google" (`access.tf:121`).

### Target state
- Access sessions are short enough that a stolen session/token has limited lifetime; sensitive apps additionally require a cluster-side identity gate.

### Implementation steps
1. **Shorten the session** on `access.tf:139` (and :159 for Photos): change `session_duration = "720h"` → `"24h"` (or `"8h"` for the most sensitive). This is a one-line change per app.
2. **Layer the cluster-side second gate** on the sensitive data apps — implemented by `forward-auth-coverage-external-data-apps` (Pocket-ID/TinyAuth). Together they give two independent identity systems.
3. **(Optional) Require device posture / WARP** on the most sensitive hostnames via an Access policy `require` block, or a shorter re-auth. Evaluate against family usability.
4. `just cloudflare plan` → expect only the `session_duration` field to change. Commit: `🔒 fix(cloudflare): shorten Access session duration`.

### Verification
- `just cloudflare plan` shows only session_duration diffs.
- After apply: an idle session forces re-auth after the new window (test by waiting past the shorter duration or inspecting the Access session cookie TTL).

### Rollback & safety
- Revert the field values, re-apply. No structural change.
- **Risk:** very short sessions annoy family users (frequent re-login). 24h is a reasonable balance; tune up if painful. Passkey re-auth via Pocket-ID is quick.

### Gotchas & dependencies
- The real defense-in-depth comes from pairing with `forward-auth-coverage-external-data-apps`; session shortening alone reduces window but not the single-gate dependency.

### Effort
S (~30 min for the session change; the second gate is tracked separately).
