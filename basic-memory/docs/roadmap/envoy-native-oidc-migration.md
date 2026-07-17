---
title: envoy-native-oidc-migration
type: note
permalink: home-ops/docs/roadmap/envoy-native-oidc-migration
---

# Envoy-native OIDC migration — retire tinyauth forward-auth

## Metadata (observation-form, schema validation)

- [topic] Replace tinyauth forward-auth with an Envoy Gateway native OIDC login gate + Pocket-ID per-client default-deny group authorization
- [status] proposed
- [priority] high
- [area] iam
- [created_at] 2026-07-17
- [updated_at] 2026-07-17
- [decided_with] human (research-backed 3-way comparison + 7-branch verification + post-verification design simplification)

## Why (motivation)

The tinyauth v5.1.x upgrade surfaced a class of ACL bugs that shook trust in it as the Policy Enforcement Point (PEP):

- Under `TINYAUTH_AUTH_ACLS_POLICY=deny`, an empty per-app whitelist abstains and the deny policy resolves that to Deny **before** the group rule runs, so groups-only config denies everyone (login gate + per-app). Upstream #1010 (in `v5.1.1-rc.1`) only fixes this under the default `allow` policy; the deny path is still broken. We filed an upstream issue and worked around it with `OAUTH_WHITELIST "/.*/"` globally and per app.
- The workaround means per-app access now hinges **solely** on `OAUTH_GROUPS`. tinyauth's `OAuthGroupRule` returns Allow on an empty/missing group ACL (documented "default to allow even with a deny policy"), so a forgotten/typo'd group ACL fails **open** to any authenticated user. The deny policy does not catch it.

Net: the enforcement semantics are subtle, version-fragile, and have a real fail-open trap. This roadmap moves enforcement out of tinyauth entirely, eliminating the component and its bug class.

## Decision (research-backed, 2026-07-17)

Evaluated three directions in depth (authoritative sources, per-option research):

1. **Envoy Gateway native OIDC (v1.8.2)** — CHOSEN. Keeps Pocket-ID; removes tinyauth entirely; fail-closed default at the IdP; zero extra runtime footprint (Envoy already runs).
2. **Authelia** — rejected for our constraint: cannot act as an OIDC Relying Party (no federation to Pocket-ID, by project intent). Would replace Pocket-ID with an LDAP/file identity store, splitting the identity source and weakening passkey-first. Strong ACL + Envoy ext-authz integration otherwise.
3. **Authentik** — rejected as overkill on a single node: Server + Worker + PostgreSQL, ~0.7–1 GB+ RAM vs two featherweight Go services; also default-ALLOW (must bind every app). Capable but footprint-wrong.

## Verification outcome + design simplification (2026-07-17)

A 7-branch verification (Envoy Gateway API schema, upstream issues, Pocket-ID behavior, header-consumption gap, codebase grep, synthesis) surfaced one migration-blocking flaw in the original design and led to a simpler, stronger architecture.

