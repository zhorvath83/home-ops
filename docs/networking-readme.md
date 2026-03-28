# Networking readme

This document describes the current ingress, DNS, and publication model for the Kubernetes cluster.

## Overview

The cluster uses Gateway API with Envoy Gateway and has two shared ingress entrypoints:

- `envoy-external`: public entrypoint for traffic published through Cloudflare Tunnel
- `envoy-internal`: LAN entrypoint exposed on a MetalLB VIP for direct internal access

The goal of the split model is to let LAN clients reach the same hostnames directly without hairpinning through Cloudflare.

## Components

The routing chain currently depends on these components:

- Envoy Gateway for Gateway API control plane and data plane
- MetalLB for the `envoy-internal` and `k8s-gateway` LAN VIPs
- Cloudflare Tunnel for public ingress into `envoy-external`
- ExternalDNS for public DNS management
- `k8s-gateway` for LAN split DNS based on Gateway API routes

## Public Path

Public traffic uses the Cloudflare-managed path:

1. Public DNS resolves `${PUBLIC_DOMAIN}` and `*.${PUBLIC_DOMAIN}` to Cloudflare
2. Cloudflare Tunnel forwards the request to `envoy-external.networking.svc.cluster.local`
3. `envoy-external` routes the request to the matching backend service

This path remains the source of truth for internet-reachable traffic.

## Internal Path

LAN traffic uses split DNS:

1. The home router DNS conditionally forwards `${PUBLIC_DOMAIN}` queries to the `k8s-gateway` VIP
2. `k8s-gateway` watches HTTPRoutes attached to `envoy-internal`
3. For matching hostnames it returns the `envoy-internal` VIP
4. The client connects directly to `envoy-internal` on the LAN
5. `envoy-internal` routes the request to the matching backend service

This avoids going through Cloudflare Tunnel for internal clients while preserving the same public hostnames.

## Gateway Model

The live Gateway API model is:

- `GatewayClass/envoy-external` backed by `EnvoyProxy/envoy-external`
- `GatewayClass/envoy-internal` backed by `EnvoyProxy/envoy-internal`
- `Gateway/envoy-external` in namespace `networking`
- `Gateway/envoy-internal` in namespace `networking`

Important behavior:

- both Gateways expose HTTP and HTTPS listeners
- the shared HTTP redirect route attaches to both Gateways
- `envoy-internal` is protected by an RFC1918-only `SecurityPolicy`
- only `envoy-external` is part of the public Cloudflare Tunnel path

## DNS Model

Public DNS:

- managed by ExternalDNS
- follows the external publication path
- should only describe the external Cloudflare-published surface

Internal DNS:

- served by `k8s-gateway`
- should resolve the same app hostnames to the `envoy-internal` VIP
- depends on router-side conditional forwarding for `${PUBLIC_DOMAIN}`
- depends on router-side rebind protection allowing `${PUBLIC_DOMAIN}` to resolve to RFC1918 addresses

The LAN VIPs come from `kubernetes/flux/vars/cluster-settings.yaml`:

- `LB_ENVOY_INTERNAL_IP`
- `LB_K8S_GATEWAY_IP`

## Router Requirements

The router DNS must be configured so LAN clients can actually use the internal path:

1. conditionally forward `${PUBLIC_DOMAIN}` to `${LB_K8S_GATEWAY_IP}`
2. allow DNS rebinding for `${PUBLIC_DOMAIN}`

Without the rebind protection exception, the router may drop or rewrite answers that point `${PUBLIC_DOMAIN}` to the RFC1918 internal Envoy VIP.

## Route Attachment Rules

Default rule for user-facing applications:

- attach the HTTPRoute to `envoy-external`
- also attach it to `envoy-internal` when the app should be directly reachable from the LAN

Technical or internet-only routes may stay external-only. Current example:

- `flux-webhook` remains attached only to `envoy-external`

## Operational Notes

- Local repository changes do not affect the live cluster until they are committed, pushed, and reconciled by Flux.
- A successful local `kustomize build` validates repo state only. It does not confirm that router conditional forwarding or client DNS behavior is correct.
- If LAN clients still reach Cloudflare after repo changes are live, inspect the client resolver path first. Per-device encrypted DNS profiles can bypass the router DNS and break split DNS even when the cluster is healthy.

## Validation Checklist

After changing networking publication behavior, verify all of the following:

1. Flux Kustomizations for Envoy Gateway, `k8s-gateway`, and affected workloads are `Ready=True`
2. `GatewayClass` objects for `envoy-external` and `envoy-internal` are accepted
3. `Gateway/envoy-internal` is programmed with the expected LAN VIP
4. `Service/k8s-gateway` is programmed with the expected LAN VIP
5. affected HTTPRoutes are attached and accepted on the intended Gateways
6. direct DNS queries to the `k8s-gateway` VIP return the `envoy-internal` VIP for LAN-published apps
7. normal client resolution on the home network uses the internal path rather than Cloudflare
