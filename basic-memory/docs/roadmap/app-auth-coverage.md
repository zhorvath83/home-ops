---
title: app-auth-coverage
type: roadmap
permalink: home-ops/docs/roadmap/app-auth-coverage
topic: Bring every exposed application under one identity layer (envoy-oidc gate OR
  native Pocket ID OIDC) so no application relies on its own local login
status: proposed
priority: high
scope: 'Audit all 26 HTTPRoute-exposed applications in the cluster and drive the 11
  currently-unprotected ones into one of the two accepted auth categories used everywhere
  else: (a) the shared gateway-oidc Envoy SecurityPolicy component, or (b) the application''s
  own native OIDC client against Pocket ID. End state: zero applications authenticate
  via an app-local username/password login as the primary gate. Three routes are excluded
  by individual judgment (Pocket ID the IdP itself, the flux github-webhook HMAC endpoint,
  the https-redirect infra route) — these are documented exceptions, NOT a hidden
  "machine endpoint" category. Cloudflare Access, where present on envoy-external
  routes, is defense-in-depth only and does NOT satisfy the cluster-side requirement.

  '
rationale: 'The cluster already has a uniform IAM platform (Pocket ID as sole OIDC
  IdP, the reusable gateway-oidc component for apps that cannot speak OIDC, and native
  OIDC for apps that can — grafana, pingvin-share-x, crowdsec-web-ui, calibre-web-automated).
  10 gateway-gated + 4 native clients are already covered, but 11 exposed applications
  still fall back to their own local accounts or no auth at all. Local app logins
  are an unmanaged, untearable-when-an-employee-leaves attack surface; they bypass
  the group taxonomy, the passkey-only credential policy, and the header-stripping
  / PKCE-always-on / admin-API-blocking guards the IdP plane provides. Closing this
  gap is a Security > Clarity > Performance item: every hostname that resolves to
  a UI must terminate identity at Pocket ID, either at the gateway or in the app.
  The work is mostly mechanical (per-app repeat of the existing gateway-oidc onboarding
  recipe or the native-OIDC config pattern), so the roadmap is a coverage sweep, not
  a research effort.

  '
options:
- Native OIDC where the app supports it (chosen default) — app-aware role/group mapping,
  better UX, matches the existing grafana/pingvin/crowdsec/calibre pattern. Used for
  mealie, paperless, actual.
- envoy-oidc gate where the app has no native OIDC — uniform, gateway-level, group
  ACL at the IdP. Used for the 8 apps with no/poor native OIDC.
- Per-app override of the default — wallos and homepage CAN do native OIDC but weakly
  (no PKCE / no group mapping); both are overridden to envoy-oidc with rationale,
  reversible at review.
related_areas:
- iam
- networking
- external-secrets
- k8s-workloads
tags:
- roadmap
- iam
- oidc
- envoy-oidc
- pocket-id
- security
- proposed
decisions:
- Method policy — native OIDC if the app supports it (strict); envoy-oidc gate only
  where the app has no native OIDC. PKCE absence on a native client is NOT a blocker
  for non-public (LAN-only / confidential) clients — Pocket ID only verifies a challenge
  for clients that require it (see [[iam]]).
- IdP group policy — every remediated app gets a Pocket ID group on its client (`allowed_user_groups`),
  default `infra_admins`, overridable per-app. The group is enforced AT THE IdP (`IsUserGroupAllowedToAuthorize`),
  so it gates authorization for native clients too, not only for envoy-oidc gates
  — this dissolves the "native app has no RBAC" concern (e.g. homepage, wallos).
- calibre-web-automated — its OIDC config lives in the app database permanently (no
  ENV-based config exists in the chart); accepted as-is, not a debt to migrate to
  ExternalSecret.
---

# app-auth-coverage — unified identity layer for every exposed app

## Meta

