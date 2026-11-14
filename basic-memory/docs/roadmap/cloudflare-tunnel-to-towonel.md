---
title: cloudflare-tunnel-to-towonel
type: roadmap
permalink: home-ops/docs/roadmap/cloudflare-tunnel-to-towonel
topic: Public ingress migration — Cloudflare Tunnel (proxied) to managed towonel (TLS
  passthrough)
status: proposed
priority: medium
scope: 'Replace the cloudflared tunnel + proxied Cloudflare records as the public
  ingress path with the managed towonel edge (edge-eu.towonel.dev) in TLS passthrough,
  so TLS terminates only on envoy-external. Cloudflare stays the DNS provider (zone,
  mail records, ExternalDNS, cert-manager DNS-01). Covers: towonel agent workload,
  envoy-external client-IP model (PROXY v2), pilot gateway, DNS cutover, CAA pinning
  + CT monitoring, monitoring, rollback, and the Cloudflare tunnel/Access/WAF decommission.'
rationale: Cloudflare currently terminates and can read every public request (documents,
  photos, IdP traffic). Passthrough keeps keys and plaintext in the cluster; Access
  is a net negative for the mobile apps; geo filtering (sole country gate since 2026-11-15),
  rate limiting, CrowdSec WAF and OIDC gating already run on-prem in Envoy, so the
  Cloudflare edge layer is largely redundant. Lock-in is low (one agent + DNS), so
  the alpha-stage managed service is an acceptable, reversible bet if CT monitoring,
  CAA pinning and a tested rollback are in place.
options:
- Managed towonel, direct one-PR cutover of envoy-external after a no-risk smoke test
  — CHOSEN (D1, 2026-11-15)
- Managed towonel, staged via a separate pilot gateway (rejected: extra gateway and
    policy copies for a short pilot)
- Self-hosted towonel hub+edge on a VPS (removes the operator dependency; adds a VPS
  to run, patch and secure)
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
- [reviewed_at] 2026-11-15

## What we gain

- End-to-end TLS: the edge reads only SNI and forwards raw TLS; certificates and plaintext stay on envoy-external. Cloudflare no longer decrypts Paperless, photos, Pocket ID or any other public traffic.
- No Cloudflare Access in front of the mobile apps (service-token headers become a no-op; apps use native auth / gateway-oidc exactly as on the LAN).
- No Cloudflare proxy limits (Free plan request-body cap of 100 MB, proxy read timeout) — relevant to Paperless/photo uploads and long streams.
- Raw TCP/UDP exposure becomes possible later (per-port, globally unique ports on the shared edge) without WARP.
- Provider-independent client IP via PROXY protocol v2 instead of an XFF hop from cloudflared.
- Smaller Cloudflare surface (tunnel, Access apps/groups/service token, the GitHub WAF list, 1Password write-back null_resources, the update-cloudflare-networks workflow).

## What we lose / accept

- No edge WAF, bot management, DDoS absorption or edge rate limiting. On-prem replacements already exist: HU-only geo authorization (SecurityPolicy/envoy-external-edge — the only country gate since the Cloudflare rule was removed 2026-11-15), CrowdSec extAuth + AppSec WAF, local rate limit (BTP/envoy: 3000/min per client v4+v6, 30000/min shared). Volumetric DDoS is not absorbed by anyone; the shared edge will rate-limit or cut a tenant under attack.
- No public HTTP/3 (the edge listens on TCP 443 only).
- Port 80 on the managed edge is undocumented: http:// first visits may fail. HSTS (2y, includeSubDomains) covers returning browsers.
- Managed service is an invite-only alpha: "best-effort, no uptime guarantee", donation-funded, single maintainer, no ToS/Privacy Policy yet, one documented edge (EU). The operator sees metadata (SNI, client IPs, byte counts).
- Per-agent concurrency ceiling: 256 active streams (one stream per client TCP connection) — see Research.

## Research findings

