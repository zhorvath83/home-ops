---
title: iam
type: area_reference
permalink: home-ops/docs/areas/iam
area: iam
status: current
confidence: high
verified_at: '2026-08-03'
summary: Pocket ID is the cluster OIDC Identity Provider; its clients and groups are
  Terraform-managed in provision/pocket-id, and workloads that do not speak OIDC are
  gated by the shared gateway-oidc Envoy-native OIDC component.
verified_against:
- kubernetes/apps/security/pocket-id/app/helmrelease.yaml
- kubernetes/apps/security/pocket-id/app/httproute.yaml
- kubernetes/components/gateway-oidc/securitypolicy.yaml
- kubernetes/components/gateway-oidc/externalsecret.yaml
- provision/pocket-id/clients.yaml
- provision/pocket-id/clients.tf
- provision/pocket-id/locals.tf
- kubernetes/apps/observability/grafana/instance/grafana.yaml
- kubernetes/apps/selfhosted/pingvin-share-x/app/config/config.yaml
- kubernetes/apps/networking/envoy-gateway/config/validatingadmissionpolicy.yaml
- kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml
- kubernetes/apps/crowdsec/crowdsec-web-ui/
- kubernetes/apps/security/pocket-id/app/backendtlspolicy.yaml
- kubernetes/apps/security/pocket-id/app/certificate.yaml
- provision/pocket-id/mod.just
- provision/pocket-id/groups.tf
---

# Identity & Access Management (IAM)

## 1. Components

### Pocket ID — the IdP

- **Role**: sole source of truth for users and groups; the single OIDC provider for every workload.
- **Placement**: `kubernetes/apps/security/pocket-id/`, namespace `security`, exposed at `idm.${PUBLIC_DOMAIN}` on both `envoy-external` and `envoy-internal`.
- **Authentication**: passkey-only. There is no password credential.
- **Serving**: the pod terminates TLS itself on port 1411 (`TLS_CERT`/`TLS_KEY` are file paths to a cert-manager `Certificate`), and a `BackendTLSPolicy` makes envoy speak HTTPS upstream with `hostname: idm.${PUBLIC_DOMAIN}`.
- **Metrics**: OTel Prometheus exporter on `:9464`, scraped through a `ServiceMonitor`.
- **State**: SQLite on the `pocket-id` PVC, backed up by the shared `components/volsync` plane. The GeoLite2 mmdb lives on an `emptyDir` so it stays out of the backup.

### gateway-oidc — the OIDC gate

- **Role**: reusable Kustomize component (`kubernetes/components/gateway-oidc/`) that attaches an Envoy-native OIDC `SecurityPolicy` to an app's `HTTPRoute`, for apps that cannot speak OIDC themselves.
- **Consumers** set `APP` (+ optional `APP_SUBDOMAIN`, `HTTPROUTE_NAME`) through Flux `postBuild.substitute`.
- **Flow**: Envoy redirects to the IdP, exchanges the authorization code, sets the id-token/access-token cookies, then forwards the authenticated request to the backend.
- **Cookies**: `${APP}-id-token` / `${APP}-access-token`, `sameSite: Strict` (safe because `idm.*` and `app.*` share the registrable domain), tokens encrypted by default.
- **No authorization block**: group access is decided at the IdP, not in the policy.

## 2. Trust chain

`User -> Envoy Gateway -> SecurityPolicy (OIDC) -> App`

- [observation] [security] **Hostname admission guard**: a `ValidatingAdmissionPolicy` (native CEL) in `envoy-gateway/config/validatingadmissionpolicy.yaml` gates HTTPRoute hostname claims — only the `security` namespace may claim `idm.${PUBLIC_DOMAIN}`, and non-security namespaces may not claim a wildcard covering it. This closes the route-collision / WebAuthn-origin-binding hijack path on the IdP plane. See [[networking]].
- [observation] [security] **Header stripping**: the Envoy Gateway `ClientTrafficPolicy` removes `Remote-User`, `Remote-Email`, `Remote-Groups`, `Remote-Name`, `Remote-Sub` from inbound requests, so identity headers cannot be supplied by a client. Defense in depth; never narrow it.
- [observation] [security] **PKCE is always on**. Envoy Gateway sends `code_challenge`/S256 on every gated flow and the behaviour is not configurable in the `SecurityPolicy`. Every client therefore carries `pkce_enabled = true` unless the app provably cannot send a challenge, because Pocket ID only *verifies* a challenge for clients that require it.
- [observation] [security] **Admin API is not publicly reachable**: the `pocket-id-external` HTTPRoute returns 403 for any request carrying an `X-API-KEY` header, and also for `/setup`, `/signup`, `/api/signup`, `/st/`, `/healthz`, and `/internal/`. The `envoy-internal` route carries no such filters, so administration and provisioning run from the LAN.

