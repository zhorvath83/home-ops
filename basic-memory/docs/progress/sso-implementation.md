---
title: sso-implementation
type: note
permalink: home-ops/progress/sso-implementation
tags:
- sso
- pocket-id
- tinyauth
- forward-auth
- envoy-gateway
- security
---

# SSO Implementation - Pocket-ID + TinyAuth + forward-auth

Roadmap reference: [[sso-implementation]]

## Scope (this iteration)

Steps 1-7 from the updated roadmap: Pocket-ID (bjw-s app-template), TinyAuth (bjw-s app-template), reusable forward-auth Kustomize Component, ReferenceGrant, VolSync backups, echo-app end-to-end test wiring. Cloudflare Access stays in place until app migrations land in follow-up MRs.

## Decisions made (post-review questions + pivot)

- **Scope**: Steps 1-7; per-app migrations and CF Access removal are follow-ups
- **Deploy method**: bjw-s app-template (after pivot from aclerici38/pocket-id-operator). User/group/OIDC-client management via Pocket-ID UI. OIDC client credentials live in 1Password and are pulled by per-app ExternalSecret resources
- **Namespace**: New `security` namespace
- **Git workflow**: Direct work on `main` after rebase

## File inventory

Created:
- `kubernetes/apps/security/namespace.yaml` + `kustomization.yaml` (registers pocket-id, tinyauth)
- `kubernetes/apps/security/pocket-id/ks.yaml + app/{kustomization,externalsecret,helmrelease}.yaml` -- bjw-s app-template, ghcr.io/pocket-id/pocket-id:v2.8.0-distroless (UID 65532), SQLite at /app/data, VolSync component (APP=pocket-id, APP_UID/APP_GID=65532, 1Gi), HTTPRoute on id.${PUBLIC_DOMAIN} via envoy-external + envoy-internal, GeoIP via MAXMIND_LICENSE_KEY
- `kubernetes/apps/security/tinyauth/ks.yaml + app/{kustomization,externalsecret,helmrelease,referencegrant}.yaml` -- bjw-s app-template, ghcr.io/steveiliop56/tinyauth:v3.6.2, SQLite at /data, VolSync component (APP=tinyauth, 1Gi), Pocket-ID generic OAuth provider with autoredirect, Google OAuth provider env stubs, ReferenceGrant authorizing cross-namespace SecurityPolicy refs from networking/selfhosted/media/observability
- `kubernetes/components/forward-auth/{kustomization,securitypolicy}.yaml` -- reusable Kustomize Component generating `${APP}-forward-auth` SecurityPolicy targeting HTTPRoute by `${APP}` name, extAuth path `/api/auth/envoy`, identity headers forwarded to backend

Modified:
- `kubernetes/apps/kustomization.yaml` -- added `./security`
- `kubernetes/apps/networking/echo/ks.yaml` -- added forward-auth component + APP=echo postBuild + dependsOn tinyauth

Removed (pivot):
- `kubernetes/apps/security/pocket-id-operator/` entire subtree (operator chart no longer used)
- `kubernetes/apps/security/pocket-id/app/instance.yaml` (CRD-based PocketIDInstance)
- `kubernetes/apps/security/pocket-id/app/usergroups.yaml` (6x PocketIDUserGroup CRDs)
- `kubernetes/apps/security/pocket-id/app/oidcclients.yaml` (PocketIDOIDCClient tinyauth)

## Validation

- yamllint: clean on all new + modified files
- `kustomize build` on each app subtree: clean output
- `kustomize build kubernetes/apps` (full tree): builds successfully

## 1Password items required before deploy (HomeOps vault)

1. **`maxmind`** (already exists) -- field `MAXMIND_LICENSE_KEY`
2. **`pocket-id`** (NEW) -- field `POCKET_ID_ENCRYPTION_KEY` (16+ byte; recommended `openssl rand -base64 32`)
3. **`tinyauth`** (NEW) -- fields:
   - `POCKETID_CLIENT_ID` (filled AFTER Pocket-ID first-boot + UI client creation)
   - `POCKETID_CLIENT_SECRET` (same)

TinyAuth v5 has no cookie-signing-secret env var (the v3 `TINYAUTH_SECRET` was removed; session keys are auto-managed in the SQLite DB). No Google OAuth credentials are needed -- Pocket-ID is the sole identity source.

## Bootstrap procedure after merge

