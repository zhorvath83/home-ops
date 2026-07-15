---
title: iam
type: area_reference
permalink: home-ops/docs/areas/iam
area: iam
status: current
confidence: high
verified_at: '2026-07-16'
summary: Centralized Identity and Access Management using Pocket-ID as the primary
  OIDC provider and TinyAuth as a forward-auth proxy for non-OIDC workloads.
verified_against:
- kubernetes/apps/security/pocket-id/app/helmrelease.yaml
- kubernetes/apps/security/tinyauth/app/helmrelease.yaml
- kubernetes/components/forward-auth/securitypolicy.yaml
- kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml
---

# Identity & Access Management (IAM)

## 1. Trust Chain & Logic
The system implements a "Secure-by-Design" identity pipeline to prevent header injection and unauthorized access.

### Traffic Flow (OIDC-less Apps)
`User → Envoy Gateway → SecurityPolicy (ExtAuthz) → TinyAuth → App`

### Critical Security Constraints
- **Header Stripping**: Envoy Gateway `ClientTrafficPolicy` removes `Remote-User`, `Remote-Email`, `Remote-Groups`, `Remote-Name`, and `Remote-Sub` before request processing. This ensures identity headers can ONLY be set by the auth provider.
- **ExtAuthz (Forward-Auth)**: The `forward-auth` component triggers a synchronous call to TinyAuth (`/api/auth/envoy`). If TinyAuth returns 401/403, the request is dropped by Envoy.
- **Identity Injection**: Upon successful auth, TinyAuth injects the validated identity headers into the request before it reaches the backend app.

## 2. Components

### Pocket-ID (The IdP)
- **Role**: Sole source of truth for users and groups.
- **Protocol**: OIDC Provider.
- **Access**: Exposed at `id.${PUBLIC_DOMAIN}`.
- **Security**: Passkey-first. No password fallback.

### TinyAuth (The Policy Enforcement Point)
- **Role**: Acts as an OIDC client to PocketID and provides a forward-auth interface for Envoy.
- **Auth Flow**: Redirects users to PocketID → Validates OIDC token → Sets session cookie → Grants access to app.
- **ACL Model**: Per-app group-based access control via `TINYAUTH_APPS_<NAME>_OAUTH_GROUPS`.

## 3. Implementation Guide for AI Agents

**CRITICAL: No application may be deployed without an associated IAM policy. Every app must be protected by either native OIDC or Forward-Auth.**

### Path A: OIDC-Native App
1. **Pocket-ID Registration**: Create an OIDC client in the Pocket-ID UI.
2. **Grouping**:
   - Create `appname_users` group in Pocket-ID (Mandatory).
   - Create `appname_administrators` group in Pocket-ID (Optional, for admin roles).
3. **Secrets**: Store the resulting `client_id` and `client_secret` in a 1Password item.
4. **ExternalSecret**: Create an `ExternalSecret` in the app namespace to pull these creds.
5. **App Config**: Set the OIDC discovery URL to `https://id.${PUBLIC_DOMAIN}`.

### Path B: OIDC-less App (Forward-Auth)
1. **Pocket-ID Grouping**: Create `appname_users` group in Pocket-ID (Mandatory).
2. **TinyAuth ACL**: Add `TINYAUTH_APPS_<APP_NAME>_OAUTH_GROUPS` to the TinyAuth `HelmRelease` values, mapping to the `appname_users` group.
3. **SecurityPolicy**: Add the `forward-auth` Kustomize component to the app's `ks.yaml`.
4. **ReferenceGrant**: Ensure a `ReferenceGrant` exists in the `security` namespace authorizing the app's namespace.

### Mandatory Infrastructure Requirements (All Paths)
- **Network Isolation**: Every app MUST have a `CiliumNetworkPolicy` (CNP).
- **Ingress Analysis**: Analyze and document all required ingress paths (e.g., Prometheus, Kubelet, other internal services) to ensure the CNP is tight but functional.
- **Verification**: Verify that the app is unreachable without identity and that group-based access is correctly enforced.

