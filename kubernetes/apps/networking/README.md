# Networking

```txt
           "app.horvathzoltan.me"

       internal:                external:

                            ┌───────────────┐
        *dns lookup*        │ external-dns  │
             │              │   creates     │
             ▼              │ public record │
   split DNS on router      └──────┬────────┘
   for horvathzoltan.me            │
             │                     ▼
             │                *dns lookup*
             │                     │
     ┌───────▼────────┐            ▼
     │  k8s-gateway   │         public
     │ LB_K8S_GATEWAY │      cloudflare IP
     └───────┬────────┘            │
             │                     │
             │                   ┌─▼─────────────┐
             │                   │ cloudflare-   │
             │                   │ tunnel        │
             │                   └──┬──────────┬─┘
             │                      │          │
   ┌─────────▼─────────┐    ┌──────▼──────┐   │
   │   envoy-internal  │    │ envoy-      │   │
   │ LB_ENVOY_INTERNAL │    │ external    │   │
   └─────────┬─────────┘    └──────┬──────┘   │
             │                     │          │
             └──────────┬──────────┘          │
                        │                     │
                 ┌──────▼──────┐              │
                 │ application │              │
                 └─────────────┘              │
                                              │
└──────────────────────────────────────────────┘
 k8s cluster
```

## Private Applications

LAN clients should use split DNS instead of Cloudflare Tunnel.

`k8s-gateway` watches HTTPRoutes attached to `envoy-internal` and returns the internal Envoy VIP. For this to work:

- the router DNS must conditionally forward `horvathzoltan.me` to `192.168.1.19`
- the router DNS must allow DNS rebinding for `horvathzoltan.me`, otherwise RFC1918 answers such as `192.168.1.18` may be dropped or rewritten
- any app that should be reachable directly from the LAN must attach its HTTPRoute to `envoy-internal`

## Public Applications

Public traffic continues to use the Cloudflare-managed path.

- ExternalDNS creates the public DNS records
- Cloudflare Tunnel forwards `horvathzoltan.me` and `*.horvathzoltan.me` to `envoy-external.networking.svc.cluster.local`
- any HTTPRoute attached to `envoy-external` is reachable from the public path, subject to any additional Cloudflare policy

## Route Model

The default user-facing route model is dual attachment:

```yaml
parentRefs:
  - name: envoy-external
    namespace: networking
    sectionName: https
  - name: envoy-internal
    namespace: networking
    sectionName: https
```

Technical or internet-only endpoints can stay `envoy-external`-only. Example:

- `flux-webhook`

## Security Notes

The public and internal paths are intentionally separated:

- `envoy-external` is only intended to receive ingress from Cloudflare Tunnel
- `envoy-internal` is protected by an RFC1918-only allowlist and is intended for LAN clients

Router or edge settings can still bypass this model. Check for:

- port forwards or DMZ rules to the Envoy VIPs or node IPs
- UPnP/NAT-PMP opening inbound ports automatically
- router DNS rebinding protection blocking `horvathzoltan.me` from resolving to the internal VIP