- [assessed] 2026-08-05 — live cluster re-verified via `kubectl get httproutes -A` and `kubectl get securitypolicies -A`, repo tree cross-checked, native-OIDC capability researched per app (official docs)
- [confidence] high on the inventory (live + repo agree); high on the method assignment (native OIDC capability confirmed per app); medium on mealie's local-login-disable timing (OIDC works today, password-disable arrives with the in-progress redesign)
- [depends_on] [[iam]] (Pocket ID clients + gateway-oidc component), [[networking]] (Envoy Gateway SecurityPolicy), [[external-secrets]] (per-app client secret delivery), [[k8s-workloads]] (per-app HelmRelease/ks.yaml)
- [convention] Two accepted auth categories, no third: `gate: envoy` (gateway-oidc SecurityPolicy) or `gate: native` (app OIDC client). Registry of truth: `provision/pocket-id/clients.yaml`.

## Current state — inventory (2026-08-05)

26 HTTPRoutes across the cluster (one infra redirect excluded from the count). Two shared Gateways: `envoy-external` (Cloudflare Tunnel) and `envoy-internal` (LAN VIP). Every `envoy-internal`-only route also inherits the Gateway-level `envoy-internal-rfc1918` SecurityPolicy (RFC1918 LAN allowlist + CrowdSec bouncer) — that is network segmentation, NOT an identity layer.

### A. Already protected — envoy-oidc gate (10 deployed + 1 pending)

Per-app `${APP}-oidc` SecurityPolicy from `kubernetes/components/gateway-oidc/securitypolicy.yaml`, OIDC issuer `https://idm.horvathzoltan.me`, group ACL at Pocket ID.

| App | FQDN | Gateway | Pocket ID group | File |
|---|---|---|---|---|
| bazarr | subs.horvathzoltan.me | internal | media_users | `kubernetes/apps/downloads/bazarr/ks.yaml:13` |
| sonarr | shows.horvathzoltan.me | internal | media_users | `kubernetes/apps/downloads/sonarr/ks.yaml:13` |
| radarr | movies.horvathzoltan.me | internal | media_users | `kubernetes/apps/downloads/radarr/ks.yaml:13` |
| prowlarr | indexers.horvathzoltan.me | internal | media_users | `kubernetes/apps/downloads/prowlarr/ks.yaml:13` |
| qbittorrent | bt.horvathzoltan.me | internal | media_users | `kubernetes/apps/downloads/qbittorrent/ks.yaml:13` |
| subsyncarr | subsync.horvathzoltan.me | internal | media_users | `kubernetes/apps/downloads/subsyncarr/ks.yaml:12` |
| maintainerr | maintainerr.horvathzoltan.me | internal | media_users | `kubernetes/apps/downloads/maintainerr/ks.yaml:13` |
| seerr | reqs.horvathzoltan.me | internal | media_users | `kubernetes/apps/downloads/seerr/ks.yaml:13` |
| hubble-ui | hubble.horvathzoltan.me | internal | infra_admins | `kubernetes/apps/kube-system/cilium/ks.yaml:15` |
| echo-server | echo.horvathzoltan.me | external+internal | infra_admins | `kubernetes/apps/networking/echo-server/ks.yaml:12` |
| suggestarr | suggestarr.horvathzoltan.me | internal | media_users | `kubernetes/apps/media/suggestarr/ks.yaml:13` — client declared, app commented out of `kubernetes/apps/media/kustomization.yaml`; deploys already-gated |

### B. Already protected — native OIDC (4)

App speaks OIDC itself against Pocket ID; no gateway-oidc SecurityPolicy (would double-gate).

