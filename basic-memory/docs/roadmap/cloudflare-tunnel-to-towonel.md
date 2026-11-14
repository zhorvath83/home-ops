---
title: cloudflare-tunnel-to-towonel
type: roadmap
permalink: home-ops/docs/roadmap/cloudflare-tunnel-to-towonel
topic: Public ingress migration — Cloudflare Tunnel (proxied) to managed towonel (TLS
  passthrough)
status: proposed
priority: medium
scope: 'Replace the cloudflared tunnel + proxied Cloudflare records as the public
  ingress path with the managed towonel edge (edge-eu.towonel.dev) running in TLS
  passthrough, so TLS terminates only on envoy-external. Cloudflare stays the DNS
  provider (zone, mail records, ExternalDNS, cert-manager DNS-01). Covers: towonel
  agent workload, envoy-external client-IP model (PROXY v2), ExternalDNS/Terraform
  DNS cutover, CAA pinning + CT monitoring, rollback path, and the later Cloudflare
  Access/WAF/tunnel decommission.'
rationale: Cloudflare currently terminates and can read every public request (documents,
  photos, IdP traffic). Passthrough keeps keys and plaintext in the cluster; Access
  is a net negative for the mobile apps; geo filtering, rate limiting, CrowdSec WAF
  and OIDC gating already run on-prem in Envoy, so Cloudflare's edge layer is largely
  redundant. Lock-in is low (one agent + DNS), so the alpha-stage managed service
  is an acceptable, reversible bet if CAA pinning and a tested rollback are in place.
options:
- Managed towonel, staged (pilot gateway, then big-bang cutover of envoy-external)
  — recommended
- Managed towonel, direct big-bang cutover of envoy-external (less YAML, larger blast
  radius on the first try)
- Self-hosted towonel hub+edge on a VPS (removes operator dependency; adds a VPS to
  run, patch and secure)
- Stay on Cloudflare Tunnel
related_areas:
- networking
- cloudflare
- iam
- external-secrets
- observability
---

# Public ingress migration — Cloudflare Tunnel to managed towonel

## Metadata (observation-form, schema validation)

- [topic] Public ingress migration — Cloudflare Tunnel (proxied) to managed towonel (TLS passthrough)
- [status] proposed
- [priority] medium
- [researched_at] 2026-11-14

## What we gain

- End-to-end TLS: the edge reads only SNI and forwards raw TLS; certificates and plaintext stay on envoy-external. Cloudflare no longer decrypts Paperless, photos, Pocket ID or any other public traffic.
- No Cloudflare Access in front of the mobile apps (service-token headers no longer needed; apps use native auth / gateway-oidc as on the LAN).
- No Cloudflare proxy limits: request body size cap (100 MB on the Free plan) and proxy read timeout disappear — relevant to Paperless/photo uploads and long streams.
- Raw TCP/UDP exposure becomes possible later (per-port, globally unique ports on the shared edge) without WARP.
- Provider-independent client IP via PROXY protocol v2 instead of an XFF hop from cloudflared.
- Smaller Cloudflare surface to maintain (tunnel, Access apps/groups/service token, WAF list, 1Password write-back null_resources).

## What we lose / accept

- No edge WAF, bot management, DDoS absorption or edge rate limiting. On-prem replacements already exist: HU-only geo authorization (SecurityPolicy/envoy-external-edge), CrowdSec extAuth + AppSec WAF, local rate limit (BTP/envoy: 3000/min per client, 30000/min shared). Volumetric DDoS is not absorbed by anyone; the shared edge will rate-limit or cut a tenant under attack.
- No public HTTP/3 (edge listens TCP 443 only).
- Port 80 behaviour on the managed edge is undocumented: http:// first visits may fail. HSTS (2y, includeSubDomains) covers returning browsers.
- Managed service is an invite-only alpha: "best-effort, no uptime guarantee", donation-funded, single maintainer, no ToS/Privacy Policy yet, single documented edge (EU). The operator still sees metadata (SNI, client IPs, byte counts).

## Research findings (towonel docs + Codeberg, read 2026-11-14)

