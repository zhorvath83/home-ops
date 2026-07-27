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

## Review correction log — 2026-07-27 second pass (Gateway-level same-level conflict)

A second evidence-based review on 2026-07-27 (live cluster + repo + EG 1.8.3 docs)
found one blocking architectural flaw in the bouncer-wiring decision. This section is
**authoritative and supersedes** the affected clauses in "Decisions (Bouncer wiring)",
"Phase 1 — Engine + bouncer", "What we gain", and the "IdP protection" claim wherever
they describe the `envoy-internal` bouncer as a *separate* Gateway-level policy living
"alongside" `envoy-internal-rfc1918`. The `envoy-external` wiring is unaffected.

### The flaw

The original decision reasons that "EG does NOT merge multiple SecurityPolicies at the
same hierarchy level on the same target" — but applies that rule only to the *route-level*
case (a second route-level `extAuth` would `Conflicted` against the existing route-level
`oidc`), and then "solves" it by attaching the bouncer at Gateway level. It does **not**
re-apply the same rule to the *Gateway-level* case it creates.

Today on `envoy-internal` there is already ONE Gateway-level SecurityPolicy:
`envoy-internal-rfc1918` (`authorization`, `defaultAction: Deny`, RFC1918 allowlist,
live 70d). The plan adds a **second** Gateway-level SecurityPolicy (`extAuth`, bouncer)
on the **same** Gateway target. That is two policies at the **same hierarchy level on the
same target** — exactly the conflict case the note itself describes.

### EG 1.8.3 documented semantics (verified)

- "When multiple SecurityPolicies target the same resource at the same hierarchy level
  ... the oldest policy (earliest creationTimestamp) takes precedence" — **single-winner,
  feature-agnostic**; there is no same-level feature merge.
- `mergeType` (StrategicMerge / JSONMerge) is **parent-child only** — it can be set on
  policies targeting HTTPRoute, **not** on Gateway-level policies. So two Gateway-level
  policies cannot be merged via `mergeType`.

Source: gateway.envoyproxy.io SecurityPolicy concepts; envoyproxy/gateway#4275, #8649.

### Consequence if left unfixed

`envoy-internal-rfc1918` is older, so it wins; the bouncer `extAuth` policy becomes
`Overridden`/`Conflicted` and is **silently inert** on `envoy-internal` — Stage 1 of
the 2-stage rollout reports a false green. (Or, if the bouncer somehow won, the rfc1918
LAN allowlist would drop off the gateway — a security regression, only masked by the
Cilium CNP at the network layer.) Either outcome is wrong.

### Corrected design (supersedes the prior wiring)

- **`envoy-internal`**: do NOT create a separate bouncer Gateway-level SecurityPolicy.
  Instead, **merge the bouncer `extAuth` block INTO the existing
  `envoy-internal-rfc1918` SecurityPolicy** — one Gateway-level policy carrying both
  `authorization` (the existing RFC1918 rules) **and** `extAuth` (bouncer,
  `failOpen: false`, `bodyToExtAuth.maxRequestBytes: 65536`,
  `backendRefs -> crowdsec-bouncer.crowdsec.svc:8080`). This is the only EG-supported
  way to get both features on the same Gateway target. The ReferenceGrant in the
  `crowdsec` namespace (`fromNamespaces: [networking]`) still permits the
  cross-namespace backendRef.
- **`envoy-external`**: unchanged — a **separate** Gateway-level bouncer SecurityPolicy
  is correct here, because there is **no** existing Gateway-level policy on
  `envoy-external` (verified live 2026-07-27: only route-level oidc policies exist on
  envoy-external-attached routes, e.g. echo-server-oidc). Route-level oidc + Gateway-level
  extAuth is the supported **parent-child, different-feature** case and combines cleanly.
- **Rollout (corrected Stage 1)**: Stage 1 is "merge `extAuth` into
  `envoy-internal-rfc1918` and verify the merged policy's status shows no
  `Conflicted`/`Overridden`", NOT "apply a second Gateway-level policy". Stage 2
  (separate bouncer policy on `envoy-external`) is unchanged.

### Corrected "precedent" framing

