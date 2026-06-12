---
title: sso-implementation
type: roadmap
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

# SSO implementation - Pocket-ID + TinyAuth replacing Cloudflare Access

## Architecture

Two authentication paths:

1. **OIDC-native apps** (Actual Budget, Grafana, Forgejo, Immich, Nextcloud, Paperless-ngx) -> Pocket-ID direct via SecurityPolicy.oidc
2. **OIDC-less apps** (Dozzle, Homepage, Uptime Kuma, etc.) -> TinyAuth forward-auth via SecurityPolicy.extAuth -> Pocket-ID

Google OAuth as second TinyAuth provider, initially tested against the echo service (kubernetes/apps/networking/echo/).

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

### 1. Pocket-ID (pocket-id-operator)

- **CRDs**: PocketIDInstance, PocketIDOIDCClient, PocketIDUserGroup, PocketIDUser
- **Instance**: SQLite backend (NOT PostgreSQL -- no Postgres operator in cluster), Envoy Gateway HTTPRoute, distroless image, hardened
- **GeoIP**: MaxMind GeoLite2 for audit logging (download GeoLite2-City.mmdb, mount or sidecar). Consider also for TinyAuth if IP-based ACL needed
- **Groups** (GitOps-managed via PocketIDUserGroup CRDs): id-admins, id-family, id-media, id-docs, id-dev, id-monitoring
- **OIDC clients** (PocketIDOIDCClient CRDs with allowedUserGroups): tinyauth, actual, grafana, forgejo, immich, nextcloud, paperless
- **Secret management**: PocketIDOIDCClient auto-generates K8s Secrets with client ID/secret. Do NOT create manual ExternalSecrets for OIDC client credentials -- the operator manages these
- **PVC**: 1Gi (democratic-csi-local-hostpath). Sufficient for family homelab -- total data ~80-100 MB
- **PVC contents** (container path /app/data):
  - pocket-id.db (SQLite: users, groups, OIDC clients, sessions, audit logs) -- few MB
  - GeoLite2-City.mmdb (MaxMind GeoIP) -- ~60-70 MB
  - keys/ (JWT signing keys) -- few KB
  - uploads/ (logos, profile pictures) -- few MB
- **Backup**: VolSync PVC-level backup. Standard component pattern with APP=pocket-id, VOLSYNC_CAPACITY=1Gi
- **CRD fields**: Refer to operator documentation for PocketIDInstance, PocketIDOIDCClient, PocketIDUserGroup, PocketIDUser specs. Do NOT copy from reference repos -- use operator docs as the authoritative source

### 2. TinyAuth (bjw-s app-template Helm chart)

- Single replica, SQLite session DB, 1Gi PVC
- Pocket-ID as primary OAuth provider (autoredirect=pocketid)
- Google OAuth as secondary provider (tested against echo service first, then available for any app needing Google identity)
- TINYAUTH_AUTH_ACLS_POLICY: deny (default-deny)
- Per-app ACL via TINYAUTH_APPS_*_OAUTH_GROUPS env vars
- Resource requests: 10m CPU / 64Mi RAM, limits: 256Mi RAM
- Health probes: GET /api/healthz
- **PVC**: 1Gi (democratic-csi-local-hostpath). Stores SQLite DB only (~few MB), no config state
- **PVC contents**: /data/tinyauth.db (active sessions, auto-generated session signing key). All config is env vars (GitOps-manageable). PVC loss = users re-login, no config loss
- **Backup**: VolSync PVC-level backup. Standard component pattern with APP=tinyauth, VOLSYNC_CAPACITY=1Gi

### 3. Forward-auth component (reusable Kustomize component)

- SecurityPolicy template targeting HTTPRoute by app name
- Envoy extAuth path: /api/auth/envoy?path=
- Headers: user-agent (required for browser detection), X-Forwarded-*, cookie, accept
- Headers to backend: Remote-User, Remote-Email, Remote-Groups, Remote-Name, Remote-Sub, Location, Set-Cookie
- ReferenceGrant per namespace for cross-namespace SecurityPolicy to Service ref
- Follow existing component pattern from kubernetes/components/volsync/: Kustomize Component type, $APP variable substitution, defaults for optional vars

### 4. OIDC-native app SecurityPolicy

- SecurityPolicy.oidc with Pocket-ID issuer
- Apps handle their own authorization via groups claim from userinfo
- EG native OIDC does NOT forward identity headers to upstream

## Group ACL Architecture

- **Single source of truth**: Pocket-ID (PocketIDUserGroup CRDs, GitOps-managed)
- **Forward-auth ACL**: TinyAuth TINYAUTH_APPS_*_OAUTH_GROUPS env vars
- **OIDC-native ACL**: PocketIDOIDCClient.allowedUserGroups CRD field
- **Default-deny**: TINYAUTH_AUTH_ACLS_POLICY=deny + PocketIDOIDCClient allowedUserGroups restrict-by-default

## Implementation Order

