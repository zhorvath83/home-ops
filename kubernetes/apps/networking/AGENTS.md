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

`envoy-external` is the shared external Gateway for the cluster.

Current live model:

- `GatewayClass` is `envoy`
- external entrypoint is `envoy-external` in namespace `networking`
- HTTP and HTTPS listeners are defined on the Gateway
- certificate material is handled separately and applied before the Gateway config
- Envoy-specific behavior is expressed through Gateway API extension CRDs such as `EnvoyPatchPolicy` and `BackendTrafficPolicy`

Rules:

- user-facing app routes should usually target `envoy-external`
- Gateway-level traffic policy belongs here, not scattered into application trees
- if changing listener behavior, also inspect related policy and certificate manifests

## Cloudflare Edge Conventions

Cloudflare Tunnel and ExternalDNS are part of the same exposure chain.

Current live model:

- `cloudflare-tunnel` forwards `${PUBLIC_DOMAIN}` and `*.${PUBLIC_DOMAIN}` to `envoy-external.networking.svc.cluster.local`
- tunnel config is provided through a ConfigMap mounted into the chart
- tunnel credentials come from an ExternalSecret-backed Secret
- ExternalDNS watches Gateway and HTTPRoute sources and manages Cloudflare DNS records

Rules:

- if you change public hostnames or gateway targets, inspect both Cloudflare Tunnel and ExternalDNS
- preserve Cloudflare-specific hardening and transport flags unless there is a concrete reason to change them
- keep secret names aligned between `externalsecret.yaml` and chart `envFrom`/`secretKeyRef` usage

## Platform Validation

For networking changes, validate in this order:

1. Flux Kustomization ordering is still correct.
2. Gateway, policy, and certificate resources still point to the same names and namespaces.
3. Cloudflare Tunnel config still targets the intended internal service.
4. ExternalDNS sources and domain filters still match the active Gateway/HTTPRoute model.
5. Any app route using `envoy-external` still matches the listener and TLS assumptions.
