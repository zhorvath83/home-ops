---
title: networking
type: area_reference
permalink: home-ops/docs/areas/networking
area: networking
status: current
confidence: high
verified_at: '2026-05-22'
summary: Gateway API with Envoy Gateway provides cluster ingress, split across two
  shared entrypoints (envoy-external for Cloudflare Tunnel public traffic and envoy-internal
  for LAN traffic on a Cilium L2-announced VIP). Split DNS by k8s-gateway (LAN) and
  ExternalDNS (public). LAN clients reach the same public hostnames without hairpinning
  through Cloudflare.
verified_against:
- kubernetes/apps/networking/envoy-gateway/config/gateway-internal.yaml
- kubernetes/apps/networking/envoy-gateway/config/gateway-external.yaml
- kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml
- kubernetes/apps/networking/envoy-gateway/config/envoy.yaml
- kubernetes/apps/networking/k8s-gateway/app/helmrelease.yaml
- kubernetes/apps/kube-system/cilium/config/pool.yaml
- kubernetes/apps/kube-system/cilium/netpols/
- docs/networking-readme.md
- .claude/skills/networking-platform/references/topology.md
- kubernetes/apps/networking/CLAUDE.md
drift_risk: LAN VIPs (ENVOY_INTERNAL_IP, K8S_GATEWAY_IP) are now centralized in
  the cluster-settings ConfigMap and injected via Flux postBuild.substituteFrom; rate-limit-external
  BackendTrafficPolicy disabled due to envoy-gateway v1.8.0 CRD regression (re-enable
  on v1.9.0 GA); envoy:v1.38.0 image tag is in EnvoyProxy spec, not chart-managed.
---

# networking — current state

## Metadata (observation-form, schema validation)
- [area] networking
- [status] current
- [confidence] high
- [verified_at] 2026-05-19

## Summary
Gateway API with Envoy Gateway provides cluster ingress, split across two shared entrypoints:
`envoy-external` for Cloudflare Tunnel public traffic (ClusterIP-only Service) and
`envoy-internal` for LAN traffic (Cilium L2-announced LoadBalancer VIP, RFC1918-restricted).
Split DNS by `k8s-gateway` (LAN) and ExternalDNS (public Cloudflare). LAN clients reach the same
public hostnames without hairpinning through Cloudflare.
Cluster-wide substitution variables (`${PUBLIC_DOMAIN}`, `${TIMEZONE}`, `${ENVOY_INTERNAL_IP}`,
`${K8S_GATEWAY_IP}`, `${NAS_IP}`, etc.) are defined in the `cluster-settings` ConfigMap
(`kubernetes/components/common/vars/cluster-settings.yaml`) and injected into every child
Kustomization via Flux `postBuild.substituteFrom`.

## Components
- [component] Envoy Gateway controller — GatewayClasses `envoy-external` and `envoy-internal` (kubernetes/apps/networking/envoy-gateway/app/)
- [component] EnvoyProxy/envoy-external — ClusterIP Service, replicas=1, envoy v1.38.0 (envoy-gateway/config/envoy.yaml:1-49)
- [component] EnvoyProxy/envoy-internal — LoadBalancer Service with externalTrafficPolicy: Local (envoy-gateway/config/envoy.yaml:51-99)
- [component] Gateway/envoy-external — HTTP+HTTPS listeners, ExternalDNS target `${PUBLIC_DOMAIN}` (gateway-external.yaml)
- [component] Gateway/envoy-internal — HTTP+HTTPS listeners, LAN VIP pinned to `${ENVOY_INTERNAL_IP}` (gateway-internal.yaml)
- [component] BackendTrafficPolicy/envoy — shared compression (Zstd/Brotli/Gzip) and retry policy across all Gateways (gateway-policies.yaml:1-26)
- [component] ClientTrafficPolicy/envoy — shared XFF, HTTP/2, HTTP/3, TLS 1.3 floor (gateway-policies.yaml:28-56)
- [component] SecurityPolicy/envoy-internal-rfc1918 — defaultAction Deny, allow 10.0.0.0/8 + 172.16.0.0/12 + 192.168.0.0/16 (gateway-policies.yaml:117-136)
- [component] EnvoyPatchPolicy/envoy-external — injects Zstd compressor on https + https-quic listeners (gateway-policies.yaml:57-86)
- [component] HTTPRoute/https-redirect — shared HTTP→HTTPS 301 redirect, attached to both Gateways (gateway-policies.yaml:138-159)
- [component] cloudflare-tunnel — forwards `${PUBLIC_DOMAIN}` + `*.${PUBLIC_DOMAIN}` to `envoy-external.networking.svc.cluster.local` (kubernetes/apps/networking/cloudflare-tunnel/)
- [component] external-dns — manages public Cloudflare DNS records from Gateway/HTTPRoute sources (kubernetes/apps/networking/external-dns/)
- [component] k8s-gateway — LAN split-DNS for `${PUBLIC_DOMAIN}`, watches HTTPRoutes filtered to GatewayClass envoy-internal, LAN VIP `${K8S_GATEWAY_IP}` (k8s-gateway/app/helmrelease.yaml)
- [component] CiliumLoadBalancerIPPool/default — LAN VIP allocation range `${LB_IP_POOL_START}`–`${LB_IP_POOL_STOP}` (kube-system/cilium/config/pool.yaml)
- [component] CiliumL2AnnouncementPolicy — L2 announcement for the pool (kube-system/cilium/config/l2-announcement-policy.yaml)
- [component] CiliumClusterwideNetworkPolicy baseline — allow-cluster-egress + allow-dns-egress (kube-system/cilium/netpols/)