### Architecture (towonel.dev docs, read 2026-11-14)
- [fact] One persistent QUIC (iroh) tunnel; the edge accepts TLS on :443, peeks SNI, forwards over a QUIC stream to the agent; the agent dials origin host:port. The edge reverse-dials the agent; behind NAT the hub-advertised iroh relay is the default path ("the agent dials out"). Source: /docs/self-hosted/architecture/, /docs/agent/kubernetes/
- [fact] Tenant config entries are ML-DSA-65 signed ("the hub operator cannot forge entries"); agent auth is an invite token (tt_inv_2_…) → hub-signed short-lived EdgeCreds.
- [fact] Passthrough is the default and, per /docs/agent/tls-modes/, "The only mode"; the README still documents a terminate mode (edge issues on-demand LE certs via TLS-ALPN-01). Docs/README inconsistent.
- [fact] In passthrough the agent prepends PROXY v2 by default (per-service "proxy_protocol": "v2"|"none"); "The origin must accept it or the connection will fail."
- [fact] Managed DNS model: CNAME each hostname (wildcard allowed in the example) to edge-eu.towonel.dev. No hostname-ownership verification is documented; cross-tenant hostname conflict rules are undocumented.
- [fact] Self-hosted edge defaults: MAX_CONNECTIONS_PER_TENANT=1000, MAX_INFLIGHT_CONNECTIONS=50000, drain 25s; managed values unpublished.

### Agent chart — towonel-agent 1.13.7 (pulled from oci://codeberg.org/towonel/charts/towonel-agent, 2026-11-15)
- [fact] bjw-s common 5.1.0, kubeVersion >=1.31. Values: agent.services / tcpServices / udpServices, agent.inviteTokenSecret.{name,key=TOWONEL_INVITE_TOKEN}, relayUrl, extraLocalAddrs, disableUdpGso, hostNetwork, directConnect (NodePort, off), mesh (off; switches to StatefulSet), controllers.main.replicas 2 (RollingUpdate), probes /healthz on :9090, requests 50m/128Mi, limit 256Mi, hardened securityContext (uid 10001, RO rootfs, drop ALL), serviceMonitor.main.enabled false, monitoring.prometheusRule / dashboards (grafanaOperator option) false.
- [fact] Default image is git.ow-ops.eu/towonel/towonel-agent pinned by digest sha256:da4b62651a7804d3116a2d5ee9a0a1414e8e3eb6a84de90db602f1679f81b654; codeberg.org/towonel/towonel-agent:1.13.7 serves the SAME index digest; both registries allow anonymous pulls (verified 2026-11-15).
- [fact] Shipped alerts: TowonelAgentEdgeLinkDown (towonel_agent_edge_session_state == 0 for 5m, critical), TowonelAgentStreamsNearCap (towonel_agent_streams_active > 200 for 15m — "near the 256 cap — the stream-driven path that OOMKilled it before"), TowonelAgentReconnectStorm, TowonelAgentStalled (a replica gets no streams while others do).
- [fact] Metrics: towonel_agent_{info, edge_path, edge_session_state, edge_session_reconnects_total, streams_active, streams_accepted_total, streams_completed_total, stream_errors_total, bytes_total}. edge_path shows relay vs direct.
- [resolved] Multi-replica: the 1.13.7 chart is built for 2 replicas (TowonelAgentStalled compares replicas). The "run at most one agent per tenant" sentence on /docs/agent/tcp-udp/ is about separate agent deployments with different env (the env reconciles the hub). Still confirm in Phase 0.

### Project maturity (corrected 2026-11-15)
- [correction] The Codeberg repo is a stale mirror for code/releases: HEAD 2026-09-16, last release object v1.6.1 (2026-09-10). Development continues elsewhere (docs point at git.ow-ops.eu, blocked to automated fetches by Anubis): the registries carry chart/image 1.7.1 … 1.13.7, and the 1.13.7 image was built 2026-11-13. The "65 days without a release" reading of 2026-11-14 was wrong.
- [fact] MIT, Rust, single visible maintainer, release commits up to 1.6.1 shipped with CI e2e failing; CI status of 1.7+ is not visible. No SECURITY.md/SBOM/audit; images, binaries and charts cosign-signed. No published hub/edge/agent version-compatibility policy.