### Architecture
- [fact] One persistent QUIC (iroh) tunnel; the edge accepts TLS on :443, peeks SNI, forwards over a QUIC stream to the agent; the agent dials origin host:port. Edge reverse-dials the agent; behind NAT the hub-advertised iroh relay is the default path ("the agent dials out"). Source: towonel.dev/docs/self-hosted/architecture/, /docs/agent/kubernetes/
- [fact] Tenant config entries are ML-DSA-65 signed ("the hub operator cannot forge entries"); agent auth is an invite token (tt_inv_2_…) → hub-signed short-lived EdgeCreds.
- [fact] Passthrough is the default and, per /docs/agent/tls-modes/, "The only mode"; the README still documents a terminate mode (edge issues on-demand LE certs via TLS-ALPN-01). Docs/README inconsistent.
- [fact] In passthrough the agent prepends PROXY v2 by default (per-service "proxy_protocol": "v2"|"none"); "The origin must accept it or the connection will fail."
- [fact] Managed DNS model: CNAME each hostname (wildcard allowed in the example) to edge-eu.towonel.dev. No ownership verification (TXT/challenge) is documented; hostname conflict rules across tenants are undocumented.
- [fact] Self-hosted edge defaults: MAX_CONNECTIONS_PER_TENANT=1000, MAX_INFLIGHT_CONNECTIONS=50000, drain 25s; managed values unpublished.

### Agent chart (codeberg.org/towonel/towonel charts/towonel-agent, bjw-s common 5.1.0, k8s >=1.31)
- [fact] Values: agent.services / tcpServices / udpServices (JSON lists), agent.inviteTokenSecret.{name,key=TOWONEL_INVITE_TOKEN}, relayUrl, directConnect (NodePort, off by default), controllers.main.replicas (default 2), probes on /healthz :9090, serviceMonitor.main.enabled (default false), monitoring.prometheusRule/dashboards (default false), hardened securityContext (non-root 10001, RO rootfs, drop ALL), requests 50m/128Mi, limit 256Mi. No networkPolicy key (common passthrough only).
- [fact] OCI location conflict: README says oci://codeberg.org/towonel/charts/towonel-agent; docs say oci://git.ow-ops.eu/... — git.ow-ops.eu served an Anubis bot-challenge page to automated fetches (Flux pulls may hit the same gate).
- [conflict] Chart default replicas: 2 vs /docs/agent/tcp-udp/ "run at most one agent per tenant" and README "stale agent IDs for the tenant are revoked" on reconcile.

