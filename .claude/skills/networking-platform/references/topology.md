# Topology

Use this reference to rebuild the current networking platform picture before editing.

## Main Responsibilities

- ingress and edge routing through Envoy Gateway
- external exposure through Cloudflare Tunnel
- DNS synchronization through ExternalDNS
- L2 and service IP plumbing through MetalLB

## Structural Patterns

Do not assume one app equals one Flux Kustomization here.

Common live patterns:

- `envoy-gateway/` split across certificate, controller, and config Kustomizations
- `metallb/` split between app and config
- config manifests may live outside `app/`
- explicit `networkpolicy.yaml` files may be part of the deployment shape

## Shared Exposure Chain

- `envoy-external` is the shared external Gateway for Cloudflare-published traffic
- `envoy-internal` is the shared LAN Gateway exposed on a MetalLB VIP
- Cloudflare Tunnel forwards the public domain and wildcard traffic to `envoy-external.networking.svc.cluster.local`
- `k8s-gateway` resolves `${PUBLIC_DOMAIN}` hostnames for LAN clients by watching HTTPRoutes attached to `envoy-internal`
- ExternalDNS watches Gateway and HTTPRoute resources and manages public DNS records for the external path

If a change alters public hostnames, listener behavior, or the tunnel target, reason about the entire chain rather than one resource in isolation.