To add a new application to the IAM system:

### Path A: OIDC-Native App
1. **Pocket-ID**: Create an OIDC Client in the UI.
2. **Secret**: Store `client_id` and `client_secret` in a 1Password item.
3. **ExternalSecret**: Create an `ExternalSecret` in the app namespace to pull these creds.
4. **App Config**: Set the OIDC discovery URL to `https://id.${PUBLIC_DOMAIN}`.

### Path B: OIDC-less App (Forward-Auth)
1. **TinyAuth ACL**: Add `TINYAUTH_APPS_<APP_NAME>_OAUTH_GROUPS` to the TinyAuth `HelmRelease` values.
2. **SecurityPolicy**: Add the `forward-auth` Kustomize component to the app's `ks.yaml`.
3. **ReferenceGrant**: Ensure a `ReferenceGrant` exists in the `security` namespace allowing the app's namespace to reference the `tinyauth` service.
4. **Verification**: Verify that the app is unreachable without login and that the correct group is required.

## 4. Known Limitations & Warnings

### TinyAuth v5.1.0 ACL Behaviour (CRITICAL)

TinyAuth was upgraded to v5.1.0 on 2026-07-16 (image `ghcr.io/tinyauthapp/tinyauth:v5.1.0`). The ACL engine changed in two ways affecting the forward-auth PEP posture:

- **deny-by-default is now ENABLED** (`TINYAUTH_AUTH_ACLS_POLICY: deny`): nil ACL / unknown host -> Deny (fail-closed). The v5.0.7 nil-ACL allow-all trap is closed. This was previously a "future fix in main"; it shipped in v5.1.0 and is now set in the HelmRelease.
- **NEW v5.1.0 trap -- empty `oauth.whitelist` denies OAuth users**: `UserAllowedRule` runs first (before `OAuthGroupRule`). In v5.1.0 `utils.CheckFilter` returns `(false, ErrFilterEmpty)` for an empty filter, and the OAuth branch of `UserAllowedRule` treats ANY error (incl. `ErrFilterEmpty`) as `EffectDeny` -- NOT Abstain. So an app with `OAUTH_GROUPS` but no `OAUTH_WHITELIST` denies every OAuth user before the group check runs (asymmetry: the `users.allow` branch treats `ErrFilterEmpty` as Abstain; the OAuth branch does not).
- **Mitigation (DEPLOYED)**: every forward-auth app sets `TINYAUTH_APPS_<NAME>_OAUTH_WHITELIST: "/.*/"` (passes any authenticated email) above `TINYAUTH_APPS_<NAME>_OAUTH_GROUPS`; access control defers to the group rule. Mandatory for every OIDC-less app on v5.1.0.
- **Matching is by `CONFIG_DOMAIN` (host), not the app ID**; `TINYAUTH_APPS_<NAME>_CONFIG_DOMAIN` is required. The app ID must be a single token -- paerser's env decoder turns `_` into `.`, so an underscored ID does not bind the ACL and the deny policy catches it.
- **Upstream status**: the empty-whitelist asymmetry is NOT fixed upstream (`UserAllowedRule` still returns Deny on `ErrFilterEmpty` for OAuth). The `/.*/` whitelist is the stable workaround, not a fix to remove later.

### TinyAuth v5.1.0 SQLite Migration -- One-Way, No Rollback (CRITICAL)

