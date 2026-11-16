---
title: cloudflare-access-decommission
type: roadmap
permalink: home-ops/docs/roadmap/cloudflare-access-decommission
topic: Retire Cloudflare Access — Pocket ID (gateway-oidc or native OIDC) becomes
  the only identity gate on every public host
status: proposed
priority: medium
scope: 'Remove all Cloudflare Access applications, policies, groups, the Google IdP
  and the mobile service token from provision/cloudflare/access.tf, plus the 1Password
  write-back. The Cloudflare Tunnel, WAF/firewall rules and DNS stay (their retirement
  belongs to cloudflare-tunnel-to-towonel). Gated on route-auth-coverage-guard: every
  public hostname must provably have a Pocket ID gate first.'
rationale: 'Since 2026-11-16 every public host has its own Pocket ID gate (gateway-oidc
  or native OIDC with local password paths blocked), so Access is a second login on
  top: Google sign-in before the Pocket ID passkey (fenykepek, dash, fin, echo), service-token
  headers for the Paperless/Mealie apps, and bypass entries that already rely on the
  app alone (books, share, idm). It keeps a second identity store (email lists in
  Terraform vars, a Google OAuth client) in sync by hand, and it hands Cloudflare
  the identity layer of traffic it already decrypts.'
options:
- Retire Access entirely after the guard proves coverage — RECOMMENDED
- Keep Access only on the most sensitive hosts (docs, fin, fenykepek) as a deliberate
  second factor
- Keep everything until the towonel cutover removes Access as a side effect
related_areas:
- cloudflare
- iam
- networking
---

# Cloudflare Access decommission

## Metadata (observation-form, schema validation)

- [topic] Retire Cloudflare Access — Pocket ID becomes the only identity gate on every public host
- [status] proposed
- [priority] medium
- [researched_at] 2026-11-16
- [effort] S–M

## What we gain

- One login per app: the Pocket ID passkey, with no Google sign-in in front of it.
- One identity source of truth. Today access is managed twice: Pocket ID groups (admin UI) and Access groups (email lists in `CF_ACCESS_UNRESTRICTED_USERS` / `CF_ACCESS_RESTRICTED_USERS`), and the two can drift.
- Mobile apps stop needing Cloudflare service-token headers: Swift Paperless and the Mealie app authenticate exactly as on the LAN.
- A smaller Cloudflare surface: Access apps, groups, policies, the Google OAuth client, the service token and its 1Password write-back `null_resource`.
- Prepares, and shrinks, Phase 5b of [[cloudflare-tunnel-to-towonel]].

## What we lose / accept