The earlier claim that "this is exactly how the existing `envoy-internal-rfc1918`
Gateway-level authorization + route-level oidc already coexist" is a **different-level**
(parent Gateway + child HTTPRoute) case and is real (the 8 downloads oidc routes — bazarr,
prowlarr, radarr, sonarr, seerr, maintainerr, qbittorrent, subsyncarr — attach to
`envoy-internal` with route-level oidc, live-verified 2026-07-27). But that precedent
does **not** justify a **same-level** dual-Gateway-policy on `envoy-internal`, which the
bouncer would introduce. The two cases must not be conflated.

### Corrected "What we gain" framing

The bouncer on `envoy-external` is **defense-in-depth behind Cloudflare WAF** (the
`networking` area-ref records that envoy-external rate-limiting is currently covered by
Cloudflare WAF pending the EG 1.8.x CRD regression fix). The **primary** edge-protection
gain is on `envoy-internal`, which is exposed on a Cilium L2 VIP with no WAF in front.

### New verification step (append to "Verification steps")

- [ ] After merging `extAuth` into `envoy-internal-rfc1918`:
  `kubectl -n networking get securitypolicy envoy-internal-rfc1918 -o jsonpath='{.status.conditions}'`
  shows `Accepted=True` with **no** `Conflicted`/`Overridden` condition; and a test
  ban (`cscli decisions add -i 1.2.3.4`) 403s on an `envoy-internal` route while the
  RFC1918 LAN allowlist still holds for a non-RFC1918 source (both features present in the
  single merged policy). Also confirm the separate `envoy-external` bouncer policy is
  `Accepted=True` (no same-level conflict there).

### Net effect on the plan

Effort and scope are essentially unchanged — the only implementation difference is one
merged SecurityPolicy on `envoy-internal` instead of two separate Gateway-level policies.
The fail-closed SPOF, trusted-IPs, self-ban whitelist, CNP, geoip, and Web UI sections are
unaffected and remain as written.

## Update 2026-07-27 — namespace rationale, OAuth callback resolved, PSA coordination

### OAuth callback — RESOLVED (human-verified 2026-07-27)

The live `crowdsec-web-ui` Pocket ID client's OAuth redirect URL is correct
(`/api/auth/oidc/callback` -> `https://crowdsec.${PUBLIC_DOMAIN}/api/auth/oidc/callback`).
The open `just pocket-id plan` / "verify the live client's callback URL" checks in
Phase 2 and "Verification steps" are **resolved** — no `callback_path` diff to apply.
(Closes the open check raised in the 2026-07-27 first-pass correction log item 12.)

### Namespace design — rationale (why a single dedicated `crowdsec` namespace)

Repo idiom (verified 2026-07-27): 12 app-group namespaces under `kubernetes/apps/<group>/`,
one per domain (`downloads`, `media`, `selfhosted`, `security`, `networking`,
`observability`, `cert-manager`, `volsync-system`, `system-upgrade`, `kube-system`,
`external-secrets`, `flux-system`). Platform components get their own ns. The plan puts
**all** crowdsec components — engine (LAPI + agent + AppSec) + bouncer + Web UI — in one
new `crowdsec` namespace. Reasons:

1. **One CiliumNetworkPolicy isolates the whole component.** LAPI (8080), AppSec (7422),
   and bouncer gRPC (8080) ingress restricted to the allowed callers (bouncer, agent,
   Web UI, and the envoy proxy pods on the critical path). A single namespaced CNP is
   simpler and tighter than cross-ns ClusterwideCNPs split across namespaces.
2. **Chart-generated credentials stay in-ns.** The bouncer API key, agent registration
   token, and Web UI LAPI machine credential are GENERATED by the chart/LAPI into K8s
   Secrets and consumed via `secretKeyRef` within `crowdsec` — no cross-namespace
   secret references (which would need extra wiring and widen the access surface).
3. **Distinct risk profile from the IdP.** `security` hosts pocket-id (the OIDC IdP,
   distroless nonroot, restricted-clean). CrowdSec mixes a hostPath-mounting log agent
   (privileged-ish), an AppSec WAF on the request critical path, and an internally-exposed
   LAPI — a different blast radius. A dedicated ns keeps its CNP and (future) PSA profile
   separate from the IdP rather than forcing one profile onto both.
4. **Lifecycle coupling.** Bouncer + Web UI depend on LAPI; one Flux Kustomization tree
   (`kubernetes/apps/crowdsec/`) keeps the dependency coherent.

