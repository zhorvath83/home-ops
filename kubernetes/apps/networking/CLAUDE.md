# Networking Platform Guide

This guide applies to `kubernetes/apps/networking/`. It captures durable guardrails for the ingress + edge exposure chain; for current-state detail (components, gateways, policies, claims, drift risk) read the Basic Memory area-reference `docs/areas/networking` via the `basic-memory` MCP.

## Scope

Platform networking, not user applications:

- ingress and edge routing through Envoy Gateway
- external exposure through Cloudflare Tunnel
- DNS synchronization through ExternalDNS (public) and `k8s-gateway` (LAN split DNS)

L2 and service IP allocation lives in `kubernetes/apps/kube-system/cilium/` (Cilium LB-IPAM + L2 announcement); this subtree consumes those VIPs but does not own them.

## Structural Guardrails

Do not assume one app equals one Flux Kustomization here:

- `envoy-gateway/` is split into separate Kustomizations (certificate, controller, config) — inspect the parent `ks.yaml` for multi-stage ordering before changing any child file.
- App manifests may include explicit `CiliumNetworkPolicy` or `SecurityPolicy` resources.
- Config manifests often live outside `app/` in dedicated `config/` directories.
- Do not collapse split Kustomizations into one unless explicitly asked.

## Envoy Gateway Conventions

`envoy-external` and `envoy-internal` are the shared Gateway API entrypoints; both live in namespace `networking`.

Rules:

- User-facing app routes should usually attach to both `envoy-external` and `envoy-internal`.
- Technical / internet-only routes can stay `envoy-external`-only when no LAN reach is needed.
- Gateway-level traffic policy (`BackendTrafficPolicy`, `ClientTrafficPolicy`, `EnvoyPatchPolicy`, `SecurityPolicy`) belongs here, not scattered into application trees.
- If changing listener behavior, inspect related policy and certificate manifests together.
- `envoy-internal` is protected by an RFC1918-only `SecurityPolicy`; do not weaken that without explicit security review.

## Cloudflare Edge Conventions

Cloudflare Tunnel and ExternalDNS are part of the same exposure chain:

- `cloudflare-tunnel` forwards the public domain to `envoy-external.networking.svc.cluster.local`; tunnel config comes from a ConfigMap, credentials from an ExternalSecret.
- ExternalDNS watches Gateway and HTTPRoute sources for the public path.
- LAN clients reach the same hostnames via router-side conditional forwarding to `k8s-gateway`, not through Cloudflare Tunnel.

Rules:

- If public hostnames or gateway targets change, inspect both Cloudflare Tunnel and ExternalDNS.
- If LAN hostname behavior changes, inspect `k8s-gateway` and the internal Gateway attachment model.
- Preserve Cloudflare-specific hardening and transport flags unless there is a concrete reason to change them.
- Keep secret names aligned between `externalsecret.yaml` and chart `envFrom` / `secretKeyRef` usage.

## Validation

See `.claude/skills/networking-platform/references/validation.md`.
