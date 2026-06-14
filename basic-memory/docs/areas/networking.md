---
title: networking
type: area_reference
permalink: home-ops/docs/areas/networking
area: networking
status: current
confidence: high
verified_at: '2026-06-14'
summary: Gateway API with Envoy Gateway provides cluster ingress, split across two
  shared entrypoints (envoy-external for Cloudflare Tunnel public traffic, envoy-internal
  for LAN traffic on a Cilium L2-announced VIP). Single HTTPS listener per Gateway
  (named `https`); listener-hostname SAN binding was attempted and reverted —
  see drift_risk. ClientTrafficPolicy is per-gateway — external uses CF-Connecting-IP
  for client IP detection, internal rejects client-supplied XFF (numTrustedHops=0).
  HTTP/3 enabled internal-only (CF Tunnel cannot relay QUIC to origin). Baseline
  security response headers (HSTS, nosniff, Referrer-Policy) injected via inline
  Lua. Per-EnvoyProxy access logs to stdout. Split DNS by k8s-gateway (LAN) and
  ExternalDNS (public).
verified_against:
- kubernetes/apps/networking/envoy-gateway/config/gateway-internal.yaml
- kubernetes/apps/networking/envoy-gateway/config/gateway-external.yaml
- kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml
- kubernetes/apps/networking/envoy-gateway/config/security-headers.yaml
- kubernetes/apps/networking/envoy-gateway/config/envoy.yaml
- kubernetes/apps/networking/envoy-gateway/config/ciliumnetworkpolicy-external.yaml
- kubernetes/apps/networking/envoy-gateway/config/ciliumnetworkpolicy-internal.yaml
- kubernetes/apps/networking/k8s-gateway/app/helmrelease.yaml
- kubernetes/apps/networking/cloudflare-tunnel/app/helmrelease.yaml
- kubernetes/apps/kube-system/cilium/config/pool.yaml
- kubernetes/apps/kube-system/cilium/netpols/
- kubernetes/apps/networking/CLAUDE.md
drift_risk: 'HSTS includeSubDomains with 2-year max-age is a one-way commitment —
  any future HTTP-only subdomain under PUBLIC_DOMAIN would be blocked from cached
  browsers; preload deliberately omitted. Listener hostname SAN-binding (split
  into https-apex + https-wildcard) was attempted and reverted in commit 6e890d8f7
  — all 30+ HTTPRoutes pin sectionName: https in parentRefs, the rename produced
  NoMatchingParent on every route. Re-introducing the split requires migrating
  every HTTPRoute parentRef first (mind single-label subdomain, so sectionName:
  https-wildcard is the right target). rate-limit-external BackendTrafficPolicy
  still disabled (envoy-gateway v1.8.0/v1.8.1 CRD regression, fix #8798 merged to
  main but not cherry-picked to release/v1.8) — Cloudflare WAF covers external rate
  limiting in the meantime. The envoy v1.38.2 image tag is hardcoded in EnvoyProxy
  spec, not chart-managed. EnvoyPatchPolicy listener naming uses the EG IR format
  gateway-namespace/gateway-name/listener-name (single `https`, plus `https-quic`
  on internal).'
---

# networking — current state

## Metadata (observation-form, schema validation)

- [area] networking
- [status] current
- [confidence] high
- [verified_at] 2026-06-14

## Summary

Gateway API with Envoy Gateway provides cluster ingress, split across two shared entrypoints:
`envoy-external` for Cloudflare Tunnel public traffic (ClusterIP-only Service) and
`envoy-internal` for LAN traffic (Cilium L2-announced LoadBalancer VIP, RFC1918-restricted).
Each Gateway exposes a single HTTP/80 listener (Same-namespace routes only, serving
the shared https-redirect) and a single HTTPS/443 listener named `https` (All-namespace
routes). A hostname-restricted listener split (https-apex + https-wildcard) was
attempted and reverted because every existing HTTPRoute pins `sectionName: https`,
which produced `NoMatchingParent` on every route after the rename — see drift_risk.
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
Cluster-wide substitution variables (`${PUBLIC_DOMAIN}`, `${TIMEZONE}`,
`${ENVOY_INTERNAL_IP}`, `${K8S_GATEWAY_IP}`, `${NAS_IP}`, etc.) are defined in the
`cluster-settings` ConfigMap (`kubernetes/components/common/vars/cluster-settings.yaml`)
and injected into every child Kustomization via Flux `postBuild.substituteFrom`.

## Components

