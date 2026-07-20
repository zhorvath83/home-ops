---
title: iam
type: area_reference
permalink: home-ops/docs/areas/iam
area: iam
status: current
confidence: high
verified_at: '2026-07-20'
summary: Centralized Identity and Access Management using Kanidm as the OIDC IdP and
  the gateway-oidc Envoy-native OIDC gate for workloads that do not speak OIDC natively.
verified_against:
- kubernetes/apps/security/kanidm/app/helmrelease.yaml
- kubernetes/components/gateway-oidc/securitypolicy.yaml
- kubernetes/components/gateway-oidc/externalsecret.yaml
- kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml
---

# Identity & Access Management (IAM)

## 1. Trust Chain & Logic
The system implements a "Secure-by-Design" identity pipeline to prevent header injection and unauthorized access.

### Traffic Flow (OIDC-gated Apps)
`User -> Envoy Gateway -> SecurityPolicy (OIDC) -> App`

### Critical Security Constraints
- **Hostname admission guard**: A `ValidatingAdmissionPolicy` (native CEL, no Kyverno) in `envoy-gateway/config/validatingadmissionpolicy.yaml` gates HTTPRoute hostname claims — only the `security` namespace may claim `idm.${PUBLIC_DOMAIN}`, and non-security namespaces may not claim a wildcard (which would cover idm). Closes the route-collision / WebAuthn-origin-binding hijack path on the IdP plane. See [[networking]].

- **Header Stripping**: Envoy Gateway `ClientTrafficPolicy` removes `Remote-User`, `Remote-Email`, `Remote-Groups`, `Remote-Name`, and `Remote-Sub` before request processing. This is a header-injection spoofing guard kept as defense-in-depth — those identity headers cannot be supplied by a client.
- **Envoy-native OIDC**: The `gateway-oidc` component makes Envoy itself perform the OIDC authorization-code flow against Kanidm. An unauthenticated request is redirected to Kanidm login; only after a successful token exchange does the request reach the backend (Envoy sets the id-token/access-token cookies). Unauthenticated traffic is dropped/redirected at Envoy before it reaches the backend.
- **Group authorization**: Per-app group access is enforced at Kanidm (per-client `allowed-groups`, default-deny), not in the SecurityPolicy — the `gateway-oidc` component carries no `authorization` block.

## 2. Components

### Kanidm (The IdP)
- **Role**: Sole source of truth for users and groups.
- **Protocol**: OIDC Provider (Kanidm per-client issuer URLs: `https://idm.${PUBLIC_DOMAIN}/oauth2/openid/<client-id>`).
- **Access**: Exposed at `idm.${PUBLIC_DOMAIN}` on both `envoy-external` and `envoy-internal`.
- **Security**: Passkey-first. No password fallback.
- **Administration**: `just kanidm` module (ad-hoc `kanidm/tools` client pod in the `security` namespace); the `kanidm/server` image ships no client CLI and there is no macOS package. See `kubernetes/apps/security/kanidm/README.md`.

### gateway-oidc (The OIDC Gate)
- **Role**: Reusable Kustomize component that attaches an Envoy-native OIDC `SecurityPolicy` to an app's `HTTPRoute`.
- **Auth Flow**: Envoy redirects to Kanidm -> exchanges the authorization code -> sets session cookies -> forwards the authenticated request to the backend.
- **ACL Model**: Per-app group access is enforced at Kanidm via per-client `allowed-groups` (default-deny). The policy itself carries no authorization block.
- **Secrets**: Per-app `${APP}-oidc-secret` `ExternalSecret` (1Password item `kanidm`, field `${APP}_client_secret`); the component ships the ExternalSecret template.

## 3. Implementation Guide for AI Agents

**CRITICAL: No application may be deployed without an associated IAM policy. Every app must be protected by either native OIDC or the `gateway-oidc` component.**

### Path A: OIDC-Native App
1. **Kanidm Registration**: Create an OAuth2 client in Kanidm (`just kanidm`).
2. **Grouping**:
   - Create `appname_users` group in Kanidm (Mandatory).
   - Create `appname_admins` group in Kanidm (Optional, for admin roles).
