---
title: networking
type: area_reference
permalink: home-ops/docs/areas/networking
area: networking
status: current
confidence: high
verified_at: '2026-08-15'
summary: Gateway API with Envoy Gateway provides cluster ingress, split across two
  shared entrypoints (envoy-external for Cloudflare Tunnel public traffic, envoy-internal
  for LAN traffic on a Cilium L2-announced VIP). Single HTTPS listener per Gateway
  (named `https`), SNI-restricted to `*.${PUBLIC_DOMAIN}` — the apex stays at an
  external provider and never enters the cluster. cloudflared ingress mirrors that
  scope (only the wildcard rule plus a 404 catch-all). ClientTrafficPolicy is
  per-gateway — external derives the client IP from XFF trusted to the pod CIDR, internal
  rejects client-supplied XFF (numTrustedHops=0). HTTP/3 enabled internal-only
  (CF Tunnel cannot relay QUIC to origin). Baseline security response headers
  (HSTS, nosniff, Referrer-Policy) set natively via lateResponseHeaders. Per-EnvoyProxy access
  logs to stdout. Split DNS by k8s-gateway (LAN) and ExternalDNS (public).
verified_against:
- kubernetes/apps/networking/envoy-gateway/config/gateway-internal.yaml
- kubernetes/apps/networking/envoy-gateway/config/gateway-external.yaml
- kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml
- kubernetes/apps/networking/envoy-gateway/config/validatingadmissionpolicy.yaml
- kubernetes/flux/cluster/ks.yaml
- kubernetes/apps/networking/envoy-gateway/config/envoy.yaml
- kubernetes/apps/networking/envoy-gateway/config/ciliumnetworkpolicy-external.yaml
- kubernetes/apps/networking/envoy-gateway/config/ciliumnetworkpolicy-internal.yaml
- kubernetes/apps/networking/k8s-gateway/app/helmrelease.yaml
- kubernetes/apps/networking/cloudflare-tunnel/app/helmrelease.yaml
- kubernetes/apps/networking/cloudflare-tunnel/app/ciliumnetworkpolicy.yaml
- kubernetes/apps/networking/cloudflare-tunnel/app/ciliumcidrgroup.yaml
- kubernetes/apps/networking/external-dns/app/ciliumnetworkpolicy.yaml
- kubernetes/apps/kube-system/cilium/config/pool.yaml
- kubernetes/apps/kube-system/cilium/netpols/
- kubernetes/apps/networking/CLAUDE.md
- kubernetes/apps/networking/envoy-gateway/ks.yaml
- kubernetes/apps/networking/envoy-gateway/app/helmrelease.yaml
- kubernetes/apps/networking/envoy-gateway/app/ocirepository.yaml
- kubernetes/apps/networking/envoy-gateway/certificate/certificate.yaml
- kubernetes/apps/networking/envoy-gateway/config/kustomization.yaml
- kubernetes/apps/networking/envoy-gateway/config/observability.yaml
- kubernetes/apps/networking/envoy-gateway/config/prometheusrule.yaml
- kubernetes/apps/networking/envoy-gateway/config/prometheusrule_test.yaml
- kubernetes/apps/networking/external-dns/app/helmrelease.yaml
- kubernetes/apps/kube-system/cilium/config/l2-announcement-policy.yaml
- kubernetes/apps/kube-system/cilium/netpols/kustomization.yaml
- kubernetes/components/common/vars/cluster-settings.yaml
- kubernetes/components/gateway-oidc/securitypolicy.yaml
- kubernetes/apps/crowdsec/crowdsec-bouncer/app/helmrelease.yaml
drift_risk: 'HSTS includeSubDomains with 2-year max-age is a one-way commitment —
  any future HTTP-only subdomain under PUBLIC_DOMAIN would be blocked from cached
  browsers; preload deliberately omitted. The listener hostname filter is
  `*.${PUBLIC_DOMAIN}` (single-label wildcard), which matches every current
  HTTPRoute hostname — adding a route with a multi-label hostname (e.g.
  foo.bar.${PUBLIC_DOMAIN}) or the bare apex would fail with NoMatchingParent
  until either the listener pattern is extended or the route hostname adjusted.
  Apex `${PUBLIC_DOMAIN}` DNS points straight at the external website provider
  (Hetzner A/AAAA, proxied=false) — moving the apex into the cluster would
  require DNS rewrite, an apex HTTPRoute, and either widening or splitting the
  listener hostname filter. rate-limit-external BackendTrafficPolicy still
  disabled (envoy-gateway v1.8.0/v1.8.1 CRD regression, fix #8798 merged to main
  but not cherry-picked to release/v1.8) — Cloudflare WAF covers external rate
  limiting in the meantime. The envoy v1.39.0 image tag is hardcoded in
  EnvoyProxy spec, not chart-managed. EnvoyPatchPolicy listener naming uses the
  EG IR format gateway-namespace/gateway-name/listener-name (single `https`,
  plus `https-quic` on internal).'
---

# networking — current state

## Metadata (observation-form, schema validation)

- [area] networking
- [status] current
- [confidence] high
- [verified_at] 2026-08-15

## Summary

Gateway API with Envoy Gateway provides cluster ingress, split across two shared entrypoints:
`envoy-external` for Cloudflare Tunnel public traffic (ClusterIP-only Service) and
`envoy-internal` for LAN traffic (Cilium L2-announced LoadBalancer VIP, RFC1918-restricted).
Each Gateway exposes a single HTTP/80 listener (Same-namespace routes only, serving
the shared https-redirect) and a single HTTPS/443 listener named `https`
(All-namespace routes, SNI-restricted to `*.${PUBLIC_DOMAIN}`). The wildcard
filter keeps the listener name stable (HTTPRoutes attach via `sectionName: https`
unchanged) while binding route attachment and TLS SNI to the cert SAN list —
HTTPRoutes with a hostname outside the wildcard pattern (apex, multi-label,
unrelated domain) are rejected with `NoMatchingParent`. The apex
`${PUBLIC_DOMAIN}` is served by an external provider and intentionally never
reaches the cluster; cloudflared's ingress mirrors that, forwarding only
`*.${PUBLIC_DOMAIN}` to envoy-external and falling through to a 404 catch-all
otherwise.
Per-gateway `ClientTrafficPolicy`: external uses `CF-Connecting-IP` (set authoritatively by
Cloudflare edge, overwritten on every request, `failClosed: false` falls back to TCP
source for non-CF callers), internal sets `numTrustedHops: 0` (LAN-direct, no proxy
in front, client-supplied XFF must not be trusted). HTTP/3 enabled internally only —
cloudflared cannot relay QUIC to the origin, public clients still get HTTP/3 via
Cloudflare's edge. Baseline security response headers (HSTS 2y + includeSubDomains,
X-Content-Type-Options: nosniff, Referrer-Policy: strict-origin-when-cross-origin)
are injected via an inline Lua filter in `EnvoyExtensionPolicy/security-response-headers`;
HSTS and nosniff are gateway-authoritative (`replace`), Referrer-Policy is set
only when absent so apps can supply a stricter value. Split DNS by `k8s-gateway`
(LAN) and ExternalDNS (public Cloudflare). LAN clients reach the same public
hostnames without hairpinning through Cloudflare.
Cluster-wide substitution variables (`${PUBLIC_DOMAIN}`,
`${ENVOY_INTERNAL_IP}`, `${K8S_GATEWAY_IP}`, `${NAS_IP}`, etc.) are defined in the
`cluster-settings` ConfigMap (`kubernetes/components/common/vars/cluster-settings.yaml`)
and injected into every child Kustomization via Flux `postBuild.substituteFrom`.

