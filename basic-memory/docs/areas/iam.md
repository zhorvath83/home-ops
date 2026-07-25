---
title: iam
type: area_reference
permalink: home-ops/docs/areas/iam
area: iam
status: current
confidence: high
verified_at: '2026-07-26'
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
- [observation] [consequence] Every endpoint is the public issuer, per AD-023. The OIDC backchannel is therefore ordinary gateway traffic (client pod -> envoy VIP -> pocket-id). Baseline-egress clients need nothing; a client carrying `egress.home.arpa/custom-egress` MUST also carry `egress.home.arpa/allow-gateways` or its token exchange is dropped by its own CNP posture. Current carriers: grafana, pingvin-share-x.
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
| `media_users` | the eight gateway-gated downloads apps |
| `infra_admins` | hubble-ui, echo-server, and Grafana's Admin role |
| `calibre-web-automated_users` / `_admins` | Calibre-Web Automated |
| `pingvin-share-x_admins` | Pingvin Share admin access |

## 7. Client inventory

**Gateway-gated** (`components/gateway-oidc`, callback `/oauth2/callback`): bazarr (subs), sonarr (shows), radarr (movies), prowlarr (indexers), qbittorrent (bt), subsyncarr (subsync), maintainerr, seerr (reqs) — all `media_users`; hubble-ui (hubble) and echo-server (echo) — `infra_admins`.

**Native OIDC**:

- [observation] [client] **grafana** — `auth.generic_oauth` on the grafana-operator instance. Endpoints are the public issuer; `use_pkce: true`; `scopes: openid email profile groups`. `role_attribute_path` maps `infra_admins` -> Admin and everything else -> None, with `role_attribute_strict: true`. The local login form is hidden (`disable_login_form`); the retained admin credential is the grafana-operator's provisioning credential for the in-cluster API, not a human login path.
- [observation] [client] **pingvin-share-x** — discovery-only client; `oidc-discoveryUri` points at `/.well-known/openid-configuration`, `oidc-rolePath: groups`, `oidc-roleAdminAccess: pingvin-share-x_admins`, password login disabled.
- [observation] [client] **calibre-web-automated** — callback `/login/generic/authorized`. `pkce_enabled: false` because Calibre-Web's flask-dance generic OAuth exposes no PKCE toggle and sends no `code_challenge`; it is a confidential client, so the secret still guards the token exchange.

## 8. Operational notes

- [observation] [onboarding] Adding a gated app is two edits plus an apply: a `clients.yaml` entry (`gate: envoy`, subdomain, groups) with `just pocket-id apply`, and the `gateway-oidc` component plus `APP`/`APP_SUBDOMAIN` in the app's `ks.yaml`. `just pocket-id lint` fails if either half is missing or the subdomains disagree.
- [observation] [debt] Calibre-Web Automated's OIDC settings are entered in its admin UI, so its client secret lives in the app database rather than arriving through External Secrets. VolSync backs it up, but it is not reproducible from git — the one workload outside the uniform secret-delivery model.
- [observation] [limitation] **SecurityPolicy discovery-fetch fragility**: the envoy-gateway controller fetches the discovery document on every SecurityPolicy generation bump. If that fetch times out, the policy goes `Accepted=False/Invalid` and the controller sets a 500 direct-response on the gated routes, and it does not self-heal once the endpoint returns. Remediation: `kubectl rollout restart deployment/envoy-gateway -n networking`, after which policies return to Accepted within a few minutes. With a single shared issuer this is one failure point for all gated apps at once.
- [observation] [limitation] There is no auth-audit tooling for the IdP. Pocket ID runs with `LOG_JSON=true`, so a VictoriaLogs-backed audit trail is buildable, but none exists today.
- [observation] [ratelimit] The external gateway carries a Local `BackendTrafficPolicy` rate limit (600 req/min), effectively global on this single-node cluster because one Envoy pod serves each gateway. Cloudflare WAF provides edge rate limiting ahead of it.

## Relations

- decided_in [[AD-023-cnp-threat-model-audit]]
- relates_to [[networking]]
- relates_to [[external-secrets]]
- relates_to [[observability]]