### CAA and Cloudflare (verified 2026-11-15)
- [fact] towonel /docs/agent/caa-pinning/: `CAA 0 issue "letsencrypt.org;validationmethods=<method>;accounturi=<account-uri>"`, CT logs as backstop.
- [fact] **Cloudflare: "Cloudflare adds CAA records automatically when you have Universal SSL and add any CAA records to your zone"** — issue + issuewild for pki.goog, letsencrypt.org, ssl.com, sectigo.com, without accounturi/validationmethods, and they "will not appear in the Cloudflare dashboard" (developers.cloudflare.com/ssl/edge-certificates/caa-records/). A plain `letsencrypt.org` issue record authorises ANY Let's Encrypt account, so **our accounturi pin is void while Universal SSL is on.** The page also states "CAA records on a CNAME target also apply" and parent CAA is inherited.
- [fact] 2026-11-14: edge-eu.towonel.dev and towonel.dev publish no CAA, so a tenant host CNAMEd to the edge falls back to the PUBLIC_DOMAIN apex CAA.

### Envoy Gateway client-IP chain (EG 1.10.0 live CRDs + gateway main geoip.go, 2026-11-15)
- [fact] ClientTrafficPolicy.proxyProtocol: "the Proxy Protocol header will be interpreted and the Client Address will be added into the X-Forwarded-For header"; `optional: true` admits connections without a header. `enableProxyProtocol` is the legacy boolean.
- [fact] EG geoip.go: when clientIPDetection.xForwardedFor.numTrustedHops is set, the geoip filter gets xff_config with that hop count; with DirectSourceIP or nothing set, Envoy uses the downstream connection source address. clientIPGeoLocations: client IP is "inferred from the X-Forwarded-For header, a custom header, or the direct downstream connection source address".
- [inference] PROXY + numTrustedHops 0 → Envoy appends the PROXY client address as the rightmost XFF entry and geo/RBAC/rate-limit read it; a client-sent XFF stays to the left and is ignored. Must be proven live (post-cutover test P3; abort criterion).
- [fact] envoyproxy/gateway#9935 (geo + trustedCIDRs) still open — numTrustedHops remains the only geo-compatible XFF mode.

## Current state (repo + cluster, 2026-11-15)

