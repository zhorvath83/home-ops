---
title: homepage-gateway-oidc
type: roadmap
permalink: docs/roadmap/homepage-gateway-oidc
topic: Move the Homepage dashboard (dash) from its built-in OIDC login to the Envoy
  gateway-oidc gate
status: proposed
priority: medium
scope: 'Switch homepage from gate native (next-auth inside the app) to gate envoy
  (components/gateway-oidc SecurityPolicy on the homepage HTTPRoute), and turn the
  app''s own auth off so there is exactly one login. Touches kubernetes/apps/selfhosted/homepage/{ks.yaml,app/helmrelease.yaml,app/externalsecret.yaml},
  provision/pocket-id/clients.yaml (Pocket ID client callback), 1Password item homepage.
  Out of scope: what the dashboard shows, its RBAC and widgets.'
rationale: 'Homepage is a high-value target: it runs with a ServiceAccount that reads
  the Kubernetes API, its widget proxy reaches internal services with stored API tokens,
  and it is published on envoy-external. Today every unauthenticated request reaches
  the Next.js app and its next-auth middleware decides. Behind gateway-oidc no request
  reaches the app before a Pocket ID login, so a future Next.js / next-auth / Homepage
  auth bug (CVE-2025-29927-class middleware bypass) is not reachable from the internet.
  It also aligns dash with the other non-OIDC-native admin tools (echo, backrest,
  kopia, victoria-logs, hubble-ui).'
options:
- Replace native auth with gateway-oidc, app auth off — RECOMMENDED (agreed 2026-11-23)
- Add gateway-oidc in front and keep native auth (double login; lint R4 forbids it
  for gate native clients)
- Keep native auth only
related_areas:
- iam
- k8s-workloads
- networking
---

# Homepage behind gateway-oidc

## Metadata (observation-form, schema validation)

- [topic] Move the Homepage dashboard from its built-in OIDC login to the Envoy gateway-oidc gate
- [status] in-progress — deployed 2026-11-23 (commit e2da05c17), AC2 and Phase 4 pending
- [priority] medium
- [researched_at] 2026-11-23
- [effort] S

## What we gain

- Zero pre-auth application surface on `dash`: Envoy answers every unauthenticated request with a redirect to `idm/authorize`; the Next.js app sees only authenticated traffic.
- One login implementation for all admin tools that are not OIDC-native, covered end to end by the route-auth guard (R3 checks the SecurityPolicy wiring, L2 the rendered policy).
- One secret fewer (`HOMEPAGE_AUTH_SECRET`, the next-auth session key) and no app-side OIDC config to keep in step with Pocket ID.

## What we accept

- `/api/healthcheck` becomes login-gated at the gateway. Kubelet probes hit the pod directly (`Host: localhost:3000`), so they are unaffected; there is no external monitor on `dash`.
- The login screen is the Pocket ID page reached through Envoy, not Homepage's own sign-in button.
- Homepage no longer knows who the user is. Nothing in the current config uses identity (no per-user layouts); access is decided by the Pocket ID group (`infra_admins`).
- A request that reaches the pod **without** passing the gateway is unauthenticated once app auth is off. The pod must only be reachable from the gateways (Phase 0 check).

## Research findings (live, 2026-11-23)

