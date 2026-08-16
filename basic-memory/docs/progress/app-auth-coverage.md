---
title: app-auth-coverage
type: progress-note
permalink: home-ops/docs/progress/app-auth-coverage
status: in-progress
priority: high
area: iam
created: 2026-08-16
roadmap: docs/roadmap/app-auth-coverage
tags:
- progress
- iam
- oidc
- envoy-oidc
- pocket-id
- security
- app-auth-coverage
---

# app-auth-coverage — unified identity layer for every exposed app (implementation)

relates_to [[app-auth-coverage]] (roadmap), [[iam]], [[networking]], [[external-secrets]], [[k8s-workloads]]

## Session 2026-08-16 — Phase 1 repo edits (direct-to-main)

Goal: bring the 8 remaining exposed apps under the Pocket ID identity layer (envoy-oidc gate OR native OIDC) so none relies on app-local login. homepage was done 2026-08-15. home-gallery is an out-of-scope documented exception (Google OAuth later).

### What landed (repo, uncommitted)

**Pocket ID registry** (`provision/pocket-id/clients.yaml`): +4 groups, +8 clients.
- Groups: `paperless_admins`, `paperless_users`, `mealie_admins`, `mealie_users`.
- envoy clients (4): `backrest` (backup), `paperless-gpt` (paperless-gpt), `kopia` (pvbackup), `victoria-logs` (logs) — `gate: envoy`, `groups: [infra_admins]`.
- native clients (4): `mealie` (recipes, cb `/login`, `[mealie_admins, mealie_users]`), `paperless` (docs, cb `/accounts/oidc/pocket-id/login/callback/`, `[paperless_admins, paperless_users]`), `actual` (pfm, cb `/openid/callback`, `[infra_admins]`), `wallos` (subscriptions, cb `""`, `pkce_enabled: false`, `[infra_admins]`).

**envoy-oidc consumers** (4 ks.yaml): added `components/gateway-oidc` + `APP`/`APP_SUBDOMAIN` substitute + `dependsOn: pocket-id (security)` — backrest, paperless-gpt, kopia (created components+postBuild), victoria-logs (created components+dependsOn+postBuild).

**alertmanager** (`kube-prometheus-stack/app/helmrelease.yaml`): deleted the inline `alertmanager.route.main` HTTPRoute (never used). Alertmanager stays in-cluster-only (Service :9093). This removes alertmanager from auth-coverage scope (no exposed route remains) instead of gating it.

**pocket-id** (`security/pocket-id/app/helmrelease.yaml`): `EMAILS_VERIFIED: "false" → "true"` (mealie v3.21.0+ requires a verified-email claim; passkey is the real auth).