## Components

- [component] Envoy Gateway controller — GatewayClasses `envoy-external` and `envoy-internal` (kubernetes/apps/networking/envoy-gateway/app/)
- [component] EnvoyProxy/envoy-external — ClusterIP Service, replicas=1, envoy v1.39.0, JSON access log to stdout (envoy.yaml first doc)
- [component] EnvoyProxy/envoy-internal — LoadBalancer Service with externalTrafficPolicy: Local, JSON access log to stdout (envoy.yaml second doc)
- [component] Gateway/envoy-external — HTTP/80 (Same-ns, redirect only) + HTTPS/443 named `https` with hostname filter `*.${PUBLIC_DOMAIN}` (All-ns routes, single-label subdomains only), ExternalDNS target external.${PUBLIC_DOMAIN} (gateway-external.yaml)
- [component] Gateway/envoy-internal — same listener layout as external, LAN VIP pinned to ${ENVOY_INTERNAL_IP} (gateway-internal.yaml)
- [component] BackendTrafficPolicy/envoy — shared compression (Zstd/Brotli/Gzip), retry on reset, circuitBreaker (maxConnections/maxPendingRequests/maxParallelRequests=2048, maxParallelRetries=128), tcpKeepalive, PLUS `rateLimit` (Local, 3000/min per client via two Distinct sourceCIDR rules for 0.0.0.0/0 and ::/0), `responseOverride` (Envoy-local 401 -> inline Hungarian access-denied page) and `timeout.http.requestTimeout: 30m` — EG allows only ONE BTP per Gateway, so everything lands here (gateway-policies.yaml:26-78)
- [component] ClientTrafficPolicy/envoy-external — provider-independent client IP detection: `xForwardedFor.trustedCIDRs: [${POD_CIDR}]` (the cloudflared pod is the only path in per CiliumNetworkPolicy/envoy-external, so trust is anchored on network position, not on a vendor header). Plus `lateResponseHeaders` security headers, `stripTrailingHostDot`, HTTP/2 hardening, TLS 1.3 floor, `requestHeadersReceivedTimeout: 10s` + `tlsHandshakeTimeout: 10s`, no HTTP/3 (gateway-policies.yaml)
- [component] ClientTrafficPolicy/envoy-internal — numTrustedHops=0 (LAN-direct, rejects client-supplied XFF), `lateResponseHeaders` security headers, `stripTrailingHostDot`, HTTP/3 enabled, the same two pre-request timeouts, TLS **1.3** floor since EG v1.9.0 — the 1.2 floor existed only because Envoy's upstream TLS client capped at 1.2, which broke the `SecurityPolicy.oidc` token-exchange hairpin onto this listener; v1.9.0 fixed that cap (gateway-policies.yaml)
- [component] Security response headers — set natively in BOTH ClientTrafficPolicies via `headers.lateResponseHeaders`: HSTS + `x-content-type-options` through `set` (gateway-authoritative), `referrer-policy` through `addIfAbsent` (an app may supply a stricter value). There is NO EnvoyExtensionPolicy any more — the Lua one was removed at the EG v1.9.0 upgrade, together with the bot-user-agent blocklist (gateway-policies.yaml)
- [component] EnvoyPatchPolicy/envoy-external — zstd compressor fine-tuning on networking/envoy-external/https (no -quic, HTTP/3 disabled here) (gateway-policies.yaml)
- [component] EnvoyPatchPolicy/envoy-internal — zstd compressor fine-tuning on networking/envoy-internal/{https,https-quic} (gateway-policies.yaml)
- [component] SecurityPolicy/envoy-internal-rfc1918 — TWO features: (1) `authorization` with defaultAction Deny and allow 10.0.0.0/8 + 172.16.0.0/12 + 192.168.0.0/16, (2) `extAuth` to the CrowdSec gRPC bouncer with `failOpen: false` and `statusOnError: 503` (gateway-policies.yaml:257-266)
- [component] HTTPRoute/https-redirect — shared HTTP→HTTPS 301 redirect, attached to both Gateways at sectionName=http (gateway-policies.yaml)
- [component] CiliumNetworkPolicy/envoy-external — ingress allowed only from cloudflare-tunnel pod (10080/10443 TCP) + prometheus + kubelet probe (ciliumnetworkpolicy-external.yaml)
- [component] CiliumNetworkPolicy/envoy-internal — ingress restricted to RFC1918 fromCIDR + cluster/host/remote-node entities on data ports, prometheus + kubelet separately (ciliumnetworkpolicy-internal.yaml)
- [component] cloudflare-tunnel — single ingress rule forwarding `*.${PUBLIC_DOMAIN}` (originServerName=external.${PUBLIC_DOMAIN}) to envoy-external, plus a `http_status:404` catch-all. Apex is intentionally not handled — its DNS points at the external website provider. (kubernetes/apps/networking/cloudflare-tunnel/)
- [component] external-dns — manages public Cloudflare DNS records from Gateway/HTTPRoute sources (kubernetes/apps/networking/external-dns/)
- [component] k8s-gateway — LAN split-DNS for ${PUBLIC_DOMAIN}, watches HTTPRoutes filtered to GatewayClass envoy-internal, LAN VIP ${K8S_GATEWAY_IP} (k8s-gateway/app/helmrelease.yaml)
- [component] CiliumLoadBalancerIPPool/default — LAN VIP allocation range ${LB_IP_POOL_START}–${LB_IP_POOL_STOP} (kube-system/cilium/config/pool.yaml)
- [component] CiliumL2AnnouncementPolicy — L2 announcement for the pool (kube-system/cilium/config/l2-announcement-policy.yaml)
- [component] CiliumClusterwideNetworkPolicy baseline (AD-023 two-tier model; V3 flip landed in commit 953626966) — **8 CCNPs** in kube-system/cilium/netpols/: allow-cluster-egress (flipped — toEndpoints {} + toEntities: cluster + toEntities: kube-apiserver; public internet no longer in baseline), allow-dns-egress (L7 DNS proxy), allow-gateways-egress (NEW — lets `custom-egress` pods reach cluster services through their PUBLIC hostnames, canonically the OIDC token-exchange hairpin), allow-world-egress (toCIDRSet 0.0.0.0/0 except RFC1918/100.64/10 — gated by the `egress.home.arpa/allow-world` label AND, in a second spec, granted namespace-wide to `flux-system` + `cert-manager` via matchExpressions, because their vendored controller pods are not naturally labelable), ingress-from-gateway-external, ingress-from-gateway-internal (the former single `ingress-from-gateways` SPLIT into one CCNP per gateway), ingress-from-prometheus, ingress-none. **7-label dictionary**: egress.home.arpa/{custom-egress,allow-world,allow-gateways} + ingress.home.arpa/{allow-gateway-external,allow-gateway-internal,allow-prometheus,none}. Per-app CNPs cover app-unique needs the flipped baseline does not grant — e.g. kube-prometheus-stack-prometheus LAN 192.168.1.1/32:9100 (kubernetes/apps/observability/kube-prometheus-stack/app/ciliumnetworkpolicy.yaml) plus AD-023 V5 narrow-world CNPs (external-dns, tuppr, victoria-logs, grafana, paperless-gpt). NOTE: the former coredns world:53 CNP was REMOVED 2026-07-11 (inert — the baseline covers the host-DNS forward; see the 2026-07-11 Update).

