# Validation

Use this reference after changing networking platform resources.

## Validation Order

1. Flux Kustomization ordering is still correct.
2. Gateway, certificate, and policy resources still refer to the same names and namespaces.
3. Cloudflare Tunnel still targets the intended internal service.
4. `k8s-gateway` still points at the intended Gateway class and LAN VIP.
5. ExternalDNS sources and domain filters still match the active public Gateway and HTTPRoute model.
6. Any affected app route still matches listener and TLS assumptions for each attached Gateway.

## Useful Checks

- read parent and child `ks.yaml` files together
- inspect sibling resources in the same subtree before inventing a new shape
- use existing Flux and Kubernetes task entry points when the environment is available