## Claims (verified against repo)
- [claim] "envoy-internal Gateway is pinned to LAN VIP `${ENVOY_INTERNAL_IP}` via lbipam.cilium.io/ips annotation" (evidence: repo, ref: gateway-internal.yaml:23-24, verified: 2026-05-19)
- [claim] "k8s-gateway Service is pinned to LAN VIP `${K8S_GATEWAY_IP}` via loadBalancerIP chart value" (evidence: repo, ref: k8s-gateway/app/helmrelease.yaml:32, verified: 2026-05-19)
- [claim] "LAN VIPs allocated from CiliumLoadBalancerIPPool/default with range `${LB_IP_POOL_START}`–`${LB_IP_POOL_STOP}` inclusive" (evidence: repo, ref: cilium/config/pool.yaml:7-11, verified: 2026-05-19)
- [claim] "envoy-internal Service is type LoadBalancer with externalTrafficPolicy: Local" (evidence: repo, ref: envoy.yaml:90-92, verified: 2026-05-19)
- [claim] "envoy-external Service is type ClusterIP — public reach is via Cloudflare Tunnel only" (evidence: repo, ref: envoy.yaml:41-42, verified: 2026-05-19)
- [claim] "envoy-internal is protected by SecurityPolicy/envoy-internal-rfc1918 with defaultAction=Deny and clientCIDRs allowlist of all three RFC1918 ranges" (evidence: repo, ref: gateway-policies.yaml:117-136, verified: 2026-05-19)
- [claim] "Shared HTTPRoute/https-redirect issues a 301 HTTP→HTTPS redirect and attaches via parentRefs to both Gateways at sectionName: http" (evidence: repo, ref: gateway-policies.yaml:138-159, verified: 2026-05-19)
- [claim] "Both Gateways expose HTTP (port 80, Same-namespace routes) and HTTPS (port 443, All-namespace routes, TLS Secret derived from `${PUBLIC_DOMAIN}`) listeners" (evidence: repo, ref: gateway-external.yaml:27-43 + gateway-internal.yaml:25-41, verified: 2026-05-19)
- [claim] "k8s-gateway watches HTTPRoute resources filtered to GatewayClass envoy-internal" (evidence: repo, ref: k8s-gateway/app/helmrelease.yaml:23-27, verified: 2026-05-19)
- [claim] "Public domain managed by this stack is `${PUBLIC_DOMAIN}` (from cluster-settings ConfigMap); ExternalDNS target on Gateway/envoy-external is `external.${PUBLIC_DOMAIN}`" (evidence: repo, ref: gateway-external.yaml:21 + k8s-gateway/app/helmrelease.yaml:13, verified: 2026-05-19)
- [claim] "Cilium ClusterwideNetworkPolicies allow-cluster-egress and allow-dns-egress exist as cluster-wide baseline" (evidence: repo, ref: kube-system/cilium/netpols/, verified: 2026-05-19)
- [claim] "envoy-gateway is split into three Kustomizations: certificate, app (controller), config" (evidence: repo, ref: kubernetes/apps/networking/envoy-gateway/{certificate,app,config}/, verified: 2026-05-19)

## Drift Risk
- [drift] EnvoyPatchPolicy/envoy-external is a workaround for missing native Zstd compression support on listeners — remove when EnvoyProxy CRD gains native support (ref: gateway-policies.yaml:57-86)
- [drift] rate-limit-external BackendTrafficPolicy intentionally disabled (commented out) due to envoy-gateway v1.8.0 CRD regression (envoyproxy/gateway#8798: uint32 Requests field emits format: int32 + maximum: 4294967295, rejected by K8s 1.36 strict OpenAPI validation). Re-enable when v1.9.0 GA lands and OCIRepository tag is bumped. Cloudflare WAF covers external rate limiting in the meantime. (ref: gateway-policies.yaml:87-116)
- [drift] envoy container image tag (envoy:v1.38.0) is hardcoded in EnvoyProxy spec rather than chart-managed — track manually via inline `# renovate:` annotation if not already

## Open Questions / Gaps
- [gap] Public path verification — Cloudflare Tunnel target assertion was inherited from area CLAUDE.md but not re-verified against cloudflare-tunnel ConfigMap in this pass; will be checked when migrating cloudflare area-reference
- [gap] Router-side requirements (conditional forward `${PUBLIC_DOMAIN}` → `${K8S_GATEWAY_IP}`, DNS rebind allowance) live outside repo — operationally documented in source readme but not reproducible from manifests alone; intent-class claim
- [gap] Live cluster verification not performed in this pass — all claims are repo (desired state) evidence; for live-state drift check, walk through `networking-platform/references/validation.md`

## Relations
- depends_on [[cilium-lb-ipam]]
- depends_on [[cloudflare]]
- relates_to [[external-secrets]]
- part_of [[home-ops-platform]]
- supersedes [[networking-readme]]