| App | FQDN | Gateway | Provider config | Notes |
|---|---|---|---|---|
| grafana | grafana.horvathzoltan.me | internal | `auth.generic_oauth` in `kubernetes/apps/observability/grafana/instance/grafana.yaml:21`; PKCE on; `role_attribute_path` maps infra_admins→Admin | local login form hidden (`disable_login_form`); operator provisioning cred is not a human path |
| pingvin-share-x | share.horvathzoltan.me | external+internal | `oauth:` block in `kubernetes/apps/selfhosted/pingvin-share-x/app/config/config.yaml:148`; discovery-only; password disabled | — |
| crowdsec-web-ui | crowdsec.horvathzoltan.me | internal | `CONFIG_AUTH_OIDC_*` in `kubernetes/apps/crowdsec/crowdsec-web-ui/app/helmrelease.yaml:60`; `UNMATCHED_ROLE: deny`; PKCE off | no `egress.home.arpa` labels — token-hairpin CNP posture open (see [[iam]]); PKCE off accepted (non-public client) |
| calibre-web-automated | books.horvathzoltan.me | external+internal | registered `gate: native` in `provision/pocket-id/clients.yaml:100`; callback `/login/generic/authorized`; PKCE off | **app-side OIDC config lives in the app database permanently** — the chart exposes no ENV-based OIDC config; accepted as-is (decided 2026-08-05), not a debt to migrate |

### C. Excluded by individual judgment (3) — documented exceptions, NOT a category

| Route | FQDN | Why excluded |
|---|---|---|
| pocket-id-external / pocket-id-internal | idm.horvathzoltan.me | The IdP / trust root. Cannot gate itself with OIDC. External route hardened with `pocket-id-deny-403` HTTPRouteFilter (`kubernetes/apps/security/pocket-id/app/httproute.yaml:46-122`) blocking /setup, /signup, /api/signup, /st/, /healthz, /internal/ and any X-API-KEY request. |
| github-webhook | flux-webhook.horvathzoltan.me | Flux webhook receiver; auth is the HMAC webhook token, not a human login surface. `kubernetes/apps/flux-system/flux-instance/app/github/httproute.yaml:4` |
| https-redirect | (no hostname) | RequestRedirect 301 http→https, no backend, not an app. `kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml:296` |

### D. Unprotected — to remediate (11)

| App | FQDN | Gateway | Today | File |
|---|---|---|---|---|
| mealie | recipes.horvathzoltan.me | external+internal | no auth / local accounts | `kubernetes/apps/selfhosted/mealie/app/helmrelease.yaml` |
| paperless | docs.horvathzoltan.me | external+internal | local accounts; signup disabled but no SSO gate | `kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml:96` |
| actual | pfm.horvathzoltan.me | internal | app-local login | `kubernetes/apps/selfhosted/actual/app/helmrelease.yaml` |
| wallos | subscriptions.horvathzoltan.me | internal | app-local login | `kubernetes/apps/selfhosted/wallos/app/helmrelease.yaml` |
| homepage | dash.horvathzoltan.me | external+internal | no auth | `kubernetes/apps/selfhosted/homepage/app/helmrelease.yaml` |
| home-gallery | photos. + fenykepek.horvathzoltan.me | external+internal | browser Basic Auth only | `kubernetes/apps/selfhosted/home-gallery/app/helmrelease.yaml` |
| backrest | backup.horvathzoltan.me | internal | built-in user/pass | `kubernetes/apps/selfhosted/backrest/app/helmrelease.yaml` |
| paperless-gpt | paperless-gpt.horvathzoltan.me | internal | no own auth (uses Paperless API token) | `kubernetes/apps/selfhosted/paperless-gpt/app/helmrelease.yaml` |
| victoria-logs | logs.horvathzoltan.me | internal | no UI auth | `kubernetes/apps/observability/victoria-logs/app/helmrelease.yaml:41` |
| alertmanager | alertmanager.horvathzoltan.me | internal | basic_auth_users only | `kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml:60` |
| kopia | pvbackup.horvathzoltan.me | internal | HTTP Basic Auth | `kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml` |

## Target state — per-app method assignment

