---
title: onprem-geoip-country-filter
type: roadmap
permalink: home-ops/docs/progress/onprem-geoip-country-filter
topic: On-prem client-IP country filter (HU-only) on envoy-external — move the geo
  gate off Cloudflare
status: done
priority: medium
scope: Re-implement the Cloudflare WAF rule "block non-HU except flux-webhook" natively
  in Envoy Gateway on envoy-external (EnvoyProxy geoIP provider + Gateway-level SecurityPolicy
  authorization with clientIPGeoLocations), fed by a MaxMind GeoLite2-Country mmdb
  kept fresh in-cluster. Run it in parallel with the Cloudflare rule first, so the
  eventual Cloudflare exit does not have to introduce a new security layer on cutover
  day.
rationale: The country gate is the only access-control layer that today exists solely
  at the Cloudflare edge. Building it on-prem now, behind Cloudflare, makes it provider-independent
  and testable at near-zero risk (Cloudflare already drops non-HU traffic), and turns
  the later Cloudflare exit into a client-IP-trust change instead of a security redesign.
options:
- 'A (recommended): Envoy Gateway native geoIP on envoy-external, L7, per-route exceptions
  possible'
- 'B: OpenWrt banIP / nftables geo-sets at L3 — complementary only, cannot express
  host exceptions, useless if the post-CF ingress is a VPS relay'
- 'C: CrowdSec country decisions / AppSec rule — rejected, deny-list model, not an
  allow-list'
related_areas:
- networking
- cloudflare
- external-secrets
- observability
---

# On-prem client-IP country filter (HU-only) on envoy-external

## Metadata (observation-form, schema validation)

- [topic] On-prem client-IP country filter (HU-only) on envoy-external
- [status] done — completed 2026-11-14; the Cloudflare country rule was removed the same day by user decision, so Envoy is the only country gate
- [priority] medium

## What we gain

- The HU-only gate stops depending on one vendor; it rides on the client IP Envoy already resolves, so it survives a Cloudflare exit unchanged.
- Defense in depth while Cloudflare stays: a WAF rule mis-edit or a bypass of the edge no longer opens every host to the world.
- Envoy-side observability of geo denials (RBAC + MaxMind stats) instead of only Cloudflare Security Events.

## Current state (evidence, 2026-11-14)