- [evidence] Homepage `v2.8.0`, `HOMEPAGE_AUTH_ENABLED: "true"`, `HOMEPAGE_OIDC_ISSUER/CLIENT_ID/NAME`, `HOMEPAGE_EXTERNAL_URL`; secrets `HOMEPAGE_AUTH_SECRET` + `HOMEPAGE_OIDC_CLIENT_SECRET` from ExternalSecret `homepage` (1Password `homepage.auth_secret`, `pocket-id-clients.homepage_client_secret`).
- [evidence] Unauthenticated probe of `https://dash.${PUBLIC_DOMAIN}` via the LAN gateway: `/` and every `/api/*` path tried (`services`, `widgets`, `bookmarks`, `config/settings.yaml`, `hash`, `kubernetes/status`, `releases`, `siteMonitor`, `ping`, `services/proxy`) → 307 to `/auth/signin`. Only `/api/healthcheck` (200 `up`), `/api/auth/session` (200 `{}`) and `/api/auth/providers` (200, provider list) answer without login.
- [evidence] `x-middleware-subrequest` (CVE-2025-29927 middleware bypass) with four payload variants → 403 from the CrowdSec AppSec virtual patch `crowdsecurity/vpatch-CVE-2025-29927` (4 LAPI alerts, no ban: LAN source whitelisted). The bypass did not reach the app, but the protection came from the WAF, not from the app.
- [evidence] Pocket ID client `homepage`: `gate: native`, `subdomain: dash`, `callback_path: /api/auth/callback/homepage-oidc`, groups `[infra_admins]`, `pkce_enabled` defaults to true (`provision/pocket-id/locals.tf:27`) — already what gateway-oidc requires (EG always sends PKCE S256).
- [evidence] The rendered HTTPRoute is `selfhosted/homepage` (app-template route key `app`), so the component default `HTTPROUTE_NAME=${APP}` = `homepage` matches without an override.
- [evidence] `components/gateway-oidc/externalsecret.yaml` reads `pocket-id-clients.${APP}_client_secret` = `homepage_client_secret` — the same 1Password field the native setup uses, so no client secret rotation is needed.
- [fact] `locals.tf:15` derives the callback for `gate: envoy` as `https://<sub>.${PUBLIC_DOMAIN}/oauth2/callback`; `extra_callback_urls` exists for a transition window.
- [fact] Lint rules that apply: R3 (gate envoy client ⇔ Kustomization includes `components/gateway-oidc`, APP/APP_SUBDOMAIN match `homepage`/`dash`, exactly one hostname on the route), R4 (a gate native client must not include the component). R4 does not inspect app env, so "native auth left on behind the gate" is a manual check.

## Design

Target state, mirroring `home-gallery`:

- `ks.yaml`: `components: [../../../../components/gateway-oidc]`, `postBuild.substitute: {APP: homepage, APP_SUBDOMAIN: dash}`, `dependsOn` + `pocket-id` (security) like home-gallery.
- `helmrelease.yaml`: drop `HOMEPAGE_AUTH_ENABLED`, `HOMEPAGE_OIDC_*`; keep `HOMEPAGE_ALLOWED_HOSTS`; drop `HOMEPAGE_EXTERNAL_URL` only if Phase 0 shows it is auth-only.
- `externalsecret.yaml`: drop `HOMEPAGE_AUTH_SECRET`, `HOMEPAGE_OIDC_CLIENT_SECRET` and the `pocket-id-clients` data entry; keep OWM token and `services.yaml`.
- `clients.yaml`: `homepage: {gate: envoy, subdomain: dash, groups: [infra_admins]}` (no `callback_path`).

## Plan

### Phase 0 — Preconditions
1. Reachability: confirm only the two envoy gateways (and Prometheus, if scraped) may reach the homepage pod on 3000 — read the CCNPs selected by `ingress.home.arpa/allow-gateway-*`, and a Hubble capture (`just k8s hubble-live-capture`, `hubble-analyze k8s:app.kubernetes.io/name=homepage FORWARDED ingress`).
2. Homepage source/docs: what `HOMEPAGE_AUTH_ENABLED=false` disables (next-auth routes gone, middleware off) and whether `HOMEPAGE_EXTERNAL_URL` has a non-auth use.
3. `just pocket-id plan` with the client change: expect an in-place update of `callback_urls` only, no replacement (a replacement would rotate the client secret).

### Phase 1 — Pocket ID first (no lock-out window)
- `clients.yaml`: `gate: envoy` **plus** temporary `extra_callback_urls: [https://dash.${PUBLIC_DOMAIN}/api/auth/callback/homepage-oidc]` so the running native login keeps working until Flux reconciles. `just pocket-id apply`.

### Phase 2 — Cluster change (one commit)
- ks.yaml, helmrelease.yaml, externalsecret.yaml as in Design. `provision/pocket-id/lint.sh` + pre-commit green; flate render shows `SecurityPolicy selfhosted/homepage-oidc` targeting `HTTPRoute homepage`, `ExternalSecret homepage-oidc`.
- After reconcile: SecurityPolicy `Accepted`, `EnvoyGatewayPolicyNotAccepted` silent, homepage pod restarted (reloader) without auth env.