- [state] cloudflared: kubernetes/apps/networking/cloudflare-tunnel/app/helmrelease.yaml — app-template, 1 replica, ingress `*.${PUBLIC_DOMAIN}` → https://envoy-external.networking.svc.cluster.local (originServerName external.${PUBLIC_DOMAIN}); CNP egress to CiliumCIDRGroup cloudflare (kept current by .github/workflows/update-cloudflare-networks.yaml).
- [state] envoy-external: EnvoyProxy ClusterIP Service (envoy.yaml:65-66); CNP ingress on 10080/10443 only from the cloudflare-tunnel pod (ciliumnetworkpolicy-external.yaml). Nothing else in the repo targets envoy-external.networking.svc directly.
- [state] ClientTrafficPolicy/envoy-external: `xForwardedFor.numTrustedHops: 1`, no HTTP/3 (gateway-policies.yaml:86-101; live: 1 / none). envoy-internal: numTrustedHops 0 + http3 (live).
- [state] SecurityPolicy/envoy-external-edge: Deny by default, allow clientIPGeoLocations HU, extAuth crowdsec-bouncer (failOpen false) — the only country gate. Route-level SecurityPolicy flux-system/github-webhook replaces geo with GitHub hooks clientCIDRs (mergeType StrategicMerge).
- [state] EnvoyProxy/envoy-external carries the geoIP provider (MaxMind GeoLite2-Country from PVC `geoip`) and filterOrder geoip + rbac before ext_authz.
- [state] BTP/envoy (targetSelectors kind Gateway) — live Accepted on both gateways; local rate limit enabled.
- [state] CrowdSec bouncer walks XFF with trustedProxies [${POD_CIDR}] (1093fb057).
- [state] CCNP ingress-from-gateway-external admits only pods with owning-gateway-name In [envoy-external] into backends labelled ingress.home.arpa/allow-gateway-external.
- [state] ExternalDNS: `--cloudflare-proxied`, `--gateway-name=envoy-external`, policy sync, txtPrefix k8s.; records CNAME → external.${PUBLIC_DOMAIN} (Gateway annotation).
- [state] Terraform: tunnel.tf (tunnel + external CNAME proxied), access.tf, firewall_rules.tf (since a5fb33272 only the GitHub-CIDR rule on flux-webhook; the country rule is gone), zone_settings.tf; no CAA records. Apex A/AAAA at the external web host, unproxied.
- [state] GeoGateFalsePositive parallel-run alert removed (61639a775).
- [state] cert-manager ClusterIssuer: ACME DNS-01 via Cloudflare (issuers/clusterissuer.yaml:15-16).
- [state] Public routes on envoy-external (14 consumers): flux-webhook, sure, pingvin-share-x, homepage, paperless, pocket-id (idm), mealie, home-gallery, echo-server, crowdsec-web-ui, grafana, cilium (hubble), crosswatch, calibre-web-automated.
- [state] Renovate: docker and helm datasources already automerge: false (.renovate/autoMerge.json5:9-21).

## Design decisions

- [decision] **Client IP on envoy-external after the switch: `proxyProtocol: {}` (header required) + `numTrustedHops: 0`.** Keeping numTrustedHops 1 would trust the rightmost client-supplied XFF entry and defeat geo, rate limit, CrowdSec and the GitHub clientCIDRs rule. The two models cannot share one Gateway, so the switch is atomic in the cutover PR (D1).
- [decision] Agent: chart 1.13.x from oci://codeberg.org/towonel/charts/towonel-agent; image repository overridden to codeberg.org/towonel/towonel-agent (same digest as git.ow-ops.eu, one registry for chart + image, no Anubis risk); pinned by tag + digest; Renovate updates reviewed manually against the release notes.
- [decision] Agent sizing: replicas 2 (rolling-update continuity; single node, so no node-failure benefit), memory limit 512Mi (chart 256Mi has an OOM history), requests 50m/128Mi. Relay path first (directConnect off) — D2.
- [decision] One agent service: hostname `*.${PUBLIC_DOMAIN}` → origin envoy-external.networking.svc.cluster.local:443, proxy_protocol v2. Before the cutover only a smoke-test entry exists (Phase 3). No TCP/UDP services.
- [decision] CAA is a two-step control: CT monitoring is the guard until Universal SSL is disabled; the accounturi pin becomes effective only after that (Phase 5a).

## Plan

### Phase 0 — Clarify with the operator (blocking)
Ask on console/Discord; record the answers here.
1. Hostname ownership: how does the managed hub stop another tenant from claiming `*.${PUBLIC_DOMAIN}` or a single host? Exact-vs-wildcard precedence across tenants?
2. Wildcard SNI routing on managed for one service `*.${PUBLIC_DOMAIN}`?
3. Two agent replicas per tenant OK?
4. Egress: hub hostname/port, relay URL/ports, edge iroh UDP port, IPv6 need.
5. Limits: per-tenant connections, bandwidth fair-use figure, TCP idle timeout (WebSocket/SSE), port 80 handling.
6. Version policy agent ↔ managed hub (how far may the agent lag/lead?); is Codeberg the supported registry?
7. Is terminate mode ever enabled for tenant hostnames on the managed edge?
8. Release notes / changelog location for 1.7+ (Codeberg stops at 1.6.1).
Exit: answers recorded; #1, #2, #7 acceptable. If #1 has no ownership check, proceed only with CT monitoring live (Phase 1) and accept "DoS but not interception" until Phase 5a.