## 3. OIDC endpoint convention

- [observation] [convention] Pocket ID serves **one issuer for every client**: `https://idm.${PUBLIC_DOMAIN}`. Clients resolve the rest through `/.well-known/openid-configuration`; there are no per-client issuer URLs.
- [observation] [endpoint] authorize `/authorize` · token `/api/oidc/token` · userinfo `/api/oidc/userinfo` · end-session `/api/oidc/end-session` · JWKS `/.well-known/jwks.json`.
- [observation] [scopes] `openid`, `profile`, `email`, `groups`, `offline_access`. The `groups` claim carries the group **name** verbatim — no realm or domain suffix — so role mappings match on the bare name.
- [observation] [consequence] Every endpoint is the public issuer, per AD-023. The OIDC backchannel is therefore ordinary gateway traffic (client pod -> envoy VIP -> pocket-id). Baseline-egress clients need nothing; a client carrying `egress.home.arpa/custom-egress` MUST also carry `egress.home.arpa/allow-gateways` or its token exchange is dropped by its own CNP posture. Current carriers: grafana, pingvin-share-x, calibre-web-automated. **The new native client `crowdsec-web-ui` carries NEITHER label** (kubernetes/apps/crowdsec/crowdsec-web-ui/app/helmrelease.yaml has no `egress.home.arpa` labels), so whether its token-exchange hairpin survives its CNP posture is an open cluster-runtime question.
- [observation] [dns] The hairpin resolves through the coredns split-horizon zone: `${PUBLIC_DOMAIN}` forwards to `${K8S_GATEWAY_IP}` (k8s-gateway), so pods reach the envoy-internal VIP without the node-resolver -> router hop.

## 4. Provisioning model

- [observation] [terraform] Clients and groups are declared in `provision/pocket-id/clients.yaml` and applied with `just pocket-id apply`. Provider `trozz/pocketid` 2.1.0; state in HCP Terraform, organization `zhorvath83`, workspace `pocket-id`.
- [observation] [terraform] The workspace runs in **local execution mode** deliberately — the admin API is only reachable from the LAN through `envoy-internal`, so a remote-executed plan can never reach it.
- [observation] [terraform] `locals.tf` derives the callback URL per client (`/oauth2/callback` for gateway-gated apps, an app-specific path for native ones) and reads `PUBLIC_DOMAIN` from `kubernetes/components/common/vars/cluster-settings.yaml`, so the domain is not duplicated.
- [observation] [terraform] `client_id` is set explicitly to the app name and is not secret, which is why manifests can carry it as a literal (`client-id: ${APP}`).
- [observation] [scope] **Users are not Terraform-managed.** Accounts, passkey enrolment, and group membership are administered in the Pocket ID admin UI. Terraform owns groups and clients only.

### Group-restriction guard (security control)

- [observation] [security] Pocket ID itself is **not** permissive: `IsUserGroupAllowedToAuthorize` returns true immediately when `IsGroupRestricted` is false, and otherwise requires membership — a client marked restricted with an empty group list denies everyone.
- [observation] [security] The gap is in the **Terraform provider**, which does not expose `isGroupRestricted` and instead derives it as "the `allowed_user_groups` list is non-empty". An empty list therefore reaches the API as *not restricted*, admitting every account.
- [observation] [remediation] Three layers guard this: a `lifecycle.precondition` in `clients.tf` blocks an empty group list at apply time; `lint.sh` mirrors the check; and `just pocket-id audit` queries the running IdP for any client whose restriction is off, which is what catches a client created in the admin UI behind Terraform's back.
- [observation] [limitation] The provider also omits `skipConsent` from its request body, so enabling "skip consent" in the admin UI is silently reverted the next time Terraform updates that client — invisibly, since the field is absent from the schema and never appears in a plan.

## 5. Secret delivery

- [observation] [secret] Client secrets live in the 1Password item `HomeOps/pocket-id-clients`, one `<app>_client_secret` field per client. `just pocket-id apply` writes them from Terraform outputs; raw `terraform apply` skips that sync and leaves consumers stale.
- [observation] [secret] A Pocket ID client secret is returned by the API **only at creation**. Terraform state and 1Password are the only two copies; losing both means recreating the client (`just pocket-id rotate <app>`).
- [observation] [secret] `HomeOps/pocket-id` holds the IdP's own `ENCRYPTION_KEY` and the `POCKET_ID_PROVISIONING_API_KEY` used by Terraform.
- [observation] [secret] Consumers pull their secret through an `ExternalSecret` backed by the `onepassword-connect` ClusterSecretStore. The `gateway-oidc` component ships the template for gated apps; native apps carry their own.