### Phase 3 — Verify
- Unauthenticated (LAN and mobile data): `/` and `/api/services` → 302 to `idm/authorize`; `/api/healthcheck` → 302; `/api/auth/providers` → 302 (no longer answered by the app).
- Logged in as an `infra_admins` member: dashboard, Kubernetes widgets and service widgets render; `/oauth2/logout` ends the session.
- A Pocket ID user outside `infra_admins` is refused at the IdP.
- Re-run the CVE-2025-29927 probe: 302 from Envoy before the WAF matters.

### Phase 4 — Cleanup and docs
- Remove `extra_callback_urls`, `just pocket-id apply`.
- 1Password: delete `homepage.auth_secret`.
- BM `docs/areas/iam` (gateway-oidc consumers), `docs/areas/k8s-workloads`; [[cloudflare-access-decommission]] table (dash: native → gateway-oidc).

## Acceptance criteria

- AC1: no unauthenticated request to `dash` reaches the homepage pod (Envoy access log `upstream_host` empty / 302 for every unauthenticated path tested).
- AC2: authenticated dashboard fully functional, including Kubernetes widgets.
- AC3: lint L1 + L2 green; no `HOMEPAGE_AUTH_*`/`HOMEPAGE_OIDC_*` left in the repo.

## Rollback

Revert the Phase 2 commit (native auth back) — the `extra_callback_urls` entry keeps the old callback valid until Phase 4, so rollback needs no Pocket ID change during the transition.

## Relations

- relates_to [[iam]]
- relates_to [[k8s-workloads]]
- relates_to [[cloudflare-access-decommission]]

## Execution — 2026-11-23 (direct to main, commit e2da05c17)

- [status] deployed; AC1 + AC3 verified, AC2 (logged-in dashboard) awaits the owner's browser check, Phase 4 cleanup pending
- [deviation] No transitional `extra_callback_urls`: the field is passed to Pocket ID verbatim (`locals.tf` does no substitution, Flux never reads `provision/`), and a literal domain may not be committed. Accepted a few-minute dash login gap instead (owner's decision). Consequence: a rollback also needs the Pocket ID client reverted (`gate: native` + `callback_path`, `just pocket-id apply`).
- [evidence] Phase 0: Cilium endpoint for homepage allows ingress only from envoy-external, envoy-internal and reserved:host. Upstream v2.8.0 `src/proxy.js`: auth off disables the whole next-auth middleware; `HOMEPAGE_EXTERNAL_URL` only feeds `NEXTAUTH_URL` and the secure-cookie decision, so it was dropped. Without auth Homepage stops sending `Cache-Control: private, no-store`; harmless here because Cloudflare bypasses cache zone-wide and anonymous traffic never reaches the app.
- [evidence] `just pocket-id plan`: 0 add / 1 change / 0 destroy, only `callback_urls`; apply synced 26 client secrets.
- [evidence] After reconcile: SecurityPolicy `homepage-oidc` Accepted on both gateways, ExternalSecrets `homepage` + `homepage-oidc` synced, pod env has `HOMEPAGE_AUTH_ENABLED=false` only.
- [evidence] Unauthenticated probe (LAN): `/`, `/api/services`, `/api/widgets`, `/api/healthcheck`, `/api/auth/providers`, `/api/auth/session`, `/api/config/custom.css`, `/api/mcp`, `/api/kubernetes/status`, `/auth/signin` → 302 to `idm/authorize` with `client_id=homepage`, `code_challenge_method=S256`, `redirect_uri=.../oauth2/callback`. CVE-2025-29927 header probe → 403.
- [evidence] Validation: `just pocket-id lint`, `lint-rendered.sh` on a flate render (16 gate-envoy routes carry their policy), pre-commit green. `flate-test` was skipped on the commit: flate 0.8.0 `test --base` livelocks (see [[flate-ci-adoption]]); flate 0.7.3 on the same tree passed 198 checks in 10 s.
- [todo] Owner: log in as an `infra_admins` member, check Kubernetes and service widgets, `/oauth2/logout`; a non-member must be refused at the IdP.
- [todo] Phase 4: delete `homepage.auth_secret` in 1Password; then move this note to docs/progress.