- **The deliberate two-system design goes away.** [[cloudflare-access-session-hardening]] (done) layered Pocket ID behind Access so that "sensitive apps require passing two independent identity systems". After this item, a phished or stolen Pocket ID session is enough on its own. Mitigations: passkey-only Pocket ID (phishing-resistant), per-app group ACLs, short Pocket ID sessions, CrowdSec and the HU-only geo gate. Decision D1 below.
- **Pre-auth app surfaces become internet-reachable** for HU source IPs: anything an app serves before login (paperless `/api/schema/` and `/api/remote_version/`, mealie `/api/app/about`, pingvin `/api/configs`, homepage `/api/healthcheck`, sure's `/sessions/new`, calibre `/static`). Behind Access only signed-in Google users saw these on the wildcard hosts. Per the 2026-11-16 audit they carry no secrets, but each app's unauthenticated code path now faces the internet.
- Cloudflare-side login telemetry (Access audit logs) disappears. Pocket ID's own audit log and login notifications remain.

## Current state (provision/cloudflare/access.tf, 2026-11-16)

| Access app | Domain | Policy | Effect today |
|---|---|---|---|
| `private_cloud` | `*.${domain}` | unrestricted users (Google), 24h | Google login before every host without its own app: dash, fin, echo, … |
| `paperless` | `docs` | service token (non_identity), then unrestricted users | mobile app via token headers, browser via Google |
| `mealie` | `recipes` | service token, then unrestricted users | same |
| `private_cloud_photos` | `fenykepek` | restricted users (Google) | Google, then the Pocket ID gate (since 2026-11-16) |
| `public_bypass` (for_each) | `www`, `share`, `idm`, `books` | bypass everyone | the app alone |
| `flux_webhook` | `flux-webhook` | bypass, GitHub hooks CIDRs | GitHub only; the route SecurityPolicy and the Flux HMAC also check |

Also: groups `UnrestrictedUsers` / `RestrictedUsers`, the Google IdP (`CF_ACCESS_GOOGLE_CL_ID/SECRET`), the `MobileAppsServiceToken` and its `op item edit cloudflare …` write-back.

- [fact] Every host reachable through envoy-external has a Pocket ID gate or is a justified exemption (route-auth-coverage-guard, live audit 2026-11-16): gateway-oidc (echo, fenykepek), native OIDC (docs, recipes, share, dash, fin, books — with paperless password paths and calibre OPDS/Kobo blocked at the route), the IdP itself (idm), and flux-webhook (CIDR + HMAC).
- [fact] `www` has a DNS-only (unproxied) record to the apex, so its Access bypass app has no effect on real traffic.

## Plan

### Phase 0 — Preconditions (blocking)
- route-auth-coverage-guard L1 is live and green. No public host may rely on Access as its only gate. Today this holds by audit; the guard makes it hold by construction.
- Paperless web login and Swift Paperless OIDC confirmed working against the public paperless client (2026-11-16 change).
- D1 decided.

### Phase 1 — Mobile apps first
- In Swift Paperless and the Mealie app, remove the Access service-token headers. They stay harmless while Access exists, and Phase 2 makes them unnecessary.

### Phase 2 — Terraform
- Remove from `access.tf`: all `cloudflare_zero_trust_access_application` resources, the access policies, groups, the Google IdP, the service token and the `null_resource` write-back. Remove the now-unused variables (`CF_ACCESS_*`) from `variables.tf`, `terraform.tfvars` and `.env`. Keep the GitHub-hooks `data.http` source if `firewall_rules.tf` still uses it.
- `just cloudflare plan`: expect only Access destroys. `just cloudflare apply`.
- 1Password: remove the `CF-Access-Client-Id/Secret` fields from the `cloudflare` item and the Google OAuth client credentials. Revoke the OAuth client in Google Cloud.

### Phase 3 — Verify (from outside the LAN, e.g. mobile data)
- Each public host answers with its own gate, not a Cloudflare Access page: gateway-oidc hosts 302 to `idm/authorize`, native apps show their SSO login, `books`/`share`/`idm` unchanged.
- `/opds`, `/kobo`, paperless Basic and `/api/token` POST still 403. A non-HU request is still 403 (geo gate). GitHub webhook redelivery still 200.

### Phase 4 — Docs
- `provision/cloudflare/CLAUDE.md`, `kubernetes/apps/networking/CLAUDE.md` (it mentions "Hosts behind the Cloudflare Access wildcard are still gated by Access first"), the cloudflare-terraform skill (user-applied), BM `docs/areas/cloudflare` and `iam`. Update [[cloudflare-tunnel-to-towonel]] Phase 5b to drop `access.tf` from its list.

## Decisions needed

- **D1 — Second factor**: retire Access everywhere (RECOMMENDED: the passkey-only IdP is phishing-resistant, and two logins per app are friction for little gain), or keep Access on docs / fin / fenykepek as a deliberate second identity system (keeps the session-hardening design for the most sensitive data).
- **D2 — Order versus towonel**: do this first, independently (RECOMMENDED: small and reversible, and it removes a towonel blocker for the mobile apps), or fold it into the towonel cutover.

## Risks & mitigations

- **A host silently relied on Access** → Phase 0 makes the guard a precondition; Phase 3 tests every public host from outside.
- **A pre-auth app endpoint has an exploitable bug** → the same exposure the bypass hosts (books, share, idm) already have. Keep apps patched (Renovate), and keep CrowdSec AppSec and the geo gate in front.
- **Rollback**: `git revert` of the Terraform change + `just cloudflare apply` restores Access in minutes. Re-issued service-token values must then be re-entered in the mobile apps.

## Acceptance criteria

1. `just cloudflare plan` after the change shows no Access resources, and `apply` succeeded.
2. From outside the LAN every public host shows its Pocket ID gate (or the app's SSO login), with no Cloudflare Access interstitial.
3. Swift Paperless and the Mealie app work without service-token headers.
4. The Phase 3 negative checks (geo 403, path 403s, GitHub webhook 200) pass.
5. Docs and BM updated; towonel Phase 5b trimmed.

## Related

- relates_to [[route-auth-coverage-guard]] (precondition)
- relates_to [[cloudflare-tunnel-to-towonel]]
- relates_to [[cloudflare-access-session-hardening]] (design this reverses)
- relates_to [[cloudflare]]
- relates_to [[iam]]