### Project maturity
- [fact] MIT, Rust, 50 releases from v0.1.0 (2026-05-25) to v1.6.1 (2026-09-10); no release in the 65 days since; HEAD 2026-09-16. Release commits ship with CI e2e (and on 1.6.1 test) failing. No SECURITY.md, SBOM or audit; artifacts/images/charts cosign-signed. No hub/edge/agent version-compatibility statement; README "wire format may change" wording is stale (still says 0.0.x).
- [fact] Open: 2 issues (#89 PROXY on tcpServices, Renovate dashboard), 4 PRs (major dep bumps with failing CI: sea-orm 2.0, totp-rs 6.0).

### CAA
- [fact] /docs/agent/caa-pinning/ recommends: `CAA 0 issue "letsencrypt.org;validationmethods=<method>;accounturi=<your-account-uri>"`, CT logs as backstop (certspotter, merklemap), and warns Cloudflare can "silently rewrite or drop CAA records" — verify with `dig @1.1.1.1 +short <host> CAA`.
- [fact] 2026-11-14: edge-eu.towonel.dev and towonel.dev publish no CAA, so CAA for a CNAME'd tenant host falls back to the apex of PUBLIC_DOMAIN (RFC 8659 tree-climb from the original name). If towonel later publishes CAA on the edge name, it takes precedence — CT monitoring catches that.

## Current state (repo, 2026-11-14)

- [state] cloudflared: kubernetes/apps/networking/cloudflare-tunnel/app/helmrelease.yaml — app-template, 1 replica, ingress `*.${PUBLIC_DOMAIN}` → https://envoy-external.networking.svc.cluster.local (originServerName external.${PUBLIC_DOMAIN}); CNP egress to CiliumCIDRGroup cloudflare.
- [state] envoy-external: ClusterIP; CNP ingress on 10080/10443 only from the cloudflare-tunnel pod (envoy-gateway/config/ciliumnetworkpolicy-external.yaml).
- [state] ClientTrafficPolicy/envoy-external: `clientIPDetection.xForwardedFor.numTrustedHops: 1` (gateway-policies.yaml:99-101), chosen because geo authorization rejects trustedCIDRs (envoyproxy/gateway#9935). HTTP/3 off.
- [state] SecurityPolicy/envoy-external-edge: defaultAction Deny, allow clientIPGeoLocations HU, extAuth → crowdsec-bouncer (fail closed). SecurityPolicy/github-webhook (flux-system) overrides geo with GitHub hook clientCIDRs.
- [state] BTP/envoy local rate limit is ENABLED (3000/min per client v4+v6, 30000/min shared).
- [state] ExternalDNS: provider cloudflare, `--cloudflare-proxied`, `--gateway-name=envoy-external`, records target external.${PUBLIC_DOMAIN} (Gateway annotation).
- [state] Terraform: tunnel.tf CNAME external → <tunnel-id>.cfargotunnel.com proxied; access.tf (Access apps, groups, service token, Google IdP); firewall_rules.tf (GitHub list + non-HU country block); zone_settings.tf. No CAA records. Apex A/AAAA point at the external website host (unproxied).
- [state] cert-manager ClusterIssuer uses ACME DNS-01 via Cloudflare (kubernetes/apps/cert-manager/cert-manager/issuers/clusterissuer.yaml:15-16).
- [state] Envoy Gateway chart 1.10.0. 29 manifests reference envoy-external. echo-server routes on envoy-external behind gateway-oidc (pilot candidate).

## CRITICAL design point — client IP trust after the switch

With passthrough, nothing in front of envoy-external appends X-Forwarded-For. Keeping `numTrustedHops: 1` would make Envoy trust the rightmost **client-supplied** XFF entry, which defeats the HU geo rule, per-client rate limiting, CrowdSec decisions and the GitHub-webhook clientCIDRs allowlist. The envoy-external ClientTrafficPolicy MUST change atomically with the traffic switch to: `proxyProtocol` (required, not optional — every connection arrives from the agent) + `numTrustedHops: 0` (same model as envoy-internal). The two client-IP models (cloudflared XFF vs towonel PROXY v2) cannot coexist on one Gateway safely — this is why the pilot uses a separate Gateway.

## Plan

### Phase 0 — Clarify with the operator (blocking)
Ask on console/Discord and record answers here:
1. Hostname ownership: how does the managed hub prevent another tenant from claiming `*.${PUBLIC_DOMAIN}`? Precedence of exact vs wildcard entries across tenants?
2. Wildcard SNI routing supported on managed (one service `*.${PUBLIC_DOMAIN}`)?
3. Replicas: is 2 agent replicas per tenant supported, or "one agent per tenant"?
4. Egress endpoints for a NetworkPolicy: hub hostname/port, relay URL/ports, edge iroh UDP port, IPv6 need.
5. Managed limits: per-tenant connections, bandwidth, idle TCP timeout (WebSocket/SSE), port 80 handling.
6. Agent ↔ managed hub version policy; canonical chart/image registry (codeberg.org vs git.ow-ops.eu).
7. Is terminate mode ever enabled on the managed edge (must stay off for our hostnames)?
Exit: answers recorded; no answer that breaks the design (esp. #1, #2).

### Phase 1 — CAA pinning + CT monitoring (prerequisite, independent of towonel)
1. Read the cert-manager ACME account URI: `kubectl get clusterissuer <name> -o jsonpath='{.status.acme.uri}'`.
2. Identify how the apex/www certificate at the external web host is issued (CA + method) via `openssl s_client` on the apex; it needs its own `issue` line or the apex renewal breaks.
3. Terraform (provision/cloudflare/dns_records.tf): apex CAA records — `issue` + `issuewild` "letsencrypt.org;validationmethods=dns-01;accounturi=<uri>", the apex host's issuer line, optional `iodef`.
4. Verify: `dig @1.1.1.1 +short CAA ${PUBLIC_DOMAIN}` and on a subdomain; force a cert-manager renewal (staging or a test Certificate) to prove the pin does not block our own issuance.
5. CT monitoring for ${PUBLIC_DOMAIN} (hosted certspotter/merklemap notification, or an in-cluster job → Pushover). Decide where.
Exit: CAA visible publicly, own renewal proven, CT alert path tested.

### Phase 2 — Agent workload (no traffic yet)
1. 1Password item `towonel` (vault HomeOps) with field TOWONEL_INVITE_TOKEN; ExternalSecret → Secret `towonel-agent-secret`.
2. New app kubernetes/apps/networking/towonel-agent/ (ks.yaml dependsOn onepassword-connect, OCIRepository for the chart pinned by version+digest, HelmRelease): replicas 1 (until Phase 0 #3), relay path (directConnect off), agent.services empty or echo-only, serviceMonitor on, reloader annotation, resources sized from cloudflared's footprint.
3. CNP for the agent: ingress Prometheus → 9090; egress kube-dns, the pilot/external envoy pods on 10443, and internet egress to the towonel endpoints from Phase 0 #4 (start with toFQDNs where possible; tighten after a Hubble capture — `just k8s hubble-live-capture 120` then `just k8s hubble-analyze k8s:app.kubernetes.io/name=towonel-agent DROPPED egress`).
4. Renovate: track chart + image (OCI datasource), no automerge; note in .renovate/ if a rule is needed.
Exit: agent Ready, connected (logs/metrics), zero Hubble drops.

### Phase 3 — Pilot on a dedicated Gateway
1. New GatewayClass/EnvoyProxy/Gateway `envoy-towonel` (ClusterIP, HTTPS listener `*.${PUBLIC_DOMAIN}`, same wildcard cert) with its own ClientTrafficPolicy (proxyProtocol required, numTrustedHops 0, same header hardening/timeouts as external), SecurityPolicy copy of envoy-external-edge (HU geo + CrowdSec extAuth), CNP ingress only from the towonel-agent pod. BTP/envoy already applies to every Gateway (targetSelectors without labels) — verify.
2. Confirm geo authorization works with the PROXY-derived address and numTrustedHops 0 (envoyproxy/gateway#9935 concerns trustedCIDRs only; prove it).
3. Agent service: hostname echo.${PUBLIC_DOMAIN} (or a dedicated pilot host) → envoy-towonel:443, proxy_protocol v2. Attach the echo-server HTTPRoute to envoy-towonel only.
4. DNS for the pilot host: unproxied CNAME → edge-eu.towonel.dev (ExternalDNS annotations `external-dns.alpha.kubernetes.io/cloudflare-proxied: "false"` + target, or a Terraform record; note the external-dns --gateway-name filter).
5. Tests (from mobile data, i.e. off-LAN, and from a non-HU vantage):
   - TLS chain = our cert; `curl -v` shows Envoy, not an edge cert.
   - echo-server shows the real client IP; a forged `X-Forwarded-For` header does NOT change the detected IP.
   - Non-HU source → 403; CrowdSec ban on the test IP → blocked; rate limit triggers.
   - gateway-oidc login round-trip through Pocket ID; WebSocket and a >100 MB upload through a test route; long idle connection (>5 min).
   - Latency/throughput comparison vs the Cloudflare path (simple curl timing, speedtest to a file route).
6. Soak ≥ 1–2 weeks; watch agent reconnects, edge outages, error rates.
Exit: all tests green, soak without unexplained outage.

### Phase 4 — Cutover of envoy-external (maintenance window, single PR)
1. Lower TTLs beforehand (records are proxied/auto now; unproxied target records at 60s).
2. One PR switching:
   - ClientTrafficPolicy/envoy-external → proxyProtocol required + numTrustedHops 0 (and comment update).
   - CNP/envoy-external ingress source → towonel-agent pod.
   - Agent service `*.${PUBLIC_DOMAIN}` → envoy-external:443 (pilot gateway removed or kept until Phase 5).
   - ExternalDNS: drop `--cloudflare-proxied` (records become unproxied CNAMEs to external.${PUBLIC_DOMAIN}).
   - cloudflared HelmRelease scaled to 0 (or Kustomization suspended), NOT deleted.
3. Terraform (same window): external CNAME → edge-eu.towonel.dev, proxied=false, ttl 60.
4. Post-checks: every public host (list from HTTPRoutes on envoy-external) returns via towonel; flux-webhook delivery from GitHub (redeliver a webhook) passes clientCIDRs; Pocket ID passkey login; Paperless + Mealie mobile apps with native auth; CrowdSec sees real IPs; blackbox/external uptime green.
Rollback (target < 15 min): git revert the PR (restores CTP numTrustedHops 1, CNP, proxied flag, cloudflared replicas) + Terraform revert of the external CNAME. Access apps still exist until Phase 5, so the CF path comes back with its old protections.

### Phase 5 — Decommission (after ≥ 4 weeks stable)
- Delete cloudflare-tunnel app + CiliumCIDRGroup, 1Password tunnel fields.
- Terraform: remove tunnel.tf, access.tf (apps, groups, service token, Google IdP), firewall_rules.tf (rules only act on proxied traffic), zone settings that only apply to proxied traffic; drop delete_stale_tunnels.sh; consider disabling Universal SSL if nothing stays proxied (re-check CAA afterwards).
- Remove the pilot Gateway (if kept).
- Update BM areas networking, cloudflare, iam; repo CLAUDE.md files and skills (networking-platform, cloudflare-terraform) that reference cloudflared.

## Observability & ops (to build in Phase 2–4)
- ServiceMonitor for the agent; discover metric names (undocumented) and add a PrometheusRule (agent down / not connected), routed to Pushover.
- External synthetic check from outside the LAN (in-cluster blackbox-exporter resolves via split-horizon to envoy-internal, so it cannot see the public path) — decide: hosted uptime service vs a probe through a public resolver.
- Runbook entry: "towonel edge down" → decide wait vs rollback to Cloudflare (Phase 4 rollback steps).

## Risks & mitigations
- Edge-issued cert for our hostnames (terminate mode / rogue ACME) → CAA accounturi+dns-01 at apex, CT monitoring.
- Another tenant claiming our hostnames on the shared edge → without CAA bypass they can only cause TLS errors (DoS), not interception; Phase 0 #1 answer required.
- Client IP spoofing via XFF → PROXY required + numTrustedHops 0, tested with forged header.
- Managed outage / service shutdown / invite revoked → kept CF path + documented rollback; self-host fallback option (VPS: TCP 443, TCP 8443, UDP 51820, IPv6).
- Version skew agent ↔ managed hub → manual, release-note-read upgrades; pin by digest.
- Registry gate (Anubis on git.ow-ops.eu) → pull from codeberg.org OCI; verify Flux can pull.
- Volumetric DDoS → accepted risk for a homelab; rollback to CF proxy is the emergency lever.

## Acceptance criteria
1. All public hostnames served via towonel with our certificate (verified per host).
2. Forged X-Forwarded-For does not change the client IP seen by geo, CrowdSec and rate limiting.
3. Non-HU request → 403; GitHub webhook redelivery → 200.
4. CAA pinned and verified; own cert renewal succeeds; CT alert tested.
5. Agent alerting + external uptime check in place.
6. Rollback rehearsed once (pilot or cutover window) within 15 minutes.

## Effort
L — Phase 0 depends on operator response; Phases 1–3 ~1–2 days of work + soak; Phase 4 ~2h window; Phase 5 ~half day.

## Related

- relates_to [[networking]]
- relates_to [[cloudflare]]
- relates_to [[iam]]
- relates_to [[cloudflare-api-token-migration]]
- relates_to [[onprem-geoip-country-filter]]