- [component] Envoy Gateway controller — GatewayClasses `envoy-external` and `envoy-internal` (kubernetes/apps/networking/envoy-gateway/app/)
- [component] EnvoyProxy/envoy-external — ClusterIP Service, replicas=1, envoy v1.38.2, JSON access log to stdout (envoy.yaml first doc)
- [component] EnvoyProxy/envoy-internal — LoadBalancer Service with externalTrafficPolicy: Local, JSON access log to stdout (envoy.yaml second doc)
- [component] Gateway/envoy-external — HTTP/80 (Same-ns routes, redirect only) + HTTPS/443 (All-ns routes), ExternalDNS target external.${PUBLIC_DOMAIN} (gateway-external.yaml)
- [component] Gateway/envoy-internal — same listener layout as external, LAN VIP pinned to ${ENVOY_INTERNAL_IP} (gateway-internal.yaml)
- [component] BackendTrafficPolicy/envoy — shared compression (Zstd/Brotli/Gzip), retry on reset, circuitBreaker (maxConnections/maxPendingRequests/maxParallelRequests=2048, maxParallelRetries=128), tcpKeepalive (gateway-policies.yaml)
- [component] ClientTrafficPolicy/envoy-external — CF-Connecting-IP client IP detection (failClosed=false), HTTP/2 hardening, TLS 1.3 floor, no HTTP/3 (gateway-policies.yaml)
- [component] ClientTrafficPolicy/envoy-internal — numTrustedHops=0, HTTP/3 enabled, TLS 1.3 floor (gateway-policies.yaml)
- [component] EnvoyExtensionPolicy/security-response-headers — inline Lua injects HSTS + nosniff (replace) + Referrer-Policy (add-if-absent) on every response, targets both Gateways (security-headers.yaml)
- [component] EnvoyPatchPolicy/envoy-external — zstd compressor fine-tuning on networking/envoy-external/https (no -quic, HTTP/3 disabled here) (gateway-policies.yaml)
- [component] EnvoyPatchPolicy/envoy-internal — zstd compressor fine-tuning on networking/envoy-internal/{https,https-quic} (gateway-policies.yaml)
- [component] SecurityPolicy/envoy-internal-rfc1918 — defaultAction Deny, allow 10.0.0.0/8 + 172.16.0.0/12 + 192.168.0.0/16 (gateway-policies.yaml)
- [component] HTTPRoute/https-redirect — shared HTTP→HTTPS 301 redirect, attached to both Gateways at sectionName=http (gateway-policies.yaml)
- [component] CiliumNetworkPolicy/envoy-external — ingress allowed only from cloudflare-tunnel pod (10080/10443 TCP) + prometheus + kubelet probe (ciliumnetworkpolicy-external.yaml)
- [component] CiliumNetworkPolicy/envoy-internal — ingress restricted to RFC1918 fromCIDR + cluster/host/remote-node entities on data ports, prometheus + kubelet separately (ciliumnetworkpolicy-internal.yaml)
- [component] cloudflare-tunnel — forwards ${PUBLIC_DOMAIN} (originServerName=${PUBLIC_DOMAIN}) and *.${PUBLIC_DOMAIN} (originServerName=external.${PUBLIC_DOMAIN}) to envoy-external (kubernetes/apps/networking/cloudflare-tunnel/)
- [component] external-dns — manages public Cloudflare DNS records from Gateway/HTTPRoute sources (kubernetes/apps/networking/external-dns/)
- [component] k8s-gateway — LAN split-DNS for ${PUBLIC_DOMAIN}, watches HTTPRoutes filtered to GatewayClass envoy-internal, LAN VIP ${K8S_GATEWAY_IP} (k8s-gateway/app/helmrelease.yaml)
- [component] CiliumLoadBalancerIPPool/default — LAN VIP allocation range ${LB_IP_POOL_START}–${LB_IP_POOL_STOP} (kube-system/cilium/config/pool.yaml)
- [component] CiliumL2AnnouncementPolicy — L2 announcement for the pool (kube-system/cilium/config/l2-announcement-policy.yaml)
- [component] CiliumClusterwideNetworkPolicy baseline — allow-cluster-egress + allow-dns-egress (kube-system/cilium/netpols/)

## Claims (verified against repo)