- [fact] Cloudflare zone ruleset `zone_waf_rules` (provision/cloudflare/firewall_rules.tf): rule 1 blocks flux-webhook unless `ip.src in $github_hooks_cidr_list`; rule 2 blocks `not ip.geoip.country eq "HU"` for every host except `country_block_exceptions`.
- [fact] `country_block_exceptions` shrinks to flux-webhook only — the mta-sts exception was removed together with the MTA-STS Worker (PR #4776, applied 2026-11-14). The ONLY non-HU-reachable host is flux-webhook.
- [fact] Live HTTPRoutes on envoy-external (2026-11-14): github-webhook (flux-webhook), calibre-web-automated (books), echo-server, https-redirect (wildcard), pocket-id-external (idm), home-gallery (photos + fenykepek), homepage (dash), mealie (recipes), paperless (docs), pingvin-share-x (share), sure-external (fin). All behind `*.${PUBLIC_DOMAIN}` on the tunnel.
- [fact] envoy-external has only HTTP/HTTPS listeners (gateway-external.yaml) — EG issue #9868 (Gateway authorization silently dropped on TCP/UDP listeners) does not apply.
- [fact] Gateway-level SecurityPolicy on envoy-external today: `envoy-external-crowdsec` (extAuth only). Route-level: `echo-server-oidc` (oidc, StrategicMerge). No other route policy on external routes.
- [fact] ClientTrafficPolicy/envoy-external resolves the client IP with `xForwardedFor.trustedCIDRs: [${POD_CIDR}]` (EG v1.9 change, verified live 2026-08-15); the trust anchor is CiliumNetworkPolicy/envoy-external (only the cloudflared pod may reach 10080/10443).
- [fact] Running versions: Envoy Gateway chart 1.10.0, Envoy v1.40.2, Kubernetes v1.37.2, default StorageClass democratic-csi-local-hostpath (single node).
- [fact] MaxMind license key already lives in 1Password item `maxmind` (vault HomeOps), consumed by pocket-id via ESO `dataFrom.extract: maxmind` (kubernetes/apps/security/pocket-id/app/externalsecret.yaml). pocket-id downloads its own GeoLite2-City into an emptyDir — not shared, deliberately.
- [fact] ACME is DNS-01 (cert-manager ClusterIssuer) and no external uptime monitor exists — no foreign inbound validator needs an exception.

## Upstream constraints (verified in source, EG v1.10.0 / Envoy v1.40.2)

- [constraint] **BLOCKER for the current CTP:** `clientIPGeoLocations` rejects `xForwardedFor.trustedCIDRs` — internal/gatewayapi/securitypolicy.go `validateAuthorizationGeoIP`: "authorization clientIPGeoLocations does not support ClientIPDetection.XForwardedFor.TrustedCIDRs". An invalid policy fails closed (routes answer 500 direct response). Accepted modes: exactly one of `numTrustedHops`, `customHeader`, `directSourceIP`; a ClientTrafficPolicy with clientIPDetection is mandatory. Upstream feature request: envoyproxy/gateway#9935 (open).
- [constraint] EG `numTrustedHops: N` is translated to Envoy `xff_num_trusted_hops: N-1` (internal/xds/translator/listener.go `xffNumTrustedHops`, compat with envoy#34241). N=1 → Envoy 0 → the rightmost XFF entry is the client. The geoip filter receives the same hop count and with 0 falls back to the address the HCM already resolved (geoip.go:200-220), so RBAC, geoip, access log and CrowdSec all see one consistent client IP.
- [constraint] **Header-spoof gap:** the geoip filter only `setCopy`s `x-eg-internal-geoip-country` when the lookup is non-empty (envoy geoip_filter.cc:125-126) and EG strips it only at the router, after RBAC. A client whose IP misses the database could send `x-eg-internal-geoip-country: HU` and match the Allow rule. Mitigation is mandatory: `ClientTrafficPolicy.headers.earlyRequestHeaders.remove: [x-eg-internal-geoip-country, x-eg-internal-geoip-region, x-eg-internal-geoip-city, x-eg-internal-geoip-asn, x-eg-internal-geoip-isp]` (+ anonymous headers if ever used).
- [constraint] Default filter order puts ext_authz (CrowdSec) and oauth2 BEFORE geoip and RBAC (EG httpfilters.go; issue envoyproxy/gateway#8913 open): a foreign client on an OIDC route would get an IdP redirect instead of a 403, and every foreign request costs a CrowdSec gRPC call. `EnvoyProxy.spec.filterOrder` (present in the cluster CRD) can move geoip + rbac ahead of ext_authz and oauth2 on envoy-external only.
- [constraint] Envoy MaxMind provider: missing/unreadable db at config load → configuration rejected (xDS NACK; before 1.40 it crashed Envoy). A fresh proxy pod that never had a good config would have no listeners → full public outage. The mmdb MUST exist before the policy reaches the proxy.
- [constraint] Hot reload is unconditional since Envoy 1.36 via inotify on the parent directory, triggered only by a rename (MovedTo) onto the exact file name; a failed reload keeps the previous db (`db_reload_error`++). ConfigMap/Secret volumes (..data symlink swap) would most likely NOT trigger it. geoipupdate writes `<db>.temporary` + fsync + rename in the same dir → triggers it, as long as writer and Envoy share one node-local filesystem (true on local-hostpath, single node).
- [constraint] No `database_type` validation in the provider; country read from `country.iso_code`; RBAC country match is exact with ignoreCase, CRD pattern `^[A-Za-z]{2}$`. Lookup miss (private/unknown IP) → header absent → principal does not match → falls to defaultAction.
- [constraint] Route-level SecurityPolicy with `mergeType: StrategicMerge`: `authorization.rules` REPLACES the parent list (no patchMergeKey), and an omitted `defaultAction` serialises as null and drops the parent's value (→ Deny). Parent `extAuth` is retained when the child omits it. A route policy that sets its own rules must therefore restate everything it needs.
- [constraint] geoipupdate image: requires GEOIPUPDATE_ACCOUNT_ID + GEOIPUPDATE_LICENSE_KEY (or _FILE) + GEOIPUPDATE_EDITION_IDS; GEOIPUPDATE_FREQUENCY=<hours> keeps it running and updates immediately on start (0/unset = run once); Dockerfile has no USER (set runAsUser), needs writable /tmp and a writable DB dir (lock file). GeoLite limits: 30 downloads/day; GeoLite2-Country updates Tuesday + Friday; EULA requires deleting superseded data within 30 days (overwrite satisfies it).

## Target design

### 1. Client-IP detection on envoy-external (prerequisite)
- Switch ClientTrafficPolicy/envoy-external from `trustedCIDRs: [${POD_CIDR}]` to `xForwardedFor.numTrustedHops: 1`.
- [decision] Accepted trade-off: Envoy no longer checks that the direct peer is a trusted CIDR before reading XFF. The compensating control is unchanged and was already the real anchor: CiliumNetworkPolicy/envoy-external admits only the cloudflared pod on 10080/10443. Revert to trustedCIDRs once envoyproxy/gateway#9935 ships.
- Rejected: `customHeader: CF-Connecting-IP` — re-couples to the vendor the 2026-08-15 change deliberately decoupled from, and has the same CNP dependency.
- Spoof resistance: Cloudflare appends the real client to any client-sent XFF; cloudflared forwards XFF unchanged (2026-08-15 access log: `x-forwarded-for: <client>,<cloudflared pod>`, the pod entry appended by Envoy) → rightmost entry = real client.

### 2. GeoIP database plane
- New Flux stage under the existing envoy-gateway split: `kubernetes/apps/networking/envoy-gateway/geoip/` → Kustomization `envoy-gateway-geoip` (wait: true), and `envoy-gateway-config` gains `dependsOn: envoy-gateway-geoip`.
- Workload: app-template **Deployment** (not CronJob) running `ghcr.io/maxmind/geoipupdate` (digest-pinned, Renovate-tracked) with `GEOIPUPDATE_EDITION_IDS=GeoLite2-Country`, `GEOIPUPDATE_FREQUENCY=24`, DB dir on a PVC. Why Deployment: it downloads immediately on start (bootstrap/DR seed with no Job or manual `kubectl create job`), and a startup/readiness probe `test -s <db>` gives Flux a real health signal, so the dependsOn above guarantees the file exists before any geo policy is pushed. Cost: one idle pod (~5m CPU / 32Mi).
- Storage: small PVC (64Mi) on democratic-csi-local-hostpath, RWO, mounted rw by geoipupdate and readOnly by the envoy-external pod (same node). Not in VolSync (regenerable). Survives envoy pod restarts, so a MaxMind outage never blocks proxy start.
- Secret: ExternalSecret in networking, `dataFrom.extract: maxmind` → GEOIPUPDATE_ACCOUNT_ID / GEOIPUPDATE_LICENSE_KEY. Same 1Password item as pocket-id, no new secret system.
- Network: `egress.home.arpa/custom-egress` + FQDN egress to download.maxmind.com, *.maxmind.com and MaxMind's R2 bucket host (copy of pocket-id's rule set), DNS via baseline; `ingress.home.arpa/none`. Pod hardening per house pattern (runAsNonRoot, readOnlyRootFilesystem, /tmp emptyDir, drop ALL).
- Download budget: 24h frequency + pocket-id's own refreshes stay far below 30/day.

### 3. Envoy wiring (EnvoyProxy/envoy-external only)
- `spec.geoIP.provider: {type: MaxMind, maxMind: {countryDbSource: {local: {path: /geoip/GeoLite2-Country.mmdb}}}}`.
- `provider.kubernetes.envoyDeployment.pod.volumes` (PVC) + `container.volumeMounts` readOnly at /geoip — fits the existing readOnlyRootFilesystem patch.
- `spec.filterOrder`: geoip + rbac before ext_authz and oauth2.
- envoy-internal untouched (RFC1918 authorization; private IPs have no country).

### 4. Policy
- Fold authorization into the existing Gateway-level policy (one SecurityPolicy per target, else Overridden): rename `envoy-external-crowdsec` → `envoy-external-edge`, carrying extAuth (unchanged) + `authorization: {defaultAction: Deny, rules: [Allow clientIPGeoLocations [{country: HU}]]}`. NO private-CIDR allow rule (corrected in the 2026-11-14 review: it would be a hole, see below). Rename touches `prometheusrule_test.yaml` (series + expected labels at ~:155-180) and the comment in the `securitypolicy-route-strategic-merge` VAP message — update both in the same PR.
- ClientTrafficPolicy/envoy-external: add the `earlyRequestHeaders.remove` list for `x-eg-internal-geoip-*`.
- Optional: `responseOverride` on the existing `envoy` BTP for 403 → short Hungarian page (same mechanism as the 401 page). Not required.

### 5. flux-webhook exception (decided 2026-11-14: 5a)
- Route-level SecurityPolicy on HTTPRoute/github-webhook, `mergeType: StrategicMerge`, with its own full authorization (rules replace the parent's, extAuth inherited):
  - Option 5a (parity with Cloudflare, recommended): `defaultAction: Deny` + Allow `clientCIDRs` = GitHub `hooks` ranges, kept in a generated file refreshed by a scheduled GitHub Actions workflow opening a PR when api.github.com/meta changes.
  - Option 5b (simpler): `defaultAction: Allow` — rely on the Flux Receiver HMAC (`github-webhook-token-secret`) + CrowdSec only.

### 6. Observability and the Grafana dashboard

Constraints found on 2026-11-14 that shape this:
- [constraint] Grafana has **no VictoriaLogs datasource and no plugins** (observability decision D13; logs stay in vmui). Grafana can only chart Prometheus data.
- [constraint] The log collector is **vlagent** (quay.io/victoriametrics/vlagent), not Vector — there is no in-pipeline geoip enrichment or log-to-metric transform to lean on.
- [constraint] Envoy exposes **no per-country metrics**: RBAC stats are per HCM listener (`http.<https-10443>.rbac.allowed/denied`, EG sets no rules_stat_prefix), geoip/maxmind stats are totals (total/hit/lookup_error, db_build_epoch, reload success/error). Per-route split is also impossible from metrics.
- [constraint] Country per request exists only inside Envoy: `x-eg-internal-geoip-country` is set by the geoip filter and stripped by the router just before forwarding upstream. For RBAC-denied requests the router never runs, so `%REQ(X-EG-INTERNAL-GEOIP-COUNTRY)%` in the access log should carry the country of every **denied** request (UNVERIFIED — spike step 3). Allowed requests are HU by definition (or GitHub on the webhook route), so denied-only coverage is enough.

Tier 1 — in scope of this item (Prometheus-only, no new component):
- New dashboard **"Envoy external — geo gate"**, folder `networking`, shipped as an in-repo JSON via kustomize `configMapGenerator` + `GrafanaDashboard.configMapRef` in envoy-gateway/config (first in-repo dashboard JSON — the existing dashboards are upstream URL or chart ConfigMaps). Grafana core panels only (D13-compatible).
- Row "Gate health": SecurityPolicy accepted state (envoy_securitypolicy_info for the edge policy and the flux-webhook route policy) · GeoIP DB age in days (time() − db_build_epoch) · last reload result (db_reload_success vs db_reload_error) · geoipupdate pod Ready + restarts (kube-state-metrics) · CrowdSec bouncer up (existing series) for context.
- Row "Decisions": allowed vs denied req/s on envoy-external (RBAC) · deny ratio % · geoip lookups vs hits vs lookup_error → miss ratio (misses = private/unknown IPs, all denied) · denials overlaid with Envoy 5xx/503 to tell a geo deny from a CrowdSec outage.
- Row "Parallel-run tripwire": denied req/s with the 5b alert threshold drawn. While Cloudflare is in front, Cloudflare already blocks non-HU AND non-GitHub-on-flux-webhook, so ANY RBAC denial on envoy-external is a MaxMind-vs-Cloudflare disagreement — the listener-level metric is sufficient for 5b without a per-route split.
- Alerts (PrometheusRule envoy-proxy group, promtool-tested per the unit-test-bar ADR): GeoIPDatabaseStale (> 10d), GeoIPReloadFailed, GeoGateFalsePositive (5b, parallel run only — delete or retune at the Cloudflare exit, because foreign scanners will then deny continuously by design).
- Access log: add `geo_country` to the envoy-external JSON format. Per-country / per-host / per-IP drill-down is done in **vmui** with LogsQL, e.g. `kubernetes.pod_name:envoy-external* response_code_details:rbac_access_denied* | stats by (geo_country) count()` and `... | stats by (":authority") count()` — record the working queries in the networking area note.

Tier 2 — deferred to the Cloudflare-exit item (when non-HU traffic actually reaches Envoy and a world map becomes informative):
- 2a: **vmalert with LogsQL recording rules** → remote-write `envoy_external_geo_denied_total{country}` (+ a bounded host label: known hostnames, everything else → "other", because scanners send random Host headers) into Prometheus → Grafana core **Geomap** panel (ISO-2 lookup) + top-N tables. Keeps D13; costs one vmalert pod and enabling the Prometheus remote-write receiver. Recommended.
- 2b: reverse D13 and add the VictoriaLogs Grafana datasource plugin — direct log panels and Geomap, but brings back plugin download egress and a plugin to keep updated.
- 2c: CrowdSec web UI already shows a country view of CrowdSec alerts (geoip-enrich) — useful context, not a traffic view.

## What to do (phased)

0. **Prereq check:** Account ID confirmed in 1Password (`ACCOUNT_ID`); flux-webhook exception = 5a (GitHub CIDR list + refresh workflow, part of step 4). The mta-sts/Worker removal prerequisite is done (PR #4776).
1a. **Offline shadow evaluation (before any enforcement, no cluster change):** export the distinct client IPs (`downstream_remote_address`) of envoy-external from VictoriaLogs (14d retention), excluding flux-webhook; look each up in a locally downloaded GeoLite2-Country; every non-HU (or miss) result is a would-be false positive, because Cloudflare already classified all of them as HU. Record the count/ratio here; if > 0, inspect the prefixes and decide on a clientCIDRs override before step 4.
1. **CTP switch (own PR):** trustedCIDRs → numTrustedHops: 1. Verify live: access log `downstream_remote_address` is the real public client (v4 + v6), `downstream_direct_remote_address` the cloudflared pod; CrowdSec bouncer still sees real IPs (X-Envoy-External-Address); a client-sent `X-Forwarded-For: 1.2.3.4` through Cloudflare does NOT become the client IP. Update networking area note (the 2026-08-15 decision is superseded, with reason).
2. **GeoIP DB plane (own PR):** geoip stage + ExternalSecret + PVC + Deployment + CNP; dependsOn wiring. Verify: pod Ready, file present, size sane; second start does not re-download (md5 match); Hubble shows no policy drops.
3. **Spike on the live proxy (no policy yet):** add geoIP provider + volume + filterOrder to EnvoyProxy/envoy-external. Verify: no xDS NACK (`EnvoyGatewayXDSRejected` silent), config dump contains geoip filter only after step 4 (filter is added lazily), stats names for maxmind/rbac captured for step 5. Test hot reload: touch-replace via geoipupdate restart with a forced re-download, watch `db_reload_success`.
4. **Enforce (own PR):** SecurityPolicy rename + authorization + earlyRequestHeaders strip + flux-webhook route policy. Verify: policies `Accepted=True`, no Conflicted/Overridden; HU client 200 on all external hosts; GitHub webhook redelivery 200 and Flux reconciles; e2e foreign test: temporarily add a throwaway `geo-test` host to Cloudflare `country_block_exceptions`, curl from a non-HU IP → 403 from Envoy (`rbac_access_denied`), spoofed `x-eg-internal-geoip-country: HU` from that IP still 403; remove the exception.
5. **Alerts + dashboard (own PR):** Tier 1 dashboard JSON + GrafanaDashboard, the three alerts with promtool tests, `geo_country` access-log field; verify every panel against live series (no empty panels), and the vmui queries return the test 403s from step 4.
5b. **False-positive tripwire for the parallel run:** a warning alert on any `rbac denied` increase on envoy-external outside the GitHub route — while Cloudflare is in front, every such denial is a MaxMind/Cloudflare disagreement, i.e. a blocked Hungarian user.
6. **Parallel run:** a few weeks with Cloudflare still blocking; expected Envoy geo denials ≈ 0 outside tests. Then the item is done; the Cloudflare rule stays until the Cloudflare-exit project removes the tunnel.

## Post-rollout review — 2026-11-14

Verified OK (live):
- [verified] Only `flux-system/github-webhook` carries its own `authorization` among the 11 envoy-external routes; `echo-server-oidc` merges without one; `components/gateway-oidc` has no authorization block.
- [verified] All 5 direct TCP peers of envoy-external over 14 days were cloudflared pods (one per rollout); only CiliumNetworkPolicy/envoy-external grants ingress to the proxy, so there is no in-cluster path to forge XFF.
- [verified] The http (80) listener carries the same geoip > rbac chain as https.
- [verified] CrowdSec parses 100% of the envoy-external access lines (the unparsed lines are Envoy's stderr), and geo 403s are poured into buckets.
- [verified] Renovate tracks app-template images without a comment (cloudflared precedent), so the geoipupdate image is tracked.
- [verified] `update-github-hooks-networks` dispatched manually: success, 9 ranges, no changes, no PR.
- [verified] No envoy-gateway controller errors in 1h; webhook delivery after a merge took about 5s.

Fixed in the review (f588992a3, 6615bcf8d, b408746d6):
- [fixed] geoipupdate v8 + entry.sh exited on the first failed update, so a MaxMind outage CrashLooped the pod, made envoy-gateway-geoip NotReady and stalled envoy-gateway-config and k8s-gateway. A shell loop now logs the failure and keeps the pod Ready; GeoIPDatabaseStale went from 10d to 7d.
- [reverted] Hungarian 403 page (BTP responseOverride): the test matrix showed it triggers an Envoy use-after-free in the RBAC response_code_details, so it was reverted in f3f1f4989 (see [[networking]] Update 2026-11-14).
- [fixed] Guardrails in kubernetes/apps/networking/CLAUDE.md: a route-level authorization replaces the parent's rules; keep numTrustedHops until gateway#9935; access from abroad needs both the Cloudflare and the Envoy exception. The alert, admission message and bouncer comment now name the geo gate and the current client-IP model.

Open:
- [done] **Hot reload verified (2026-11-14):** a same-content `cp` + `mv` onto GeoLite2-Country.mmdb inside the geoipupdate pod raised db_reload_success from 0 to 1 on envoy-external (log: "Loaded Maxmind database country_db"); a HU request still returned 200. The inotify reload works across the two pods sharing the local-hostpath PVC.
- [fixed] **CrowdSec bouncer never saw external client IPs (found 2026-11-14, likely pre-existing).** A self-ban test (`cscli decisions add` on the home public IP, request through Cloudflare) reached the bouncer cache (`decisions_added_total{origin="cscli"}`), but 12 requests over 60s passed. With `trustedIPHeader: X-Envoy-External-Address` the bouncer resolved public requests to the cloudflared pod IP, so `exemptIPs: 10.0.0.0/8` skipped decisions AND AppSec for all envoy-external traffic. Fix 1093fb057: drop trustedIPHeader and set `trustedProxies: [${POD_CIDR}]`. The bouncer walks XFF right-to-left past pod IPs; Envoy appends its direct peer, so the result is the public client externally and the LAN client internally. Retest: 403 `ext_authz_denied` (with the Hungarian 403 page) within one 10s sync, and access was back about 10s after the decision was deleted; LAN hosts are unaffected and the bouncer shows no errors. Side effect: AppSec WAF now inspects all public traffic for the first time; watch for false positives (uploads, unusual APIs).
- [note] flux-local CI only runs on PRs, so the direct-to-main commits were validated by the live reconcile, not by CI.
- [note] At the Cloudflare exit: delete or retune GeoGateFalsePositive and revisit client-IP detection (see the Post-Cloudflare-exit section).

## Test matrix — 2026-11-14 (direct port-forward to the proxy, arbitrary XFF)

- [verified] envoy-external, idm: no XFF → 403 · XFF private 192.168.1.50 → 403 · reserved 240.0.0.1 (DB miss) → 403 · US 8.8.8.8 → 403 · HU v4 → 200 · HU v6 → 200 · DE v6 → 403 · "HU, US" → 403 (rightmost wins) · "US, HU" → 200 (left entries ignored, which is correct because the edge appends the real client) · garbage XFF → 403 · DB miss + spoofed geo header → 403 · US + spoofed header (any case) → 403.
- [verified] http listener (80): US → 403, HU → 301 redirect.
- [verified] flux-webhook /hook/: GitHub v4 + v6 → reach the Receiver (404 for the fake token) · HU, US, no XFF → 403. So the route policy does not inherit the HU allow.
- [observation] Requests that match no route (unknown path or host) get 404 `route_not_found` before RBAC, whatever the country. This is not a hole, because no backend is reachable that way.
- [verified] geoipupdate failure path: an invalid licence key gives rc=1 (401 AUTHORIZATION_INVALID), the mmdb md5 is unchanged and no temp file is left behind.
- [finding] Envoy use-after-free with the 403 responseOverride (found by this matrix, reverted).
- [verified] **Matrix extension (2026-11-14 night), port-forward + live:**
  - Client identity: IPv4-mapped v6 HU → 200 / US → 403 · XFF with port → 403 even for HU (unparseable, fail-closed; Cloudflare never sends ports) · two XFF headers are joined, the rightmost wins (HU,US → 403; US,HU → 200) · empty XFF → 403 · padded whitespace HU → 200 · `Forwarded`, `X-Real-IP`, `CF-Connecting-IP`, `X-Envoy-External-Address` carrying HU with a US or missing XFF → 403 (ignored) · 60-entry XFF ending in HU → 200.
  - Hosts: all 10 external app hosts → US 403 / HU passes (200/30x); flux-webhook `/` → 404 route_not_found for both · host variants (trailing dot, uppercase, `:443`) with US → 403.
  - Protocol/method with US: HTTP/1.1, HTTP/2, OPTIONS (CORS preflight), HEAD, POST, WebSocket upgrade → 403 · webhook `/hook/../hook/x` normalised → 403; `/HOOK/x` → 404 (no route).
  - Alert delivery: Pushover sends at 20:32Z (GeoGateFalsePositive fired), 20:57Z (resolved), 22:32Z (fired by the port-forward matrix); 0 failed notifications.
  - CrowdSec AppSec on public traffic: `/.env` via Cloudflare from the home IP → 403 ext_authz_denied, alert `crowdsecurity/vpatch-env-access` with the real IP, no ban from a single hit; a control path passes.
  - Reload-error path: a corrupt file renamed onto the mmdb → db_reload_error 1, previous DB kept (HU 200, US 403 meanwhile); restoring the original → db_reload_success 2, md5 unchanged. GeoIPReloadFailed fires for about 1h as a side effect.
- [verified] **External OIDC login (2026-11-14, user on mobile data, IPv6):** docs → paperless OIDC login → idm /authorize → passkey interaction → /authorize 303 → paperless callback 302 → app 200 and websocket 101; dash, books and idm assets all 200. 154 requests with no 403 and no 5xx. Paperless uses app-level OIDC; the Envoy gateway-oidc filter on external serves only the echo test app (redirect verified, full login not exercised).
- [not-tested] a full-cluster DR bootstrap with an empty geoip PVC, the hooks-workflow PR path, and an Envoy restart while the mmdb on the PVC is corrupt (would be an outage by design: Envoy rejects the provider; geoipupdate would only fix it on its next daily run or a pod restart).

## Closure — 2026-11-14: Cloudflare country rule removed

- [decision] User decision: stop the parallel run early and remove the Cloudflare WAF country rule. Evidence: 14 days of real clients all HU in GeoLite2 (0 would-be false positives), foreign v4/v6 e2e tests, the full port-forward matrix, and a real external OIDC login.
- [done] 61639a775: `GeoGateFalsePositive` deleted (with foreign traffic reaching Envoy, denials are normal); the dashboard tripwire row became a plain "Geo denials per 15m" panel; the networking guide names envoy-external-edge as the only country gate.
- [done] a5fb33272: `provision/cloudflare/firewall_rules.tf` loses rule 2 and the `country_block_exceptions` locals; the GitHub-CIDR rule on flux-webhook stays. Applied; `terraform plan` shows no changes.
- [verified] After the removal, foreign requests via Cloudflare (check-host.net): idm (ID, IR) and books (CH, SI, US) → 403 `rbac_access_denied` from Envoy; dash → 302 to the Cloudflare Access login (Access still gates first); flux-webhook → 403 from the Cloudflare GitHub-CIDR rule. HU idm → 200. One HU check-host node got 403 `ext_authz_denied` (on a CrowdSec blocklist): the bouncer fix at work.
- [fact] Pocket ID (`idm`, route pocket-id-external) is covered by the gateway-level HU gate: no route policy with authorization, US → 403 in the matrix. It is a Cloudflare Access bypass app, so geo + CrowdSec + passkey-only login are its only gates now.
- [residual] Without Cloudflare in front, nothing distinguishes a misclassified Hungarian client from a foreign one. Watch the dashboard's deny panels and vmui (`stats by (geo_country)`); fix such a case with a `clientCIDRs` Allow in envoy-external-edge.

## Post-closure review — 2026-11-15

- [verified] **iCloud Private Relay:** all 361 HU egress ranges in Apple's list (mask-api.icloud.com/egress-ip-ranges.csv; 29 IPv4, 332 IPv6) resolve to HU in GeoLite2-Country. Cloudflare geolocated relay IPs natively; MaxMind agrees for HU, so iPhone users with Private Relay are not locked out.
- [verified] Every Cloudflare-proxied host is an ExternalDNS record pointing to the tunnel → envoy-external; none of the Terraform-managed DNS records is proxied, so removing the Cloudflare country rule left no host without the Envoy gate.
- [verified] Load after the removal is negligible (first 30 min: 7 denials vs about 1800 allowed). RBAC denies before ext_authz, so foreign scans cost neither CrowdSec nor AppSec calls. Cloudflare `security_level: high` and L7 DDoS stay in front.
- [fixed] **GeoGateInactive** (d8e765d17, critical): KSM's `envoy_securitypolicy_info` only exposes the Accepted condition, so an Overridden or detached edge policy, or an rbac filter dropped by an EG upgrade, would open every public route silently now that no Cloudflare backstop exists. The alert fires when backends receive traffic that mostly never passed RBAC (allowed < 0.5 × forwarded over 10m, for 5m). Unmatched-route 404s cannot trigger it; an idle night cannot either. Eight promtool cases. Live ratio allowed/forwarded = 1.0.
- [known-risk] The Cloudflare GitHub-hooks list refreshes only on a manual `terraform apply`, while the Envoy list refreshes via the daily workflow PR (pre-existing).
- [known-risk] No automatic signal for a Hungarian client misclassified by GeoLite (it silently gets a 403); find it via vmui `stats by (geo_country)`.
- [decision] The Envoy use-after-free (403 responseOverride) will not be reported upstream (user decision); the guardrail in the networking guide stays.

## Rollback

- Each phase is one revert. Removing the authorization block restores today's behaviour instantly; the geoip filter disappears from the listener once no route uses clientIPGeoLocations. The DB plane is inert without the policy. CTP revert returns to trustedCIDRs.

## Post-Cloudflare-exit implications (input for that future item)

- The geo policy itself stays; only client-IP detection changes with the new ingress path: direct exposure via Cilium LB (externalTrafficPolicy: Local) → `directSourceIP`; VPS/WireGuard relay → PROXY protocol on the listener + `directSourceIP`, or `numTrustedHops` matching the relay; once #9935 lands, trustedCIDRs again.
- Option B (OpenWrt banIP country sets) becomes worthwhile only with direct exposure — it drops non-HU before the TCP handshake and covers non-HTTP ports; the flux-webhook GitHub ranges are IP-based, so they are expressible at L3.
- Other Cloudflare-only controls that the exit must replace separately: tunnel (no open port, home IP hidden), DDoS absorption, Access apps (Google OAuth wildcard gate, service-token for the Paperless/Mealie mobile clients), Bot/security-level settings, DNS hosting.

## Risks / open questions

- [risk] numTrustedHops drops the peer-CIDR check; a CNP regression on envoy-external would let a cluster pod forge client IPs (and with it, the country). Mitigation: keep the CNP under the existing HubblePolicyDeny/area-note review; revert to trustedCIDRs after #9935.
- [risk] Fresh proxy pod + missing mmdb = no listeners. Mitigated by the dependsOn + readiness-gated Deployment and the persistent PVC; residual risk during full-cluster DR is ordering-only.
- [risk] False positives: Hungarian prefixes misclassified by GeoLite (new allocations, mobile CGNAT). EU roaming on HU SIMs is home-routed (HU IP). Same exposure as today's Cloudflare rule; mitigation is a clientCIDRs allow override.
- [open] Exact Prometheus names of maxmind/rbac stats (step 3).
- [resolved] flux-webhook: 5a chosen by the user (2026-11-14) — GitHub hooks CIDR allow-list, kept fresh by a scheduled GitHub Actions workflow that opens a PR on change; parity with today's Cloudflare rule.
- [resolved] MaxMind Account ID is present: 1Password item `maxmind` (HomeOps) has fields `ACCOUNT_ID` and `MAXMIND_LICENSE_KEY` (labels checked 2026-11-14) — map them to GEOIPUPDATE_ACCOUNT_ID / GEOIPUPDATE_LICENSE_KEY in the ExternalSecret template.


## Review 2026-11-14 — gaps found and closed

- [correction] **Private-CIDR "safety net" removed — it was a hole.** With `numTrustedHops`, a request that arrives with NO X-Forwarded-For falls back to the TCP peer, i.e. the cloudflared pod (10.244.x, inside 10.0.0.0/8 and POD_CIDR). An allow rule for RFC1918/POD_CIDR would turn "missing XFF" into "allowed". No legitimate private-source path exists on envoy-external (LAN uses envoy-internal), so the geo miss → defaultAction Deny is the correct outcome.
- [verified] `EnvoyProxy.spec.filterOrder` enum contains `envoy.filters.http.geoip` and `envoy.filters.http.rbac`; `envoyDeployment.pod.volumes` and `envoyDeployment.container.volumeMounts` exist in the live CRD (kubectl explain, 2026-11-14). The envoy-external proxy pod runs in namespace `networking` on k8s-cp0, so the PVC lives there.
- [verified] Admission guard `securitypolicy-route-strategic-merge` (envoy-gateway/config/validatingadmissionpolicy.yaml) already forces StrategicMerge on route-level policies — the flux-webhook route policy complies by design.
- [gap-closed] **e2e foreign test was incomplete:** every host sits behind the Cloudflare Access wildcard app `private_cloud` (Google OAuth), so a foreign request to a throwaway host would stop at the Access login, never reaching Envoy. The test needs BOTH a temporary `country_block_exceptions` entry AND a temporary `public_bypass_apps` entry. Use the existing `echo` host (already on envoy-external; with the new filterOrder RBAC answers 403 before its OIDC gate). A non-HU vantage point is needed (VPN exit or a foreign cloud shell). Revert both Terraform entries right after.
- [gap-closed] **False-positive rate was unquantified.** Added step 1a (offline shadow evaluation against 14 days of real client IPs) and step 5b (tripwire alert). EG exposes no RBAC shadow mode, so these two replace it.
- [decision] **PVC vs native sidecar for the DB.** PVC puts democratic-csi in envoy-external's start path; a native sidecar (initContainer with restartPolicy: Always + startupProbe) would instead put MaxMind/internet reachability in the start path of every proxy pod. PVC chosen: local-hostpath is already in the critical path of every stateful app on this node, the data is local, and a MaxMind outage then never blocks a restart. Spike must verify the envoy container (non-root uid) can read the mmdb written by geoipupdate (file mode / fsGroup).
- [pattern] **GitHub hooks CIDR refresh = copy of `update-cloudflare-networks`.** `.github/workflows/update-cloudflare-networks.yaml` + `.github/scripts/update_cloudflare_networks.py` (daily cron, ruamel.yaml rewrite, peter-evans/create-pull-request, SHA-pinned actions) is the house pattern; the new workflow rewrites `authorization.rules[0].principal.clientCIDRs` of the flux-webhook route SecurityPolicy from `api.github.com/meta` → `.hooks` (IPv4 + IPv6). Known limitation shared with the existing workflow: PRs opened with GITHUB_TOKEN do not trigger other workflows (flux-local), so review is manual.
- [observation] **CrowdSec keeps visibility.** The CrowdSec agent tails envoy-external access logs (acquisition `podName: envoy-external-*`), so geo 403s are still parsed even though RBAC now answers before ext_authz. After the Cloudflare exit, repeated geo-denied scanners therefore still feed the existing http scenarios (verify the scenario set counts 403s at that time).
- [observation] **Regression guard already exists:** the envoy_securitypolicy_info-based alert (prometheusrule_test.yaml) fires when a SecurityPolicy is not Accepted — it would catch a future change that re-adds trustedCIDRs (which invalidates the geo policy and 500s every route) or a Conflicted/Overridden policy.
- [observation] Licensing: GeoLite2 EULA permits this internal use; no attribution needed because geo data is never displayed; superseded data is overwritten in place (30-day deletion clause satisfied as long as the updater runs — covered by the stale-DB alert at 10d).

## Related

- relates_to [[networking]]
- relates_to [[cloudflare]]
- relates_to [[external-secrets]]
- relates_to [[observability]]
- relates_to [[iam]]
- relates_to [[client-ip-trust-topology]]

## Execution log — 2026-11-14

Executed directly on main (user decision: phase by phase, no PRs, outage acceptable).

- [result] **1a shadow evaluation:** 14 days of envoy-external access logs (2026-10-31 → 11-14, flux-webhook excluded) contain 8 distinct public client IPs (4 IPv4, 4 IPv6), all `HU` in GeoLite2-Country (build 2026-11-13) → **0 would-be false positives**. The 1199 IP-less lines are Envoy stderr, not access logs.
- [done] **Phase 1** (273a4602d) CTP `numTrustedHops: 1`, Accepted. Verified: `X-Forwarded-For: 1.2.3.4` via Cloudflare → client 94.21.207.197 (XFF `1.2.3.4,<client>,<cloudflared>`); GitHub hooks resolve to 140.82.x / 9.234.98.161 (inside the hooks ranges). IPv6 not re-tested from the workstation (no v6 path through Cloudflare from here); the 14d log has v6 clients resolved the same way.
- [done] **Phase 2** (4e4aeaed4) envoy-gateway-geoip stage: ExternalSecret synced, PVC Bound, mmdb 3.3MB mode 0644 uid 65532; restart → same hash, no re-download.
- [done] **Phase 3** (b7ac8cc8c) EnvoyProxy geoIP provider + read-only PVC + filterOrder: EnvoyProxy Accepted, proxy rolled, mmdb readable from the envoy container, no NACK.
- [done] **Phase 4** (5b11a4fc3) envoy-external-edge (HU allow, Deny default) + header strip + flux-webhook route policy (5a) + hooks refresh workflow. Both policies Accepted/Merged, old policy pruned. Live chain: header_mutation > geoip > rbac > ext_authz > oauth2. HU client 200/302 on idm/books; GitHub webhook after enforcement 200 from 140.82.115.44. A spoofed `x-eg-internal-geoip-country` from a HU IP is harmless (allowed anyway); the non-HU spoof case is part of the pending e2e test.
- [done] **Phase 5** (b45c290ab) alerts + dashboard + `geo_country` log field; every dashboard query returns live data. `geo_country` is empty on allowed requests (confirmed), expected filled on denied ones (to confirm with the e2e test).
- [resolved] Stat names (the step-3 open question) — recorded in [[networking]] Update 2026-11-14.
- [observation] `just k8s test-prom-rules` fails locally on a mise shim (`No version is set for shim: promtool` inside the mktemp dir); the pre-commit `promtool-rule-tests` hook passes. Follow-up: pin promtool for the recipe's scratch dir.
- [done] **e2e foreign test (step 4), 2026-11-14:** temporary Terraform entries for `echo` (`country_block_exceptions` + `public_bypass_apps`) applied, then reverted (post-revert `terraform plan`: no changes). check-host.net from CH, MD, IR, US, VN → all 403 from Envoy (`rbac_access_denied_matched_policy[DENY]`), `geo_country` filled with the right country, real client IPs. HU control from the home IP → passed the gate (302 = echo's OIDC redirect). After the revert, foreign requests are 403 at the Cloudflare edge again and never reach Envoy. `GeoGateFalsePositive` fired on the test 403s as expected (ALERTS=1), then self-resolves after 15m. The spoofed-header case was covered by the follow-up IPv6 test below.
- [done] **Foreign IPv6 + spoof test, 2026-11-14:** Globalping API (HTTPS, ipVersion 6, custom headers) with the same temporary Terraform entries, reverted afterwards (no drift). NL and US probes reached Envoy over IPv6 and got 403 `rbac_access_denied_matched_policy[DENY]`, with real IPv6 clients and `geo_country` NL/US. With a spoofed `x-eg-internal-geoip-country: HU` header, NL and US were still 403 with their real country: the early header strip works. The DE probes got a Cloudflare HTML 403 and never reached Envoy (another Cloudflare control); not an Envoy finding.
- [done] **IPv6 (phase 1 follow-up):** a request from the user's mobile network over IPv6 to books resolved to the real IPv6 client (`[2a00:1110:…]`, XFF `<v6 client>,<cloudflared>`), passed the geo gate and reached the upstream (404 from Calibre).
- [observation] `geo_country` is filled whenever Envoy answers the request itself, not only on RBAC denials: the HU control request answered by the oauth2 redirect also logged `HU`. Requests forwarded upstream log it empty, because the router strips the header.
- [observation] First ~1h: 286 allowed, 5 denied (all from the e2e test), GeoIP database hits = lookups (no misses).
- [open] **Parallel run (step 6):** a few weeks with Cloudflare in front; expected geo denials ≈ 0. Then move this note to progress/.