### Phase 1 — CT monitoring (+ CAA groundwork)
1. CT alerting (D4): enable Cloudflare Certificate Transparency Monitoring on the zone (SSL/TLS → Edge Certificates → Certificate Transparency Monitoring → Add Email) with the Pushover e-mail gateway address. Free; the zone stays on Cloudflare DNS; Cloudflare-issued certs are filtered out, every other CA's cert for the domain/subdomains alerts (so each cert-manager renewal produces one expected alert, ~every 60 days). Record the manual dashboard step in provision/cloudflare/CLAUDE.md (no Terraform resource known — check the v5 provider). Prove the alert path on the next real issuance (the wildcard renewal). Fallback if it proves unreliable: the open-source certspotter CLI as an in-cluster CronJob → Alertmanager.
2. Gather CAA inputs, do not publish yet:
   - cert-manager ACME account URI: `kubectl get clusterissuer <name> -o jsonpath='{.status.acme.uri}'`.
   - Apex/www certificate issuer and method at the external web host (`openssl s_client -connect <apex>:443 -servername <apex>`), so its renewals keep working.
3. Prepare (branch only) the Terraform CAA resources in provision/cloudflare/dns_records.tf: apex `issue` + `issuewild` "letsencrypt.org;validationmethods=dns-01;accounturi=<uri>", the apex host's issuer line, `iodef` mailto.
Exit: CT alert path proven; CAA values known.

### Phase 2 — Agent workload (no traffic)
1. 1Password item `towonel` (vault HomeOps), field TOWONEL_INVITE_TOKEN; ExternalSecret → Secret `towonel-agent-secret` (template copies the field).
2. New app kubernetes/apps/networking/towonel-agent/: ks.yaml (dependsOn onepassword-connect; healthChecks HR), ocirepository.yaml (codeberg chart, tag 1.13.x), externalsecret.yaml, helmrelease.yaml:
   - agent.inviteTokenSecret.name towonel-agent-secret; agent.services: [] at first; logLevel info.
   - image.repository codeberg.org/towonel/towonel-agent, tag + digest pinned.
   - replicas 2; memory limit 512Mi; reloader annotation (secret.reloader.stakater.com/reload).
   - serviceMonitor.main.enabled true; monitoring.prometheusRule.enabled true (labels as other rules, severity routing to Pushover); monitoring.dashboards.grafanaOperator.enabled true (folder Networking, matchLabels of the grafana instance).
3. NetworkPolicy (AD-023 vocabulary): labels `egress.home.arpa/allow-world: "true"` (public IPv4 egress; endpoints unknown, iroh learns IPs from the hub so FQDN rules do not fit) + `ingress.home.arpa/allow-prometheus: "true"`; a dedicated CNP egress rule to envoy pods (owning-gateway-name envoy-external) on 10443. DNS via the baseline CCNP.
4. Capture and tighten: `just k8s hubble-live-capture 120`, `just k8s hubble-analyze k8s:app.kubernetes.io/name=towonel-agent DROPPED egress`; check IPv6 attempts (allow-world-egress is IPv4-only).
Exit: both pods Ready, towonel_agent_edge_session_state == 1, edge_path recorded, zero Hubble drops.