## 6. Group taxonomy

| Group | Grants |
|---|---|
| `media_users` | the nine gateway-gated clients (eight downloads apps + suggestarr, which lives in the `media` namespace) |
| `infra_admins` | hubble-ui, echo-server, crowdsec-web-ui, and Grafana's Admin role |
| `calibre-web-automated_users` / `_admins` | Calibre-Web Automated |
| `pingvin-share-x_admins` | Pingvin Share admin access |

## 7. Client inventory

**Gateway-gated** (`components/gateway-oidc`, callback `/oauth2/callback`): bazarr (subs), sonarr (shows), radarr (movies), prowlarr (indexers), qbittorrent (bt), subsyncarr (subsync), maintainerr, seerr (reqs) and suggestarr — all `media_users`; hubble-ui (hubble) and echo-server (echo) — `infra_admins`. That is 11 gateway-gated clients. NOTE: `suggestarr` is declared in Terraform AHEAD of a deployed workload — its `ks.yaml` wires the gateway-oidc component but the app is commented out of `kubernetes/apps/media/kustomization.yaml`.

**Native OIDC**:

- [observation] [client] **crowdsec-web-ui** — a 4th native OIDC client (`gate: native`, subdomain `crowdsec`, callback `/api/auth/oidc/callback`, `pkce_enabled: false`, group `infra_admins`) declared in provision/pocket-id/clients.yaml with its app at kubernetes/apps/crowdsec/crowdsec-web-ui/. PKCE is off, unlike grafana.
- [observation] [client] **grafana** — `auth.generic_oauth` on the grafana-operator instance. Endpoints are the public issuer; `use_pkce: true`; `scopes: openid email profile groups`. `role_attribute_path` maps `infra_admins` -> Admin and everything else -> None, with `role_attribute_strict: true`. The local login form is hidden (`disable_login_form`); the retained admin credential is the grafana-operator's provisioning credential for the in-cluster API, not a human login path.
- [observation] [client] **pingvin-share-x** — discovery-only client; `oidc-discoveryUri` points at `/.well-known/openid-configuration`, `oidc-rolePath: groups`, `oidc-roleAdminAccess: pingvin-share-x_admins`, password login disabled.
- [observation] [client] **calibre-web-automated** — callback `/login/generic/authorized`. `pkce_enabled: false` because Calibre-Web's flask-dance generic OAuth exposes no PKCE toggle and sends no `code_challenge`; it is a confidential client, so the secret still guards the token exchange.

## 8. Operational notes

- [observation] [onboarding] Adding a gated app is two edits plus an apply: a `clients.yaml` entry (`gate: envoy`, subdomain, groups) with `just pocket-id apply`, and the `gateway-oidc` component plus `APP`/`APP_SUBDOMAIN` in the app's `ks.yaml`. `just pocket-id lint` fails if either half is missing or the subdomains disagree.
- [observation] [debt] Calibre-Web Automated's OIDC settings are entered in its admin UI, so its client secret lives in the app database rather than arriving through External Secrets. VolSync backs it up, but it is not reproducible from git — the one workload outside the uniform secret-delivery model.
- [observation] [limitation] **SecurityPolicy discovery-fetch fragility**: the envoy-gateway controller fetches the discovery document on every SecurityPolicy generation bump. If that fetch times out, the policy goes `Accepted=False/Invalid` and the controller sets a 500 direct-response on the gated routes, and it does not self-heal once the endpoint returns. Remediation: `kubectl rollout restart deployment/envoy-gateway -n networking`, after which policies return to Accepted within a few minutes. With a single shared issuer this is one failure point for all gated apps at once.
- [observation] [limitation] There is no auth-audit tooling for the IdP. Pocket ID runs with `LOG_JSON=true`, so a VictoriaLogs-backed audit trail is buildable, but none exists today.
- [observation] [ratelimit] The external gateway carries a Local `BackendTrafficPolicy` rate limit of **3000 requests/minute PER CLIENT** — `clientSelectors.sourceCIDR` with `type: Distinct` on both `0.0.0.0/0` and `::/0`, so each source address gets its own bucket and IPv6 clients are not silently unlimited. This replaced an earlier shared 600/min limit after a single gallery visitor exhausted it and 429-ed everyone else on that route (rationale recorded in the manifest comment). Local type = no rate-limit backend deployed. Cloudflare WAF provides edge rate limiting ahead of it; behavioural abuse detection is CrowdSec's job, this is only a volumetric backstop (kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml:26-43).

