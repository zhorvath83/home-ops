---
title: sso-implementation
type: note
permalink: home-ops/docs/roadmap/sso-implementation
status: proposed
priority: high
scope: 'Passkey-first SSO: Pocket-ID (OIDC provider) + TinyAuth (forward-auth), replacing
  CF Access. SQLite backend, VolSync backup, MaxMind GeoIP. Default-deny. Two paths:
  OIDC-native -> Pocket-ID direct, OIDC-less -> TinyAuth -> Pocket-ID.'
rationale: Cloudflare Access kivaltasa, passkey-first, csaladbarat, GitOps CRDs, SQLite,
  VolSync backup.
options:
- Pocket-ID + TinyAuth (chosen)
related_areas:
- networking
- external-secrets
- k8s-workloads
tags:
- pocket-id
- tinyauth
- sso
- oidc
- forward-auth
- envoy-gateway
- roadmap
---

## Open Security Gaps & TODOs

> These items must be resolved before considering the SSO migration production-complete.

- [ ] **TinyAuth ACL default-deny gap** — `TINYAUTH_AUTH_ACLS_POLICY: deny` is currently unavailable in TinyAuth v5.0.7 (only in `main`). Per-app ACL blocks (`TINYAUTH_APPS_<NAME>_OAUTH_GROUPS`) are **mandatory**; without them the OAuthGroupRule returns `Allow` on nil ACLs and lets any authenticated user through. Track upstream for a stable release containing the fix.
- [ ] **Rate limiting on external gateway** — `rate-limit-external` `BackendTrafficPolicy` is disabled due to Envoy Gateway v1.8.0 CRD regression (PR envoyproxy/gateway#8798). Cloudflare WAF covers us externally, but this is a cluster-side gap. Re-enable once Envoy Gateway v1.9.0 GA lands and the OCIRepository tag is bumped.
- [ ] **Trusted proxy CIDR review** — `TINYAUTH_AUTH_TRUSTEDPROXIES` is currently set to the full Pod CIDR (`10.244.0.0/16`). Evaluate whether this can be narrowed to the gateway service endpoints only.

---
# SSO implementation - Pocket-ID + TinyAuth replacing Cloudflare Access

## Architecture

Two authentication paths:

1. **OIDC-native apps** (Actual Budget, Grafana, Paperless-ngx) -> Pocket-ID direct via SecurityPolicy.oidc
2. **OIDC-less apps** (Dozzle, Homepage, Uptime Kuma, etc.) -> TinyAuth forward-auth via SecurityPolicy.extAuth -> Pocket-ID

Pocket-ID is the sole identity source. No second OAuth provider at the TinyAuth layer: the passkey-first design means users without a Pocket-ID account simply do not log in. Pocket-ID's OIDC client allowed-groups is the single ACL gate for forward-auth; per-app refinement comes from per-app TinyAuth ACLs (TINYAUTH_APPS_*_USERS_ALLOW). No global TINYAUTH_OAUTH_WHITELIST.

Default-deny: no access unless explicitly configured.

**Migration strategy**: All apps are currently behind Cloudflare Access on the external gateway. Do NOT remove CF Access until the full migration is verified. Migrate apps one by one, testing each path. Only remove CF Access after all apps are confirmed working through Pocket-ID/TinyAuth.

## Pre-flight: Cluster Infrastructure

| Resource | Value | Source |
|---|---|---|
| Public domain | $PUBLIC_DOMAIN | cluster-settings ConfigMap |
| Pod CIDR | 10.244.0.0/16 ($POD_CIDR) | cluster-settings ConfigMap |
| Service CIDR | 10.245.0.0/16 ($SVC_CIDR) | cluster-settings ConfigMap |
| Cluster DNS | 10.245.0.10 ($CLUSTER_DNS_IP) | cluster-settings ConfigMap |
| Storage class | democratic-csi-local-hostpath (default) | AD-011, single-node |
| Secret store | ClusterSecretStore/onepassword-connect, vault HomeOps | external-secrets |
| Wildcard TLS | $PUBLIC_DOMAIN + *.$PUBLIC_DOMAIN via letsencrypt-production | cert-manager |
| Envoy external | ClusterIP, Cloudflare Tunnel -> envoy-external | networking |
| Envoy internal | LoadBalancer, LAN VIP $ENVOY_GATEWAY_IP | networking |
| CNI | Cilium (replaces kube-proxy + CoreDNS) | talos-cluster |
| Backup | VolSync + Kopia + OVH S3, hourly, component-based | volsync-backup |
| Postgres | None -- no database operator in cluster | cluster survey |
| CF Access | Private Cloud (*.horvathzoltan.me), Photos, Flux webhook, Share | cloudflare TF |

Kustomize variable substitution pattern: $VAR from cluster-settings ConfigMap, injected via Flux postBuild.substituteFrom. Defaults via $VAR:=default syntax (see VolSync component).

ExternalSecret pattern: spec.secretStoreRef.name: onepassword-connect, spec.refreshInterval: 12h, spec.target.creationPolicy: Owner, no namespace (Flux sets it). Template data uses Go templating with 1Password field references.

VolSync component pattern: $APP, $APP_UID, $APP_GID, $VOLSYNC_CAPACITY:=1Gi, $VOLSYNC_STORAGECLASS:=democratic-csi-local-hostpath. ExternalSecret composes from 1P items volsync-template + ovh.

## Components

### 1. Pocket-ID (bjw-s app-template Helm chart)

- **Chart**: bjw-s app-template (consistent with repo patterns). The aclerici38/pocket-id-operator was evaluated and rejected -- adds CRD machinery for a small static config surface, includes maintainer-disclosed AI-generated code with manual auditing, and offers no clear advantage over the env-var config model
- **Image**: ghcr.io/pocket-id/pocket-id:v2.8.0-distroless (UID 65532, nonroot distroless base)
- **Backend**: SQLite at /app/data/pocket-id.db (NOT PostgreSQL -- no Postgres operator in cluster)
- **GeoIP**: MaxMind GeoLite2 for audit logging -- MAXMIND_LICENSE_KEY env var; Pocket-ID downloads + auto-refreshes the DB
- **Users / groups**: managed in the Pocket-ID UI by the first admin (passkey-enrolled via setup token at first boot). Sized for family homelab -- UI-driven CRUD is appropriate, no need for GitOps CRDs
- **OIDC clients**: created in the Pocket-ID UI; resulting client_id + client_secret stored in 1Password and delivered to consumer apps via per-app ExternalSecret
- **PVC**: 1Gi (democratic-csi-local-hostpath). Total data ~80-100 MB
- **PVC contents** (container path /app/data):
  - pocket-id.db (SQLite: users, groups, OIDC clients, sessions, audit logs) -- few MB
  - GeoLite2-City.mmdb (MaxMind GeoIP) -- ~60-70 MB
  - keys/ (JWT signing keys) -- few KB
  - uploads/ (logos, profile pictures) -- few MB
- **Backup**: VolSync PVC-level backup. Standard component pattern with APP=pocket-id, APP_UID=65532, APP_GID=65532, VOLSYNC_CAPACITY=1Gi
- **Exposure**: HTTPRoute on id.$PUBLIC_DOMAIN attached to BOTH envoy-external and envoy-internal

### 2. TinyAuth (bjw-s app-template Helm chart)

- Single replica, SQLite session DB, 1Gi PVC
- Pocket-ID is the ONLY OAuth provider (TINYAUTH_OAUTH_AUTOREDIRECT=pocketid)
- No Google or other secondary OAuth provider -- consistent with passkey-first design and single-source-of-truth principle. Federating Google into Pocket-ID is not an option (Pocket-ID is passkey-only)
- Per-app ACL via TINYAUTH_APPS_<NAME>_USERS_ALLOW / TINYAUTH_APPS_<NAME>_USERS_BLOCK env vars
- No global TINYAUTH_OAUTH_WHITELIST -- Pocket-ID OIDC client allowed-groups already restricts who can complete the auth flow
- Resource requests: 10m CPU / 64Mi RAM, limits: 256Mi RAM
- Health probes: GET /api/healthz
- **PVC**: 1Gi (democratic-csi-local-hostpath). Stores SQLite DB only (~few MB), no config state
- **PVC contents**: /data/tinyauth.db (active sessions, auto-generated session signing key). All config is env vars (GitOps-manageable). PVC loss = users re-login, no config loss
- **Backup**: VolSync PVC-level backup. Standard component pattern with APP=tinyauth, VOLSYNC_CAPACITY=1Gi

### 3. Forward-auth component (reusable Kustomize component)

- SecurityPolicy template targeting HTTPRoute by app name
- Envoy extAuth path: /api/auth/envoy
- Headers to backend: Remote-User, Remote-Email, Remote-Groups, Remote-Name, Remote-Sub, Location, Set-Cookie
- ReferenceGrant in the security namespace authorizes cross-namespace SecurityPolicy -> tinyauth Service references (networking, selfhosted, media, observability)
- Follow existing component pattern from kubernetes/components/volsync/: Kustomize Component type, $APP variable substitution, defaults for optional vars

### 4. OIDC-native app SecurityPolicy

- SecurityPolicy.oidc with Pocket-ID issuer
- client_id + client_secret delivered via per-app ExternalSecret (1Password)
- Apps handle their own authorization via groups claim from userinfo
- EG native OIDC does NOT forward identity headers to upstream

## Group ACL Architecture

- **Single source of truth**: Pocket-ID UI (users + groups managed manually by the first admin). Family-sized homelab, not multi-tenant
- **Forward-auth coarse gate**: Pocket-ID OIDC client allowed-groups on the "tinyauth" client. Users outside those groups never complete the auth flow
- **Forward-auth fine ACL**: per-app TINYAUTH_APPS_<NAME>_USERS_ALLOW (and _BLOCK)
- **OIDC-native ACL**: app-level group claim filtering (e.g. allowedGroups configured in app env)
- **Default-deny**: TinyAuth's autoredirect=pocketid means every request must pass Pocket-ID auth + group check; OIDC-native apps require explicit group match

## Implementation Order

1. **Pocket-ID** - deploy via bjw-s app-template, mount SQLite PVC via VolSync component, set MAXMIND_LICENSE_KEY for GeoIP, expose at id.$PUBLIC_DOMAIN
2. **First-admin bootstrap** - at first boot the Pocket-ID container prints a setup token in its log; use it via the UI to enroll the first admin with a passkey
3. **TinyAuth OIDC client (manual)** - in the Pocket-ID UI create an OIDC client named "tinyauth" with callback https://auth.$PUBLIC_DOMAIN/api/oauth/callback/pocketid; copy client_id + client_secret into 1Password item "tinyauth" (fields POCKETID_CLIENT_ID, POCKETID_CLIENT_SECRET)
4. **TinyAuth** - deploy with bjw-s chart, ExternalSecret pulls all OAuth credentials (TinyAuth secret, Pocket-ID OIDC creds, Google OAuth creds, OAuth whitelist) from the single 1P "tinyauth" item
5. **Forward-auth component** - kubernetes/components/forward-auth/, reusable kustomize component
6. **ReferenceGrant** - in security ns, lists allowed consumer namespaces (networking, selfhosted, media, observability)
7. **VolSync backups** - already wired via the standard component
8. **Migrate first forward-auth app** - test with one OIDC-less app (e.g. Dozzle) via the forward-auth component
9. **Migrate first OIDC-native app** - Actual Budget (callback URL: https://actual.$PUBLIC_DOMAIN/openid/callback). Create the OIDC client in the Pocket-ID UI, copy creds to 1P, wire ExternalSecret into the actual app
10. **Migrate remaining apps** - one by one, verify each before moving to next
11. **Remove Cloudflare Access** - only after all apps confirmed working through Pocket-ID/TinyAuth. Update Cloudflare Terraform (remove Private Cloud Access app, keep bypass rules for public services)
12. **Update BM area-references** - networking, external-secrets, k8s-workloads

## First OIDC-native App: Actual Budget

Pocket-ID client setup (in UI):
- Client name: actual
- Callback URL: https://actual.$PUBLIC_DOMAIN/openid/callback (or leave blank to autofill on first login)
- Restrict to the appropriate users/group via Pocket-ID UI

Actual Budget configuration:
- Environment variables: ACTUAL_OPENID_DISCOVERY_URL=https://id.$PUBLIC_DOMAIN, ACTUAL_OPENID_CLIENT_ID and ACTUAL_OPENID_CLIENT_SECRET from a per-app ExternalSecret backed by a 1Password item "actual-oidc"
- Requires Actual Budget server version 25.1.0+ and HTTPS
- First successful login becomes the administrator

## Decisions

- **SQLite for Pocket-ID**: No Postgres operator in cluster; SQLite is the natural choice for single-node
- **bjw-s app-template instead of pocket-id-operator**: Operator adds CRDs and reconcile machinery for what is ultimately a small env-var config surface. Operator README discloses significant AI-generated code with manual auditing. Direct chart deploy follows repo patterns (consistent with grafana, paperless, tinyauth) and keeps the cluster simpler. User/group/OIDC-client management via Pocket-ID UI is acceptable for a family homelab
- **Default deny**: No access unless explicitly granted
- **Passkey-only**: Pocket-ID has no password fallback (by design)
- **Google OAuth as second provider**: Tested against echo service first, then available for any app needing Google identity. Restricted by email domain whitelist per app
- **bjw-s Helm chart for TinyAuth**: Consistent with repo patterns
- **No Redis**: SQLite for TinyAuth sessions (single-node, no HA needed)
- **No LDAP**: Pocket-ID is the single source of truth for users and groups
- **Component pattern for forward-auth**: Reusable kustomize component following VolSync component pattern
- **Envoy Gateway extAuth path**: /api/auth/envoy
- **VolSync backup for auth infra**: Both Pocket-ID and TinyAuth get PVC-level backup using the standard component pattern. Pocket-ID: 1Gi (SQLite DB + GeoIP + keys + uploads, ~80-100 MB actual). TinyAuth: 1Gi (SQLite sessions + signing key, ~few MB actual)
- **MaxMind GeoIP**: For Pocket-ID audit logging
- **CF Access stays until migration complete**: Do not remove Cloudflare Access until all apps are verified through Pocket-ID/TinyAuth
- **OIDC client credentials in 1Password**: All client_id/client_secret pairs are created manually in the Pocket-ID UI and stored in dedicated 1P items per consumer app

## References

- Pocket-ID env vars: https://pocket-id.org/docs/configuration/environment-variables
- Pocket-ID OIDC client auth: https://pocket-id.org/docs/guides/oidc-client-authentication
- Pocket-ID proxy services: https://pocket-id.org/docs/guides/proxy-services
- Pocket-ID callback wildcards: https://pocket-id.org/docs/advanced/callback-url-wildcards
- Pocket-ID hardening: https://pocket-id.org/docs/advanced/hardening
- Pocket-ID troubleshooting: https://pocket-id.org/docs/troubleshooting/common-issues
- Actual Budget OIDC setup: https://pocket-id.org/docs/client-examples/actual-budget
- TinyAuth Pocket-ID guide: https://tinyauth.app/docs/guides/pocket-id/
- TinyAuth Google OAuth: https://tinyauth.app/docs/guides/google-oauth/
- TinyAuth configuration: https://tinyauth.app/docs/reference/configuration/
- TinyAuth Kubernetes: https://tinyauth.app/docs/community/kubernetes/
- drag0n141 SecurityPolicy: https://github.com/drag0n141/home-ops/blob/fa5cd2d7f5b7449d181d23ebed0ef3b88c8bd145/kubernetes/components/tinyauth/securitypolicy.yaml
- heavy-ops forward-auth SecurityPolicy: https://github.com/heavybullets8/heavy-ops/blob/53be6d2eb46015e88ed492a3bdf77f7fa40d3b1b/kubernetes/components/forward-auth/securitypolicy.yaml
- Envoy Gateway ext-auth: https://gateway.envoyproxy.io/latest/tasks/security/ext-auth/
- Envoy Gateway OIDC: https://gateway.envoyproxy.io/docs/tasks/security/oidc/
- Envoy Gateway JWT claim auth: https://gateway.envoyproxy.io/v1.8/tasks/security/jwt-claim-authorization/

## Related

- relates_to [[networking]]
- relates_to [[external-secrets]]
- relates_to [[k8s-workloads]]


## Audit Update (2026-06-15)
- **Current State**: System is fully operational with Pocket-ID as IdP and TinyAuth as the forward-auth PEP. Envoy Gateway manages traffic with strict header sanitization on both internal/external paths.
- **Constraint**: `TINYAUTH_AUTH_ACLS_POLICY: deny` is currently unavailable in v5.0.7 (only in `main`). This is a known gap; monitor upstream for a stable release.
- **Security Posture**: Trust-chain is verified: `Client → Envoy (Header Strip) → ExtAuthz → TinyAuth (Identity Verify) → App`.