**The one deliberate cross-namespace boundary:** the Gateway-level `SecurityPolicy` MUST
live in `networking` (EG constraint: a SecurityPolicy is in the same namespace as its
Gateway target — verified: `envoy-internal-rfc1918` is in `networking`). The bouncer
Service stays in `crowdsec`; `networking` references it cross-ns via a `ReferenceGrant`
in `crowdsec` (`fromNamespaces: [networking]`). This is the **minimal** cross-ns surface:
one CR (the SecurityPolicy in `networking`) + one ReferenceGrant (in `crowdsec`).

**Rejected alternatives:**
- **Bouncer in `networking`:** would create a cross-ns secret ref (bouncer -> LAPI API
  key in `crowdsec`), split the isolating CNP across namespaces, and decouple the bouncer
  lifecycle from LAPI. More complexity, no benefit.
- **CrowdSec in `security` (with pocket-id):** forces one PSA/CNP profile onto two
  components with different risk profiles (hostPath agent vs distroless IdP); see PSA note
  below — the hostPath requirement makes `crowdsec` need `privileged` enforce, which
  pocket-id must not carry.

### PSA coordination — detail (why the `crowdsec` ns cannot be baseline/restricted)

The crowdsec agent needs `hostVarLog: true` -> it mounts hostPath `/var/log` to read the
envoy proxy pods' stdout logs from `/var/log/pods/...` (acquisition globs
`envoy-external-*` / `envoy-internal-*`, `program: envoy`). PSS **`baseline` forbids
hostPath mounts**, and PSS has **no per-pod in-namespace exception** (the
`pod-security-admission-enforcement` roadmap states this explicitly: a single
non-compliant pod blocks the whole namespace). Therefore:

- The `crowdsec` namespace **cannot** be `enforce: baseline` (or `restricted`) while
  the agent uses `hostVarLog` — the agent pod would be rejected at admission.
- The `crowdsec` ns fits the **infra-namespace -> `privileged` enforce** pattern in the
  PSA roadmap (`kube-system`, `system-upgrade`, `volsync-system`, `cert-manager` stay
  `privileged` for legit privileged infra). The non-agent pods (LAPI, AppSec, bouncer,
  Web UI) ARE restricted-clean (runAsNonRoot, drop ALL, seccomp RuntimeDefault,
  readOnlyRootFS) — but they share the ns with the hostPath agent, so the ns-level label
  must accommodate the agent.

**Current cluster state (verified 2026-07-27):** NO `pod-security.kubernetes.io/*` labels
on any app namespace except `flux-system` (`warn=restricted`, auto-applied by the
flux-operator). So the repo idiom today is "no PSA labels"; the PSA roadmap proposes
adding them. Consistent with that, the crowdsec roadmap does **NOT** add a PSA label to
the `crowdsec` namespace now — the PSA roadmap owns that label and will classify
`crowdsec` as `enforce: privileged` (with `warn`/`audit: restricted` to keep the non-agent
pods honest).

**Alternatives that would avoid the privileged profile** (not chosen for this single-node
cluster — logged as PSA-roadmap coordination, not implemented here):
1. Ship envoy access logs to the agent over network via a Fluent Bit / Vector sidecar or
   DaemonSet (no hostPath) — adds a component and a hop.
2. CrowdSec Kubernetes-audit / API-stream acquisition instead of file acquisition —
   different detection surface (k8s audit events, not envoy HTTP logs); loses the WAF
   feed value.
3. Split: LAPI/AppSec/bouncer/Web UI in a `crowdsec` ns at `restricted` + the agent as
   a DaemonSet in a dedicated privileged infra ns — cleanest separation but
   over-engineered for a single-node cluster.

**Coordination handoff:** when the `pod-security-admission-enforcement` roadmap lands,
it must label `crowdsec` as `enforce: privileged` (NOT baseline/restricted) because of
`hostVarLog`. This is the crowdsec roadmap's only PSA contribution — a documented
constraint, not a label to add now.

### HostPath-free acquisition — the victoria-logs pipeline option (2026-07-27)

The `hostVarLog` hostPath requirement is NOT the only acquisition path. Evidence-backed
alternatives exist that keep the `crowdsec` namespace hostPath-free, which reopens the
PSA profile from `privileged` back to `restricted`.