Policy (decided with human, 2026-08-05): **native OIDC if the app supports it (strict); envoy-oidc gate only where the app has no native OIDC.** PKCE absence on a native client is acceptable for non-public (LAN-only / confidential) clients — not a blocker. LAN-only apps are in scope too. Cloudflare Access does not satisfy the requirement — a cluster-side method is required regardless. **Every remediated app gets a Pocket ID group on its client, default `infra_admins`, overridable per-app; the group is enforced at the IdP for both methods.**

| App | Target method | Native OIDC capability | IdP group (default) | Rationale / caveat |
|---|---|---|---|---|
| paperless | native | yes — mature, PKCE, group sync, `PAPERLESS_DISABLE_REGULAR_LOGIN` | infra_admins | best native fit; django-allauth OIDC |
| mealie | native | yes — PKCE, group mapping (`OIDC_ADMIN_GROUP`/`OIDC_USER_GROUP`) | infra_admins | OIDC works today; mealie is under active OIDC redesign (will get more sophisticated + `ALLOW_PASSWORD_LOGIN=false`); until the redesign lands in stable, the local password login remains a secondary path |
| actual | native | yes — `ACTUAL_OPENID_ENFORCE=true` disables local | infra_admins | no app-side group mapping, but group enforced at IdP client; PKCE unconfirmed |
| wallos | native | yes — v4.0.0 OIDC; no PKCE, no app-side group map | infra_admins | PKCE off accepted (non-public); group enforced at IdP client; local-disable conditional on single-user (acceptable) |
| homepage | native | yes — v2.0 NextAuth OIDC; no app-side RBAC | infra_admins | no app-side RBAC, but group enforced at IdP client (`infra_admins`); OIDC overrides password login |
| home-gallery | envoy-oidc | no — browser Basic Auth only | infra_admins | no SSO in config schema |
| backrest | envoy-oidc | no — built-in auth disableable for reverse-proxy | infra_admins | disable built-in auth, gate in front |
| paperless-gpt | envoy-oidc | no — no own auth layer | infra_admins | gate in front |
| victoria-logs | envoy-oidc | partial only — via vmauth JWT/OIDC (v1.138.0+, heavy) | infra_admins | victoria-logs itself has no UI auth; vmauth-OIDC is a separate component, envoy-oidc gate is simpler |
| alertmanager | envoy-oidc | no — basic_auth_users only | infra_admins | standard solution is reverse-proxy gate |
| kopia | envoy-oidc | no — HTTP Basic Auth only | infra_admins | gate in front |

Net: **5 native OIDC + 6 envoy-oidc = 11 apps to remediate.** Each envoy-oidc app needs a `gate: envoy` Pocket ID client + a 1Password `<app>_client_secret` field + the gateway-oidc component in its `ks.yaml` + `allowed_user_groups` (default infra_admins). Each native app needs a `gate: native` client (app-specific callback) + a 1Password secret + app-side OIDC config + local-login disabled (where the app supports it) + `allowed_user_groups` (default infra_admins, enforced at the IdP).

## Operational notes — Pocket ID provisioning

Every new OIDC client (all 11 remediated apps) requires a Terraform-managed registry edit plus an apply — this is NOT a kubectl/Flux reconcile, and the work batch sizing reflects it.

- [observation] [provisioning] **Client registration** = add an entry to `provision/pocket-id/clients.yaml` (the Terraform-managed client registry consumed by `clients.tf`/`locals.tf` via the `trozz/pocketid` provider), then `just pocket-id apply`. This is a repo edit + Terraform apply. It is batchable — all clients of a phase can land in one `clients.yaml` change and one apply.
- [observation] [provisioning] **`just pocket-id apply` is the only correct apply path**: it runs Terraform in **local-exec mode** (the Pocket ID admin API is reachable only from the LAN through `envoy-internal`, so a remote-exec plan can never reach it — see [[iam]] §4) AND syncs each new `<app>_client_secret` into the 1Password `HomeOps/pocket-id-clients` item. Raw `terraform apply` skips the 1Password sync and leaves ExternalSecret consumers stale.
- [observation] [provisioning] **New groups** (only if a per-app override needs a group beyond the `infra_admins` default) require a separate edit to `provision/pocket-id/groups.tf` in the same apply. `infra_admins` already exists, so the 11 default assignments need no group edit.
- [observation] [provisioning] **Drift checks** after each batch: `just pocket-id lint` (clients.yaml ↔ gateway-oidc consumers agreement) and `just pocket-id audit` (no unrestricted client) — both read-only.
- [decision] Apply per phase, not 11 separate applies: Phase 1 batch = 6 `gate: envoy` clients; Phase 2 batch = 5 `gate: native` clients — keeps the 1Password sync and the Terraform state churn atomic per phase.
## Phases