### Phase 3 — Smoke test (no change to envoy-external policies)
Proves tunnel, SNI routing, certificate and agent → envoy-external networking before the window, without weakening any control.
1. Agent service entry: hostname `tw-smoke.${PUBLIC_DOMAIN}` (no HTTPRoute) → envoy-external:443 with `proxy_protocol: none`. Terraform: `tw-smoke` CNAME → edge-eu.towonel.dev, proxied false, ttl 60.
2. Why it is safe: without PROXY and without XFF, Envoy sees the agent pod IP as the client; it has no country, so SecurityPolicy envoy-external-edge answers 403 before routing; nothing behind the gateway is reachable.
3. Checks from off-LAN: S1 `openssl s_client -connect tw-smoke.<domain>:443 -servername tw-smoke.<domain>` → our wildcard cert; S2 `curl -sI https://tw-smoke.<domain>` → 403 from Envoy (access log: rbac_access_denied, downstream_remote_address = agent pod); S3 towonel_agent_edge_session_state == 1 on both replicas, edge_path recorded. Throughput cannot be measured here (403) — it is P9 after the cutover.
4. Prepare and review before the window: the cutover PR, the revert PR, and the Terraform change + revert (plan output saved). Measure the P9 baseline through Cloudflare.
Exit: S1–S3 green; both PRs + both Terraform plans reviewed; baseline recorded.

### Phase 4 — Cutover of envoy-external (maintenance window)
Pre-flight: Phase 3 exit met; cloudflared still running; announce the window; note current DNS state (`dig` of a few hosts).
1. Single PR:
   - ClientTrafficPolicy/envoy-external → proxyProtocol {} + numTrustedHops 0 (update the comment block at gateway-policies.yaml:86-89).
   - CNP/envoy-external ingress source → towonel-agent pod.
   - Agent service → `*.${PUBLIC_DOMAIN}` → envoy-external:443 (proxy v2); remove the tw-smoke entry.
   - ExternalDNS: drop `--cloudflare-proxied` (records become unproxied CNAMEs → external.${PUBLIC_DOMAIN}).
   - cloudflare-tunnel HelmRelease replicas 0 (keep the app and secret).
2. Terraform in the same window: external CNAME → edge-eu.towonel.dev, proxied false, ttl 60; delete the tw-smoke record.
3. Expected disruption: up to ~5 min (resolver caches of the proxied answers, 300s).
4. Post-cutover tests (off-LAN = mobile data; abroad = check-host.net for IPv4, Globalping for IPv6/custom headers):
   - P1 TLS: every host in the 14-route list presents our cert (`openssl s_client -servername <host>`).
   - P2 IP: echo shows the real client IP; Envoy access log downstream_remote_address = client, direct = agent pod.
   - P3 Spoof: `curl -H 'X-Forwarded-For: 1.2.3.4'` from HU → still real IP; from abroad with a forged HU XFF → still 403.
   - P4 Geo: non-HU → 403 rbac_access_denied with geo_country logged.
   - P5 CrowdSec: `cscli decisions add --ip <own public IP> --duration 5m` → 403 ext_authz_denied; delete afterwards.
   - P6 Rate limit: burst > 3000/min from one IP → 429.
   - P7 OIDC: gateway-oidc login via Pocket ID (echo); Pocket ID passkey login.
   - P8 Protocols: WebSocket, >100 MB upload, an idle connection held > 10 min.
   - P9 Performance: TTFB/throughput vs the Phase 3 baseline; record towonel_agent_edge_path.
   - Apps: GitHub webhook redelivery → 200 (clientCIDRs); Paperless + Mealie mobile apps; home-gallery browsing.
   Abort → immediate rollback if P1, P3, P4 or P5 fails.
Rollback (target < 15 min; revert PR + Terraform revert prepared in Phase 3): 1) scale cloudflared to 1 and wait Ready; 2) revert the PR (CTP numTrustedHops 1 without proxyProtocol, CNP, proxied flag); 3) Terraform revert of the external CNAME (tunnel target, proxied). Access apps and the GitHub WAF rule are still in place until Phase 5b, so the Cloudflare path returns as before (country gating stays on-prem either way).