**Existing pipeline (live-verified 2026-07-27):** `victoria-logs-collector` is a DaemonSet
in the `observability` ns mounting hostPath `/var/log` (readOnly) + `/var/lib` (ReadOnly),
shipping all pod stdout logs to `victoria-logs-server.observability.svc:9428`. The envoy
proxy pods' JSON access logs already flow through it (`envoy.yaml` `type: File -> /dev/stdout`
-> `/var/log/pods/...` -> collector -> victoria-logs-server). This is the repo's only log
shipper (no vector/fluent-bit/otel-collector DaemonSet besides it).

**CrowdSec network acquisition sources (Context7-verified, doc.crowdsec.net):** the agent
supports DataSource modules `file`, `http`, `syslog`, `kafka`, `kubernetes-audit`,
`journald`, `docker`, `Loki`, `VictoriaLogs`, `Appsec`, `AWS`. So file/hostPath is NOT
the only option — `http`, `syslog`, and a native `VictoriaLogs` source all receive logs
over the network.

**Ranked hostPath-free options:**
1. **`victorialogs` source (RECOMMENDED, zero new infra):** the crowdsec agent reads envoy
   access logs from `victoria-logs-server` via the native VictoriaLogs datasource. No new
   component, no hostPath on `crowdsec`, one CNP egress rule (crowdsec agent ->
   `victoria-logs-server.observability.svc:9428`). Verification point: the collector-stored
   envoy log field format must match the `yanis-kouidri/envoy` parser (preserve the raw
   envoy JSON line in the collector config, or write a crowdsec parser for the VL fields).
2. **`http` source + collector sink:** add a second sink to the existing victoria-logs-collector
   config that POSTs envoy log lines to the crowdsec agent's HTTP source. Reuses the
   collector; +1 sink + CNP (collector -> crowdsec http port). Raw envoy JSON line passes
   through -> existing parser stays.
3. **`syslog` source + collector syslog sink:** equivalent to 2 over syslog TCP (Vector
   supports a syslog sink).
4. **EnvoyProxy `OpenTelemetry`/`ALS` sink (EG-native, NOT reuse):** EG 1.8.3 supports
   `type: OpenTelemetry` (OTLP gRPC) and `type: ALS` (gRPC Access Log Service) access-log
   sinks — both network, not file. But no OTel collector exists in the repo today, and the
   OTLP AccessLog schema != the envoy JSON line the `yanis-koudri/envoy` parser expects
   (needs a collector transform). More new infra + a format bridge -> less attractive than
   1-3 on a single node.