## Claims (verified against repo)
- [claim] "The wildcard HTTPS listener's All-namespace attachment (allowedRoutes.from: All) is mitigated by a ValidatingAdmissionPolicy (native kube-apiserver CEL, no Kyverno) in envoy-gateway/config/validatingadmissionpolicy.yaml: only the security namespace may claim idm.${PUBLIC_DOMAIN}, and non-security namespaces may not claim a wildcard hostname (a *.${PUBLIC_DOMAIN} claim would cover idm and every other app). Hostname-scoped guard against route-collision / WebAuthn-origin-binding hijack of the IdP plane — closes the gap that the shared wildcard cert would otherwise present the same browser origin as Kanidm." (evidence: repo, ref: validatingadmissionpolicy.yaml, verified: 2026-07-20)

- [claim] "envoy-internal Gateway is pinned to LAN VIP ${ENVOY_INTERNAL_IP} via lbipam.cilium.io/ips annotation" (evidence: repo, ref: gateway-internal.yaml, verified: 2026-06-14)
- [claim] "k8s-gateway Service is pinned to LAN VIP ${K8S_GATEWAY_IP} via loadBalancerIP chart value" (evidence: repo, ref: k8s-gateway/app/helmrelease.yaml:32, verified: 2026-05-19)
- [claim] "LAN VIPs allocated from CiliumLoadBalancerIPPool/default with range ${LB_IP_POOL_START}–${LB_IP_POOL_STOP} inclusive" (evidence: repo, ref: cilium/config/pool.yaml:7-11, verified: 2026-05-19)
- [claim] "envoy-internal Service is type LoadBalancer with externalTrafficPolicy: Local" (evidence: repo, ref: envoy.yaml, verified: 2026-06-14)
- [claim] "envoy-external Service is type ClusterIP — public reach is via Cloudflare Tunnel only" (evidence: repo, ref: envoy.yaml, verified: 2026-06-14)
- [claim] "envoy-internal is protected by SecurityPolicy/envoy-internal-rfc1918 with defaultAction=Deny and clientCIDRs allowlist of all three RFC1918 ranges" (evidence: repo, ref: gateway-policies.yaml, verified: 2026-06-14)
- [claim] "Shared HTTPRoute/https-redirect issues a 301 HTTP→HTTPS redirect and attaches via parentRefs to both Gateways at sectionName: http" (evidence: repo, ref: gateway-policies.yaml, verified: 2026-06-14)
- [claim] "Each Gateway exposes a single HTTPS/443 listener named `https` with hostname filter `*.${PUBLIC_DOMAIN}` (All-namespace route attach, single-label subdomains only) plus a HTTP/80 listener restricted to local-namespace routes that only attaches the shared https-redirect. HTTPRoutes outside the wildcard pattern are rejected with NoMatchingParent at attach time." (evidence: repo, ref: gateway-external.yaml + gateway-internal.yaml, verified: 2026-06-14)
- [claim] "cloudflared ingress contains a single rule forwarding `*.${PUBLIC_DOMAIN}` (originServerName=external.${PUBLIC_DOMAIN}) to envoy-external, plus a final http_status:404 catch-all — the apex is served entirely by an external provider (Hetzner A/AAAA, proxied=false) and never enters the tunnel." (evidence: repo, ref: cloudflare-tunnel/app/helmrelease.yaml + provision/cloudflare/dns_records.tf, verified: 2026-06-14)
- [claim] "cloudflare-tunnel runs a dedicated custom-egress CiliumNetworkPolicy (AD-023 opt-out) as its sole egress source: CoreDNS 53/UDP, envoy-external 10080/10443 TCP, Cloudflare edge (CIDRGroup `cloudflare`) 80/443/7844 TCP+UDP, plus ICMP echo+unreachable to the Cloudflare edge (cloudflared ICMP-proxy + QUIC control path) and unrestricted egress to the Cloudflare public resolvers 1.1.1.1/1.0.0.1 for the remote connectivity diagnostic (traceroute). The ICMP + resolver grants are not tunnel-function-critical (QUIC/H2 prechecks pass without them) — they exist solely to clear recurring HubblePolicyDeny drops." (evidence: repo, ref: cloudflare-tunnel/app/ciliumnetworkpolicy.yaml + ciliumcidrgroup.yaml, verified: 2026-07-10)
- [claim] "ClientTrafficPolicy is per-gateway: envoy-external uses CF-Connecting-IP customHeader (failClosed=false), envoy-internal uses numTrustedHops=0 and enables HTTP/3" (evidence: repo, ref: gateway-policies.yaml, verified: 2026-06-14)
- [claim] "Both EnvoyProxy resources emit JSON access logs to /dev/stdout, picked up by the cluster log pipeline" (evidence: repo, ref: envoy.yaml, verified: 2026-06-14)
- [claim] "BackendTrafficPolicy/envoy declares circuitBreaker thresholds (2048 for connections/pending/parallel, 128 for retries) so a misbehaving backend cannot exhaust envoy worker capacity" (evidence: repo, ref: gateway-policies.yaml, verified: 2026-06-14)
- [claim] "EnvoyExtensionPolicy/security-response-headers injects HSTS + X-Content-Type-Options (replace) and Referrer-Policy (add-if-absent) on every response via inline Lua, targets both Gateways" (evidence: repo, ref: security-headers.yaml, verified: 2026-06-14)
- [claim] "CiliumNetworkPolicy/envoy-internal restricts ingress on data ports to RFC1918 fromCIDR plus cluster/host/remote-node entities — defense-in-depth behind SecurityPolicy/envoy-internal-rfc1918" (evidence: repo, ref: ciliumnetworkpolicy-internal.yaml, verified: 2026-06-14)
- [claim] "k8s-gateway watches HTTPRoute resources filtered to GatewayClass envoy-internal" (evidence: repo, ref: k8s-gateway/app/helmrelease.yaml:23-27, verified: 2026-05-19)
- [claim] "Public domain managed by this stack is ${PUBLIC_DOMAIN} (from cluster-settings ConfigMap); ExternalDNS target on Gateway/envoy-external is external.${PUBLIC_DOMAIN}" (evidence: repo, ref: gateway-external.yaml + k8s-gateway/app/helmrelease.yaml:13, verified: 2026-06-14)
- [claim] "Cilium baseline (AD-023 V3+) is 8 CCNPs in kube-system/cilium/netpols/: allow-cluster-egress (flipped — toEndpoints {} + cluster + kube-apiserver, no toEntities: world), allow-dns-egress (L7 DNS proxy), allow-gateways-egress (custom-egress pods reaching cluster services via public hostnames), allow-world-egress (toCIDRSet 0.0.0.0/0 except RFC1918/100.64/10, gated by egress.home.arpa/allow-world plus a namespace-wide spec for flux-system + cert-manager), ingress-from-gateway-external, ingress-from-gateway-internal, ingress-from-prometheus, ingress-none. The label dictionary is 7, not 5" (evidence: repo, ref: kube-system/cilium/netpols/kustomization.yaml:5-13 + the individual files, verified: 2026-08-03)
- [claim] "envoy-gateway is split into three Kustomizations: certificate, app (controller), config" (evidence: repo, ref: kubernetes/apps/networking/envoy-gateway/{certificate,app,config}/, verified: 2026-05-19)

