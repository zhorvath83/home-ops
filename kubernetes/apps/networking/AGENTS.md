# Networking Platform Guide

This guide applies to `kubernetes/apps/networking/`.

## What Is Special Here

This subtree contains platform networking components, not just user applications. Expect more multi-stage deployment structure and more cross-cutting dependencies than in `default/`.

Main responsibilities in this subtree:

- ingress and edge routing through Envoy Gateway
- external exposure through Cloudflare Tunnel
- DNS synchronization through ExternalDNS
- L2 and service IP plumbing through MetalLB

## Structural Patterns

Do not assume one app equals one Flux Kustomization here.

Observed live patterns:

- `envoy-gateway/` is split into certificate, controller, and config Kustomizations
- `metallb/` separates app and config
- apps may include explicit `networkpolicy.yaml`
- config manifests often live outside `app/` in dedicated `config/` directories

When editing this subtree:

- inspect the parent `ks.yaml` for multi-stage ordering before changing any child files
- verify whether a resource belongs in `app/`, `config/`, or `certificate/`
- avoid collapsing split Kustomizations into one unless explicitly asked

## Envoy Gateway Conventions

`envoy-external` and `envoy-internal` are the shared Gateway API entrypoints for the cluster.

Current live model:

- `GatewayClass` values are `envoy-external` and `envoy-internal`
- `envoy-external` is the public entrypoint in namespace `networking`
- `envoy-internal` is the LAN entrypoint in namespace `networking`
- HTTP and HTTPS listeners are defined on the Gateway
- certificate material is handled separately and applied before the Gateway config
- Envoy-specific behavior is expressed through Gateway API extension CRDs such as `EnvoyPatchPolicy`, `BackendTrafficPolicy`, `ClientTrafficPolicy`, and `SecurityPolicy`
- `envoy-internal` is exposed through MetalLB on a fixed LAN VIP and protected with an RFC1918-only allowlist
- `k8s-gateway` watches routes attached to `envoy-internal` and answers split-DNS queries for `${PUBLIC_DOMAIN}`

Rules:

- user-facing app routes should usually target both `envoy-external` and `envoy-internal`
- technical or internet-only routes can stay `envoy-external`-only when internal publication is not needed
- Gateway-level traffic policy belongs here, not scattered into application trees
- if changing listener behavior, also inspect related policy and certificate manifests

## Cloudflare Edge Conventions

Cloudflare Tunnel and ExternalDNS are part of the same exposure chain.

Current live model:

- `cloudflare-tunnel` forwards `${PUBLIC_DOMAIN}` and `*.${PUBLIC_DOMAIN}` to `envoy-external.networking.svc.cluster.local`
- tunnel config is provided through a ConfigMap mounted into the chart
- tunnel credentials come from an ExternalSecret-backed Secret
- ExternalDNS watches Gateway and HTTPRoute sources and manages Cloudflare DNS records for the public path
- LAN clients should reach the same hostnames through router-side conditional forwarding to `k8s-gateway`, not through Cloudflare Tunnel

Rules:

- if you change public hostnames or gateway targets, inspect both Cloudflare Tunnel and ExternalDNS
- if you change LAN hostname behavior, inspect `k8s-gateway` and the internal Gateway attachment model
- preserve Cloudflare-specific hardening and transport flags unless there is a concrete reason to change them
- keep secret names aligned between `externalsecret.yaml` and chart `envFrom`/`secretKeyRef` usage

## Platform Validation

For networking changes, validate in this order:

1. Flux Kustomization ordering is still correct.
2. Gateway, policy, and certificate resources still point to the same names and namespaces.
3. Cloudflare Tunnel config still targets the intended internal service.
4. `k8s-gateway` still points at the intended internal Gateway class and LAN VIP.
5. ExternalDNS sources and domain filters still match the active public Gateway/HTTPRoute model.
6. Any affected app route still matches the listener and TLS assumptions for both Gateways.