- [claim] "envoy-internal Gateway is pinned to LAN VIP ${ENVOY_INTERNAL_IP} via lbipam.cilium.io/ips annotation" (evidence: repo, ref: gateway-internal.yaml, verified: 2026-06-14)
- [claim] "k8s-gateway Service is pinned to LAN VIP ${K8S_GATEWAY_IP} via loadBalancerIP chart value" (evidence: repo, ref: k8s-gateway/app/helmrelease.yaml:32, verified: 2026-05-19)
- [claim] "LAN VIPs allocated from CiliumLoadBalancerIPPool/default with range ${LB_IP_POOL_START}–${LB_IP_POOL_STOP} inclusive" (evidence: repo, ref: cilium/config/pool.yaml:7-11, verified: 2026-05-19)
- [claim] "envoy-internal Service is type LoadBalancer with externalTrafficPolicy: Local" (evidence: repo, ref: envoy.yaml, verified: 2026-06-14)
- [claim] "envoy-external Service is type ClusterIP — public reach is via Cloudflare Tunnel only" (evidence: repo, ref: envoy.yaml, verified: 2026-06-14)
- [claim] "envoy-internal is protected by SecurityPolicy/envoy-internal-rfc1918 with defaultAction=Deny and clientCIDRs allowlist of all three RFC1918 ranges" (evidence: repo, ref: gateway-policies.yaml, verified: 2026-06-14)
- [claim] "Shared HTTPRoute/https-redirect issues a 301 HTTP→HTTPS redirect and attaches via parentRefs to both Gateways at sectionName: http" (evidence: repo, ref: gateway-policies.yaml, verified: 2026-06-14)
- [claim] "Each Gateway exposes a single HTTPS/443 listener named `https` (no hostname filter, All-namespace route attach) plus a HTTP/80 listener restricted to local-namespace routes that only attaches the shared https-redirect. Listener-hostname SAN binding was attempted (https-apex + https-wildcard) and reverted in commit 6e890d8f7 because every HTTPRoute pins sectionName: https." (evidence: repo + git log, ref: gateway-external.yaml + gateway-internal.yaml, verified: 2026-06-14)
- [claim] "ClientTrafficPolicy is per-gateway: envoy-external uses CF-Connecting-IP customHeader (failClosed=false), envoy-internal uses numTrustedHops=0 and enables HTTP/3" (evidence: repo, ref: gateway-policies.yaml, verified: 2026-06-14)
- [claim] "Both EnvoyProxy resources emit JSON access logs to /dev/stdout, picked up by the cluster log pipeline" (evidence: repo, ref: envoy.yaml, verified: 2026-06-14)
- [claim] "BackendTrafficPolicy/envoy declares circuitBreaker thresholds (2048 for connections/pending/parallel, 128 for retries) so a misbehaving backend cannot exhaust envoy worker capacity" (evidence: repo, ref: gateway-policies.yaml, verified: 2026-06-14)
- [claim] "EnvoyExtensionPolicy/security-response-headers injects HSTS + X-Content-Type-Options (replace) and Referrer-Policy (add-if-absent) on every response via inline Lua, targets both Gateways" (evidence: repo, ref: security-headers.yaml, verified: 2026-06-14)
- [claim] "CiliumNetworkPolicy/envoy-internal restricts ingress on data ports to RFC1918 fromCIDR plus cluster/host/remote-node entities — defense-in-depth behind SecurityPolicy/envoy-internal-rfc1918" (evidence: repo, ref: ciliumnetworkpolicy-internal.yaml, verified: 2026-06-14)
- [claim] "k8s-gateway watches HTTPRoute resources filtered to GatewayClass envoy-internal" (evidence: repo, ref: k8s-gateway/app/helmrelease.yaml:23-27, verified: 2026-05-19)
- [claim] "Public domain managed by this stack is ${PUBLIC_DOMAIN} (from cluster-settings ConfigMap); ExternalDNS target on Gateway/envoy-external is external.${PUBLIC_DOMAIN}" (evidence: repo, ref: gateway-external.yaml + k8s-gateway/app/helmrelease.yaml:13, verified: 2026-06-14)
- [claim] "Cilium ClusterwideNetworkPolicies allow-cluster-egress and allow-dns-egress exist as cluster-wide baseline" (evidence: repo, ref: kube-system/cilium/netpols/, verified: 2026-05-19)
- [claim] "envoy-gateway is split into three Kustomizations: certificate, app (controller), config" (evidence: repo, ref: kubernetes/apps/networking/envoy-gateway/{certificate,app,config}/, verified: 2026-05-19)

## Drift Risk

- [drift] HSTS includeSubDomains with 2-year max-age is a one-way commitment — once a browser caches it, any future HTTP-only subdomain under ${PUBLIC_DOMAIN} (IoT, legacy tool, dev instance) is unreachable from that browser until the entry expires. `preload` was intentionally omitted to keep this revocable (preload registers the domain with browser vendors and is far harder to unwind). (ref: security-headers.yaml)
- [drift] Listener-hostname SAN binding (https-apex + https-wildcard split) was attempted and reverted in commit 6e890d8f7. Re-introduction requires migrating every HTTPRoute parentRef from `sectionName: https` to `sectionName: https-wildcard` first (all current routes are single-label subdomains, so the wildcard listener is the target). Until then, the single `https` listener accepts All-namespace routes without SAN-based attach filtering. (ref: gateway-external.yaml, gateway-internal.yaml)
- [drift] EnvoyPatchPolicy is a workaround for missing native Zstd compressor fine-tuning options on EnvoyProxy/BackendTrafficPolicy — drop both EnvoyPatchPolicy/envoy-external and envoy-internal when the EnvoyProxy CRD exposes `choose_first` and `remove_accept_encoding_header` on the compressor field. (ref: gateway-policies.yaml)
- [drift] rate-limit-external BackendTrafficPolicy still disabled (commented out) — envoy-gateway v1.8.0 CRD regression (envoyproxy/gateway#8798: uint32 Requests field emits format: int32 + maximum: 4294967295, rejected by K8s 1.36 strict OpenAPI validation). The fix is merged to main but not cherry-picked to release/v1.8, so v1.8.1 is still affected. Re-enable when v1.9.0 GA lands or a v1.8.2 patch backport ships, then bump the OCIRepository tag. Cloudflare WAF covers external rate limiting in the meantime. (ref: gateway-policies.yaml)
- [drift] envoy container image tag (v1.38.2) is hardcoded in EnvoyProxy spec rather than chart-managed — track manually via inline `# renovate:` annotation. (ref: envoy.yaml)

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