## Relations

- decided_in [[AD-023-cnp-threat-model-audit]]
- relates_to [[networking]]
- relates_to [[external-secrets]]
- relates_to [[observability]]

## Update 2026-08-03 — staleness re-verification

Full re-verification against the live repo as part of the `area-reference-staleness-audit`
roadmap item. Previous `verified_at` was 2026-07-26 (one week old). Verdict: MINOR-DRIFT —
34 claims re-verified true, the summary and the whole trust chain held, every `verified_against`
path still existed. What drifted was the client inventory and one number.

- [correction] **The rate limit was wrong in a way that inverted its meaning.** The note said
  600 req/min, "effectively global because one Envoy pod serves each gateway". It is now
  **3000 req/min PER CLIENT** — `sourceCIDR` selectors with `type: Distinct` on both `0.0.0.0/0`
  and `::/0`. The manifest comment records why: a single gallery visitor exhausted the old shared
  600/min and 429-ed everyone else on that route. Both address families are listed so IPv6 clients
  are not silently unlimited. "Effectively global" is exactly what it is no longer.
- [correction] `media_users` grants NINE gateway-gated clients, not eight — `suggestarr` was added,
  and it lives in the `media` namespace, so "the eight gateway-gated downloads apps" was doubly
  wrong. Note that suggestarr is a **declared-but-undeployed** client: Terraform creates it while
  the app is commented out of `kubernetes/apps/media/kustomization.yaml`.
- [correction] A 4th native OIDC client exists: `crowdsec-web-ui` (`infra_admins`, PKCE OFF,
  callback `/api/auth/oidc/callback`). It also joins `infra_admins`, which the group taxonomy did
  not list.
- [correction] The custom-egress/allow-gateways carrier list was incomplete: `calibre-web-automated`
  carries both too. More interesting — **`crowdsec-web-ui` carries NEITHER label**, so whether its
  token-exchange hairpin survives its own CNP posture is an open question that only cluster
  observation can settle. Recorded rather than guessed.
- [observation] A `idm.${PUBLIC_DOMAIN}` coredns override forwards that name straight to the
  envoy-internal ClusterIP instead of the K8S_GATEWAY_IP VIP — a refinement of the split-horizon
  claim that does not contradict it.
- [observation] The passkey-only, token-encryption and SecurityPolicy-fragility claims remain
  UNVERIFIABLE from the repo (IdP runtime / envoy-gateway controller behavior). Left as-is rather
  than promoted to verified.

## Update 2026-08-15 — homepage joins as the 5th native OIDC client

Homepage 2.0 shipped a built-in auth gate, so the dashboard moved from having no identity gate at the origin to being a native OIDC client. Recorded from a live measurement of the deployed change, not from the plan.

- [observation] [client] **homepage** — 5th native OIDC client (`gate: native`, subdomain `dash`, callback `/api/auth/callback/homepage-oidc`, group `infra_admins`), declared in provision/pocket-id/clients.yaml with its app at kubernetes/apps/selfhosted/homepage/. Total client count is now 16 (11 gateway-gated + 5 native).
- [observation] [security] **PKCE is ON for homepage** — no `pkce_enabled` override. Verified twice: upstream source (`src/pages/api/auth/[...nextauth].js` sets `checks: ["pkce", "state", "nonce"]`) and the live authorize redirect, which carries `code_challenge` plus `code_challenge_method=S256`. It is the second native client to keep PKCE on, after grafana; pingvin-share-x, calibre-web-automated and crowdsec-web-ui remain off.
- [observation] [security] **Homepage applies no claim-based authorization of its own.** Upstream documents it explicitly: it grants access to any identity the configured provider authorizes. Unlike grafana (`role_attribute_path`) or crowdsec-web-ui (`CONFIG_AUTH_OIDC_ADMIN_GROUPS_0` plus `UNMATCHED_ROLE: deny`), the Pocket ID client's `allowed_user_groups` is the ONLY access control. Weakening that group restriction is a full dashboard exposure with no second line of defense inside the app.
- [observation] [secret] homepage needs TWO secrets, not one: `HOMEPAGE_OIDC_CLIENT_SECRET` from the usual `HomeOps/pocket-id-clients` field `homepage_client_secret`, plus `HOMEPAGE_AUTH_SECRET` (min. 32 chars, NextAuth cookie signing) which is app-owned and lives in `HomeOps/homepage` as `auth_secret`. A native OIDC client is not automatically a single-secret consumer.
- [observation] [egress] The token-exchange hairpin was **measured working** for a client carrying `egress.home.arpa/allow-world: "true"` (baseline egress plus world): the pod resolved the discovery document and produced a complete authorize redirect to the public issuer. This confirms the AD-023 claim that baseline-egress clients need no extra label, for the allow-world case. It says nothing about crowdsec-web-ui's no-label posture — that question stays open.
- [observation] [taxonomy] `infra_admins` now grants: hubble-ui, echo-server, crowdsec-web-ui, homepage, and Grafana's Admin role.
- [observation] [gotcha] **`just pocket-id apply` must not be run with piped stdin.** The recipe's `sync-secrets` step calls `op item edit`, which reads a non-TTY stdin as a JSON template and fails with `invalid JSON provided`. The Terraform apply succeeds while the 1Password sync silently does not, leaving every consuming ExternalSecret stale. Recovery is `just pocket-id sync-secrets` run without a pipe — the secret survives in Terraform state, so the client does not need rotating.
- [correction] The provisioning-model section says provider `trozz/pocketid` 2.1.0; `provision/pocket-id/main.tf:15` pins **2.3.0**. Noticed incidentally while applying the homepage client (a stale local plugin cache surfaced the version), not as part of a full re-verification.