- v5.1.0 added sqlite migrations `000009_oidc_userinfo_profile` and `000010_oidc_rework` (v5.0.7 has only 000001-000008). The DB on the `tinyauth` PVC is migrated to version 10 on first v5.1.0 boot.
- **Rolling back from v5.1.0 to v5.0.7 is FATAL**: v5.0.7 has no v9/v10 down-migration, so it crashes with `no migration found for version 10: read down for version 10 migrations: file does not exist`. This caused the 2026-07-16 outage: the v5.1.0 rollout timed out (10m HelmRelease timeout; reason not retained in logs), Flux `remediateLastFailure` rolled back to v5.0.7, and v5.0.7 crash-looped against the v10 DB.
- **Lesson**: the v5.1.0 DB migration is one-way. Do NOT roll tinyauth back across the v5.0.7 <-> v5.1.0 boundary. If v5.1.0 must be reverted, the `tinyauth` PVC DB must be reset first (v5.1.0 re-migrates an empty DB cleanly; v5.0.7 cannot run a v10 DB). The DB holds sessions only -- users/groups live in Pocket-ID -- so a reset forces re-login, not data loss.
- **Recovery applied 2026-07-16**: re-deployed v5.1.0 (DB already at v10, no re-migration) with the ACL fix above.
### Forward-Auth Onboarding Checklist (Mandatory for Every New OIDC-less App)
1. [ ] Create `appname_users` group in Pocket-ID UI.
2. [ ] Add `TINYAUTH_APPS_<APP_NAME>_CONFIG_DOMAIN`, `TINYAUTH_APPS_<APP_NAME>_OAUTH_WHITELIST: "/.*/"`, and `TINYAUTH_APPS_<APP_NAME>_OAUTH_GROUPS` to the TinyAuth `HelmRelease` values (the whitelist is mandatory on v5.1.0 -- see the v5.1.0 ACL section above).
3. [ ] Add the `forward-auth` Kustomize component to the app's `ks.yaml`.
4. [ ] Verify the app's namespace is listed in the `tinyauth-extauth` `ReferenceGrant` in the `security` namespace.
5. [ ] Verify the app is unreachable without login and that only the designated group can access it.
### ReferenceGrant Namespace Coverage
- The `tinyauth-extauth` `ReferenceGrant` currently authorises `SecurityPolicy` resources in: `networking`, `selfhosted`, `media`, `downloads`, `kube-system`, `observability`.
- When adding a forward-auth app in a **new namespace**, extend the `ReferenceGrant` first or the `SecurityPolicy` will be rejected by Envoy Gateway.

## 5. Operational Findings from Security Audit (2026-06-15)

### Trusted Proxy CIDR (HIGH)
- **Current**: `TINYAUTH_AUTH_TRUSTEDPROXIES: 10.244.0.0/16` (full Pod CIDR).
- **Upstream doc**: TinyAuth v5 does not document a narrower proxy trust model; the setting is a single CIDR or comma-separated list.
- **Physical enforcement**: The `CiliumNetworkPolicy` (`tinyauth`) restricts ingress to the Envoy Gateway pods only, so even if another pod in the Pod CIDR could route to TinyAuth, Cilium blocks it.
- **Decision**: Keep the full Pod CIDR. It is a deliberate compromise: the CiliumNetworkPolicy is the true enforcement point, and narrowing the CIDR would gain no practical security while increasing fragility if the gateway IPs shift.
- **Action**: Documented here; no config change required.

### Audit Log Destination (LOW)
- **Finding**: TinyAuth has no native destination configuration for log streams. All streams (HTTP, APP, AUDIT) write to stdout.
- **Current config**: `TINYAUTH_LOG_STREAMS_AUDIT_ENABLED: "true"` and `TINYAUTH_LOG_JSON: "true"` are both enabled.
- **Implication**: Audit events are emitted as JSON lines to stdout. The cluster's log collection pipeline (Promtail/Loki) is responsible for ingesting them.
- **Action**: Verify that the cluster log pipeline actually collects and indexes TinyAuth pod logs. If not, add a Promtail scrape config or Loki stream label for the `security` namespace.