1. **Pre-seed 1P**: create the 3 items above (POCKETID_* fields can be placeholders for now -- ExternalSecret will reconcile again once filled)
2. **Deploy Pocket-ID**: Flux applies the security ns + pocket-id HelmRelease. PVC bootstraps empty, container starts, first-run prints setup token to stdout
3. **First admin**: `kubectl logs -n security deploy/pocket-id` -- grab the setup token, visit `https://id.${PUBLIC_DOMAIN}`, enroll first admin with a passkey
4. **Create user groups** in Pocket-ID UI (id-admins, id-family etc.) and assign the first admin to id-admins
5. **Create tinyauth OIDC client in UI**: admin section -> OIDC clients -> new client named "tinyauth", callback `https://auth.${PUBLIC_DOMAIN}/api/oauth/callback/pocketid`, restrict to id-admins + id-family (or whichever groups should be able to log in to forward-auth-protected apps). Copy client_id + client_secret into 1P item "tinyauth" (POCKETID_CLIENT_ID, POCKETID_CLIENT_SECRET)
6. **Force ESO refresh**: `kubectl annotate externalsecret tinyauth -n security force-sync=$(date +%s) --overwrite` (or wait 12h)
7. **TinyAuth + echo test**: visit `https://echo.${PUBLIC_DOMAIN}`, expect redirect to Pocket-ID login, complete passkey login, see echo response with identity headers

## Follow-ups (NOT in this iteration)

- Per-app forward-auth migrations (Dozzle, Homepage, etc.) and OIDC-native migrations (actual, grafana, paperless)
- Per-app ACL refinement using `TINYAUTH_APPS_*_USERS_ALLOW` once user IDs are known
- Cloudflare Access removal once all apps verified
- BM area-reference updates (networking, external-secrets, k8s-workloads)
- Renovate annotations review for new container tags

## Observations

- [pivot] Initially built around aclerici38/pocket-id-operator with PocketIDInstance/UserGroup/OIDCClient CRDs; flipped to direct bjw-s app-template after second look. Reasons: operator adds reconcile machinery for a tiny config surface; AI-generated code with manual audit disclaimer; UI-based user/group/client management is fine at homelab scale; bjw-s is the repo's canonical pattern
- [pivot] Originally planned Google OAuth as second TinyAuth provider; dropped after analysis. TinyAuth has no per-provider access control (TINYAUTH_OAUTH_WHITELIST is global across all providers), and Pocket-ID is passkey-only so Google cannot be federated INTO Pocket-ID either. Adding Google would either bypass Pocket-ID's group-based ACL or force a duplicate email allowlist on the TinyAuth side. Single Pocket-ID provider is simpler and aligned with passkey-first design
- [decision] Pocket-ID OIDC client allowed-groups is the coarse forward-auth gate (single source of truth); per-app TINYAUTH_APPS_<NAME>_USERS_ALLOW handles fine-grained access
- [decision] Security namespace dedicated to auth infrastructure; future auth tooling (e.g., vault) can land here
- [risk] First-admin bootstrap is interactive (passkey enrollment via UI with setup token) -- expected, not automatable without UI scripting
- [defense] ReferenceGrant scoped to 4 namespaces (networking, selfhosted, media, observability) -- extend list when adding new namespaces
- [defense] VolSync 1Gi PVC backup on both pocket-id and tinyauth; pocket-id holds ~80-100 MB actual (SQLite + GeoIP DB + keys + uploads), tinyauth holds ~few MB (session DB)
- [defense] Pocket-ID image is distroless nonroot (UID 65532); VolSync component fed APP_UID=65532, APP_GID=65532 so the mover security context matches the runtime UID

## Relations

- implements [[sso-implementation]]
- relates_to [[networking]]
- relates_to [[external-secrets]]
- relates_to [[volsync-backup]]


## Errata (caught during review)

- [errata] Initial TinyAuth HelmRelease pinned to `v3.6.2` (memory error). Latest is `v5.0.7`; v5 removed the top-level `TINYAUTH_SECRET` env var (validated in v3 with `required,len=32`) -- corrected to v5.0.7 and dropped the variable from the ExternalSecret + 1P plan.
- [errata] Initial "TinyAuth has no per-provider whitelist" claim was based on stale docs; v5 source has `oauth.providers.<name>.whitelist` (`TINYAUTH_OAUTH_PROVIDERS_<NAME>_WHITELIST`). Irrelevant for our final design (Google dropped, only one provider), but worth recording for future migrations that might need per-provider scoping.
- [errata] `TINYAUTH_AUTH_ACLS_POLICY: deny` was missing from the HelmRelease (v5 default is `allow`). Added so the default-deny baseline is explicit.