Note: `verified_at` is deliberately NOT bumped. Only the claims touched above were re-verified; the rest of this note still dates from the 2026-08-03 audit.


## Update 2026-08-15 — pocket-id transactional email

Pocket ID now sends outbound transactional email through the shared SMTP2GO relay, closing the
"silent IdP" gap. Recorded from the committed config plus a human-verified live delivery test,
not from an independent AI cluster observation.

- [observation] [feature] **Transactional email is ON.** The IdP emits login-from-new-device
  notifications, admin-initiated one-time login codes, API-key-expiry warnings, and
  signup/email-change verification mail via mail-eu.smtp2go.com:465 (implicit TLS,
  SMTP_TLS=tls). Credentials come from the shared HomeOps/smtp2go 1Password item through the
  pocket-id ExternalSecret (dataFrom extract with the smtp2go_ prefix rewrite, same shape as
  pingvin-share-x); no SMTP credential is committed to git.
- [observation] [decision] **UI_CONFIG_DISABLED=true** — the Pocket ID docs are explicit that
  SMTP_* and EMAIL_* env vars are effective ONLY with this flag (the admin UI is the default
  source), so the GitOps/env path necessarily takes the global override. Every override-able
  var is pinned in the helmrelease env for determinism (no silent reset on rollout): APP_NAME=IdM,
  SESSION_DURATION=60, HOME_PAGE_URL=/settings/account, REQUIRE_USER_EMAIL=true,
  EMAILS_VERIFIED=false, ALLOW_OWN_ACCOUNT_EDIT=true, ALLOW_USER_SIGNUPS=disabled (agrees with
  the pocket-id-external HTTPRoute /signup + /api/signup 403), DISABLE_ANIMATIONS=false,
  ACCENT_COLOR=default, LDAP_ENABLED=false (LDAP unused), the four EMAIL_* flags ON,
  EMAIL_ONE_TIME_ACCESS_AS_UNAUTHENTICATED_ENABLED=false (passkey-only posture preserved),
  WebAuthn defaults (required / synced / any), and CIMD_URL_ALLOWLIST=[] (metadata-document
  clients disabled). 21 dead-config vars excluded (SIGNUP_DEFAULT_* with signup off, 18 LDAP_*
  maps with LDAP off, SMTP_PASSWORD_FILE).
- [observation] [security] **Passkey-only posture unchanged.** The email-code login bypass
  (EMAIL_ONE_TIME_ACCESS_AS_UNAUTHENTICATED_ENABLED) is explicitly OFF; email adds notification
  + verification + admin recovery, it does NOT add a mailbox-access auth path.
- [observation] [debt-closed] The CNP SMTP2GO egress rule (012239c16), committed ahead with no
  in-pod consumer, now has one — this roadmap closes that dangling allow.
- [observation] [verify] Delivery was human-verified live (test mail arrived, DMARC-aligned on
  .msg; just pocket-id audit unchanged; no SMTP errors in VictoriaLogs). The AI did not
  independently re-run the cluster checks.
- [observation] [verify-status] verified_at is deliberately NOT bumped — only the email-related
  claims above are freshly verified; the rest of this note still dates from the 2026-08-03 audit
  (per the area-reference-staleness-audit convention, same as the homepage update above).
- relates_to [[pocket-id-email-sending]] (progress)