3. **Secrets**: Store the resulting `client_id` and `client_secret` in the 1Password item `kanidm` (field `${APP}_client_secret`).
4. **ExternalSecret**: The per-app `ExternalSecret` (or the `gateway-oidc` component template) pulls these creds into `${APP}-oidc-secret`.
5. **App Config**: Set the OIDC issuer/discovery URL to `https://idm.${PUBLIC_DOMAIN}` (Kanidm per-client issuer: `https://idm.${PUBLIC_DOMAIN}/oauth2/openid/<client-id>`).

### Path B: OIDC-less App (gateway-oidc)
1. **Kanidm Grouping**: Create `appname_users` group in Kanidm (Mandatory) and add it to the client's `allowed-groups`.
2. **Component**: Add the `gateway-oidc` Kustomize component to the app's `ks.yaml`. Set `APP` (+ optional `APP_SUBDOMAIN`, `HTTPROUTE_NAME`) via `postBuild.substitute`.
3. **No ReferenceGrant needed**: the OIDC provider is reached via the public issuer URL, not an in-cluster Service backendRef, so there is no cross-namespace `ReferenceGrant` to maintain.

### Mandatory Infrastructure Requirements (All Paths)
- **Network Isolation**: Every app MUST have a `CiliumNetworkPolicy` (CNP).
- **Ingress Analysis**: Analyze and document all required ingress paths (e.g., Prometheus, Kubelet, other internal services) to ensure the CNP is tight but functional.
- **Verification**: Verify that the app is unreachable without identity and that group-based access is correctly enforced.

## 4. Known Limitations & Warnings

### gateway-oidc carries no authorization block
Per-app group access is enforced at Kanidm (client `allowed-groups`, default-deny). Define the client's `allowed-groups` before exposing a new `gateway-oidc` app, or no authenticated user can reach it. (The nil-ACL fail-open trap is gone: the failure mode is now fail-closed, not fail-open.)

