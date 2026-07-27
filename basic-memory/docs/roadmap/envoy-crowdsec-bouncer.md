---
title: envoy-crowdsec-bouncer
type: note
permalink: envoy-crowdsec-bouncer
status: pending
priority: medium
tags:
- networking
- security
- crowdsec
---

# Envoy CrowdSec Bouncer + Web UI Integration

Integrate CrowdSec (detection + decisions) with the Envoy Gateway edge via the
`envoy-proxy-bouncer` as a native `SecurityPolicy.extAuth` service, and deploy the
self-hosted CrowdSec Web UI (TheDuffman85) for alert/decision visibility. Scope expanded
from the bouncer-only original to cover the Web UI per the 2026-07-27 research sweep.

Revised 2026-07-27 after a review against the live repo, the BM area-references, and
EG 1.8.3 docs, then re-verified against the chart sources and the live cluster; follow-ups
resolved with the human 2026-07-27 — see "Review correction log" at the end for the change set.

## Goal

- Automate blocking of malicious actors at the Envoy Gateway edge (IP-ban + AppSec WAF),
  reducing attack surface for every backend application behind `envoy-external`/`envoy-internal`.
- Add a self-hosted, OIDC-protected dashboard (CrowdSec Web UI) for alert/decision
  investigation, historical retention, and notifications — LAN-only, Pocket ID auth.

## Research basis (evidence-backed)

Surveyed two reference homelabs + the Web UI repo + the bouncer chart repo (all via `gh`
on 2026-07-27, this branch). Versions current as of the sweep.