- **Original design flaw** — it relied on a `jwt` provider re-extracting the ID token from the OIDC session cookie to feed claims to a proxy-level `authorization` block. That "bridge" is NOT upstream-documented, and at v1.8.2 it works only with `oidc.disableTokenEncryption: true` — a raw ID token sitting in the browser cookie, an OAuth BCP / BFF anti-pattern. `forwardIDToken` is unimplemented (envoyproxy/gateway #9082, v1.9.0-planned) and the access token is opaque, so the cookie route was effectively the only way to do proxy-level group authz — at the cost of token exposure. This is the single highest-risk assumption in the original note and it does not hold to a security-first bar.
- **Simplification (CHOSEN)** — move group enforcement to where it already lives for OIDC-native apps: **Pocket-ID per-client `allowed-groups`**. Pocket-ID v2 is **default-deny per client**: *"If you create a new OIDC Client, no user groups and therefore no users are allowed to access the client"* (pocket-id.org/docs/configuration/allowed-groups); opening a client to all users requires an explicit `Unrestrict` action. The repo runs `ghcr.io/pocket-id/pocket-id:v2.8.0-distroless`, so this is live behavior. An out-of-group user is denied at the IdP (never completes the auth-code flow, sees "You're not allowed to access this service"), so the Envoy SecurityPolicy needs only the `oidc` block — no `jwt`, no `authorization`, no `disableTokenEncryption`.

Net effect of the simplification: fail-closed at the IdP, **zero token exposure**, **nothing forwarded to the app**, and the whole class of jwt/cookie risks drops out (#7315 groups-overflow, #8649 policy composition, #9082 forwardIDToken).

## Correction to prior belief

The `sso-implementation` note implies OIDC-native apps already use `SecurityPolicy.oidc`. **There is currently NO SecurityPolicy with an `oidc` block anywhere in the repo** (grep-verified). OIDC-native apps (Grafana, Paperless, Actual, Pingvin) use **app-level** OIDC (their own client env/secret), not Envoy Gateway OIDC. So `SecurityPolicy.oidc` is a **new pattern** for this repo — treat the migration as a genuine first-introduction with a real pilot. (What IS already proven in-repo is Pocket-ID per-client default-deny group gating — the OIDC-native apps rely on exactly that.)

## Current state (grep-verified 2026-07-17)

tinyauth forward-auth protects **10 apps** via the shared component `kubernetes/components/forward-auth` (`SecurityPolicy.extAuth` → tinyauth in `security` ns, fail-closed, ReferenceGrant for cross-ns backendRef). Each app `ks.yaml` pulls the component and sets `postBuild.substitute.APP`.

Per-app inventory (host = CONFIG_DOMAIN, group = OAUTH_GROUPS, from tinyauth helmrelease):

| App | Namespace | Host | Group |
|---|---|---|---|
| echo | networking | echo.${PUBLIC_DOMAIN} | echo_server_users |
| hubble-ui | kube-system | hubble.${PUBLIC_DOMAIN} | hubble_users |
| bazarr | downloads | subs.${PUBLIC_DOMAIN} | bazarr_users |
| prowlarr | downloads | indexers.${PUBLIC_DOMAIN} | prowlarr_users |
| qbittorrent | downloads | bt.${PUBLIC_DOMAIN} | qbittorrent_users |
| radarr | downloads | movies.${PUBLIC_DOMAIN} | radarr_users |
| seerr | downloads | reqs.${PUBLIC_DOMAIN} | seerr_users |
| sonarr | downloads | shows.${PUBLIC_DOMAIN} | sonarr_users |
| maintainerr | downloads | maintainerr.${PUBLIC_DOMAIN} | maintainerr_users |
| subsyncarr | downloads | subsync.${PUBLIC_DOMAIN} | subsyncarr_users |

Today's per-app fine ACL lives in tinyauth env; the coarse gate is Pocket-ID's `allowed-groups` on the single shared `tinyauth` client. The migration moves the fine ACL onto **per-app** Pocket-ID clients (one client per app, each restricted to its group).

`dependsOn: {name: tinyauth, namespace: security}` is present in **8** app `ks.yaml` files: `bazarr, prowlarr, qbittorrent, radarr, seerr, sonarr, subsyncarr, echo`. **hubble-ui** (`kubernetes/apps/kube-system/cilium/ks.yaml`) and **maintainerr** deliberately have NO such dependsOn (cilium is the CNI root — an in-file comment documents that its SecurityPolicy fails closed rather than deadlocking bootstrap). These 8 dependsOn entries must be removed as each app migrates (Phase 2).

Security boundary today: per-gateway `ClientTrafficPolicy` strips `Remote-User/Email/Groups/Name/Sub` before ext-auth so only tinyauth can set them (`kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml`). This strip STAYS as defense-in-depth.

Client-secret delivery pattern to mirror: `ExternalSecret` → `onepassword-connect` ClusterSecretStore, `template.data` (see `kubernetes/apps/security/tinyauth/app/externalsecret.yaml` and `observability/grafana/instance/externalsecret.yaml`) — but note the mandatory key-name difference below.

## Target architecture (revised — OIDC login gate + IdP-side group authz)

Per protected HTTPRoute, one self-contained SecurityPolicy carrying a SINGLE `oidc` block (mirrors the current tinyauth-per-route topology). **Group authorization is NOT in the manifest** — it lives in the app's Pocket-ID client (`allowed-groups`, default-deny).

Request flow:
- unauthenticated → Envoy oidc filter redirects to Pocket-ID
- out-of-group → Pocket-ID denies (no auth code issued) → never reaches the app
- in-group → **encrypted** session cookie (`disableTokenEncryption` stays `false`) → reaches the app
- the app receives **NO identity headers** (EG native OIDC does not forward identity headers upstream)

Key consequences:
- tinyauth Deployment, its ExternalSecret, its SecurityPolicy target, and the `security`-ns ReferenceGrant all go away (Phase 3).
- Both OIDC credentials become **per-app**: a generated client_id (via `clientIDRef`) and the client secret live in one per-app Secret `${APP}-oidc-secret` (own ExternalSecret in the app namespace). **No cross-namespace ReferenceGrant** needed (secret + policy are route-local; the existing security-ns ReferenceGrant retires only in Phase 3).
- No jwt / authorization / token-encryption complexity. Enforcement is fail-closed at Pocket-ID; the proxy only runs the login gate.

### Reusable component `kubernetes/components/gateway-oidc`

The component ships **both** a templated `securitypolicy.yaml` and a templated `externalsecret.yaml`, parametrized via `postBuild.substitute`. Simpler than forward-auth: **no group parameter** (the group is in Pocket-ID), **no cross-ns ReferenceGrant** (secret + policy are route-local).

Per-app `ks.yaml` swaps `components: [../../../../components/forward-auth]` → `[../../../../components/gateway-oidc]` and sets the substitutes below. The manual Pocket-ID + 1Password steps are the per-app HUMAN GATE.

#### Naming & templating conventions (LOCKED)

| Concern | Convention | Notes |
|---|---|---|
| Template params | `APP` (required), `APP_SUBDOMAIN` (optional, default `${APP}`), `HTTPROUTE_NAME` (optional, default `${APP}`) | `${PUBLIC_DOMAIN}` comes from cluster-settings substituteFrom |
| Pocket-ID client | one per app, **generated (UUID) client_id**, `restricted`, `allowed-groups: [${APP}_users]`, **PKCE-require OFF** | UI-managed; default-deny (v2) |
| Pocket-ID group | `${APP}_users`, one per app | NOT referenced by the manifest (enforcement is at the IdP) |
| client_id → manifest | `oidc.clientIDRef.name: ${APP}-oidc-secret` (EG reads key **`client-id`**) | no inline `clientID`; generated id stays out of Git |
| client_secret → manifest | `oidc.clientSecret.name: ${APP}-oidc-secret` (EG reads key **`client-secret`**) | both creds in ONE Secret |
| 1Password item | item name = **`${APP}`** (the app's existing item), fields `${APP}_OIDC_CLIENT_ID` + `${APP}_OIDC_CLIENT_SECRET` | per-app item, app-prefixed fields |
| ExternalSecret | target Secret `${APP}-oidc-secret`; `template.data` maps 1P `${APP}_OIDC_CLIENT_ID`→`client-id`, `${APP}_OIDC_CLIENT_SECRET`→`client-secret` | store = `onepassword-connect` |
| Host (single source) | `${APP_SUBDOMAIN:=${APP}}.${PUBLIC_DOMAIN}` drives BOTH the app HTTPRoute host AND the oidc `redirectURL` | guarantees redirectURL == route host |
| Callback / logout | `redirectURL` path `/oauth2/callback`; `logoutPath` `/oauth2/logout` | namespaced to avoid app-route collision (verify in pilot) |
| SecurityPolicy name | `${APP}-oidc` | |
| cookieNames | `${APP}-id-token` / `${APP}-access-token` | |
| scopes | `["openid","profile","email"]` | groups scope NOT required (gating is at Pocket-ID) — keeps cookie small |

**Subdomain unification (why `APP_SUBDOMAIN` is safe as a default-to-`${APP}` var):** the danger of a subdomain default is a `redirectURL` that silently diverges from the real route host (most of our hosts differ from the app name — e.g. qbittorrent = `bt`). We remove the danger by making `${APP_SUBDOMAIN:=${APP}}` the SINGLE source consumed by BOTH the app's HTTPRoute hostname (templated in the app manifest) and the oidc `redirectURL`. They cannot diverge. Apps whose subdomain differs set `APP_SUBDOMAIN` in their `ks.yaml`; apps where subdomain == app name set nothing.

### Example SecurityPolicy (echo pilot), repo conventions

```yaml
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: ${APP}-oidc
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: ${HTTPROUTE_NAME:=${APP}}
  oidc:
    provider:
      issuer: "https://id.${PUBLIC_DOMAIN}"
    clientIDRef:
      name: ${APP}-oidc-secret          # EG reads key: client-id
    clientSecret:
      name: ${APP}-oidc-secret          # EG reads key: client-secret
    redirectURL: "https://${APP_SUBDOMAIN:=${APP}}.${PUBLIC_DOMAIN}/oauth2/callback"
    logoutPath: "/oauth2/logout"
    scopes: ["openid", "profile", "email"]
    cookieNames:
      idToken: ${APP}-id-token
      accessToken: ${APP}-access-token
```

### Example ExternalSecret (shipped by the component, app namespace)

```yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: ${APP}-oidc
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: ${APP}-oidc-secret
    creationPolicy: Owner
    template:
      data:
        client-id: "{{ .client_id }}"
        client-secret: "{{ .client_secret }}"
  data:
    - secretKey: client_id
      remoteRef: { key: ${APP}, property: ${APP}_OIDC_CLIENT_ID }
    - secretKey: client_secret
      remoteRef: { key: ${APP}, property: ${APP}_OIDC_CLIENT_SECRET }
```

Group gating for echo lives in its Pocket-ID client: `echo` (generated id), `allowed-groups: [echo_server_users]`, `restricted` (default-deny), PKCE-require OFF. No `jwt` and no `authorization` block anywhere in this policy. Confirmed against the live CRD: `clientIDRef` reads key `client-id`, `clientSecret` reads key `client-secret`, and "exactly one of clientID or clientIDRef must be set".

## Key decisions, risks, and mitigations (revised)

1. **Enforcement is authentication + login-time authorization, NOT per-request.** After login, the encrypted session cookie grants access until expiry; a group revoked in Pocket-ID takes effect only at session/refresh expiry, not immediately. Mitigation: short session TTL (tune + verify in pilot). Accepted tradeoff for zero token exposure — correct for a homelab.
2. **The app is unauthenticated behind the gate.** The dumb apps have weak/no native auth, so total security depends on the gateway being the ONLY ingress path to the app. Backstop: per-app CiliumNetworkPolicy default-deny + `ingress-from-gateways` (DONE — V1–V5 CNP rollout, see `docs/progress/cnp-per-app-audit`). Any new Service/route exposure without CNP coverage reopens this.
3. **Per-route policy coverage is a discipline risk.** There is no gateway-wide auth default (deliberately avoided, #8649). A new HTTPRoute / second hostname without the gateway-oidc component is silently unauthenticated. Closed by guardrail (A).
4. **Pocket-ID client config is out-of-band** (UI / SQLite, not Git). The client→group binding and the `Unrestrict` flag are not code-reviewed and ride only in VolSync backup. Closed by guardrail (B). Conscious tradeoff vs the rejected pocket-id-operator (AI-generated code + CRD overhead).
5. **Per-app OIDC client + per-app group are MANDATORY for per-app ACL.** The `allowed-groups` restriction is a property of the client, and each app has a distinct host (own callback) + own secret — so per-app clients are required regardless of ACL, and doubly so for per-app access rules. Decided: 1:1 model — one client per app (**generated client_id**) + one group `${APP}_users` per app, client `restricted` (default-deny). The group-taxonomy is fixed at 1:1 (not consolidated).
6. **Single IdP = single point of compromise.** Inherent to any SSO. Pocket-ID is passkey-only (phishing-resistant authn), distroless/nonroot, CNP-restricted. Verify the JWT signing keys in the PVC are covered by an **encrypted** Kopia→S3 backup.
7. **API stability: v1alpha1 (alpha).** No version bump at v1.8.2, but the API may shift; pin and watch release notes.
8. **Cookie 4096-byte limit (#7315, OPEN)** — largely moot now (groups are not needed in the token for gating). Still measure the real session cookie size in the pilot.
9. **External-gateway rate-limit disabled** (#8798, awaits v1.9.0). Cloudflare WAF covers external. Pre-existing gap, not introduced here.
10. **Header-strip stays.** Keep the ClientTrafficPolicy Remote-* strip as defense-in-depth even though the oidc gate injects nothing.
11. **No VolSync/backup impact** (no new stateful component).
12. **PKCE is not reliably usable at v1.8.2 (accepted).** The live CRD has no `pkce` field, and Envoy Gateway's OIDC filter has incomplete PKCE — it sends `code_challenge` but omits the `code_verifier` on token exchange (envoyproxy/gateway #7844), so a provider that *enforces* PKCE breaks the login (401). Mitigation: keep **PKCE-require OFF** on the Pocket-ID clients. Security impact accepted: the Envoy gate is a **confidential client** (server-side `client_secret`, server-to-server token exchange over TLS, strict Pocket-ID `redirect_uri` validation), so PKCE here is defense-in-depth, not the primary control. It is a residual gap vs the OAuth 2.1 "PKCE everywhere" bar, inherent to EG's OIDC maturity — revisit when a `pkce` knob lands upstream.
13. **EG version pin.** Repo pins `gateway-helm` `tag: 1.8.2`. `clientIDRef` is present and functional in that CRD (verified live). `forwardIDToken` appears in the CRD but is functionally incomplete at v1.8.2 (#9082) — not used by this design.

## Guardrails (close the fail-open discipline gaps — make it as security-first as this stack sensibly allows)

- **(A) Route-coverage CI check** — assert every HTTPRoute attached to `envoy-external` / `envoy-internal` has an attached SecurityPolicy (gateway-oidc or forward-auth) OR is on an explicit public-service allowlist. pre-commit or CI. Closes risk #3. Land with Phase 3.
- **(B) Client-restricted assertion** — a periodic check (cron/CI) via the Pocket-ID API asserting every gated client is `restricted` and bound to the expected group (spec = the client→group mapping recorded in Phase 0). Closes risk #4 and part of #1. Land with Phase 4.
- **(C) App-native auth as defense-in-depth** — keep each app's own auth where it exists (qbittorrent WebUI password, *arr auth) so the gate is not the sole layer.
- **(D) Exposure reduction (open decision, orthogonal to auth)** — apps that do not need internet move to `envoy-internal` only (LAN). The single biggest attack-surface reducer; decide per app in Phase 0 (mirrors the Grafana LAN-only decision).
- **(E) Pilot-verify session security** — confirm PKCE-require is OFF on the client (EG can't complete PKCE, #7844), cookie `HttpOnly`/`Secure`/`SameSite` + encryption default (`disableTokenEncryption` stays false), logout + refresh behavior, measured cookie size. Do not assume — verify on echo.

## Interim hardening (do now, independent of migration)

1. CI/pre-commit guard: assert every `TINYAUTH_APPS_<app>_CONFIG_DOMAIN` has a non-empty `_OAUTH_GROUPS` (closes the fail-open missing-group trap while tinyauth is still live).
2. Pin tinyauth off the release candidate onto stable GA once released (an RC guarding all internal apps is elevated risk).

## Phased execution plan (revised)

### Phase 0 — prep
- Confirm Pocket-ID default-deny is live (v2.8.0). **Group taxonomy is fixed at 1:1** (`${APP}_users` per app) — record the app→(host/subdomain, group) mapping in this note (the spec guardrail (B) asserts against).
- Decide per-app **exposure** (external vs internal-only) — guardrail (D).
- Author `kubernetes/components/gateway-oidc` — ships templated `securitypolicy.yaml` (clientIDRef + clientSecret + redirectURL from `${APP_SUBDOMAIN:=${APP}}`) **and** `externalsecret.yaml` (maps 1P `${APP}` item fields to keys `client-id`/`client-secret`). Params: `APP` + optional `APP_SUBDOMAIN` + optional `HTTPROUTE_NAME`.
- Apply the two interim hardening items.
- Acceptance: component renders (flux-local / kustomize build); a Pocket-ID test client (generated id, restricted, PKCE-require OFF) denies an out-of-group user at login; an in-group user completes login.

### Phase 1 — pilot on echo (lowest risk, networking ns)
- Pocket-ID: create client `echo` (**generated client_id**, redirect `https://echo.${PUBLIC_DOMAIN}/oauth2/callback`), `restricted`, `allowed-groups: [echo_server_users]`, **PKCE-require OFF**. Add fields `echo_OIDC_CLIENT_ID` + `echo_OIDC_CLIENT_SECRET` to the 1Password item `echo`.
- The gateway-oidc component supplies echo's `externalsecret.yaml` → Secret `echo-oidc-secret` (keys `client-id` + `client-secret`).
- Swap echo `ks.yaml`: forward-auth → gateway-oidc component; substitute `APP=echo` (echo's subdomain == app name, so no `APP_SUBDOMAIN` needed); **remove `dependsOn: {name: tinyauth, namespace: security}`**. Keep tinyauth for all other apps.
- Template echo's HTTPRoute host to `${APP_SUBDOMAIN:=${APP}}.${PUBLIC_DOMAIN}` (single-source host) if not already.
- Verify (observable): in-group user reaches echo (200); out-of-group authenticated user is denied at Pocket-ID (not the app); unauthenticated → Pocket-ID login; logout works; refresh works; measure the session cookie size (#7315); confirm echo needs no injected identity headers; confirm no ext-auth call to tinyauth in Envoy logs.
- Guardrail (E) checks pass.
- Acceptance: all checks pass; no tinyauth involvement for echo.

### Phase 2 — roll out app by app
Order (low blast radius first): hubble-ui, then the *arr read-only UIs (bazarr, subsyncarr, maintainerr), then prowlarr/sonarr/radarr, then seerr, then qbittorrent last (most-used). For each app:
1. Pocket-ID: create client (generated id) `restricted` + `allowed-groups: [${APP}_users]`, PKCE-require OFF; add `${APP}_OIDC_CLIENT_ID` + `${APP}_OIDC_CLIENT_SECRET` fields to the app's 1P item `${APP}`.
2. Swap the component (forward-auth → gateway-oidc) + set substitutes in `ks.yaml`: `APP`, and **`APP_SUBDOMAIN`** where the subdomain differs from the app name (e.g. qbittorrent → `APP_SUBDOMAIN=bt`, bazarr → `subs`, prowlarr → `indexers`, radarr → `movies`, sonarr → `shows`, seerr → `reqs`, subsyncarr → `subsync`, hubble-ui → `hubble`).
3. Template the app's HTTPRoute host to `${APP_SUBDOMAIN:=${APP}}.${PUBLIC_DOMAIN}` (single-source host shared with the redirectURL).
4. **Remove the tinyauth `dependsOn`** (only the 8 apps that carry it — hubble-ui and maintainerr have none).
5. Reconcile; run the Phase-1 verification set. tinyauth stays live for not-yet-migrated apps throughout.
- Acceptance per app: group gating verified (in/out at Pocket-ID), redirectURL == route host, cookie size OK, app functional, dependsOn removed where present.

### Phase 3 — decommission tinyauth
Only after all 10 apps are migrated and verified:
- Remove `kubernetes/apps/security/tinyauth` (HelmRelease, ExternalSecret, referencegrant, ks.yaml, ciliumnetworkpolicy).
- Remove the `security`-ns ReferenceGrant and the now-unused `components/forward-auth` (or keep archived if any future header-injection need arises).
- Remove the tinyauth 1Password item.
- Land guardrail (A) route-coverage check.
- Acceptance: no references to tinyauth remain (grep); all apps still gated; flux reconciled clean.

### Phase 4 — docs + close-out
- Update `docs/areas/iam` (new trust chain: Envoy oidc login gate + Pocket-ID default-deny group authz, no PEP service), `sso-implementation` (supersede the tinyauth PEP path), `kubernetes/apps/security/CLAUDE.md`.
- Land guardrail (B) client-restricted assertion.
- Cross-link the upstream tinyauth issue outcome.
- Record an ADR for the PEP change (`docs/decisions`).

## Rollback

Per app, until Phase 3: revert the `ks.yaml` component swap (gateway-oidc → forward-auth), restore the tinyauth `dependsOn`, and remove the SecurityPolicy; tinyauth still protects it. After Phase 3, rollback means re-deploying tinyauth from git history. Keep Phase 3 as a distinct, late, reversible-by-revert commit.

## Open questions to resolve during Phase 0/1

- Envoy oauth2 filter callback path convention (`/oauth2/callback` vs other) at v1.8.2.
- Measured session cookie size with our real group memberships (largest-group user).
- Group taxonomy decision (1:1 per app vs consolidated per audience) — Phase 0.
- Per-app exposure decision (external vs internal-only) — Phase 0.
- Whether any app has a trusted-header auto-login mode we rely on (expectation: none; all 10 are gate-only per grep — no `remote_user|auth_proxy|REMOTE_|X-Forwarded-User` consumption found in the app trees).

## Related

- relates_to [[sso-implementation]] (docs/roadmap) — supersedes its tinyauth PEP path
- relates_to [[iam]] (docs/areas) — updates the trust chain
- relates_to [[networking]] (docs/areas) — Envoy Gateway SecurityPolicy
- relates_to [[external-secrets]] (docs/areas) — per-app OIDC client secret
- relates_to [[cnp-per-app-audit]] (docs/progress) — the CNP default-deny backstop that risk #2 depends on
- fixes [[tinyauth-deny-policy-groups-only]] — upstream bug that motivated this
