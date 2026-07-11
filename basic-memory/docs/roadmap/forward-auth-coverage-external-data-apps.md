---
title: forward-auth-coverage-external-data-apps
type: roadmap
permalink: home-ops/docs/roadmap/forward-auth-coverage-external-data-apps
topic: Second independent identity gate on the external data apps
status: proposed
priority: high
scope: Bring the internet-exposed personal-data apps (paperless/docs, actual/pfm,
  photos, books, subscriptions) behind the cluster-side Pocket-ID / TinyAuth layer
  that already protects the downloads apps, and scope the Cloudflare Access mobile
  service token to only what needs non-browser access.
rationale: 'A cluster-side identity gate makes the data apps defense-in-depth: access
  then requires passing both Cloudflare Access and Pocket-ID/TinyAuth, so no single
  edge credential or misconfiguration exposes personal data.'
related_areas:
- iam
- networking
- cloudflare
options:
- OIDC-native per app where supported
- forward-auth via TinyAuth for the rest
---

# Second independent identity gate on the external data apps

## Metadata (observation-form, schema validation)

- [topic] Second independent identity gate on the external data apps
- [status] proposed
- [priority] high

## What we gain

- Personal-data apps gain a second, independent, passkey-backed authn factor on top of the edge.
- The mobile service token stops being a skeleton key — its reach shrinks to exactly the app(s) that need programmatic access.
- Uniform auth posture across all externally-exposed apps.

## What to do

1. Extend the existing forward-auth component (or OIDC-native SecurityPolicy) to docs/pfm/photos/books/subscriptions with per-app Pocket-ID group ACLs.
2. Prefer OIDC-native where supported (paperless, actual), forward-auth otherwise.
3. Narrow the Cloudflare Access service-token policy so non-identity access is granted only to the specific app(s) that require it, not the whole wildcard.
4. Verify each app: browser SSO works; the service token reaches only its intended app.

## Options

1. OIDC-native per app where supported
2. forward-auth via TinyAuth for the rest

## Related

- relates_to [[sso-implementation]]
- relates_to [[iam]]
- relates_to [[networking]]
- relates_to [[cloudflare]]

## Execution plan (research-backed)

### Current state (live)
- Externally-exposed data apps on `envoy-external` with **no cluster-side SecurityPolicy** (CF Access is their only gate) — from live `kubectl get httproute -A` + `kubectl get securitypolicy -A`:
  | App | Host | OIDC-native support | Recommended gate |
  |---|---|---|---|
  | selfhosted/paperless | docs.* | yes (paperless-ngx OIDC via django-allauth) | app-native OIDC |
  | selfhosted/actual | pfm.* | yes (ACTUAL_OPENID_* env) | app-native OIDC |
  | selfhosted/mealie | recipes.* | yes (mealie OIDC_* env) | app-native OIDC |
  | selfhosted/home-gallery | photos.*, fenykepek.* | no native OIDC | forward-auth |
  | selfhosted/wallos | subscriptions.* | no | forward-auth |
  | media/calibre-web-automated | books.* | weak/none | forward-auth |
  | selfhosted/pingvin-share-x | share.* | native (Pocket-ID) + public by design | keep public share; ensure admin behind OIDC |
- Existing cluster-side auth (`kubectl get securitypolicy -A`): only `downloads/*-forward-auth` (8 apps), `kube-system/hubble-ui-forward-auth`, `networking/echo-forward-auth`. None of the data apps.
- ReferenceGrant `kubernetes/apps/security/tinyauth/app/referencegrant.yaml` already lists `selfhosted` (:15) and `media` (:18) — **no ReferenceGrant change needed** for these apps.
- CF service-token (`provision/cloudflare/access.tf:99-106`, precedence 1 on the `*.domain` app) grants non-identity access to all of the above.

### Target state
- Every external data app requires a Pocket-ID identity (app-native OIDC where supported, TinyAuth forward-auth otherwise) in addition to Cloudflare Access; the CF mobile service token is scoped to only the app(s) that truly need programmatic access.

