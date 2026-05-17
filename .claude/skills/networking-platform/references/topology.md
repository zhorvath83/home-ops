# Topology

Use this reference to rebuild the current networking platform picture before editing.

## Main Responsibilities

`kubernetes/apps/networking/` owns:

- ingress and edge routing through Envoy Gateway
- external exposure through Cloudflare Tunnel
- DNS synchronization through ExternalDNS
- LAN split DNS through `k8s-gateway`

L2 announcement and LoadBalancer IP allocation live in `kubernetes/apps/kube-system/cilium/` (Cilium LB-IPAM, `CiliumLoadBalancerIPPool/default`, `CiliumL2AnnouncementPolicy`). The networking subtree consumes those VIPs but does not own them.

## Structural Patterns

Do not assume one app equals one Flux Kustomization here.

Common live patterns:

- `envoy-gateway/` split across certificate, controller, and config Kustomizations
- config manifests may live outside `app/` (e.g. `envoy-gateway/config/`)
- explicit `CiliumNetworkPolicy` or `SecurityPolicy` files may be part of the deployment shape

## Shared Exposure Chain

- `envoy-external` is the shared external Gateway for Cloudflare-published traffic; ClusterIP-only Service inside the cluster
- `envoy-internal` is the shared LAN Gateway, exposed on a Cilium L2-announced VIP (pinned via `lbipam.cilium.io/ips`)
- Cloudflare Tunnel forwards the public domain and wildcard traffic to `envoy-external.networking.svc.cluster.local`
- `k8s-gateway` resolves `${PUBLIC_DOMAIN}` hostnames for LAN clients by watching HTTPRoutes attached to `envoy-internal`
- ExternalDNS watches Gateway and HTTPRoute resources and manages public DNS records for the external path

## Cluster-Wide Network Policy Baseline

`kubernetes/apps/kube-system/cilium/netpols/` contains the opinionated cluster-wide baseline:

- `allow-cluster-egress` — broad egress for every pod that does not carry the opt-out label `egress.home.arpa/custom-egress`
- `allow-dns-egress` — UDP/TCP 53 to kube-dns with L7 DNS proxy (`rules.dns.matchPattern: "*"`)

Per-app hardening is layered on top of this baseline. The Tier I / Tier II decision model and the SecurityPolicy boundaries (e.g. why `clientCIDRs` cannot guard `envoy-external`) are documented in `docs/migration/16-repo-refactor.md` (Phase 16.c) — read that before adding new per-app CNP / SecurityPolicy resources.

If a change alters public hostnames, listener behavior, the tunnel target, or the LAN VIP allocation, reason about the entire chain rather than one resource in isolation.