### Phase 5a — Close the CAA gap (4 weeks after a stable cutover — D5)
1. Confirm no record is proxied any more (`cloudflare_dns_record` resources + ExternalDNS).
2. Disable Universal SSL (Terraform if the v5 provider exposes it — verify the resource name — otherwise dashboard; record the manual step in provision/cloudflare/CLAUDE.md).
3. Publish the prepared CAA records; verify with `dig @1.1.1.1 +short CAA <apex>` and `<host>` that ONLY our pinned lines remain (no auto-added CA lines).
4. Force a cert-manager renewal (or wait for the next) and confirm success; confirm the apex host renews.
Note: after this step a rollback to the Cloudflare proxy needs Universal SSL re-enabled first (edge cert issuance can take minutes to hours) — this is why it waits for the rollback window.

### Phase 5b — Decommission
- Kubernetes: delete kubernetes/apps/networking/cloudflare-tunnel/ (+ entry in kubernetes/apps/networking/kustomization.yaml), CiliumCIDRGroup cloudflare; update the comments in ciliumnetworkpolicy-external.yaml, gateway-policies.yaml and crowdsec-bouncer/app/helmrelease.yaml that name cloudflared/CF-Connecting-IP.
- GitHub: remove .github/workflows/update-cloudflare-networks.yaml + .github/scripts/update_cloudflare_networks.py.
- Renovate: drop the cloudflared changelog rule in .renovate/changeLogs.json5; optionally add a towonel changelog URL once Phase 0 #8 is known.
- Terraform: remove tunnel.tf, access.tf (apps, groups, service token, Google IdP), firewall_rules.tf (GitHub list + rule only act on proxied traffic; on-prem github-webhook SecurityPolicy covers it), delete_stale_tunnels.sh and the tunnel vars in variables.tf; review zone_settings.tf for proxy-only settings (security_level, browser_check, bot management, always_use_https, …) and keep zone-wide ones (DNSSEC).
- 1Password: remove tunnel_* fields and the CF-Access service-token fields from the cloudflare item; remove the Access headers from the Paperless/Mealie mobile app configs.
- Docs: CLAUDE.md (root), kubernetes/CLAUDE.md, kubernetes/apps/networking/CLAUDE.md, provision/cloudflare/CLAUDE.md, .claude/skills/networking-platform (SKILL.md, references/topology.md, validation.md, change-patterns.md), .claude/skills/cloudflare-terraform; README.md is human-owned — ask before touching it.
- BM: docs/areas/networking, cloudflare, iam updated; this note → status done, progress note created.