### Implementation steps

**A. Forward-auth apps (home-gallery, wallos, calibre-web-automated)** — copy the proven downloads pattern.
1. For each, in the app's `ks.yaml` add:
   ```yaml
   spec:
     components: [../../../../components/forward-auth]
     postBuild:
       substitute: { APP: <route-name> }   # must equal the HTTPRoute name (home-gallery, wallos, calibre-web-automated)
   ```
   (Mirror `kubernetes/apps/downloads/sonarr/ks.yaml:13,25-26`.)
2. **Define the per-app TinyAuth ACL BEFORE attaching** (nil-ACL trap → default allow): add `TINYAUTH_APPS_<NAME>_OAUTH_GROUPS` (e.g. `TINYAUTH_APPS_HOME_GALLERY_OAUTH_GROUPS`) scoped to the allowed Pocket-ID group, in the tinyauth config/ExternalSecret.
3. Reconcile and test each app before moving on.

**B. OIDC-native apps (actual, paperless, mealie)** — app does its own OIDC against Pocket-ID (pattern from `docs/roadmap/sso-implementation`, "First OIDC-native App: Actual Budget").
1. In the **Pocket-ID UI**, create an OIDC client per app (name, callback URL). Callbacks: actual → `https://pfm.${DOMAIN}/openid/callback`; paperless → `https://docs.${DOMAIN}/accounts/oidc/<provider>/login/callback/`; mealie → `https://recipes.${DOMAIN}/login` (verify each app's docs). Restrict the client to the allowed group.
2. Store `client_id`/`client_secret` in a per-app 1Password item; wire a per-app `ExternalSecret` (pattern: `kubernetes/apps/external-secrets/CLAUDE.md`) — never inline the secret.
3. Set the app's OIDC env from that secret:
   - actual: `ACTUAL_OPENID_DISCOVERY_URL=https://id.${DOMAIN}`, `ACTUAL_OPENID_CLIENT_ID`, `ACTUAL_OPENID_CLIENT_SECRET` (needs server ≥25.1.0).
   - paperless: `PAPERLESS_APPS=allauth.socialaccount.providers.openid_connect` + `PAPERLESS_SOCIALACCOUNT_PROVIDERS` JSON pointing at `https://id.${DOMAIN}/.well-known/openid-configuration`.
   - mealie: `OIDC_AUTH_ENABLED=true`, `OIDC_CONFIGURATION_URL=https://id.${DOMAIN}/.well-known/openid-configuration`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`.
4. **All OIDC endpoints use the public issuer** `https://id.${DOMAIN}/...` (per apps/security/CLAUDE.md, AD-023 rev4). If the app pod opts out of baseline egress (`custom-egress`), it must also carry `egress.home.arpa/allow-gateways` so the token exchange (which hairpins through envoy) isn't dropped by its own CNP.
5. Enable/require OIDC login and disable local-account signup where the app allows, so Pocket-ID is the only path.

**C. Scope the Cloudflare service token** (dovetails with `cloudflare-access-terraform-parity`).
1. Identify which app genuinely needs the mobile service token (non-browser/mobile client). If none do, consider removing the `service_token_auth` policy from the `*.domain` app entirely.
2. Otherwise create a **dedicated CF Access application** for only that hostname and attach the service-token policy there; remove it from the wildcard app so it no longer opens all data apps.

### Verification
- `kubectl get securitypolicy -A` → new `<app>-forward-auth` policies Accepted=True for the forward-auth apps.
- Browser test each app: hitting the host redirects to Pocket-ID (forward-auth) or the app's own OIDC login; only the allowed group gets in; local accounts can't bypass.
- OIDC apps: login round-trips through `id.${DOMAIN}` and lands authenticated.
- Service token no longer opens a non-designated app: with only the CF-Access-Client headers, a scoped-out host returns Access login instead of passing through.

### Rollback & safety
- Forward-auth: remove the `components`/`substitute` block from ks.yaml. OIDC-native: unset the OIDC env / disable the client. CF: revert the access.tf policy attachment.
- **Test ONE app first — recommend actual (pfm)** since sso-implementation already documents its exact flow. Verify end-to-end before doing the rest.
- **Risks:** (1) nil-ACL trap — always set the TinyAuth per-app OAuth-groups ACL before attaching forward-auth, or it silently allows all authenticated users; (2) a wrong OIDC callback URL locks you out of an app — keep an admin/local fallback until the flow is verified; (3) the `allow-gateways` egress label is required for custom-egress OIDC apps or the token exchange fails.

### Gotchas & dependencies
- `APP` substitution must equal the HTTPRoute name exactly.
- TinyAuth `TINYAUTH_AUTH_ACLS_POLICY: deny` is unavailable in the pinned v5.0.7 (per sso-implementation) — per-app OAuth-groups ACLs are mandatory, not optional.
- Pocket-ID client creation is a **manual UI step** per app (family-sized homelab convention) — not GitOps-managed.
- Ordering: pairs with `cloudflare-access-session-hardening` (shorter sessions) and `cloudflare-access-terraform-parity` (service-token scoping in code). `pingvin-share-x` stays intentionally public (share links) — only ensure its admin surface uses Pocket-ID.

### Effort
L (~1–1.5 days: ~3 forward-auth apps are quick copy-paste; the 3 OIDC-native apps each need a Pocket-ID client + ExternalSecret + app config + testing).


## Progress log

### 2026-07-11 — Step C (Cloudflare service-token scoping) implemented in Terraform

- [decision] Only **paperless (docs)** and **mealie (recipes)** use CF Access header-based auth (native mobile clients) — user-confirmed. No other externally-exposed app consumes the `MobileAppsServiceToken`.
- [evidence] The service-token credentials (`CF-Access-Client-Id`/`-Secret`) have **zero in-cluster consumers** — the only repo reference is the Terraform `op item edit` write-back (`provision/cloudflare/access.tf:14`). The token is used purely by external native clients, so scope is a user-only fact.
- [change] `provision/cloudflare/access.tf`: removed the `service_token_auth` (`non_identity`) policy from the wildcard `Private Cloud` app (`*.${CF_DOMAIN_NAME}`); added two dedicated `self_hosted` Access apps — `Paperless` (`docs.*`) and `Mealie` (`recipes.*`) — each keeping `service_token_auth` (prec 1) + `unrestricted_users_policy` (prec 2). Most-specific hostname wins over the wildcard (same mechanism the existing `fenykepek.*` app relies on).
- [effect] The mobile token can no longer bypass identity on every subdomain — only on `docs` and `recipes`. Every other host under the wildcard now requires Google-OAuth identity (unrestricted-users) in addition to the edge.
- [related] The same commit also shortened `session_duration` 720h→24h on the wildcard + photos apps (belongs to `cloudflare-access-session-hardening`; co-located in one file so committed together).
- [commit] `139ab76dd` 🔒 fix(cloudflare): scope mobile service-token to docs/recipes
- [validation] `tflint` clean; blocks fmt-clean; **authoritative `just cloudflare plan` NOT yet run** (`op` not signed in). Run `op signin && just cloudflare plan` then `just cloudflare apply` to reach live Cloudflare. Expected plan: +2 apps, wildcard app loses the service-token policy attachment, session_duration updates — no destroys.
- [status] Step C done-in-code (pending apply). Steps A (forward-auth for home-gallery/wallos/calibre) and B (OIDC-native for actual/paperless/mealie) remain **proposed / not started**.
- [verify-after-apply] With only `CF-Access-Client-*` headers, a scoped-out host (e.g. `pfm`, `books`, `photos`) must return the CF Access login instead of passing through; `docs` and `recipes` must still pass with the token.