1. **Pocket-ID Operator** - deploy operator, PocketIDInstance (SQLite), GeoIP setup, user groups, first OIDC client (tinyauth)
2. **TinyAuth** - deploy with bjw-s chart, configure Pocket-ID provider, Google OAuth, per-app ACLs
3. **Forward-auth component** - create reusable kustomize component following VolSync component pattern
4. **ReferenceGrant** - grants for each namespace using forward-auth
5. **VolSync backups** - configure PVC backup for pocket-id and tinyauth using the standard component
6. **Migrate first forward-auth app** - test with one OIDC-less app (e.g. Dozzle)
7. **Migrate first OIDC-native app** - Actual Budget (callback URL: https://actual.$PUBLIC_DOMAIN/openid/callback)
8. **Migrate remaining apps** - one by one, verify each before moving to next
9. **Remove Cloudflare Access** - only after all apps confirmed working through Pocket-ID/TinyAuth. Update Cloudflare Terraform (remove Private Cloud Access app, keep bypass rules for public services)
10. **Update BM area-references** - networking, external-secrets, k8s-workloads

## First OIDC-native App: Actual Budget

Pocket-ID client setup:
- Client name: actual
- Callback URL: https://actual.$PUBLIC_DOMAIN/openid/callback (or leave blank to autofill on first login)
- allowedUserGroups: reference the appropriate PocketIDUserGroup CRD

Actual Budget configuration:
- Environment variables: ACTUAL_OPENID_DISCOVERY_URL=https://id.$PUBLIC_DOMAIN, ACTUAL_OPENID_CLIENT_ID and ACTUAL_OPENID_CLIENT_SECRET from the operator-generated Secret
- Requires Actual Budget server version 25.1.0+ and HTTPS
- First successful login becomes the administrator

## Decisions

- **SQLite for Pocket-ID**: No Postgres operator in cluster; SQLite is the natural choice for single-node. The pocket-id-operator supports SQLite natively
- **Default deny**: No access unless explicitly granted via group membership
- **Passkey-only**: Pocket-ID has no password fallback (by design)
- **Google OAuth as second provider**: Tested against echo service first, then available for any app needing Google identity. Restricted by email domain whitelist per app
- **bjw-s Helm chart for TinyAuth**: Consistent with repo patterns
- **pocket-id-operator for Pocket-ID**: GitOps-managed CRDs for instance, users, groups, clients. Operator manages OIDC client secrets -- no manual ExternalSecrets needed
- **No Redis**: SQLite for TinyAuth sessions (single-node, no HA needed)
- **No LDAP**: Pocket-ID is the single source of truth for users and groups
- **Component pattern for forward-auth**: Reusable kustomize component following VolSync component pattern
- **Envoy Gateway extAuth path**: /api/auth/envoy?path= with user-agent header (browser detection)
- **VolSync backup for auth infra**: Both Pocket-ID and TinyAuth get PVC-level backup using the standard component pattern. Pocket-ID: 1Gi (SQLite DB + GeoIP + keys + uploads, ~80-100 MB actual). TinyAuth: 1Gi (SQLite sessions + signing key, ~few MB actual). All config is env vars (GitOps-manageable), PVC stores only runtime state
- **MaxMind GeoIP**: For Pocket-ID audit logging (and possibly TinyAuth if IP-based ACL needed)
- **CF Access stays until migration complete**: Do not remove Cloudflare Access until all apps are verified through Pocket-ID/TinyAuth

## References

- Pocket-ID allowed groups: https://pocket-id.org/docs/configuration/allowed-groups
- Pocket-ID env vars: https://pocket-id.org/docs/configuration/environment-variables
- Pocket-ID OIDC client auth: https://pocket-id.org/docs/guides/oidc-client-authentication
- Pocket-ID proxy services: https://pocket-id.org/docs/guides/proxy-services
- Pocket-ID callback wildcards: https://pocket-id.org/docs/advanced/callback-url-wildcards
- Pocket-ID hardening: https://pocket-id.org/docs/advanced/hardening
- Pocket-ID custom keys: https://pocket-id.org/docs/advanced/custom-keys
- Pocket-ID troubleshooting: https://pocket-id.org/docs/troubleshooting/common-issues
- Pocket-ID operator: https://github.com/aclerici38/pocket-id-operator
- Pocket-ID operator CRD docs: https://github.com/aclerici38/pocket-id-operator/blob/main/docs/pocketidinstance.md
- Pocket-ID operator annotations: https://github.com/aclerici38/pocket-id-operator/blob/main/docs/annotations.md
- Pocket-ID operator OIDC client: https://github.com/aclerici38/pocket-id-operator/blob/main/docs/pocketidoidcclient.md
- Pocket-ID operator user groups: https://github.com/aclerici38/pocket-id-operator/blob/main/docs/pocketidusergroup.md
- Pocket-ID operator users: https://github.com/aclerici38/pocket-id-operator/blob/main/docs/pocketiduser.md
- Actual Budget OIDC setup: https://pocket-id.org/docs/client-examples/actual-budget
- TinyAuth Pocket-ID guide: https://tinyauth.app/docs/guides/pocket-id/
- TinyAuth Google OAuth: https://tinyauth.app/docs/guides/google-oauth/
- TinyAuth configuration: https://tinyauth.app/docs/reference/configuration/
- TinyAuth authentication: https://tinyauth.app/docs/reference/authentication/
- TinyAuth labels: https://tinyauth.app/docs/reference/labels/
- TinyAuth headers: https://tinyauth.app/docs/reference/headers/
- TinyAuth flow: https://tinyauth.app/docs/reference/flow/
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