**native OIDC app wiring**:
- mealie: env (OIDC_AUTH_ENABLED, OIDC_CONFIGURATION_URL, OIDC_CLIENT_ID, OIDC_GROUPS_CLAIM, OIDC_USER_GROUP, OIDC_ADMIN_GROUP, OIDC_AUTO_REDIRECT, ALLOW_PASSWORD_LOGIN=false) + BASE_URL fixed `mealie.* → recipes.*`; ES extended with `OIDC_CLIENT_SECRET` + `data:` from `mealie_client_secret`. Callback `/login` (verified against mealie oidc-v2 docs).
- paperless: env (PAPERLESS_APPS=openid_connect, PAPERLESS_DISABLE_REGULAR_LOGIN, PAPERLESS_REDIRECT_LOGIN_TO_SSO, flipped SOCIALACCOUNT_ALLOW_SIGNUPS/SOCIAL_AUTO_SIGNUP true, SOCIAL_ACCOUNT_SYNC_GROUPS + claim=groups) + pod label `allow-gateways`; ES extended with `PAPERLESS_SOCIALACCOUNT_PROVIDERS` JSON blob (provider_id=pocket-id, client_id=paperless, secret interpolated, server_url=issuer, SCOPE includes groups, OAUTH_PKCE_ENABLED) + `data:` from `paperless_client_secret`. Callback `/accounts/oidc/pocket-id/login/callback/` (verified against django-allauth docs).
- actual: env (ACTUAL_OPENID_DISCOVERY_URL, CLIENT_ID, SERVER_HOSTNAME=https://pfm.*, AUTH_METHOD=openid, ENFORCE=true, USER_CREATION_MODE=login) + envFrom new `actual-secret` + pod label `allow-gateways`; NEW ExternalSecret (`actual_client_secret` → `ACTUAL_OPENID_CLIENT_SECRET`); kustomization updated; per-app CNP comment updated. Callback `/openid/callback` (verified against actualbudget.org docs).
- wallos: NO repo OIDC config — wallos OIDC is admin-UI-only (env-var OIDC is an unimplemented feature request, ellite/Wallos#1026). The `clients.yaml` registration stands; wiring is a Phase 3 manual admin-UI step. Callback bare-hostname `https://subscriptions.horvathzoltan.me` (callback_path "").

### Discoveries / corrections (vs roadmap)
- **wallos admin-UI-only** — deviation from the plan's "env + new ES" approach; env-var OIDC doesn't exist. Recorded; wallos remains `gate: native`, delivered via admin UI (like calibre-web-automated).
- **kopia** — roadmap said "HTTP Basic Auth"; reality `--without-password` + KOPIA_PASSWORD (no UI auth). envoy-oidc is clean (no double-gate).
- **victoria-logs vmauth-OIDC** — not a UI identity layer (JWT Bearer validation only); envoy-oidc gate chosen.
- **mealie** — roadmap caveat "keeps password login until redesign" is stale (v3.22.0 supports ALLOW_PASSWORD_LOGIN=false → disabled now). BASE_URL was wrong (`mealie.*` vs route `recipes.*`) — fixed.
- **EMAILS_VERIFIED** — global IdP flip (cleaner than per-app disabling) makes mealie's/wallos' verified-email checks pass.

### Validation
- `just pocket-id lint` — passes (clients.yaml ↔ ks.yaml agree; group refs exist; non-empty groups; wallos empty callback_path tolerated).
- `pre-commit run` on all 15 touched files — passes (yamlfmt/yamllint/gitleaks/secret checks).

### Next (Phase 2-4, user — needs op session + LAN)
1. `just pocket-id apply` (creates 8 clients + 8 `<app>_client_secret` 1Password fields; NEVER piped stdin — sync-secrets `op item edit` dies on non-TTY).
2. `just pocket-id audit` (zero unrestricted clients).
3. Commit-doc-commit + push (apply-before-push ordering so ExternalSecrets/SecurityPolicies don't go Pending/Invalid transiently; Flux deploys on push to main).
4. Pocket ID admin UI: assign user to `infra_admins` + the 4 new groups (paperless_admins/users, mealie_admins/users). Without this, group-restricted clients deny everyone.
5. backrest: set `{"auth":{"disabled":true}}` in `/data/config.json` (PVC, one-time, volsync-backed-up).
6. wallos: configure OIDC in Admin UI (issuer, client_id=wallos, client_secret from 1Password `wallos_client_secret`, redirect `https://subscriptions.horvathzoltan.me`, scopes `openid email profile`, disable password login).
7. victoria-logs: verify the chart-generated HTTPRoute is named `victoria-logs` in-cluster so the SecurityPolicy targetRef binds; if renamed, set `HTTPROUTE_NAME` in the ks.yaml substitute.
8. EMAILS_VERIFIED: confirm the existing user's `email_verified` claim is true (mealie login test); if Pocket ID only marks NEW users verified, a one-time admin-UI email-verify flip may be needed.
9. Per-app login tests: unauthenticated → 302 to idm.*; authenticated-as-allowed-group → admitted; authenticated-as-non-allowed-group → denied at the IdP. Confirm no app-local login is the primary gate.

### Risks open
- wallos bare-hostname callback (`callback_path: ""`): confirm Pocket ID accepts the no-path redirect URI and wallos completes the `?code=` on the base URL.
- paperless allauth JSON blob with embedded secret: validate the JSON renders and the secret interpolates on first reconcile.
- mealie logout redirect (`/login?direct=1` vs hardcoded bare logout_url in locals.tf): login works; logout may land on `/`. Minor.
- actual readiness probe (`httpGet path: /`) with `ACTUAL_OPENID_ENFORCE=true`: `/` likely 302s to OIDC (k8s counts 302 as success); verify the pod stays Ready.


## Deploy & verify (2026-08-16, continuation)

Phase 2 ran after the first push. Flux reconciled all 9 affected app Kustomizations
to the new revision; native OIDC ExternalSecrets (mealie, paperless, actual,
paperless-gpt-oidc) all reached SecretSynced=True.

Envoy-oidc SecurityPolicies: the envoy-gateway controller went Invalid across ALL 16
OIDC policies (existing + new) — its discovery fetch
(https://idm.*/.well-known/openid-configuration) timed out inside pocket-id's own Helm
rollout window (the EMAILS_VERIFIED flip restarted pocket-id). This is the documented
iam discovery-fetch fragility; remediated with
`kubectl rollout restart deployment/envoy-gateway -n networking` (user-approved).
After restart, 13/14 OIDC SecurityPolicies reached Accepted=True
(`status.ancestors[].conditions`, "Policy has been accepted.").

victoria-logs-oidc stayed unattached (empty status, no ancestor): the gateway-oidc
component defaults `targetRefs[].name` to `${APP}`=victoria-logs, but the chart
generates its HTTPRoute named `victoria-logs-server`. Fixed by overriding
`HTTPROUTE_NAME: victoria-logs-server` in
`kubernetes/apps/observability/victoria-logs/ks.yaml` (commit 62d9bc957); re-attaches
on the next Flux reconcile after push. Closes the Phase 3 "verify chart-generated
HTTPRoute name" item.

Still open (Phase 3/4): Pocket ID admin-UI group membership for the user (infra_admins +
paperless_*/mealie_*); backrest auth.disabled in PVC config.json; wallos admin-UI OIDC;
per-app login smoke (302 to idm, allowed-group admitted, non-allowed denied at IdP);
EMAILS_VERIFIED effect on the existing user.
## Wallos — OIDC via env (2026-08-16, continuation)

Switched wallos from the abandoned admin-UI path to env-based OIDC config (deployed 5.4.2 supports it: includes/oidc_settings.php -> wallos_get_effective_oidc_configuration overrides the admin-UI DB at runtime).

Files: app/externalsecret.yaml (NEW — wallos-secret from 1Password pocket-id-clients wallos_client_secret), app/kustomization.yaml (registered ES), app/helmrelease.yaml (OIDC env + envFrom). Commit 4ec102f07.

Env: OIDC_ENABLED, OIDC_PROVIDER_NAME=IdM, OIDC_CLIENT_ID=wallos, OIDC_ISSUER=https://idm.* (triggers .well-known discovery — auth/token/userinfo auto-populated by discoveryMap), OIDC_REDIRECT_URL=bare https://subscriptions.* (matches Pocket ID callback_path empty), OIDC_USER_IDENTIFIER=sub, OIDC_SCOPES="openid email profile", OIDC_AUTO_CREATE_USER=true, SSRF_ALLOWLIST=idm.*. Secret via envFrom.

Gotchas (deployed-source verified):
- SSRF guard: idm.* resolves in-cluster (k8s-gateway split DNS) to 10.245.247.245 (RFC1918); ssrf_helper.php FILTER_FLAG_NO_PRIV_RANGE blocks it. The admin-UI save error ("link-local or loopback") is misleading — all RFC1918 is blocked. SSRF_ALLOWLIST env (overrides the empty DB allowlist) is the bypass; covers OIDC endpoint URLs. Exact-host match, no wildcard.
- Discovery map (oidc_settings.php:204-207) auto-fills ONLY authorization_url/token_url/user_info_url. logout_url is NOT discovered (default empty) -> OIDC_LOGOUT_URL must be set explicitly (https://idm.*/api/oidc/end-session, from end_session_endpoint).
- require_email_verified defaults to 1 (required); global EMAILS_VERIFIED=true makes the claim always true -> no OIDC_REQUIRE_EMAIL_VERIFIED env needed.
- Bare-URL callback works: checksession.php:15 detects code+state on every page load (via index.php->header.php). So OIDC_REDIRECT_URL=bare hostname matches Pocket ID callback_path empty — no client change needed.
- Egress: live curl from the wallos pod reached idm at 10.245.247.245 (404 on GET /api/oidc/token) -> allow-world posture already reaches the in-cluster IdP; no allow-gateways label / CNP needed.

Deferred: OIDC_DISABLE_PASSWORD_LOGIN not set yet (lockout safety). Add in a follow-up after OIDC login is verified AND the user is in the infra_admins group.

Manual follow-ups (user): add self to infra_admins in Pocket ID admin UI (allowed_user_groups denies without membership); first OIDC login creates a new wallos user (sub-identified) — verify subscription association.

## Wallos — password login disabled (2026-08-16, follow-up)

OIDC login verified end-to-end by the user (passkey -> idm -> wallos callback, infra_admins membership confirmed, new user created). Deferred OIDC_DISABLE_PASSWORD_LOGIN now applied: set to "true" in the wallos helmrelease env (commit 472e9ee70). This removes the local password fallback — Pocket ID (infra_admins) is the only login path. End-state of the roadmap item for wallos reached.

Recovery note (if OIDC ever breaks access): git revert 472e9ee70 + push, Flux redeploys with the password fallback re-enabled (~1-2 min).