### Phase 0 — verify the existing native clients (spike, no cluster change)
- [ ] Verify calibre-web-automated's app-side OIDC is actually configured and working (login test) — the config lives in the app DB, so verify by logging in, not by reading the repo.
- [ ] Resolve the crowdsec-web-ui token-hairpin CNP posture (no `egress.home.arpa` labels) — confirm the native OIDC flow actually completes, or add `allow-gateways`.

### Phase 1 — envoy-oidc sweep (6 apps, mechanical, low risk)
Order by exposure: external-first (home-gallery) then internal (backrest, paperless-gpt, victoria-logs, alertmanager, kopia). For each: add `gate: envoy` client with `allowed_user_groups: [infra_admins]` to `provision/pocket-id/clients.yaml` → `just pocket-id apply` → add 1Password secret field → add gateway-oidc component to app `ks.yaml` with APP/APP_SUBDOMAIN → Flux reconcile → login test (authed + non-allowed-group denied). Run `just pocket-id lint` to confirm registry/cluster agreement.

### Phase 2 — native OIDC sweep (5 apps, app-specific config)
For each (paperless, mealie, actual, wallos, homepage): add `gate: native` client with app callback + `allowed_user_groups: [infra_admins]` → `just pocket-id apply` → add 1Password secret ExternalSecret → wire app-side OIDC env/config → disable local login where supported (`PAPERLESS_DISABLE_REGULAR_LOGIN`, `ACTUAL_OPENID_ENFORCE`, homepage OIDC-override; mealie waits for redesign; wallos conditional). Check each app's CNP egress labels — a native client carrying `egress.home.arpa/custom-egress` MUST also carry `egress.home.arpa/allow-gateways`. Login test.

### Phase 3 — verification + settling
- [ ] `just pocket-id audit` — no client with restriction off (every client group-restricted).
- [ ] `just pocket-id lint` — every client has its cluster half.
- [ ] For every hostname in Table D: unauthenticated request → 302 to idm.horvathzoltan.me; authenticated-as-infra_admins → admitted; authenticated-as-non-allowed-group → denied at the IdP.
- [ ] No app-local login form reachable as the primary gate on any non-excluded app (mealie excepted until its OIDC redesign lands).

## Acceptance criteria

1. The 11 apps in Table D each terminate identity at Pocket ID — envoy-oidc SecurityPolicy attached OR native OIDC configured — confirmed by an authenticated login test per app.
2. No application in Table D relies on an app-local username/password as the primary gate (local logins removed, disabled, or sitting behind the OIDC gate). Known transition: mealie keeps password login until its OIDC redesign lands in stable.
3. `provision/pocket-id/clients.yaml` lists all 11 new clients with the correct `gate` tag, `allowed_user_groups` (default infra_admins unless overridden), and callback path; `just pocket-id lint` passes; `just pocket-id audit` reports zero unrestricted clients.
4. The 3 documented exclusions (Table C) remain the only exceptions; no new hidden exception category is introduced.
5. calibre-web-automated's protection is verified by login test (config in app DB, accepted permanent).

## Open questions / risks