### Rate Limiting on External Gateway — enabled (2026-07-20)
- **Current**: the `rate-limit` `BackendTrafficPolicy` is **enabled** (Local, 600 req/min, `kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml:186-200`; commit `1a7ac6cd5` "enable Local rate-limit"). Local (not Global) is effective here because the single-node cluster runs one Envoy pod per gateway, so the per-route Local aggregate is effectively global.
- **Complementary coverage**: Cloudflare WAF still provides edge rate limiting / brute-force protection ahead of the in-cluster Local limiter.
- **History**: the limiter was previously disabled due to an Envoy Gateway v1.8.0 CRD regression (envoyproxy/gateway#8798); Local rate-limit is functional on the current EG version, so the regression no longer blocks it.

### gateway-oidc discovery-fetch fragility — Invalid policies don't self-heal (2026-07-20)
- [observation] The envoy-gateway controller fetches the OIDC discovery doc (`https://idm.<PUBLIC_DOMAIN>/oauth2/openid/<app>/.well-known/openid-configuration`) on every SecurityPolicy generation bump. If that fetch times out (`context deadline exceeded`), the policy goes `Accepted=False/Invalid` and the controller sets a **500 direct-response** on the gated routes (log: `gatewayapi/securitypolicy.go:1075 setting 500 direct response in routes due to errors in SecurityPolicy`). From Invalid, the policy does NOT self-heal even once the endpoint is reachable again.
- [observation] Triggers observed 2026-07-20: (a) a SecurityPolicy spec change (`sameSite: Strict`, commit `0e1c1daa5`) forced a re-fetch during an envoy-internal xDS reload; (b) a Kanidm restart made the discovery endpoint briefly unavailable mid-fetch. Both left all 10 OIDC SecurityPolicies stuck Invalid → 500s on every protected site.
- [observation] The `cookieConfig.sameSite: Strict` field itself is schema-valid and NOT the cause — the 500 mechanism is the discovery timeout, not cookie behavior. `idm.*` and `app.*` share the registrable domain, so SameSite=Strict is functionally safe for the OIDC callback here.
- [observation] CoreDNS commit `5cf7ab141` (2026-07-20) rewrote the split-horizon zone from `id.*` to `idm.*`, resolving `idm.<PUBLIC_DOMAIN>` to the `envoy-internal` **ClusterIP** (not the LB VIP) to fix the data-plane OIDC token-exchange hairpin (eTP:Local). This path works for the controller discovery fetch too (verified post-recovery). Not the cause, but it reshaped the resolution path on the same morning.
- [remediation] Recovery: `kubectl rollout restart deployment/envoy-gateway -n networking` forces a clean re-fetch; all policies return to Accepted within ~4 min. Apply on any Kanidm restart or gateway-oidc spec change that leaves policies stuck Invalid.
## SSO / OIDC endpoint convention (AD-023 rev4, 2026-07-10 — deployed)

- [observation] [convention] Every native OIDC client uses the PUBLIC issuer `https://idm.<PUBLIC_DOMAIN>` for ALL endpoints (auth/token/userinfo/discovery). Split configs (public auth_url + in-cluster token/userinfo — the former grafana pattern) are RETIRED: discovery-only clients (pingvin-share-x) cannot follow them, and the token endpoint is world-exposed by design so an in-cluster-only network path adds no boundary.
- [observation] [consequence] The OIDC backchannel is ordinary gateway traffic (client pod -> envoy VIP -> kanidm). Baseline-egress clients need nothing. Clients with egress.home.arpa/custom-egress MUST also carry egress.home.arpa/allow-gateways (allow-gateways-egress CCNP, envoy :10443) or their token exchange is dropped. Current carriers: grafana, pingvin-share-x.
- [observation] [dns] The hairpin resolves via the coredns split-horizon zone: ${PUBLIC_DOMAIN} forwards to ${K8S_GATEWAY_IP} (k8s-gateway) so pods get the envoy-internal VIP without the node-resolver -> router hop.
- [observation] [status] Decided, implemented, and DEPLOYED 2026-07-10. Full verification in [[cnp-per-app-audit]] (docs/progress).

## Relations addendum

- decided_in [[AD-023-cnp-threat-model-audit]]

## 5. OIDC-Native Apps Registry

### Grafana (added 2026-07-10, roadmap grafana-operator-migration P5)

- **Path**: A (OIDC-native via `auth.generic_oauth`, grafana-operator-managed instance).
- **Kanidm client**: "Grafana" at `grafana.${PUBLIC_DOMAIN}`, redirect `/login/generic_oauth`.
- **Group -> role**: `grafana_admins` -> Admin; any other authenticated user -> None (no access). `role_attribute_strict: true`, `skip_org_role_sync: false`.
- **Endpoints**: public issuer only (AD-023) — Kanidm per-client issuer `https://idm.${PUBLIC_DOMAIN}/oauth2/openid/grafana` for authorize | token | userinfo. The token/userinfo backchannel hairpins through envoy, so the grafana pod carries `egress.home.arpa/allow-gateways` in addition to `custom-egress`.
- **Secret**: 1Password item `grafana`, keys `GRAFANA_OIDC_CLIENT_ID`/`GRAFANA_OIDC_CLIENT_SECRET` -> ExternalSecret `grafana-secret` -> env `GF_AUTH_GENERIC_OAUTH_CLIENT_ID`/`_SECRET`.
- **Local login**: form hidden (`disable_login_form: true`). **DEVIATION from roadmap D5** (which planned to keep the form as documented break-glass). The `admin-user`/`admin-password` in `grafana-secret` are retained — they are NOT a human login path once the form is hidden, but the **grafana-operator's provisioning credential**: the operator authenticates to the Grafana API with them to push dashboard/datasource/folder CRs. Removing them breaks provisioning. Break-glass recovery = `grafana-cli admin reset-admin-password` in-pod, or temporarily flip `disable_login_form`.
- **Gotcha (fixed 2026-07-10)**: the earlier config used `disable_login` (a non-existent grafana.ini key -> no-op, form stayed visible); the valid key is `disable_login_form`. Also an "Invalid client secret" login failure was a value mismatch between the 1Password field and the IdP client secret (not a network/CNP issue) — the token exchange reaches the IdP and is rejected; resync the secret + restart the pod (ephemeral DB re-seeds admin from env).
- Closes Grafana's standing IAM exception (S3: no app without an IAM policy).