### Rate Limiting on External Gateway (MEDIUM)
- **Current**: `rate-limit-external` `BackendTrafficPolicy` is commented out due to Envoy Gateway v1.8.0 CRD regression (envoyproxy/gateway#8798).
- **Interim coverage**: Cloudflare WAF provides external rate limiting.
- **Action**: Re-enable once Envoy Gateway v1.9.0 GA lands and the OCIRepository tag is bumped. Tracked in the SSO roadmap TODOs.

## SSO / OIDC endpoint convention (AD-023 rev4, 2026-07-10 — local-only, pending deploy)

- [observation] [convention] Every native OIDC client uses the PUBLIC issuer https://id.<PUBLIC_DOMAIN> for ALL endpoints (auth/token/userinfo/discovery). Split configs (public auth_url + in-cluster token/userinfo — the former grafana/tinyauth pattern) are RETIRED: discovery-only clients (pingvin-share-x) cannot follow them, and the token endpoint is world-exposed by design so an in-cluster-only network path adds no boundary.
- [observation] [consequence] The OIDC backchannel is ordinary gateway traffic (client pod -> envoy VIP -> pocket-id). Baseline-egress clients need nothing. Clients with egress.home.arpa/custom-egress MUST also carry egress.home.arpa/allow-gateways (allow-gateways-egress CCNP, envoy :10443) or their token exchange is dropped. Current carriers: grafana, pingvin-share-x.
- [observation] [dns] The hairpin resolves via the coredns split-horizon zone: ${PUBLIC_DOMAIN} forwards to ${K8S_GATEWAY_IP} (k8s-gateway) so pods get the envoy-internal VIP without the node-resolver -> router hop.
- [observation] [status] Decided, implemented, and DEPLOYED 2026-07-10 (commit 409242998); VERIFIED live — pingvin OIDC login OK with the token/userinfo hairpin FORWARDED to the envoy pod :10443 (LB-VIP resolves to envoy identity via socketLB, so allow-gateways-egress toEndpoints matches — no toCIDR grant needed). coredns split-horizon live (id.\${PUBLIC_DOMAIN} → envoy-internal VIP 192.168.1.18 from pods). Full verification in [[cnp-per-app-audit]] (docs/progress) Session 13.

## Relations addendum

- decided_in [[AD-023-cnp-threat-model-audit]]


## 5. OIDC-Native Apps Registry

### Grafana (added 2026-07-10, roadmap grafana-operator-migration P5)

- **Path**: A (OIDC-native via `auth.generic_oauth`, grafana-operator-managed instance).
- **Pocket-ID client**: "Grafana" at `grafana.${PUBLIC_DOMAIN}`, redirect `/login/generic_oauth`.
- **Group → role**: `grafana_admins` → Admin; any other authenticated user → None (no access). `role_attribute_strict: true`, `skip_org_role_sync: false`.
- **Endpoints**: public issuer only (AD-023) — `https://id.${PUBLIC_DOMAIN}/authorize | /api/oidc/token | /api/oidc/userinfo`. The token/userinfo backchannel hairpins through envoy, so the grafana pod carries `egress.home.arpa/allow-gateways` in addition to `custom-egress`.
- **Secret**: 1Password item `grafana`, keys `GRAFANA_OIDC_CLIENT_ID`/`GRAFANA_OIDC_CLIENT_SECRET` → ExternalSecret `grafana-secret` → env `GF_AUTH_GENERIC_OAUTH_CLIENT_ID`/`_SECRET`.
- **Local login**: form hidden (`disable_login_form: true`). **DEVIATION from roadmap D5** (which planned to keep the form as documented break-glass). The `admin-user`/`admin-password` in `grafana-secret` are retained — they are NOT a human login path once the form is hidden, but the **grafana-operator's provisioning credential**: the operator authenticates to the Grafana API with them to push dashboard/datasource/folder CRs. Removing them breaks provisioning. Break-glass recovery = `grafana-cli admin reset-admin-password` in-pod, or temporarily flip `disable_login_form`.
- **Gotcha (fixed 2026-07-10)**: the earlier config used `disable_login` (a non-existent grafana.ini key → no-op, form stayed visible); the valid key is `disable_login_form`. Also an "Invalid client secret" login failure was a value mismatch between the 1Password field and the Pocket-ID client secret (not a network/CNP issue) — the token exchange reaches Pocket-ID and is rejected; resync the secret + restart the pod (ephemeral DB re-seeds admin from env).
- Closes Grafana's standing IAM exception (§3: no app without an IAM policy).