- [question] **Per-app group overrides** — all 11 default to `infra_admins`. Confirm per-app whether any should widen (e.g. a family/home group for mealie, paperless, home-gallery) — a non-existent group may need creating in `provision/pocket-id/groups.tf` first.
- [question] **mealie redesign timing** — mealie's OIDC is being redesigned; pin current stable + accept password login as a secondary path until the redesign lands, OR track mealie-next for `ALLOW_PASSWORD_LOGIN=false`? Re-evaluate at Phase 2.
- [risk] **per-app CNP posture for native OIDC clients** — a native client carrying `egress.home.arpa/custom-egress` MUST also carry `egress.home.arpa/allow-gateways` or its token exchange is dropped (see [[iam]] §3). Check mealie/paperless/actual/wallos/homepage egress labels during Phase 2.
- [risk] **double-gate** — for the 6 envoy-oidc apps, do NOT also enable native OIDC; the gateway-oidc component is explicit that gating an OIDC-speaking app double-gates the login.
- [risk] **group enforcement is at the IdP, not the app** — for native apps without app-side group mapping (actual, wallos, homepage), the `infra_admins` restriction is enforced by Pocket ID's `IsUserGroupAllowedToAuthorize`, not by the app. This is correct and sufficient, but it means the app itself cannot grant differentiated roles within the allowed group (only allow/deny).

## Update 2026-08-15 — homepage remediated (Phase 2, 1 of 5)

The first app of the Phase 2 native-OIDC sweep landed. Inventory shifts: **Table B is now 5 native clients**, **Table D drops to 10 unprotected**. Overall coverage is 10 envoy-gated + 5 native.

- [done] **homepage** — `gate: native`, subdomain `dash`, callback `/api/auth/callback/homepage-oidc`, `allowed_user_groups: [infra_admins]`. Exactly the method the target-state table assigned it (line: "native | yes — v2.0 NextAuth OIDC; no app-side RBAC"). Terraform apply was 1 add / 0 change / 0 destroy; `just pocket-id audit` reports all 16 clients group-restricted.
- [observation] [pkce] The target-state table accepted PKCE-off as non-blocking, but homepage did NOT need the concession: upstream sets `checks: ["pkce", "state", "nonce"]` and the live authorize redirect carries `code_challenge_method=S256`. No `pkce_enabled` override was added.
- [observation] [local-login] Nothing to disable. Homepage's OIDC config overrides password login by construction, and no `HOMEPAGE_AUTH_PASSWORD` is set, so the passkey-only posture holds with no extra flag.
- [resolved-partly] The Phase 0 / §risk question about native-client CNP posture is **answered for homepage**: it carries `egress.home.arpa/allow-world: "true"`, and the token-exchange hairpin was measured end-to-end (the pod fetched discovery and produced a full authorize redirect to the public issuer). crowdsec-web-ui's no-label case remains open — homepage's result does not transfer to it.
- [confirmed] The §risk "group enforcement is at the IdP, not the app" is now documented upstream for homepage, not merely inferred: Homepage grants access to any identity the provider authorizes and applies no claim-based authorization. For homepage the IdP group restriction is the ONLY control.
- [decision] Cloudflare Access is **retained** in front of `dash` (double gate on the external path) by explicit human decision. This is not the §risk about double-gating an envoy-oidc app with native OIDC — that prohibition still stands unchanged.
- [gotcha] Relevant to the remaining batched applies (§decision "apply per phase, not 11 separate applies"): **never run `just pocket-id apply` with piped stdin.** The `sync-secrets` step's `op item edit` reads a non-TTY stdin as a JSON template and dies with `invalid JSON provided` — Terraform succeeds, the 1Password sync does not, and every consuming ExternalSecret is left stale. Recovery: `just pocket-id sync-secrets` without a pipe. See [[iam]].
- [open] Phase 2 remainder: paperless, mealie, actual, wallos. Phase 1 (6 envoy-oidc apps) untouched. Status stays `proposed`.
