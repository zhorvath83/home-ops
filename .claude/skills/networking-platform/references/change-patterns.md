# Change Patterns

Use this reference when deciding which files to inspect for a networking change.

## Gateway And Listener Changes

If the change touches listeners, HTTPS behavior, or Gateway-level traffic policy:

- inspect the Gateway resource
- inspect related certificate manifests
- inspect Envoy-specific policy resources such as `EnvoyPatchPolicy` or `BackendTrafficPolicy`

## Tunnel And DNS Changes

If the change touches hostnames or gateway targets:

- inspect Cloudflare Tunnel ConfigMap content
- inspect the ExternalSecret that provides tunnel credentials
- inspect ExternalDNS sources and domain filters

## Resource Placement

Before editing, confirm whether the resource belongs in:

- `app/`
- `config/`
- `certificate/`

Do not collapse multi-stage Kustomizations into one unless the task explicitly calls for that refactor.