**Revised PSA implication:** the earlier conclusion ("`crowdsec` ns must be `enforce:
privileged` because of `hostVarLog`") holds ONLY for the hostPath-agent path. With option
1 (`victorialogs`) or 2 (`http`), the `crowdsec` ns can be `enforce: restricted` — the agent
gets no hostPath, and the non-agent pods (LAPI/AppSec/bouncer/Web UI) are already
restricted-clean. So the PSA-roadmap table row for `crowdsec` is conditional on the chosen
acquisition path: hostVarLog -> `privileged`; victorialogs/http -> `restricted`.

**Side finding (repo-wide, affects the PSA roadmap):** the `observability` ns ALREADY hosts
hostPath-mounting DaemonSets — `victoria-logs-collector` (`/var/log`, `/var/lib`) and
`kube-prometheus-stack-prometheus-node-exporter` (`/`, `/sys`, `/proc`). PSS `baseline`
forbids hostPath, so `observability` cannot be `enforce: baseline` without exceptions — it
must be `privileged`, like the other infra namespaces. The `pod-security-admission-
enforcement` roadmap's "observability -> baseline" row is already blocked by the live
cluster; that roadmap's per-namespace table needs correcting. The hostPath problem is
repo-wide (any ns running node-level DaemonSets), not crowdsec-specific.

**Recommendation:** on a single node, `hostVarLog` remains the pragmatic default (simplest,
matches the crowdsec chart defaults, and is consistent with the existing `observability`
hostPath-DaemonSet pattern — sets no new precedent). The `victorialogs` source is the clean
upgrade when the PSA roadmap tightens, recorded here as the explicit alternative — not
implemented now. If the goal is `crowdsec` ns `restricted` from day one, take option 1 and
verify the collector's envoy-log field format as the first implementation step.

## Locked decision — 2026-07-27 (human): `restricted` PSA + `victorialogs` acquisition

Human-locked 2026-07-27. This section is **authoritative** and supersedes every prior
clause about (a) the `crowdsec` namespace PSA profile, (b) envoy log acquisition, and
(c) the acquisition-alternatives ranking. Specifically it supersedes:
- the Phase 0 line "Do NOT add a pod-security.kubernetes.io/enforce label ... coordinate
  with the pod-security-admission-enforcement roadmap";
- the Phase 1 "Log acquisition" / agent `hostVarLog: true` hostPath plan;
- the "PSA coordination — detail" conclusion that `crowdsec` must be `enforce: privileged`;
- the "HostPath-free acquisition" ranked alternatives list (options 2-5 are DROPPED).

### Decision 1 — `crowdsec` ns is `enforce: restricted` from day one

The `crowdsec` namespace gets the strict PSA label **self-applied by this roadmap in Phase 0**
(not deferred to the `pod-security-admission-enforcement` roadmap):
```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.36
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: v1.36
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: v1.36
```
Every pod in `crowdsec` must satisfy PSS `restricted`: `runAsNonRoot: true`,
`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]` (no `add` except
`NET_BIND_SERVICE`, and none is needed — LAPI 8080, AppSec 7422, bouncer gRPC 8080,
Web UI 3000 are all unprivileged ports), `seccompProfile: RuntimeDefault`, and NO
`hostPath`/`hostNetwork`/`hostPID`/`hostIPC`. `readOnlyRootFilesystem` is NOT required by
`restricted` (SQLite PVCs on local-hostpath are fine).

**Implementation blocker to verify BEFORE applying the label:** the crowdsec OCI chart
0.24.0 (LAPI/agent/AppSec) and the kdwils bouncer chart 0.7.0 must support these
securityContexts. The crowdsec image has historically run as root — confirm the chart
exposes `securityContext` overrides AND the image runs non-root (or supports a non-root
UID). The Web UI (bjw-s app-template) is already restricted-clean per the plan. If any
chart forces root / privilege escalation, that is a **hard blocker** — resolve it (chart
values, or a different image) before creating the namespace with the label, otherwise the
pods are rejected at admission. Run `kubectl label --dry-run=server ns crowdsec
pod-security.kubernetes.io/enforce=restricted` after a staged apply to preview rejections.

### Decision 2 — acquisition via the crowdSec `victorialogs` datasource (no hostPath)

The agent does NOT use `hostVarLog`, does NOT mount hostPath `/var/log`, does NOT read
envoy proxy pod log files. Instead it uses CrowdSec's native **`victorialogs`** DataSource
(Context7-verified, doc.crowdsec.net) to query envoy access logs from the existing
`victoria-logs-server.observability.svc:9428`, where the `victoria-logs-collector` DaemonSet
already ships all pod stdout logs (including the envoy proxy pods' JSON access logs —
live-verified 2026-07-27). Configure the acquisition in the crowdsec chart's
`config.yaml.local` override (a `victorialogs` source pointing at
`victoria-logs-server.observability.svc:9428`, label `type: envoy`, collection
`yanis-kouidri/envoy`).

**CNP change:** add `crowdsec` agent egress to `victoria-logs-server.observability.svc:9428`
(TCP) — copy the egress-label idiom used for the observability plane. The hostPath `/var/log`
mount + its node RBAC concern are removed entirely. The agent's only egress is now: LAPI
(in-ns), `victoria-logs-server:9428` (observability), MaxMind GeoLite2, CAPI (if enrolled).

**Gate verification (FIRST implementation step, before anything else):** confirm the
victoria-logs-collector stores the envoy access log such that the `yanis-kouidri/envoy`
parser can parse it — i.e. the raw envoy JSON line is preserved as the log body in
VictoriaLogs (not collapsed into unrelated structured fields). If the collector parses the
envoy JSON into VL structured fields, either (a) adjust the collector config to preserve
the raw line for envoy pods, or (b) write a small crowdsec parser for the VL field shape.
Do not proceed to bouncer wiring until this gate passes — it is the load-bearing
assumption of the whole acquisition change.

### Dropped alternatives (NOT in the plan)

Closed 2026-07-27 — option 1 (`victorialogs`) chosen; the rest are dropped:
- `hostVarLog` hostPath agent reading envoy pod stdout from `/var/log/pods/...` (the
  original Phase 1 plan) — DROPPED.
- `http` source + a second collector sink POSTing to the crowdsec agent — DROPPED.
- `syslog` source + collector syslog sink — DROPPED.
- EnvoyProxy `OpenTelemetry` / `ALS` access-log sink + an OTel collector / custom ALS
  receiver — DROPPED.

### Updated implications

- **PSA coordination:** the `crowdsec` row in the `pod-security-admission-enforcement`
  roadmap's per-namespace table is now "`restricted`, self-applied by the crowdsec roadmap
  in Phase 0" — the PSA roadmap must NOT re-label `crowdsec` (no drift). The repo-wide
  side-finding (observability ns already blocked from `baseline` by its hostPath
  DaemonSets) stands and is a PSA-roadmap correction, independent of this decision.
- **Security review:** the hostPath trust-boundary concern is gone — the agent no longer
  touches node `/var/log`. The `restricted` label is itself an admission guarantee that no
  future crowdsec pod can regress to privileged/hostPath.
- **Scope/effort:** roughly unchanged — +1 CNP egress rule (crowdsec -> victoria-logs-server),
  -1 hostPath mount + its RBAC, +1 namespace label, +1 gate verification (envoy log format
  match).

### Updated verification steps (supersede the hostVarLog ones)

- [ ] `crowdsec` ns labeled `enforce: restricted` (+warn/audit, *-version: v1.36);
  every crowdsec pod (LAPI, agent, AppSec, bouncer, Web UI) admits and stays Running — no
  PodSecurity admission denials (confirms all charts are restricted-clean).
- [ ] **Gate:** envoy log field format match verified — a test request to a protected route
  produces an envoy access-log line in VictoriaLogs that the `yanis-kouidri/envoy` parser
  ingests (`cscli metrics` shows non-zero parsed envoy lines). This MUST pass before bouncer
  wiring.
- [ ] `victorialogs` source egress: crowdsec agent can reach `victoria-logs-server:9428`
  (CNP egress rule); a pod outside the allowed set cannot.

## Gate verification — 2026-07-27 (live)

Both gates run live against the cluster (victoria-logs-server port-forward + LogsQL), the chart sources (helm pull), and the image registries (docker.io / ghcr.io config blobs). Results below supersede the optimistic assumptions in the locked decision.

### Gate 1 — envoy log format vs yanis-kouidri/envoy parser: CONDITIONAL FAIL (rework needed)

Evidence (live LogsQL, query kubernetes.pod_name:envoy-external* and envoy-internal*):
- envoy-external / envoy-internal proxy access logs ARE collected into VL (container envoy, ns networking).
- The victoria-logs-collector (vlagent v1.52.0) runs with --kubernetesCollector.msgField=message,msg,log . Envoy JSON access logs have NO message/msg/log field, so _msg is set to the literal placeholder "missing _msg field; see https://docs.victoriametrics.com/victorialogs/keyconcepts/#message-field".
- The envoy access-log fields are decomposed into structured VL top-level fields: method, path, response_code, downstream_remote_address, x_forwarded_for, start_time, authority, bytes_received, bytes_sent, duration_ms, protocol, request_id, route_name, upstream_cluster, upstream_host, user_agent, response_code_details, response_flags.
- CrowdSec victorialogs datasource (Context7-confirmed: source: victorialogs, mode: tail, query: <LogsQL>) tails VL and feeds log lines to parsers; the type label directs to the parser. CrowdSec parsers grok a log-line string (Str), not flat VL fields.

Verdict: the raw envoy JSON access-log line is NOT preserved as _msg; the victorialogs + yanis-kouidri/envoy parser plan does NOT work as-is IF the datasource feeds only _msg (placeholder) to the parser -> acquisition would produce nothing. The structured fields are present in VL but unusable by a line-grok parser.

Definitive verification requires a running crowdsec + cscli explain --log <VL-returned envoy line> --type envoy -v — not possible pre-deployment.

Mitigation paths (pick before implementation):
1. Adjust the envoy access log so a usable line reaches _msg — e.g. add a second access-log sink in the EnvoyProxy telemetry config that emits a raw text line the collector keeps verbatim, or add a message-style field to the JSON body. Touches shared envoy-gateway config (external + internal) — needs its own change evaluation.
2. Reconfigure the collector to not decompose envoy JSON (keep the raw line as _msg) — needs a vlagent flag investigation; risks the shared observability pipeline (AD-023).
3. Verify the victorialogs datasource actually returns the full VL record as a JSON line (not just _msg) — if so, the yanis-kouidri/envoy parser may grok the reconstructed envoy fields. Needs datasource source/docs dive or the post-deploy cscli explain.

### Gate 2 — chart securityContext / non-root: SPLIT verdict

Bouncer (oci://ghcr.io/kdwils/charts/envoy-proxy-bouncer, image ghcr.io/kdwils/envoy-proxy-bouncer):
- Chart version 0.7.0 (locked decision) DOES NOT EXIST in the registry; latest is 0.6.0 (appVersion v0.6.0). Correction required.
- Image USER=1000 (non-root).
- Chart container securityContext defaults: runAsNonRoot:true, runAsUser:1000, allowPrivilegeEscalation:false, capabilities.drop:[all], readOnlyRootFilesystem:true. No hostPath/hostNetwork.
- Only seccompProfile:RuntimeDefault missing — add via podSecurityContext (chart allows toYaml).
- VERDICT: restricted-READY with one seccompProfile line. PASS.

Crowdsec (oci://ghcr.io/crowdsecurity/helm-charts/crowdsec 0.24.0, image crowdsecurity/crowdsec:v1.7.8):
- Image USER empty (root). Entrypoint [/bin/bash, /docker_start.sh], WorkingDir /.
- LAPI entrypoint (docker-start-custom.sh) does chown -f ":$GID" <db_path> — explicitly assumes root (chown needs CAP_CHOWN). The GID env (default 1000) is a group-based DB-access mechanism for sidecar/non-root-group patterns, NOT full non-root support.
- Chart container securityContext defaults: only allowPrivilegeEscalation:false, privileged:false — missing runAsNonRoot, runAsUser, capabilities.drop:[ALL], seccompProfile. All configurable via values.
- agent DaemonSet/Deployment mounts /var/log hostPath (agent.hostVarLog:true default) + /var/lib/docker/containers if container_runtime:docker. With victorialogs acquisition: set agent.hostVarLog:false + non-docker runtime -> hostPath removed. LAPI + AppSec deployments are hostPath-free.
- VERDICT: restricted-PSA NOT feasible out-of-the-box. restricted requires runAsNonRoot:true; the image runs as root, so the kubelet rejects the pod unless runAsUser:<nonzero> is set AND the crowdsec process functions as that UID. The entrypoint chown calls are guarded (fail gracefully) and writable paths are mounted volumes (emptyDir/PVC), so a non-root run with runAsUser:1000 + fsGroup:1000 is PLAUSIBLE but UNVERIFIED and not officially supported (docs always show a root container). Real crash-loop risk if any image-owned root path needs writing.

### Impact on the locked decision — two revisions required

1. restricted PSA on the crowdsec ns from day 1 is AT RISK. Revise to: start the crowdsec ns at baseline (hostPath already avoided via victorialogs), deploy crowdsec with runAsUser:1000, runAsNonRoot:true, fsGroup:1000, capabilities.drop:[ALL], seccompProfile:RuntimeDefault + agent.hostVarLog:false, confirm a non-root smoke test (LAPI ready, cscli works, no chown-permission crash-loop), THEN promote the ns to enforce: restricted. restricted is gated on the empirical non-root run, not applied blind.
2. victorialogs acquisition is NOT implementation-ready as-is. Before building the crowdsec acquisition, resolve Gate 1: either verify the datasource returns a parser-grokable envoy line (post-deploy cscli explain), or adjust the envoy access-log / collector so a raw envoy line reaches _msg. The hostPath-free benefit of victorialogs stands; the parser-ingestion path does not.
3. Chart version correction: bouncer chart is 0.6.0, not 0.7.0.

Net: the locked decision two pillars (restricted from day 1; victorialogs works for envoy) both need the revisions above before this roadmap item is implementation-ready.