## Observability & operations
- Alerts: the four chart rules (EdgeLinkDown critical) routed through the existing Alertmanager → Pushover path; plus a towonel_agent_edge_path change notification if direct/relay flapping matters after D2.
- Dashboard: chart dashboard via GrafanaDashboard (folder Networking).
- External synthetic check (D3 — blackbox probe): split-horizon DNS sends in-cluster lookups of our hostnames to envoy-internal, so the probe targets the edge name instead: new blackbox module (e.g. `http_towonel_edge`) with `tls_config.server_name: idm.${PUBLIC_DOMAIN}`, a `Host: idm.${PUBLIC_DOMAIN}` header and `fail_if_not_ssl`; Probe CR (blackbox-exporter/app/probes.yaml pattern) with target `https://edge-eu.towonel.dev/.well-known/openid-configuration` (Pocket ID, public, not OIDC-gated, expects 200). The request hairpins home IP → edge → tunnel → envoy-external, so it exercises the whole public path and geo (home IP is HU). blackbox-exporter carries custom-egress: add an egress rule for public TCP 443. Alert: probe_success == 0 for 5m → Pushover. Known limit: it cannot alert when the home uplink itself is down (Pushover delivery leaves through the same uplink) — accepted.
- Runbook (networking CLAUDE.md or BM): "towonel edge down" → check EdgeLinkDown + operator status; > 30 min or unknown ETA → rollback (Phase 4 steps) while the rollback window is open; afterwards → self-host fallback or Cloudflare re-enable incl. Universal SSL.
- Upgrades: read release notes (Phase 0 #8), bump chart + image digest together, watch reconnects for 24h.

## Risks & mitigations
- Edge/rogue-issued cert for our hostnames → CT monitoring (from Phase 1), accounturi CAA once Universal SSL is off (Phase 5a). Until then interception requires a CT-visible certificate.
- Another tenant claiming our hostnames on the shared edge → TLS errors (DoS) without a cert; with a cert see above. Phase 0 #1.
- Client-IP spoofing via XFF → PROXY required + numTrustedHops 0, tested (P3).
- Managed outage / shutdown / invite revoked → rollback path during the window, then self-host fallback (VPS: TCP 443, TCP 8443, UDP 51820, IPv6).
- Stream cap 256/agent and OOM history → 2 replicas, 512Mi, StreamsNearCap alert.
- Relay-path throughput (home-gallery media) → measure (P9); D2 directConnect if needed.
- Version skew agent ↔ managed hub → manual upgrades, Phase 0 #6.
- Volumetric DDoS → accepted homelab risk; emergency lever is re-proxying through Cloudflare.

## Decisions (2026-11-15)
- D1 Cutover shape: direct one-PR cutover of envoy-external, preceded by the Phase 3 smoke test (no pilot gateway).
- D2 Path: relay first (no inbound port); revisit directConnect + an OpenWrt UDP port-forward only if P9 shows the relay path is too slow. iroh hole punching may give a direct path anyway (towonel_agent_edge_path).
- D3 External check: in-cluster blackbox probe through the edge (see Observability).
- D4 CT monitoring: Cloudflare CT Monitoring (free, e-mail to the Pushover gateway) — confirmed 2026-11-15. Checked 2026-11-15: SSLMate Cert Spotter has no free tier (Hobbyist $15/month, 30-day trial), merklemap has no free e-mail alerts, Meta's CT tool page returned 404.
- D5 Rollback window before Phase 5a: 4 weeks after the cutover — confirmed 2026-11-15.

## Acceptance criteria
1. Every public hostname is served via towonel with our certificate (checked per host).
2. A forged X-Forwarded-For does not change the client IP seen by geo, CrowdSec and rate limiting.
3. Non-HU request → 403; GitHub webhook redelivery → 200.
4. CT alert path tested (Phase 1); after Phase 5a only the pinned CAA lines are published and our renewal succeeds.
5. Agent alerts + external uptime check live and tested.
6. Revert PR + Terraform revert prepared and reviewed before the window; rollback executable within 15 minutes.

## Review log
- 2026-11-15 review: (1) CAA pin void under Universal SSL → Phase 1 split into CT first, CAA in Phase 5a; (2) project activity corrected (registry 1.13.7 built 2026-11-13; Codeberg repo is a stale mirror); (3) chart 1.13.7 read: 256-stream cap, OOM history, shipped alerts/metrics, image registry choice; (4) pilot completed: CCNP ingress-from-gateway-external gap, EnvoyProxy geo copy, ExternalDNS gateway filter and record handover order, echo reused for OIDC; (5) cutover ordering, disruption window and rollback order made explicit; (6) decommission inventory from a repo grep; (7) client-IP chain grounded in EG geoip.go + live CRD docs; (8) decisions D1–D4 applied: pilot gateway replaced by a no-risk smoke test, tests moved after the cutover with abort criteria, edge-targeted blackbox probe, Cloudflare CT Monitoring; (9) aligned with the same-day removal of the Cloudflare country rule (a5fb33272) and the GeoGateFalsePositive alert (61639a775).

## Effort
L — Phase 0 depends on the operator; Phases 1–3 ~1.5 days; Phase 4 ~2–3h window incl. tests; Phase 5a ~1h; Phase 5b ~half day.

## Related

- relates_to [[networking]]
- relates_to [[cloudflare]]
- relates_to [[iam]]
- relates_to [[cloudflare-api-token-migration]]
- relates_to [[onprem-geoip-country-filter]]