- **artichoked1/homelab** — Envoy Gateway stack (closest to this repo's log source).
  CrowdSec chart 0.24.0, PostgreSQL backend, `agent.acquisition` reads Envoy pod stdout
  logs (`podName: envoy-networking-web-gateway-*`, `program: envoy`,
  `poll_without_inotify: true`) with `COLLECTIONS: yanis-kouidri/envoy`. Bouncer chart
  0.5.5, `referenceGrant.create: true` for cross-namespace SecurityPolicy refs.
  AppSec enabled (`crowdsecurity/appsec-virtual-patching`).
- **aclerici38/home-ops** — kgateway (not EG), but the most complete reference.
  CrowdSec chart 0.24.0 (OCI `ghcr.io/crowdsecurity/helm-charts/crowdsec`), CloudNativePG,
  LAPI 2 replicas + Cilium L2 LoadBalancer, syslog acquisition (OPNsense/pf), AppSec
  enabled (`appsec-virtual-patching appsec-crs appsec-generic-rules`), Grafana dashboard
  21689. Web UI: bjw-s app-template, image `ghcr.io/theduffman85/crowdsec-web-ui`,
  **built-in OIDC** (`CONFIG_AUTH_OIDC_*`, Pocket ID, `unmatchedRole: deny`,
  `adminGroups: [admin]`), PVC `/app/data` (SQLite), internal-only route.
  Bouncer: kdwils chart 0.6.3, gRPC 8080, WAF to `crowdsec-appsec-service:7422`.
- **TheDuffman85/crowdsec-web-ui** (451 stars, TypeScript/React+Hono, image tagged by date
  e.g. `2026.7.21`). Built-in auth (password+TOTP, passkeys, **OIDC SSO**), group roles,
  read-only mode, multi-instance, Prometheus metrics page, notifications
  (Email/Gotify/MQTT/ntfy/Webhook), SQLite retention under `/app/data`. **The corelab.tech
  guide's "no built-in auth" warning is outdated** — current images have full auth.
  Health probe `GET /api/health` (public). Gotcha: the Web UI network must be in CrowdSec
  `api.server.trusted_ips` for delete/clean operations (403 otherwise). `zekker6` Helm
  chart is **stale** (old `CROWDSEC_URL` env names vs the image's `CONFIG_*` contract) —
  use bjw-s app-template with correct `CONFIG_*` envs instead.
- **kdwils/envoy-proxy-crowdsec-bouncer** (chart latest 0.7.0). Integrates with Envoy
  Gateway via the **native `SecurityPolicy.extAuth.grpc.backendRefs`** API — NOT
  `EnvoyPatchPolicy`. Per the chart author's DEPLOYMENT.md: "SecurityPolicies must be
  created at the HTTPRoute level, not at the Gateway level, and in the same namespace as
  your HTTPRoutes." — this is a *blast-radius recommendation*, not a hard EG constraint;
  Gateway-level `SecurityPolicy` is supported by EG and is already used in this repo for
  `envoy-internal-rfc1918`. We intentionally override it for the Gateway-level bouncer
  (see Decisions). `bodyToExtAuth.maxRequestBytes: 65536` is required to forward the
  request body for WAF inspection of POST payloads (without it, WAF only sees URL/path).
  `ReferenceGrant` needed for cross-namespace Service refs (chart auto-creates via
  `referenceGrant.create` + `fromNamespaces`). Bouncer exposes no health endpoint.
  **Verified 2026-07-27 against the chart sources**: the chart ships NO SecurityPolicy
  template (templates dir: `deployment`, `service`, `referencegrant`, `httproute`,
  `servicemonitor`, `serviceaccount`, `hpa`, `configmap-*` only) — there is no
  `securityPolicy` value, so nothing to disable; we hand-write the SecurityPolicy. Value
  keys confirmed: `config.bouncer.lapiURL` (default `http://crowdsec-service:8080`),
  `config.bouncer.apiKeySecretRef`, `config.waf.enabled`/`config.waf.appSecURL` (capital S,
  default `http://crowdsec-appsec-service:7422`), `referenceGrant.create`/`fromNamespaces`.
  The bouncer Service name is `{{ include "envoy-proxy-bouncer.fullname" }}` — set
  `fullnameOverride: crowdsec-bouncer` so it renders as `crowdsec-bouncer` (without the
  override, release `crowdsec-bouncer` would render `crowdsec-bouncer-envoy-proxy-bouncer`).

## Decisions (locked with human, 2026-07-27)

Locked with human 2026-07-27; bouncer-wiring revised the same day after a review against
the live repo + EG 1.8.3 docs (see "Review correction log" at the end).

- [decision] **Bouncer wiring**: native `SecurityPolicy.extAuth.grpc` attached at **Gateway
  level** (`Gateway/envoy-external`, plus a separate policy for `Gateway/envoy-internal` in
  Stage 1), mirroring the existing `envoy-internal-rfc1918` Gateway-level authorization
  policy — **NOT** a per-route SecurityPolicy and **NOT** `EnvoyPatchPolicy + ext_authz`.
  Rationale: EG does NOT merge multiple SecurityPolicies at the same hierarchy level on the
  same target — a second route-level `extAuth` policy would `Accepted=False / Conflicted`
  against the existing route-level `oidc` policy from the `gateway-oidc` component. A
  Gateway-level (parent) `extAuth` policy combines cleanly with a route-level (child) `oidc`
  policy: different level, different feature -> both apply (this is exactly how the existing
  `envoy-internal-rfc1918` Gateway-level authorization + route-level `oidc` already coexist in
  EG 1.8.3). Filter order is `ext_authz -> oidc`, so banned IPs get 403 before reaching the
  Pocket ID OIDC login flow. `bodyToExtAuth.maxRequestBytes: 65536` forwards the request body
  for WAF inspection of POST payloads. The SecurityPolicy lives in the `networking` namespace
  (same ns as the Gateway target, alongside `rfc1918`); the ReferenceGrant in the `crowdsec`
  namespace allows `networking` to reference the bouncer Service. **This is what preserves
  Pocket ID OIDC.**
- [decision] **Gateway-level tradeoff accepted**: Gateway-level attachment loses the per-route
  incremental rollout the original plan wanted — the bouncer protects *all* routes on the
  gateway at once. Mitigation: 2-stage rollout — apply the bouncer SecurityPolicy on
  `Gateway/envoy-internal` first (LAN only; blast radius is LAN users, and `rfc1918` already
  IP-allowlists that gateway), verify no 403-storm on legitimate traffic, then apply on
  `Gateway/envoy-external`. The bouncer SPOF (single replica, fail-closed) now spans the whole
  gateway instead of one route — accepted; the bouncer-down Prometheus alert is therefore critical.
- [decision] **failOpen: false** (fail-closed), security-first. Reverses the original
  roadmap's `fail_closed: false` (Availability > Security). If the bouncer is unavailable,
  Envoy denies (5xx) — the security check always runs. **Human accepted the implication**:
  the bouncer is a hard SPOF; its outage blocks all routes on the gateway it is attached to.
  **No HA**: single replica (human declined bouncer HA). Security > Availability applied literally.
- [decision] **Phase 1 full WAF**: `bodyToExtAuth.maxRequestBytes: 65536` + AppSec collections
  (`crowdsecurity/appsec-virtual-patching`, `crowdsecurity/appsec-crs`,
  `crowdsecurity/appsec-generic-rules`) from day 1. Cost: every protected request *with a body*
  buffers up to 64KB and makes a bouncer round-trip; with fail-closed the bouncer is on the
  critical path with no bypass. Accepted.
- [decision] **Web UI auth**: app-level OIDC via Pocket ID (the Web UI's **built-in OIDC**,
  `CONFIG_AUTH_OIDC_*`), NOT the `gateway-oidc` SecurityPolicy gate (that would double-gate).
  The Web UI does app-level OIDC itself, exactly like grafana. `adminGroups` +
  `unmatchedRole: deny`. A Pocket ID client (`crowdsec-web-ui`) is provisioned via the
  Terraform pocket-id module, `gate: native` style like the `grafana` client — NOT
  `gate: envoy`, since the Web UI does app-level OIDC.
- [decision] **Web UI exposure**: internal-only (`envoy-internal` HTTPRoute), LAN-only, never
  `envoy-external`. Matches the grafana LAN-only precedent (`grafana.${PUBLIC_DOMAIN}` on
  `envoy-internal`).
- [decision] **No external DB**: CrowdSec LAPI state on SQLite (single-node, no CNPG in this
  repo — verified); Web UI SQLite under `/app/data`. Both on local-hostpath PVCs via
  `democratic-csi-local-hostpath`. Reaffirms the original roadmap's SQLite choice.
- [decision] **Log acquisition**: read Envoy JSON access logs from the Envoy proxy pods'
  stdout via the crowdsec agent (artichoked1 pattern). The repo already emits JSON access
  logs to `/dev/stdout` (`envoy.yaml` `telemetry.accessLog` with `downstream_remote_address`
  + `x_forwarded_for`), so the agent reads `/var/log/pods/...` with
  `COLLECTIONS: yanis-kouidri/envoy` + program `envoy`. Client IP detection already handled
  by `ClientTrafficPolicy` (CF-Connecting-IP via `customHeader` on `envoy-external`,
  `xForwardedFor.numTrustedHops: 0` on `envoy-internal`).
- [decision] **Web UI deployment**: bjw-s app-template (repo idiom, ~27 uses) with the
  correct `CONFIG_*` env contract, NOT the stale zekker6 chart.
- [decision] **Geo-enrichment**: MaxMind GeoLite2 via 1Password, reusing the repo's EXISTING
  `maxmind` 1Password item (already consumed by pocket-id). No new 1Password item, no
  plaintext key. ExternalSecret + CNP follow the pocket-id pattern (see Phase 1).
- [decision] **Generated credentials stay out of 1Password**: the bouncer API key, the agent
  registration token, and the Web UI's LAPI machine credential are GENERATED by the
  crowdsec chart / LAPI into K8s Secrets (referenced via `secretKeyRef`), not pre-created in
  1Password. Only externally-sourced secrets go to 1Password: the CAPI enroll token (from
  the CrowdSec Console), the MaxMind key (existing), the Web UI OIDC client secret (in the
  shared `pocket-id-clients` item).

## Execution plan (research-backed)

### Current state

- Greenfield: `grep -ril crowdsec kubernetes/ provision/` returns nothing (the Pocket ID
  client entry in `provision/pocket-id/clients.yaml` is the only crowdsec artifact yet).
- No CloudNativePG / postgres operator in the repo -> SQLite is the correct backend.
- Envoy Gateway already emits JSON access logs to stdout (`envoy.yaml`), so the detection
  feed is wired — only acquisition needs adding.
- `SecurityPolicy` is an established API in the repo (`gateway-oidc` component is route-level
  `oidc`; `envoy-internal-rfc1918` is a Gateway-level `authorization` policy — the latter is
  the pattern the bouncer reuses). `EnvoyPatchPolicy` is used only for compressor tuning —
  the bouncer will NOT use it.
- ESO + `onepassword-connect` ClusterSecretStore is the secret channel for the externally-
  sourced secrets only (CAPI enroll token, MaxMind key, Web UI OIDC client secret). The
  chart-generated credentials (bouncer API key, agent registration token, Web UI LAPI
  machine credential) live in K8s Secrets, not 1Password.
- The `maxmind` 1Password item + MaxMind GeoLite2 egress CNP pattern already exist for
  pocket-id (`kubernetes/apps/security/pocket-id/app/externalsecret.yaml`,
  `ciliumnetworkpolicy.yaml`) — reuse for CrowdSec geoip.
- The `crowdsec-web-ui` Pocket ID client already exists in `provision/pocket-id/clients.yaml`
  (key `crowdsec-web-ui`, `gate: native`, `subdomain: crowdsec`, `groups: [infra_admins]`,
  `callback_path: /api/auth/oidc/callback` — fixed 2026-07-27) AND is registered live
  (client_id `crowdsec-web-ui`, secret in `pocket-id-clients`/`crowdsec-web-ui_client_secret`,
  confirmed 2026-07-27).

### Phase 0 — Namespace + secrets

- Create `crowdsec` namespace (Flux Kustomization + Namespace). Do NOT add a
  `pod-security.kubernetes.io/enforce` label: PSA is not enforced anywhere in this repo
  (the Talos config only disables legacy PSP — `kubernetes/talos/machineconfig.yaml.j2`),
  and PSS `baseline` would *forbid* the `hostPath` `/var/log` mount the agent needs for
  `hostVarLog` log acquisition. Match the repo idiom (no PSA label). The hostPath requirement
  and the `crowdsec` namespace's eventual PSA profile are owned by the separate
  `pod-security-admission-enforcement` roadmap — coordinate there, do not pre-empt it here.
- 1Password items (only what is NOT generated by the chart/LAPI):
  - **`crowdsec`** — CAPI enroll token, field `CAPI_ENROLL_TOKEN` (created 2026-07-27; see
    CAPI followup).
  - **`pocket-id-clients`** (existing) — field `crowdsec-web-ui_client_secret` = the Web UI
    OIDC client secret (synced by `just pocket-id apply`, confirmed present 2026-07-27). The
    Web UI ExternalSecret reads from this shared item, same idiom as grafana.
  - **`maxmind`** (existing) — `MAXMIND_LICENSE_KEY`, reused for geoip (no new item).
  - The bouncer API key, the agent registration token, and the Web UI's LAPI machine
    credential are GENERATED by the chart/LAPI into K8s Secrets (referenced via
    `secretKeyRef`, NOT ESO from 1P) — verify the exact chart mechanism at Phase 1.
  - ExternalSecrets bound to `onepassword-connect`.

### Phase 1 — Engine + bouncer (the core)

- `kubernetes/apps/crowdsec/app/`: HelmRelease for the crowdsec OCI chart 0.24.0
  (`oci://ghcr.io/crowdsecurity/helm-charts/crowdsec`), digest-pinned via OCIRepository.
  Values: SQLite backend (no `db_config` override -> the container's default file SQLite
  applies); LAPI single replica (single-node); `lapi.storeCAPICredentialsInSecret: true`;
  set `api.server.trusted_ips` via the chart's `config.yaml.local` override (it is not a flat
  values key) to `[10.0.0.0/8, ${LAN_SUBNET}]` (covers the Web UI's delete-ops requirement:
  Web UI pod IPs are in `${POD_CIDR}` ⊂ 10.0.0.0/8; `10.0.0.0/8` also covers `${SVC_CIDR}`;
  `${LAN_SUBNET}` covers node + LAN); `auto_registration.enabled: true` with token for the
  agent (the chart's default `auto_registration.allowed_ranges` already includes
  `10.0.0.0/8` and `192.168.0.0/16`); postoverflow whitelist of own infra (`10.0.0.0/8` —
  covers `${POD_CIDR}` + `${SVC_CIDR}` — plus `${LAN_SUBNET}` for node + LAN) so the cluster
  never bans itself.
- Agent acquisition: read Envoy proxy pod logs
  (`podName: envoy-external-*`, `envoy-internal-*`, `program: envoy`,
  `poll_without_inotify: true`), `COLLECTIONS: yanis-kouidri/envoy`. (`hostVarLog: true` is the
  chart default -> the agent mounts hostPath `/var/log`; requires hostPath — see Phase 0 note.)
  EG 1.8.3 names the managed envoy pods `envoy-{gateway-name}-{hash}` — verified live
  2026-07-27: `envoy-external-5dd8db458d-ldpv5`, `envoy-internal-64c94974-rkctk` in the
  `networking` namespace (no `networking-` segment in the pod name, no double `envoy-`
  prefix). The EG controller pod `envoy-gateway-*` is excluded by the `program: envoy` filter
  (it runs the gateway controller binary, not envoy).
- AppSec: `appsec.enabled: true` + `appsec.acquisitions` (`source: appsec`,
  `listen_addr: 0.0.0.0:7422`, `appsec_config: crowdsecurity/appsec-default`) + collections
  `crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-crs crowdsecurity/appsec-generic-rules`.
  None of these are chart defaults (the chart's `appsec.enabled` defaults to false and 7422
  is only a commented example) — all explicit.
- Geo-enrichment: a crowdsec-namespace `ExternalSecret` reusing the existing `maxmind`
  1Password item — `dataFrom.extract.key: maxmind` -> `MAXMIND_LICENSE_KEY` — following the
  pocket-id ExternalSecret pattern (`kubernetes/apps/security/pocket-id/app/externalsecret.yaml`).
  Wire the key into the crowdsec geoip enrichment config. The crowdsec namespace CNP allows
  the MaxMind GeoLite2 egress (copy the pocket-id CNP egress rule: `download.maxmind.com`,
  `*.maxmind.com`, `mm-prod-geoip-databases.a2649acb697e2c09b632799562c076f2.r2.cloudflarestorage.com:443`
  — `kubernetes/apps/security/pocket-id/app/ciliumnetworkpolicy.yaml`).
- `kubernetes/apps/crowdsec/bouncer/`: HelmRelease for kdwils chart 0.7.0
  (`oci://ghcr.io/kdwils/charts/envoy-proxy-bouncer`), single replica, gRPC 8080.
  **`fullnameOverride: crowdsec-bouncer`** so the Service is `crowdsec-bouncer` (the chart's
  Service name is `{{ include "envoy-proxy-bouncer.fullname" }}`; without the override the
  release `crowdsec-bouncer` would render as `crowdsec-bouncer-envoy-proxy-bouncer`).
  `config.bouncer.lapiURL: http://crowdsec-service.crowdsec.svc:8080` + apiKeySecretRef (ESO),
  `config.waf.enabled: true` + `config.waf.appSecURL: http://crowdsec-appsec-service.crowdsec.svc:7422`,
  `config.trustedProxies` + `exemptIPs` = `10.0.0.0/8` + `${LAN_SUBNET}`,
  `referenceGrant.create: true`, `referenceGrant.fromNamespaces: [networking]`. The kdwils
  chart ships **no SecurityPolicy template** (verified 2026-07-27) — there is no
  `securityPolicy` value to disable; we hand-write the Gateway-level SecurityPolicy in the
  envoy-gateway config (alongside `envoy-internal-rfc1918`). Prometheus + ServiceMonitor
  enabled. (Chart value keys + service names verified 2026-07-27 against the chart sources.)
- Gateway-level `SecurityPolicy` in `kubernetes/apps/networking/envoy-gateway/config/` (same
  file pattern as `gateway-policies.yaml`, namespace `networking`):
  `extAuth.grpc.backendRefs -> crowdsec-bouncer.crowdsec.svc:8080` (matches the bouncer
  chart's Service with `fullnameOverride: crowdsec-bouncer`), `failOpen: false`,
  `bodyToExtAuth.maxRequestBytes: 65536`, `targetRefs -> Gateway/envoy-external` (and a
  second policy `targetRefs -> Gateway/envoy-internal` for Stage 1). The cross-namespace
  backendRef (networking -> crowdsec) is permitted by the ReferenceGrant the bouncer chart
  creates in the `crowdsec` namespace with `fromNamespaces: [networking]`.
- 2-stage rollout: (1) apply the `Gateway/envoy-internal` bouncer policy first — LAN-only,
  blast radius is LAN, `rfc1918` already IP-allowlists; verify no 403-storm on legitimate LAN
  traffic; (2) apply the `Gateway/envoy-external` policy. There is no finer-grained per-route
  rollout under Gateway-level attachment — this 2-stage is the coarsest safety step.

### Phase 2 — Web UI

- `kubernetes/apps/crowdsec/web-ui/`: bjw-s app-template HelmRelease, image
  `ghcr.io/theduffman85/crowdsec-web-ui:<date-tag>@sha256:...digest`. Env (verified against
  the Web UI repo README `server/app-auth.ts` 2026-07-27):
  `CONFIG_INSTANCE_LAPI_URL: http://crowdsec-service.crowdsec.svc:8080`,
  `CONFIG_INSTANCE_LAPI_AUTH_USERNAME: crowdsec-web-ui` + password secretKeyRef (the LAPI
  machine credential generated by the chart/LAPI into a K8s Secret — NOT 1Password; see
  Phase 0), `CONFIG_AUTH_OIDC_ISSUER_URL: https://idm.${PUBLIC_DOMAIN}` + client_id/secret
  (ESO from the `pocket-id-clients` item, field `crowdsec-web-ui_client_secret`),
  `CONFIG_AUTH_OIDC_SCOPE: openid profile email groups`, `CONFIG_AUTH_OIDC_GROUPS_CLAIM:
  groups`, `CONFIG_AUTH_OIDC_ADMIN_GROUPS_0: infra_admins` (the Pocket ID client's `groups:
  [infra_admins]` — same admin group as grafana), `CONFIG_AUTH_OIDC_UNMATCHED_ROLE: deny`.
  Probes on `/api/health:3000`. readOnlyRootFS, runAsNonRoot, seccomp RuntimeDefault.
  Persistence: local-hostpath PVC at `/app/data` (SQLite + WAL — mount the directory, not
  just the db file). HTTPRoute on `envoy-internal` only (LAN-only), hostname
  `crowdsec.${PUBLIC_DOMAIN}` (matches the grafana LAN-only precedent — `${PRIVATE_DOMAIN}`
  does not exist as a Flux var; `home.arpa` is not a repo pattern). **No `gateway-oidc`
  SecurityPolicy on this route** — the Web UI does its own app-level OIDC; a gateway gate
  would double-gate.
- Pocket ID client: the `crowdsec-web-ui` client already exists in
  `provision/pocket-id/clients.yaml` (key `crowdsec-web-ui`, `gate: native`, `subdomain:
  crowdsec`, `groups: [infra_admins]`, `callback_path: /api/auth/oidc/callback` — verified
  against `server/app-auth.ts:1256,1265,1296`, fixed 2026-07-27) AND is registered live
  (client_id `crowdsec-web-ui`, secret in `pocket-id-clients`/`crowdsec-web-ui_client_secret`,
  confirmed 2026-07-27). `locals.tf` derives
  `callback_url = https://crowdsec.${PUBLIC_DOMAIN}/api/auth/oidc/callback` for `gate:
  native`. PKCE stays on (the `openid-client` lib sends a challenge; `locals.tf` defaults
  `pkce_enabled: true`). **Verify the live client's callback URL** — run `just pocket-id plan`;
  if it shows a `callback_path` diff, the live client still has the pre-fix
  `/api/oauth/callback/oidc` (i.e. `apply` ran before the fix) and needs
  `just pocket-id apply` to correct it. If no diff, the live client is already correct.

### Phase 3 — Observability

- ServiceMonitors for LAPI, agent, appsec (crowdsec chart) + bouncer (kdwils chart) ->
  kube-prometheus-stack Prometheus.
- Grafana via grafana-operator (repo idiom — NOT the chart's ConfigMap-sidecar label, which
  grafana-operator does not auto-discover):
  (a) **CrowdSec dashboard 21689** — a `GrafanaDashboard` CR with `spec.url:
  https://grafana.com/api/dashboards/21689/revisions/1/download` + datasource `prometheus`
  (aclerici38 pattern; link verified 200 OK 2026-07-27). Covers LAPI/agent/appsec.
  (b) **Bouncer dashboard** — enable the chart's `grafana.dashboard.enabled: true` (ships
  `dashboards/bouncer.json` as a ConfigMap `<bouncer>-dashboard`), then bridge it to
  grafana-operator with a `GrafanaDashboard` CR using `configMapRef` to that ConfigMap (the
  `GrafanaDashboard` field is `configMapRef` — there is no `contentFrom` wrapper; see
  `kubernetes/apps/observability/victoria-logs/app/grafanadashboard.yaml` for the pattern).
  The operator watches CRs, not the `grafana_dashboard: "1"` sidecar label.
- Alerts (human-confirmed required 2026-07-27): (1) bouncer pod unavailable / 5xx spike on
  the attached gateway — **critical under fail-closed** (means all routes on that gateway
  are 5xx-ing); (2) `crowdsec_decisions_total` surge; (3) LAPI down. Wire to Pushover
  (existing alerting channel). The bouncer-down alert is the operational cost of the
  security-first fail-closed + Gateway-level choice — include a runbook for the gateway-wide
  5xx behavior.
- Web UI built-in notifications -> webhook to Pushover for Alert-Spike / IP-Ban /
  LAPI-Availability rules (the Web UI's own notification system, separate from Prometheus).

### Phase 4 — CAPTCHA (deferred)

- Cloudflare Turnstile for "suspicious" IPs (kdwils chart supports Turnstile + reCAPTCHA v2).
  Needs a Turnstile site/secret key (ESO) + the bouncer's HTTPRoute for `/captcha`
  (chart `httproute.yaml` template). Implement only after Phase 1 (403 + WAF) is stable.

## Security review

- **fail-closed SPOF**: by design, the bouncer (single replica) on the critical path with no
  bypass. Bouncer outage = all routes on the attached gateway return 5xx. This is the
  security-first tradeoff the human accepted (and the Gateway-level choice widens it from
  per-route to per-gateway). The bouncer-down Prometheus alert is therefore critical.
- **Trusted IPs gotcha**: the Web UI pod IP range must be in CrowdSec `api.server.trusted_ips`
  for delete/clean IP operations (else 403). Covered by `10.0.0.0/8` (Web UI pods are in
  `${POD_CIDR}` ⊂ 10.0.0.0/8).
- **Self-ban guard**: postoverflow whitelist of own infra (`10.0.0.0/8` covers `${POD_CIDR}` +
  `${SVC_CIDR}`; `${LAN_SUBNET}` covers node + LAN) so CrowdSec never bans the cluster's own
  probes/healthchecks/egress or LAN clients.
- **Secrets**: externally-sourced secrets via ESO -> 1Password (`onepassword-connect`); no
  plaintext credentials in manifests (repo non-negotiable). The MaxMind key reuses the
  existing `maxmind` item; the Web UI client secret reuses the shared `pocket-id-clients`
  item (synced by `just pocket-id apply`); the CAPI enroll token is in the `crowdsec` item.
  The chart-generated credentials (bouncer API key, agent registration token, Web UI LAPI
  machine credential) live in K8s Secrets, not 1Password.
- **CiliumNetworkPolicy**: restrict LAPI (8080) to bouncer + agent + Web UI pods only;
  restrict AppSec (7422) to bouncer only; restrict bouncer gRPC (8080) to the envoy-external /
  envoy-internal proxy pods only (select by label `app.kubernetes.io/name: envoy` +
  `gateway.envoyproxy.io/owning-gateway-name`, the repo CNP idiom — never by pod name). Deny
  everything else in the `crowdsec` namespace. Egress: allow MaxMind GeoLite2 download (copy
  the pocket-id CNP egress rule) for the geoip enrichment; allow LAPI->CAPI (the CrowdSec
  Console endpoints, only if CAPI enroll is enabled); deny other egress.
- **Client IP trust**: relies on Envoy `ClientTrafficPolicy` (`customHeader` CF-Connecting-IP
  on `envoy-external`, `xForwardedFor.numTrustedHops: 0` on `envoy-internal`) already in place
  — the bouncer reads the real client IP from the ext_authz request, not a spoofable header.
- **Web UI OIDC**: `unmatchedRole: deny` — only Pocket ID users in the admin group get
  access; no open registration. App-level auth means the Web UI route does NOT get the
  gateway-oidc SecurityPolicy (avoid double-gating).
- **IdP protection (Gateway-level consequence)**: because the bouncer is Gateway-level,
  every route on the attached gateway — including Pocket ID's own `idm.${PUBLIC_DOMAIN}` login
  page on `envoy-external` (which has no `gateway-oidc` policy, being the IdP itself) — is
  bouncer-protected automatically once the `envoy-external` policy is applied. No separate
  per-route policy is needed for the IdP.

## Resource profile (single-node, conservative)

| Component | CPU Req/Lim | RAM Req/Lim | Note |
| :--- | :--- | :--- | :--- |
| LAPI (+SQLite) | 50m / 200m | 128Mi / 256Mi | Core API + state |
| Agent (envoy logs) | 50m / 200m | 64Mi / 128Mi | Log read + parse |
| AppSec | 100m / 500m | 128Mi / 256Mi | WAF body inspect burst |
| Bouncer | 20m / 100m | 64Mi / 128Mi | gRPC ext_authz, critical path |
| Web UI | 10m / null | 64Mi / 128Mi | SQLite dashboard |

## Verification steps

- [ ] `kubectl -n crowdsec get pods` — all components healthy; LAPI + agent + appsec +
  bouncer + web-ui Running.
- [ ] `kubectl -n crowdsec exec crowdsec-... -- cscli machines list` shows the bouncer +
  web-ui watcher registered; `cscli decisions add -i 1.2.3.4` then confirm a request from
  1.2.3.4 to a protected route gets 403, and `cscli decisions delete 1.2.3.4` clears it
  (trusted_ips gotcha verified).
- [ ] `cscli metrics` shows the envoy parser ingesting envoy access logs (non-zero parsed
  lines); AppSec shows requests inspected; geoip enrichment populates country/ASN fields.
- [ ] Send a malicious POST body (e.g. `' OR 1=1 --`) to a protected route -> 403 from AppSec
  (WAF body inspect verified).
- [ ] Native-OIDC app protection: with a test ban on an IP, that IP hitting the Pocket ID
  external login (`idm.${PUBLIC_DOMAIN}`) and grafana (LAN) gets 403 — confirms the
  Gateway-level bouncer covers routes without a route-level oidc policy (automatic under
  the Gateway-level design).
- [ ] Web UI: browse `https://crowdsec.${PUBLIC_DOMAIN}` -> Pocket ID OIDC redirect ->
  login as infra_admins user -> dashboard shows local alerts/decisions; a non-group user is
  denied (`unmatchedRole: deny`); the OIDC callback `/api/auth/oidc/callback` completes.
- [ ] `just pocket-id plan` shows no `callback_path` diff for `crowdsec-web-ui` (the live
  client's callback is `/api/auth/oidc/callback`); if it does show a diff, run
  `just pocket-id apply` to correct it before relying on the Web UI login.
- [ ] Prometheus: `crowdsec_*` and bouncer metrics scrape; Grafana dashboard 21689 renders;
  bouncer-down alert fires when the bouncer pod is deleted (verify the 5xx protected-route
  behavior + the alert).
- [ ] CiliumNetworkPolicy: a pod outside the allowed set cannot reach LAPI/AppSec/bouncer;
  the LAPI/agent pod CAN reach MaxMind (GeoLite2 download) and (if enrolled) CAPI.
- [ ] fail-closed: delete the bouncer pod (single replica) -> all routes on the attached
  gateway return 5xx while the bouncer is down (the accepted SPOF behavior, verified not
  silent fail-open). Confirm the exact response code (EG extAuth `failOpen: false`) at
  implementation.

## Rollback & safety

- Per-app rollback: NOT available under Gateway-level attachment — the bouncer protects all
  routes on the gateway at once. Rollback granularity is per-gateway.
- Gateway rollback: delete the bouncer `SecurityPolicy` for that gateway (`envoy-external`
  or `envoy-internal`) -> that gateway's routes revert to pre-bouncer behavior (no ext_authz).
  The other gateway is unaffected (the 2-stage deployment means the two policies are
  independent).
- Full rollback: delete both bouncer SecurityPolicies -> all routes revert; then
  suspend/remove the crowdsec + bouncer + web-ui Flux Kustomizations. SQLite PVCs remain
  (data preserved) or are deleted for a clean slate.
- fail-closed means a bad bouncer upgrade blocks all routes on the attached gateway — stage
  bouncer chart upgrades carefully; the 2-stage (internal -> external) gives a test surface:
  upgrade with only the `envoy-internal` policy active, observe, then re-apply
  `envoy-external`.
- No cluster-mutating out-of-band actions: all changes via GitOps (Flux watches main).

## Open sub-decisions / follow-ups

- [resolved 2026-07-27] **Geo-enrichment**: MaxMind GeoLite2 via 1Password, reusing the
  repo's EXISTING `maxmind` 1Password item (already consumed by pocket-id:
  `kubernetes/apps/security/pocket-id/app/externalsecret.yaml` extracts
  `MAXMIND_LICENSE_KEY` from `dataFrom.extract.key: maxmind`). Add a crowdsec-namespace
  ExternalSecret with the same `dataFrom.extract.key: maxmind` pattern. The crowdsec
  namespace CNP allows MaxMind GeoLite2 egress — copy the pocket-id CNP egress rule
  (`download.maxmind.com`, `*.maxmind.com`,
  `mm-prod-geoip-databases.a2649acb697e2c09b632799562c076f2.r2.cloudflarestorage.com:443` —
  `kubernetes/apps/security/pocket-id/app/ciliumnetworkpolicy.yaml`). No new 1Password item,
  no plaintext key.
- [followup] **CAPI community blocklist**: CAPI = the CrowdSec Central API (the CrowdSec
  Console network). Enrolling the LAPI makes it pull the aggregated **community blocklist**
  — IPs every CrowdSec user worldwide has flagged as malicious — and push your local
  decisions up (anonymized) so others benefit. This is the main value of CrowdSec: you block
  not just what your own logs detect, but what the whole network detects. **Procedure**:
  (1) sign up (free) at https://app.crowdsec.net; (2) in the Console, "Add instance" / "Enroll
  a new instance" -> it shows `cscli console enroll <TOKEN>`; (3) copy `<TOKEN>`. **1Password
  item**: `crowdsec` with field `CAPI_ENROLL_TOKEN` = the token (created 2026-07-27; store the
  Console login email in the item notes for recovery). After enrollment the LAPI mints its
  own CAPI machine credentials and (with `lapi.storeCAPICredentialsInSecret: true`) stores
  them in a K8s Secret automatically — do NOT pre-create those, do NOT put them in 1Password;
  the enroll token is the only thing brought from the website. **Wiring**: a crowdsec-ns
  ExternalSecret extracts `CAPI_ENROLL_TOKEN` from the `crowdsec` 1P item -> K8s Secret;
  enrollment runs via `cscli console enroll $TOKEN` against the LAPI pod (one-shot
  `kubectl exec`, or a chart init job if the chart exposes an enroll value — exact chart
  mechanism to verify against crowdsec chart 0.24.0 at Phase 1). Recommend: enroll (it is the
  point of running CrowdSec); keep the Web UI `includeCapi` flag default **false** initially
  to avoid alert overload (corelab warning), flip to true later. Decide at Phase 1.
- [followup] **Bouncer namespace**: planned `crowdsec` (engine + UI + bouncer together, one
  Cilium CNP to isolate). The Gateway-level `SecurityPolicy` lives in the `networking`
  namespace (alongside `envoy-internal-rfc1918`) because a SecurityPolicy must be in the same
  namespace as its Gateway target; the ReferenceGrant lives in `crowdsec` allowing
  `from: networking`. Confirmed at Phase 0.
- [verified 2026-07-27] **Envoy proxy pod naming**: the acquisition glob is
  `envoy-external-*` / `envoy-internal-*`. Verified live against the cluster: envoy proxy
  pods are `envoy-external-5dd8db458d-ldpv5` and `envoy-internal-64c94974-rkctk` in the
  `networking` namespace (label `gateway.envoyproxy.io/owning-gateway-name`). EG 1.8.3 names
  them `envoy-{gateway-name}-{hash}` — no namespace segment, no double `envoy-` prefix. (The
  earlier `envoy-networking-envoy-*` and the original `envoy-envoy-*` forms were both wrong.)
  The EG controller pod `envoy-gateway-*` is excluded by `program: envoy`.
- [verified 2026-07-27] **Chart service names + value keys**: crowdsec chart LAPI Service =
  `{{ .Release.Name }}-service` -> `crowdsec-service`; AppSec Service = `crowdsec-appsec-service`
  (confirmed via the kdwils chart default `appSecURL`). kdwils bouncer chart value keys
  confirmed: `config.bouncer.lapiURL` (default `http://crowdsec-service:8080`),
  `config.bouncer.apiKeySecretRef`, `config.waf.appSecURL` (capital S, default
  `http://crowdsec-appsec-service:7422`), `referenceGrant.create`/`fromNamespaces`.
  `securityPolicy.create` does NOT exist — the kdwils chart ships no SecurityPolicy template
  (templates: deployment/service/referencegrant/httproute/servicemonitor/serviceaccount/hpa/
  configmaps only). The bouncer Service is `{{ include "envoy-proxy-bouncer.fullname" }}` ->
  set `fullnameOverride: crowdsec-bouncer`. crowdsec `api.server.trusted_ips` is set via the
  `config.yaml.local` override, not a flat value; `auto_registration.allowed_ranges`
  defaults to `10.0.0.0/8` + `192.168.0.0/16`. AppSec 7422 + collections are explicit config
  (not chart defaults).
- [verified 2026-07-27] **Web UI OIDC = native + callback path + client live**: the Web UI
  has built-in OIDC (`CONFIG_AUTH_OIDC_*`, env contract confirmed in the repo README) — it
  does app-level OIDC itself (like grafana), so NO `gateway-oidc` SecurityPolicy gate in
  front of it (that would double-gate). The OIDC callback path is `/api/auth/oidc/callback`
  — verified against `server/app-auth.ts:1256` (redirect URI built as
  `${origin}${basePath}/api/auth/oidc/callback`), `:1265` (`auth.get('/oidc/callback')`),
  `:1296` (`app.route('${basePath}/api/auth', auth)`). The `crowdsec-web-ui` Pocket ID client
  already exists in `provision/pocket-id/clients.yaml` (key `crowdsec-web-ui`, `gate:
  native`, `subdomain: crowdsec`, `groups: [infra_admins]`) AND is registered live (client_id
  `crowdsec-web-ui`, secret in `pocket-id-clients`/`crowdsec-web-ui_client_secret`, confirmed
  2026-07-27). Its `callback_path` in `clients.yaml` was wrong
  (`/api/oauth/callback/oidc`, copied from pingvin-share-x) and is fixed to
  `/api/auth/oidc/callback`; `locals.tf:15` derives
  `callback_url = https://${subdomain}.${PUBLIC_DOMAIN}${callback_path}` for `gate: native`
  -> `https://crowdsec.${PUBLIC_DOMAIN}/api/auth/oidc/callback`. PKCE stays on (the
  `openid-client` lib sends a challenge; `locals.tf:21` defaults `pkce_enabled: true`).
  Open check: `just pocket-id plan` to confirm the LIVE client's callback matches the fix
  (in case `apply` ran before the callback-path correction).
- [confirmed 2026-07-27] **Bouncer-down Prometheus alert**: required (human-confirmed).
  Critical under fail-closed — a bouncer outage means all routes on the attached gateway
  return 5xx. Tune the alert + write a runbook for the gateway-wide 5xx behavior at Phase 3.
- [followup] **PSA profile for the `crowdsec` namespace**: the hostPath `/var/log` requirement
  (hostVarLog) needs a privileged/baseline-exempt profile; this is owned by the separate
  `pod-security-admission-enforcement` roadmap — coordinate there when that lands.

## What we gain

- Automated IP-ban enforcement + WAF (SQLi/XSS/path) at the edge for every backend, with no
  per-app bouncer code.
- A self-hosted, OIDC-protected, LAN-only security dashboard with historical alert retention
  (the Web UI's sleeper feature) — no reliance on CrowdSec Console.
- Community threat intelligence via CAPI blocklists, applied at the edge.
- Native Envoy Gateway integration (Gateway-level `SecurityPolicy.extAuth`) that combines
  with the existing route-level Pocket ID OIDC gate via EG's parent→child different-feature
  merge — the same pattern the existing `envoy-internal-rfc1918` authorization + route-level
  `oidc` already use. Native-OIDC apps (Pocket ID, grafana) are protected automatically by the
  Gateway-level policy, with no per-route policy needed.
- Geo-enrichment (country/ASN world map) reusing the repo's existing MaxMind key — no new
  secret material.
- All self-contained on SQLite — no external DB dependency for a single-node cluster.

## Effort

L (~1-1.5 days staged): Phase 0+1 (~1d: chart values, envoy acquisition tuning, Gateway-level
SecurityPolicy + ReferenceGrant, geoip ExternalSecret + CNP, CAPI enrollment, 2-stage
verification) + Phase 2 (~0.5d: Web UI + OIDC — the Pocket ID client already exists + is
live) + Phase 3 (~0.25d: dashboards + alerts + runbook) + Phase 4 deferred. The Gateway-level
design is slightly cheaper than the originally planned per-route component (no `gateway-oidc`
component refactor). The fail-closed 2-stage rollout is the slow part — staged internal ->
external to verify no 403-storm on legitimate traffic and to tune the whitelist.

## Relations

- relates_to [[docs/areas/networking]]
- relates_to [[docs/areas/k8s-workloads]]
- relates_to [[docs/areas/observability]]
- relates_to [[docs/areas/iam]]
- depends_on [[docs/areas/external-secrets]]
- relates_to [[grafana-operator-migration]]

## Review correction log (2026-07-27)

Revised against the live repo (`kubernetes/`, `provision/`), the BM area-references, and
EG 1.8.3 docs; points 1 (chart keys/service names) and 2 (envoy pod naming) then verified
against the chart sources and the live cluster; follow-ups resolved with the human 2026-07-27.

1. **Bouncer wiring → Gateway-level** (chosen "Megoldás A"): the original "two route-level
   SecurityPolicies (extAuth + oidc) coexist via section-merge" was wrong — EG does not merge
   same-level policies on the same target (would `Conflicted`). Rewired to a Gateway-level
   `extAuth` SecurityPolicy (parent), which combines with the route-level `oidc` (child) the
   same way `envoy-internal-rfc1918` already does. Tradeoff: no per-route rollout; 2-stage
   internal → external; bouncer SPOF widens to the whole gateway.
2. `${CLUSTER_POD_CIDR}` → `${POD_CIDR}` (the real Flux var; `10.244.0.0/16`) in trusted_ips /
   postoverflow / exemptIPs; `10.0.0.0/8` already covers it + `${SVC_CIDR}`, plus
   `${LAN_SUBNET}` for node/LAN.
3. `${PRIVATE_DOMAIN}` → `${PUBLIC_DOMAIN}` for the Web UI hostname
   (`crowdsec.${PUBLIC_DOMAIN}` on `envoy-internal`, grafana precedent); `home.arpa` dropped
   (not a repo pattern).
4. Envoy pod-name globs corrected to `envoy-{external,internal}-*` (see item 9 — the live
   cluster disproved the `networking-` segment).
5. Dropped the `pod-security.kubernetes.io/enforce: baseline` namespace label — PSA is not
   enforced in this repo and `baseline` would forbid the hostPath `/var/log` the agent needs;
   this is owned by the `pod-security-admission-enforcement` roadmap.
6. `GrafanaDashboard` field: `configMapRef` (no `contentFrom` wrapper).
7. bjw-s app-template uses ≈27 (not 31).
8. IdP protection reworded: under Gateway-level, Pocket ID's own external login is protected
   automatically (no per-route policy needed).
9. **Envoy pod glob re-corrected (live-verified 2026-07-27)**: the first correction
   (`envoy-networking-envoy-*`) was itself wrong — live pods are `envoy-external-*` /
   `envoy-internal-*` (EG 1.8.3 names envoy pods `envoy-{gateway-name}-{hash}`, no namespace
   segment, no double `envoy-` prefix). All prior forms corrected to
   `envoy-{external,internal}-*`.
10. **Chart verification (live + chart sources, 2026-07-27)**: kdwils bouncer chart 0.7.0
    ships NO SecurityPolicy template/value (`securityPolicy.create` absent) — the "disable
    securityPolicy.create" line was removed; the bouncer Service needs
    `fullnameOverride: crowdsec-bouncer` (else it renders `crowdsec-bouncer-envoy-proxy-bouncer`).
    crowdsec chart services confirmed `crowdsec-service` + `crowdsec-appsec-service`
    (`{{ .Release.Name }}-service` pattern). `config.waf.appSecURL` (capital S) confirmed.
    `api.server.trusted_ips` is set via the `config.yaml.local` override, not a flat value;
    `auto_registration.allowed_ranges` defaults to `10.0.0.0/8` + `192.168.0.0/16`. AppSec
    7422 + collections are explicit config (not chart defaults).
11. **Follow-up resolutions (with human, 2026-07-27)**: (a) geo-enrichment resolved — reuse
    the existing `maxmind` 1Password item (pocket-id already consumes it) + copy the pocket-id
    MaxMind egress CNP rule; (b) CAPI explained — the CrowdSec Central API community
    blocklist (the main value of CrowdSec); recommend enroll, `includeCapi` default false;
    (c) Web UI OIDC confirmed native (built-in `CONFIG_AUTH_OIDC_*`), no `gateway-oidc` gate,
    `gate: native` Pocket ID client like grafana; (d) bouncer-down Prometheus alert confirmed
    required (critical under fail-closed) + runbook. The Web UI decision block was reworded
    to state "built-in OIDC" explicitly, and Phase 1/3 gained the geoip ExternalSecret + CNP
    egress lines.
12. **Web UI callback + CAPI procedure (verified 2026-07-27)**: the OIDC callback path is
    `/api/auth/oidc/callback`, verified against `server/app-auth.ts:1256,1265,1296` (route
    `auth.get('/oidc/callback')` mounted at `${basePath}/api/auth`; redirect URI
    `${origin}${basePath}/api/auth/oidc/callback`). The env contract (`CONFIG_AUTH_OIDC_*`,
    `CONFIG_INSTANCE_*`) confirmed in the repo README. The existing `crowdsec-web-ui` entry
    in `provision/pocket-id/clients.yaml` had the WRONG `callback_path`
    (`/api/oauth/callback/oidc`, copied from pingvin-share-x) — fixed to
    `/api/auth/oidc/callback` (lint passes); `just pocket-id plan` should show only that
    callback-path diff. CAPI procedure + 1Password item recorded in the CAPI followup. Phase 2
    admin group made concrete (`infra_admins`) and the Web UI client-secret flow corrected: it
    reads from the shared `pocket-id-clients` 1Password item (synced by `just pocket-id apply`),
    not a separate `crowdsec-web-ui-oidc` item.
13. **Secrets in place + client live (human, 2026-07-27)**: the `crowdsec-web-ui` Pocket ID
    client is registered live (client_id `crowdsec-web-ui`, secret in
    `pocket-id-clients`/`crowdsec-web-ui_client_secret`). The CAPI enroll token is in a 1P
    item named **`crowdsec`** (field `CAPI_ENROLL_TOKEN`) — not `crowdsec-capi` as previously
    drafted; the CAPI followup + Phase 0 updated to the real name. Removed the unnecessary
    `crowdsec-lapi` 1P item: the bouncer API key, agent registration token, and Web UI LAPI
    machine credential are GENERATED by the chart/LAPI into K8s Secrets (a new decision block
    records this), not pre-created in 1P — only externally-sourced secrets (CAPI token,
    MaxMind key, OIDC client secret) go to 1Password. Added a verification step:
    `just pocket-id plan` to confirm the live client's callback URL matches the corrected
    `/api/auth/oidc/callback` (in case `apply` ran before the callback-path fix).