## Drift Risk

- [drift] HSTS includeSubDomains with 2-year max-age is a one-way commitment — once a browser caches it, any future HTTP-only subdomain under ${PUBLIC_DOMAIN} (IoT, legacy tool, dev instance) is unreachable from that browser until the entry expires. `preload` was intentionally omitted to keep this revocable (preload registers the domain with browser vendors and is far harder to unwind). (ref: security-headers.yaml)
- [drift] Listener hostname filter is `*.${PUBLIC_DOMAIN}` (single-label wildcard). Adding a multi-label hostname HTTPRoute (e.g. `foo.bar.${PUBLIC_DOMAIN}`) or an apex route would fail NoMatchingParent — either widen the listener pattern (split apex+wildcard with HTTPRoute parentRef migration) or adjust the route hostname. The hostname split was attempted in commit 6e890d8f7 and reverted because every HTTPRoute pinned `sectionName: https`; the current setup avoids that by keeping the listener name `https` and only adding the hostname filter. (ref: gateway-external.yaml, gateway-internal.yaml)
- [drift] EnvoyPatchPolicy is a workaround for missing native Zstd compressor fine-tuning options on EnvoyProxy/BackendTrafficPolicy — drop both EnvoyPatchPolicy/envoy-external and envoy-internal when the EnvoyProxy CRD exposes `choose_first` and `remove_accept_encoding_header` on the compressor field. (ref: gateway-policies.yaml)
- [drift] rate-limit-external BackendTrafficPolicy still disabled (commented out) — envoy-gateway v1.8.0 CRD regression (envoyproxy/gateway#8798: uint32 Requests field emits format: int32 + maximum: 4294967295, rejected by K8s 1.36 strict OpenAPI validation). The fix is merged to main but not cherry-picked to release/v1.8, so v1.8.1 is still affected. Re-enable when v1.9.0 GA lands or a v1.8.2 patch backport ships, then bump the OCIRepository tag. Cloudflare WAF covers external rate limiting in the meantime. (ref: gateway-policies.yaml)
- [drift] envoy container image tag (v1.39.0) is hardcoded in EnvoyProxy spec rather than chart-managed — track manually via inline `# renovate:` annotation. (ref: envoy.yaml:17)
- [drift] cloudflare-tunnel ICMP egress is scoped to the Cloudflare edge CIDRGroup + 1.1.1.1/1.0.0.1, but cloudflared's ICMP-proxy forwards pings to arbitrary WARP-requested targets — a ping through the tunnel to a non-Cloudflare address would drop and re-trigger HubblePolicyDeny. If that recurs, extend the grant point-wise or disable the ICMP-proxy rather than widening egress broadly. (ref: cloudflare-tunnel/app/ciliumnetworkpolicy.yaml)

## Open Questions / Gaps

- [gap] HTTP/3 client experience on the public path: clients negotiate H/3 with Cloudflare's edge, but the edge→cloudflared→origin leg is HTTP/1.1 or HTTP/2 over TCP. The user-visible H/3 metric (e.g. browser-side QUIC negotiation rate) is not surfaced by repo telemetry — it would live on Cloudflare's side.
- [gap] Router-side requirements (conditional forward ${PUBLIC_DOMAIN} → ${K8S_GATEWAY_IP}, DNS rebind allowance) live outside repo — operationally documented in source readme but not reproducible from manifests alone; intent-class claim.
- [gap] Live cluster verification: claims marked 2026-06-14 are based on repo state plus a server-side dry-run of the kustomize build; the CTP split, EEP/security-response-headers, accessLog, circuitBreaker, and RFC1918 CNP tighten are reconciled and active. The access-log pipeline ingestion end-to-end is not yet asserted here.

## Relations

- depends_on [[cilium-lb-ipam]]
- depends_on [[cloudflare]]
- relates_to [[external-secrets]]
- part_of [[home-ops-platform]]
- supersedes [[networking-readme]]

## LAN Split-DNS & Edge Bypass (operational, router side)

The LAN path to public hostnames depends on router-side configuration that lives outside the cluster (managed in the private OpenWRT provisioning repo). Durable requirements:

- [claim] "The router DNS must conditionally forward ${PUBLIC_DOMAIN} to the k8s-gateway VIP ${K8S_GATEWAY_IP}, so LAN clients resolve the internal Envoy VIP instead of hairpinning through Cloudflare" (evidence: behavior, ref: migrated from kubernetes/apps/networking/README.md, verified: 2026-06-20)
- [claim] "The router must allow DNS rebinding for ${PUBLIC_DOMAIN}; otherwise RFC1918 answers (e.g. ${ENVOY_INTERNAL_IP}) returned by k8s-gateway may be dropped or rewritten" (evidence: behavior, ref: migrated from networking/README.md, verified: 2026-06-20)
- [claim] "An app is reachable directly from the LAN only if its HTTPRoute attaches to envoy-internal; dual attachment is the default, while envoy-external-only routes (e.g. flux-webhook) are intentionally internet-only" (evidence: repo, ref: networking route model, verified: 2026-06-20)

Edge bypass checklist — the public/internal separation can be silently defeated at the router/edge. When auditing exposure, check for:

- [drift] port forwards or DMZ rules pointing at the Envoy VIPs or the node IP
- [drift] UPnP / NAT-PMP opening inbound ports automatically
- [drift] router DNS rebinding protection blocking ${PUBLIC_DOMAIN} from resolving to the internal VIP

(Migrated 2026-06-20 from kubernetes/apps/networking/README.md, which hardcoded the public domain and LAN IPs in violation of the repo non-negotiables; replaced here with cluster-settings variables.)


## Update — 2026-07-11: AD-023 V5 CNP changes (coredns CNP removed; per-app narrow-world CNPs)

- [observation] **coredns per-app CNP REMOVED** (V5k, @6b621c68b + a one-time manual `kubectl delete` — the coredns ks is `prune: false`). Its only rule was `toEntities: world :53`, which was never the enforcement point: Talos `hostDNS.forwardKubeDNSToHost: true` makes coredns forward `.` to the host DNS on the node (→ `kube-apiserver` identity on the single node, already covered by the allow-cluster-egress baseline), and the rev4 split-horizon `${PUBLIC_DOMAIN}`→`${K8S_GATEWAY_IP}` forward is socket-LB DNAT'd to the in-cluster k8s-gateway pod:1053 (covered by baseline `toEndpoints`). Verified live: internal/external/split-horizon DNS resolve with zero coredns DROPPED.
- [observation] **external-dns per-app CNP added** (V5h, @df71cdef5): dropped `egress.home.arpa/allow-world` → `egress.home.arpa/custom-egress` + `ingress.home.arpa/prometheus`; the per-app CNP is the sole egress source — `toFQDNs api.cloudflare.com:443` (DNS record sync) + `toEntities kube-apiserver:6443` (watches Ingress/HTTPRoute/Gateway sources). (`kubernetes/apps/networking/external-dns/app/ciliumnetworkpolicy.yaml`)
- [observation] Other AD-023 V5 narrow-world per-app CNPs landed cluster-wide (not all under networking): tuppr (factory.talos.dev + apiserver/Talos-apid), victoria-logs server (DNS-only sink + closed ingress), grafana, paperless-gpt, plex-trakt-sync, calibre-web-automated. The `ingress.home.arpa/gateways` label gained users (e.g. victoria-logs server); the (m) split into `gateways-external`/`gateways-internal` **has since LANDED** (see the 2026-08-03 update) — two CCNPs now, `ingress-from-gateway-external` and `ingress-from-gateway-internal`, each with its own label.
- [observation] DNS-exfil detection (V5l): the Cilium Hubble `dns` metric gained `labelsContext=source_*` and a `HubbleDNSExfilSuspected` PrometheusRule was added — details in [[observability]].

See [[cnp-per-app-audit]] (progress) Sessions 16–21 for the execution log.
## Update — 2026-07-26: EG one-per-target policy exclusivity — BTP and EEP merges

- [observation] **EG exclusivity rule (load-bearing)**: one BackendTrafficPolicy and one EnvoyExtensionPolicy may attach per Gateway target. A second is rejected as `Conflicted` (neither attaches — the failure is silent at the route level, no traffic error). This was the root cause of two pre-existing silent failures, both fixed today by merging features into the already-Accepted gateway-scoped policies instead of adding siblings.
- [observation] **BackendTrafficPolicy merged**: the standalone `rate-limit` BTP and the standalone `oidc-error-page` BTP were both `Conflicted` on both gateways (the `envoy` BTP owned the targets). Merged `rateLimit` (Local 600/min) and `responseOverride` (source:Local 401 → friendly Hungarian access-denied page; an inline JS recovers `error_description` from the callback URL — EG can't surface it server-side, and the gateway sets no CSP so the script runs) into the `envoy` BTP in gateway-policies.yaml. Dropped both standalone BTP docs. The `envoy` BTP is now `Accepted=True` on both gateways.
- [observation] **EnvoyExtensionPolicy merged**: the standalone `envoy-external` EEP (bot user-agent block via the `envoy-external-extensions` ConfigMap, `envoy_on_request`) was `Conflicted` on `envoy-external` since 2026-06-14 (the `security-response-headers` EEP owned both gateways). Merged the ConfigMap `valueRef` into the `security-response-headers` EEP `lua` list as a second entry; `envoy_on_request` runs the block, `envoy_on_response` runs the security headers. The block now applies to both gateways — no-op on `envoy-internal` (LAN-only, RFC1918-gated, no real client sends these UAs). Dropped the standalone `envoy-external` EEP.
- [observation] **Correction to the 2026-07-20 drift_risk**: the `rate-limit-external BackendTrafficPolicy still disabled (commented out) — CRD regression #8798` note is superseded. The rate-limit is no longer a standalone BTP and no longer commented out — it lives in the `envoy` BTP and is `Accepted=True` at EG v1.8.3 (the uint32/int32 regression does not block Local rateLimit acceptance on this version). Re-evaluate only if a future EG upgrade regresses.
- [guardrail] **Durable rule recorded in `kubernetes/apps/networking/CLAUDE.md` (Envoy Gateway Conventions)**: one BTP and one EEP per Gateway target — extend the existing `envoy` BTP / `security-response-headers` EEP, don't create a sibling; after any gateway-policy change, verify the live policy is `Accepted=True`, not `Conflicted`.
- [gap] **Automated guard still missing**: a ValidatingAdmissionPolicy (native CEL, like the existing `envoy-gateway/config/validatingadmissionpolicy.yaml` for hostname claims) that rejects create/update of a BTP or EEP targeting a Gateway that already has one attached would prevent this class of silent failure before it reaches the cluster. Tracked as a follow-up — not yet implemented.

See commits `4b4c36e66` (BTP merge) and `7e1e76000` (EEP merge) on main.

## Update — 2026-07-28: SecurityPolicy parent-child merging + CrowdSec ext_authz on both gateways

Companion to the 2026-07-26 exclusivity note. That one covers **same-level** conflicts (two
BTPs/EEPs on one target → `Conflicted`, neither attaches). This is the **parent-child** case,
which fails differently and more quietly: the child wins and the parent silently stops
applying.

- [observation] **EG parent-child rule (load-bearing)**: a route-level SecurityPolicy without
  `mergeType` does not combine with the Gateway-level one — it *replaces* it for that route.
  CRD, verbatim: *"MergeType determines how this configuration is merged with existing
  SecurityPolicy configurations targeting a parent resource. … If unset, no merging occurs,
  and only the most specific configuration takes effect."* The parent then reports
  `Overridden=True` listing the routes. Unlike `Conflicted`, the child keeps working, so the
  loss is invisible from the app side.
- [observation] **Pre-existing silent gap, found by attaching CrowdSec**: every
  `components/gateway-oidc` consumer set no `mergeType`, so
  `SecurityPolicy/envoy-internal-rfc1918` had **never applied to any OIDC-gated route** —
  downloads/{bazarr,maintainerr,prowlarr,qbittorrent,radarr,seerr,sonarr,subsyncarr},
  kube-system/hubble-ui, networking/echo-server. Not exploitable in practice (envoy-internal
  is only reachable on the LAN VIP, and `CiliumNetworkPolicy/envoy-internal` enforces RFC1918
  independently at L3), but the policy did not do what its name implies.
- [observation] **Correction to the Claim** *"envoy-internal is protected by
  SecurityPolicy/envoy-internal-rfc1918 with defaultAction=Deny and clientCIDRs allowlist of
  all three RFC1918 ranges"* (verified 2026-06-14): true for the Gateway, but until
  2026-07-28 it excluded the ten OIDC-gated routes above. Now accurate for all routes.
- [observation] **Fix**: `mergeType: StrategicMerge` added to
  `kubernetes/components/gateway-oidc/securitypolicy.yaml` — one line in the shared component,
  closing the RFC1918 gap and extending the CrowdSec gate to those routes at once. Verified
  live: the condition flipped `Overridden=True` → `Merged=True` for all ten, and the OIDC flow
  still redirects to `idm.${PUBLIC_DOMAIN}/authorize` with a PKCE `code_challenge`.
- [observation] **`bodyToExtAuth` is unusable on these gateways.** CRD, verbatim: *"Envoy will
  return HTTP 413 and will not initiate the authorization process when buffer reaches the
  number set in this field. Note that this setting will have precedence over failOpen mode."*
  There is no partial-message option in the EG API, so the cap is a hard ceiling on every
  request body. Measured live with `maxRequestBytes: 65536`: a 1KB POST to grafana returned
  401, a 133KB POST returned **413**. That silently capped every upload path on
  envoy-internal (pingvin-share, paperless, calibre, grafana dashboard import) for the ~20
  minutes it was live. Removed from both policies; the WAF keeps URL/query/path/header
  coverage.
- [component] **SecurityPolicy/envoy-internal-rfc1918 now carries two features**: the existing
  `authorization` (defaultAction Deny + RFC1918 allowlist) **and** `extAuth` (CrowdSec gRPC
  bouncer, `failOpen: false`, `statusOnError: 503`, no `bodyToExtAuth`). Merged into one
  object on purpose — a second Gateway-level SecurityPolicy on the same target would lose the
  same-level contest and sit inert. (gateway-policies.yaml)
- [component] **SecurityPolicy/envoy-external-crowdsec** — new, standalone, correct here
  because envoy-external carries no other Gateway-level SecurityPolicy to merge into. Same
  extAuth shape. Covers the Pocket ID login page, which has no route-level gate by nature.
  (gateway-policies.yaml)
- [observation] The bouncer Service lives in the `crowdsec` namespace; the cross-namespace
  `backendRefs` is permitted by a `ReferenceGrant` in `crowdsec` (`from: SecurityPolicy in
  networking`), created by the bouncer chart.
- [observation] **Fail-closed SPOF, accepted**: single bouncer replica, `failOpen: false`, so
  its outage 5xx-es every route on both gateways. `statusOnError: 503` keeps that
  distinguishable from a real 403 ban. The `CrowdSecBouncerDown` PrometheusRule (critical,
  2m) is the compensating control; rollback is deleting the `extAuth` block from the affected
  policy.
- [observation] Live after both stages: `bouncer_requests_total{action="allow"}` 3835 with
  **zero bans**, `bouncer_waf_errors_total` 0, `bouncer_decision_cache_size{origin="CAPI"}`
  ~15000. Client IP comes from `trustedIPHeader: X-Envoy-External-Address`, i.e. the value the
  existing ClientTrafficPolicies already resolve (CF-Connecting-IP externally, TCP source on
  the LAN gateway) — no XFF walking, no proxy CIDR list to maintain.
- [guardrail] Recorded in `kubernetes/apps/networking/CLAUDE.md`: a route-level SecurityPolicy
  needs `mergeType` or it silently drops the Gateway-level policy for that route; and
  `bodyToExtAuth` 413s any body over the cap.
- [gap] The 2026-07-26 follow-up still stands and now covers a third case: a
  ValidatingAdmissionPolicy could also reject a route-level SecurityPolicy that lacks
  `mergeType` while a Gateway-level policy exists on its parent. Not implemented.

See commits `50814b79b` (stage 1), `6d2c00f98` (413 fix), `ee0990fd3` (mergeType + stage 2)
on main, and [[envoy-crowdsec-bouncer]] (progress) Session 3 for the execution log.

## Update — 2026-07-28: gateway rate limit was one shared bucket per route

Found while investigating 429s on the photo gallery; unrelated to CrowdSec except that the
CrowdSec rollout is what makes the blunt limit less load-bearing.

- [observation] The `envoy` BTP's Local rate limit rule carried no `clientSelectors`, and the
  CRD's `shared` field defaults to false — *"If set to true, the rule is treated as a common
  bucket and is shared across all policy targets (xRoutes)"*. So it was **one 600/min bucket
  per route, shared by every client of that route**, not a per-client limit. One active
  visitor could 429 everyone else on the same route.
- [evidence] Live VictoriaLogs over 14 days: **2260 of 4740 requests to
  `photos.${PUBLIC_DOMAIN}` returned 429** (48%), every one of them an
  `image-preview-{320,480,640}.jpg` thumbnail.
- [evidence] Measured per-minute peaks: photos **1600 from a single client**, idm 914 (split
  across its two routes, hence no 429), books 576, recipes 479. So 600 was marginal for
  several routes, not just photos — books sat at 96% of the limit.
- [observation] The heaviest client is **IPv6** (`2a00:1110:…`). Relevant because a
  `sourceCIDR: 0.0.0.0/0` selector matches no IPv6 client, and a non-matching rule means no
  limit at all — an IPv4-only fix would have silently exempted exactly the client that
  triggered the investigation.
- [decision] Two `Distinct` source-CIDR rules (`0.0.0.0/0` and `::/0`) at 3000/min: per-client
  buckets, ~2x the observed legitimate peak, still bounding one abuser to 50 req/s. Rules are
  mutually exclusive by address family; the CRD resolves multi-rule matches by strictest
  limit, so the pair is safe.
- [observation] The role of this limit has shrunk: behavioural abuse detection is now
  CrowdSec's (`http-probing`, `http-crawl-non_statics`, plus the CAPI blocklist), with
  Cloudflare WAF in front of the public path. It only has to be a volumetric backstop.
- [gap] **home-gallery barely caches**: 2431 × 200 against 46 × 304 over the same window, and
  a single browser re-fetched 1600 thumbnails in one minute. Raising the limit hides this;
  the root cause is response caching on the app side (`Cache-Control` on `/files/**`
  previews, which are content-addressed and therefore immutable). Not a gateway-policy
  question — tracked as a follow-up, not implemented.

See commit `fc222f988` on main.
## Update — 2026-07-28: CrowdSec/envoy down alerts fixed (absent + count)

The `CrowdSecBouncerDown` rule referenced above as the fail-closed SPOF's
compensating control was itself broken: `up{...} == 0` only fires when a
scrape ran and failed, but scale-to-0 / crashloop / a readiness-split pod
drops the target from the scrape pool and the `up` series vanishes, so the
alert never fired for the common outage shapes. Verified live 2026-07-28:
with the bouncer deployment scaled to 0, `up{job="crowdsec-bouncer"} == 0`
returned an empty vector while `absent(up{job="crowdsec-bouncer"})` returned
1. Fix: `up{...} == 0 or absent(up{...})` on both `CrowdSecBouncerDown`
(`for: 2m`) and `CrowdSecLAPIDown` (`for: 5m`). End-to-end test the same
day: scaled both crowdsec deployments to 0, `CrowdSecBouncerDown` went
pending→firing via the absent branch and reached Alertmanager
`state=active` → Pushover (severity=critical route, `group_wait: 1m`);
`CrowdSecLAPIDown` fired likewise. Restored, both cleared (`send_resolved`).

- [component] **EnvoyProxyDown** PrometheusRule (new, `networking` ns,
  `envoy-gateway/config/prometheusrule.yaml`): the envoy proxies are the
  data plane — envoy-external (public) and envoy-internal (LAN), one replica
  each, sharing one PodMonitor job `networking/envoy-proxy`. Either down
  kills its path; both down kills all ingress (same blast-radius class as the
  bouncer SPOF). The single-target `up == 0 or absent()` shape would miss
  one proxy vanishing (absent needs every series gone), so the expr is
  `count(up{job="networking/envoy-proxy",namespace="networking"} == 1) < 2`,
  covering one-down, both-down, scrape failure, and all-vanished; `for: 2m`
  skips a rolling-update blip on the single replica. The envoy-gateway
  controller (control plane, job `envoy-gateway`) is a separate
  ServiceMonitor and is not covered by this alert.
- [observation] CNP isolation for the crowdsec namespace verified live
  (Hubble, 2026-07-28): engine ingress only from bouncer/web-ui/prometheus +
  kubelet health-probe (Cilium `enableEndpointHealthChecking` bypasses
  policy, which is why the CNP need not list probes); bouncer ingress only
  from the two envoy proxies + prometheus + kubelet; egress is in-cluster
  (victoria-logs:9428 via the `allow-cluster-egress` CCNP baseline) plus
  `crowdsec.net:443` (hub/CAPI/mmdb via the per-app CNP) — no world egress.
- [observation] Commits on main: `be6982769` (crowdsec alert absent fix),
  `572d4787f` (EnvoyProxyDown rule). See [[envoy-crowdsec-bouncer]]
  (progress) Session 4 for the alert test log and self-ban cleanup.

## Update 2026-08-03 — staleness re-verification

Full re-verification against the live repo as part of the `area-reference-staleness-audit`
roadmap item. Previous `verified_at` was 2026-07-28 (six days old); the body Metadata block still
said 2026-07-11. Verdict: MINOR-DRIFT — 26 claims held and all 16 `verified_against` paths still
existed, but the drift that DID exist was in the security model, so it matters more than the count.

- [correction] **The Cilium baseline is 8 CCNPs, not 6, and the label dictionary is 7, not 5.**
  `ingress-from-gateways` SPLIT into `ingress-from-gateway-external` and
  `ingress-from-gateway-internal`, each with its own label — the note recorded that split as "still
  pending" in its 2026-07-11 update. A new `allow-gateways-egress` CCNP also appeared, granting
  `custom-egress` pods access to cluster services through their PUBLIC hostnames (the OIDC
  token-exchange hairpin). Anyone labelling a new pod from this note would have used the retired
  `ingress.home.arpa/gateways` label and got no policy at all.
- [correction] `allow-world-egress` gained a SECOND spec granting world egress namespace-wide to
  `flux-system` and `cert-manager` via matchExpressions, because their vendored controller pods are
  not naturally labelable. That is a real widening of the world-egress surface beyond the
  label-gated model the note described, and it was undocumented.
- [correction] The internal ClientTrafficPolicy TLS floor is **1.2, not 1.3**. The manifest comment
  records why: the `SecurityPolicy.oidc` token-exchange hairpin lands on this listener and Envoy's
  upstream TLS client caps at 1.2 (EG sets no `tls_params` on the cluster). A deliberate, documented
  concession — but the note asserted the stricter value, which would make a reviewer "fix" it.
- [correction] envoy image is `v1.39.0`, not `v1.38.2` (three places in the note).
- [correction] `${TIMEZONE}` was listed as a cluster-settings substitution variable. It does not
  exist — k8tz owns timezone. Same defect as in the flux-gitops note; both are now fixed.
- [correction] Three Components bullets had gone stale against their own later Update sections: the
  `envoy` BTP also carries rateLimit + responseOverride + a 30m request timeout, the
  `security-response-headers` EEP has a second lua entry (the bot-user-agent block), and
  `SecurityPolicy/envoy-internal-rfc1918` also carries the CrowdSec `extAuth` gate. The Update
  sections were right; the Components list they superseded was not updated. **That is a structural
  lesson: appending a dated Update without reconciling the Components/Claims sections leaves two
  contradictory answers in one note.**
- [addition] Not covered anywhere: the `headers.earlyRequestHeaders.remove` spoofing guard in both
  ClientTrafficPolicies (strips `Remote-User`/`-Email`/`-Groups`/`-Name`/`-Sub` before route
  matching and auth), the BTP 30m request timeout, and the envoy-gateway Grafana dashboard/folder.


## Update — 2026-08-06: EnvoyProxyDown could not detect total ingress loss (found by a unit test)

Corrects the `[component] EnvoyProxyDown` entry in the "Update — 2026-07-28: CrowdSec/envoy down
alerts fixed (absent + count)" section above. That entry recorded the expression
`count(up{job="networking/envoy-proxy",namespace="networking"} == 1) < 2` as "covering one-down,
both-down, scrape failure, and all-vanished". **The both-down and all-vanished half of that claim was
false**, and the expression has since changed.

- [correction] `count()` over an empty instant vector returns an EMPTY result, not 0. When BOTH proxies
  are down (or every `up` series has vanished — scale-to-0, crashloop, PodMonitor removed), `up == 1`
  selects nothing, so `count(...)` is empty and `< 2` has nothing to compare. The alert therefore fired
  **only when exactly one proxy was up**, and stayed silent in the two worst states: both proxies dead
  (all ingress gone) and all targets vanished. A `critical` alert guarding the entire data plane could
  not detect total ingress loss.
- [fix] Commit `eb60131ad` (branch `test/prometheusrule-unit-test-coverage`):
  `expr: (count(up{job="networking/envoy-proxy", namespace="networking"} == 1) or vector(0)) < 2`.
  `or vector(0)` gives the empty case a 0 to compare, so both-down and all-vanished now fire.
  `vector(0)` carries no labels, which is safe here because this alert's annotations are static.
- [observation] The still-valid part of the original rationale is UNCHANGED and remains the reason for
  the counting shape: envoy-external (Cloudflare Tunnel public) and envoy-internal (LAN) are two
  single-replica proxies sharing ONE PodMonitor job `networking/envoy-proxy`, so a single-target
  `up == 0 or absent()` shape would miss one proxy vanishing — `absent()` only fires once EVERY series
  is gone. Counting `up == 1` against the expected 2 is still correct; it just needed the empty-vector
  guard. `for: 2m` still skips a rolling-update blip.
- [evidence] Found by a promtool unit test, NOT by an incident. Every conventional signal was green:
  `promtool check rules` passed, the rule group loaded, `prometheus_rule_evaluation_failures_total`
  was 0. The alert had simply never fired for those states, so nothing ever exercised them.
- [observation] The same false claim had been recorded in TWO places — this area note and the rule's own
  code comment — each reinforcing the other. Two mutually-confirming sources, both wrong. This is the
  strongest evidence produced by the `prometheusrule-unit-test-coverage` work: manifest review,
  `yamllint`, `kustomize build`, `pre-commit` and `promtool check rules` all pass over a rule that
  cannot do what its documentation says.
- [observation] All four states are now pinned by
  `kubernetes/apps/networking/envoy-gateway/config/prometheusrule_test.yaml` (2-up no-fire, one-down
  fire, both-down fire, all-vanished fire). Reverting the expression makes exactly the both-down and
  all-vanished cases fail — mutation-verified in both directions.

- relates_to [[prometheusrule-unit-test-coverage]]

## Update — 2026-08-15: EG v1.9.0 — Lua removed, provider-independent client IP

- [observation] **Lua is gone from the gateway path.** EG v1.9.0 disables Lua EnvoyExtensionPolicies by default (`extensionApis.enableLua`, with `disableLua` deprecated). Rather than opting back in, both Lua consumers were retired: the bot user-agent blocklist was dropped outright (self-declared UAs are trivially spoofed; CrowdSec's `http-bad-user-agent` scenario covers the impolite crawlers behaviourally), and the security response headers moved to the native `ClientTrafficPolicy.headers.lateResponseHeaders`. `EnvoyExtensionPolicy/security-response-headers`, the `envoy-external-extensions` ConfigMap, `config/resources/block-user-agents.lua` and the scheduled `update-ai-bots` workflow + script are all removed.
- [observation] **`lateResponseHeaders` was available since v1.8.3**, not new in v1.9.0 — the inline Lua had simply outlived the workaround it was written as (its own manifest comment said "v1.8.1 has no native gateway-level response-header injection"). `set` for HSTS + nosniff, `addIfAbsent` for Referrer-Policy, which maps 1:1 onto what the Lua did.
- [observation] **Client IP detection is no longer Cloudflare-specific.** `clientIPDetection.customHeader: CF-Connecting-IP` was replaced by `xForwardedFor.trustedCIDRs: [${POD_CIDR}]`. EG maps this to Envoy's `original_ip_detection.xff` extension with `xff_trusted_cidrs`: the direct peer must be inside a trusted CIDR, then XFF is walked right-to-left and the first untrusted address wins. The trust anchor is now the network position enforced by `CiliumNetworkPolicy/envoy-external` (only the cloudflared pod may reach 10443), so replacing the edge provider is a CIDR change, not a header-name change.
- [evidence] Envoy does **not** append XFF when an original-IP-detection extension is configured (`internal/xds/translator/listener.go`: `originalIPDetectionExtensions != nil → useRemoteAddress = false`). The single-entry `x-forwarded-for` seen in the envoy-external access log therefore comes from Cloudflare, which is what makes the right-to-left walk resolve to the real client. The `xff` extension does its own append unless `disableXForwardedForAppend` is set — deliberately left unset so backends still receive the client IP.
- [decision] **`directSourceIP` (new in v1.9.0) is NOT the provider-independent answer** despite how the release notes read. It is consumed only by `internal/xds/translator/geoip.go` and SecurityPolicy `clientIPGeoLocations` — it is not a general client-IP mode, and on envoy-external the TCP peer is the cloudflared pod anyway.
- [observation] **envoy-internal moved to a TLS 1.3 floor.** v1.9.0 fixed backend/upstream TLS being capped at 1.2 by default, which was the sole reason for the documented 1.2 concession (the OIDC token-exchange hairpin onto this listener).
- [observation] **Pre-request timeouts bounded**: `timeout.http.requestHeadersReceivedTimeout: 10s` and `timeout.tcp.tlsHandshakeTimeout: 10s` on both gateways. `requestReceivedTimeout: 30m` is the whole-request ceiling and left 30 minutes of slowloris headroom in the header phase. `connectionInspectionTimeout` was left at its 15s default.
- [observation] **`headers.host.stripTrailingHostDot: true`** on both gateways — a trailing-dot Host would otherwise miss hostname-scoped route matching and the `httproute-reserved-hostnames` admission guard.
- [observation] **New alert `EnvoyGatewayXDSRejected`** on `xds_nack_total` (new metric in v1.9.0, labels `nodeID` + `typeURL`, un-prefixed like the other EG control-plane metrics). A rejected config push is otherwise invisible: the proxy keeps serving its last known good config and only fails at the next restart. `increase(...[15m]) > 0` with `for: 5m` so a healed NACK stops alerting instead of latching. Lives in a second PrometheusRule document (`envoy-gateway`) beside the data-plane `envoy-proxy` one; the promtool harness merges `.spec.groups` across documents.
- [correction] **CRDs are NOT applied by hand.** `kubernetes/flux/cluster/ks.yaml` already injects `install.crds: CreateReplace` + `upgrade.crds: CreateReplace` into every HelmRelease, and `helm-controller` is a managedFields owner of `gateways.gateway.networking.k8s.io`. The Gateway API bundle therefore moves v1.5.1 → v1.6.1 with the chart upgrade on its own. `kubernetes/bootstrap/helmfile.d/00-crds.yaml` stays as the bootstrap-ordering path only.
- [observation] **The gateway-helm `safe-upgrades` ValidatingAdmissionPolicy needs no action**, contrary to how the v1.9.0 breaking-changes note reads. Its chart template carries a `lookup` guard that renders it only when the object is absent or already owned by this Helm release; the cluster object is the bootstrap-era one (v1.5.0-dev, Flux labels, no Helm ownership metadata), so it is skipped — identical guard in 1.8.3 and 1.9.0. Its CEL also admits `v1.6.1`.
- [verified] **The XFF switch resolves correctly (2026-08-15, live traffic).** envoy-external access log: `downstream_direct_remote_address: 10.244.0.227` (the cloudflared pod), `downstream_remote_address: [2a00:1110:103:e0ea:...]` (a real public IPv6 client), `x-forwarded-for: <client>,10.244.0.227`. The right-to-left walk skips the trusted pod address and picks the client, and it works for IPv6 clients too. Cloudflare does forward XFF, as the `useRemoteAddress = false` deduction predicted. The two access-log address fields stay in place as the standing read-back for this.
- [gap] **Ordering race with a 1h retry.** `stripTrailingHostDot`, `requestHeadersReceivedTimeout` and `tlsHandshakeTimeout` only exist in the v1.9.0 CRDs. `envoy-gateway-config` `dependsOn: envoy-gateway` (HelmRelease health check), so the normal path is safe, but if the config Kustomization wins a race against the HelmRelease upgrade it fails validation and Flux retries at `interval` — 1h here, no `retryInterval` set. `just k8s sync-ks envoy-gateway-config networking` clears it immediately.

## Update — 2026-08-15: v1.9.0 rollout — one failure, and what verified

- [incident] **`deployment.envoyGateway.strategy: {type: Recreate}` broke the upgrade and must not be retried.** Three Helm attempts failed and Flux rolled back: `Deployment.apps "envoy-gateway" is invalid: spec.strategy.rollingUpdate: Forbidden: may not be specified when strategy \`type\` is 'Recreate'`. Server-side apply merges `type: Recreate` onto a live Deployment whose `spec.strategy.rollingUpdate` was defaulted in by the API server; the merged object is invalid. Clearing the stale field needs an out-of-band `kubectl patch`, which is not worth it for a controller requesting 5m CPU / 192Mi. Reverted in #4178; the reason is recorded in `app/helmrelease.yaml` so it is not attempted again. **General rule: switching an existing Deployment from RollingUpdate to Recreate is not a safe GitOps-only change.**
- [observation] **A failed HelmRelease rollback does NOT revert CRDs.** Helm applies the chart's CRDs ahead of the templates, so the Gateway API bundle went v1.5.1 → v1.6.1 and stayed there while the release itself rolled back to 1.8.3. The cluster briefly ran v1.6.1 CRDs under a v1.8.3 controller with no ill effect (v1.6 still serves v1alpha2, and there are no TCP/UDPRoutes here).
- [observation] **The blast radius of the failed upgrade was zero.** The controller pod never restarted, the envoy proxies were untouched, and `envoy-gateway-config` stayed blocked on its `dependsOn`, so no half-applied ClientTrafficPolicy ever reached the cluster. The dependency chain did its job.
- [verified] **TLS 1.3 floor on envoy-internal**: `openssl s_client -tls1_2` against the LAN VIP is refused with `tlsv1 alert protocol version` (alert 70); `-tls1_3` completes with TLS_AES_256_GCM_SHA384.
- [verified] **The OIDC token-exchange hairpin survives the 1.3 floor**: a real login completed at 16:00:58Z (`302 oauth.logged_in`, 104ms) — after the 15:59:09Z controller restart — followed by `200 via_upstream` on both `echo.` and `dash.` So Envoy's upstream TLS client does negotiate 1.3 at v1.9.0, which is what made the 1.2 concession removable.
- [verified] **`lateResponseHeaders` also applies to filter-generated local replies.** The one behavioural difference flagged when trading the Lua filter for native headers was that Lua ran on every response while route-level response headers might miss local replies. Measured: the oauth2 filter's 302 redirect carries all three headers. No regression.
- [gap] **`xds_nack_total` is not empirically confirmed.** The counter is exported only after its first increment, so the series does not exist on a healthy cluster and `EnvoyGatewayXDSRejected` cannot be smoke-tested without deliberately pushing a rejected config. The name is taken from source (`internal/xds/cache/metrics.go`: `metrics.NewCounter("xds_nack_total", ...)`) and the un-prefixed convention is confirmed by its siblings (`xds_snapshot_update_total` scrapes exactly as declared in that same file), but a typo here would leave the alert silently dead. Re-check the next time a NACK is provoked.
