# Investigation

Use this reference to structure operational debugging.

## Default Sequence

1. Confirm the symptom and affected scope.
2. Inspect the relevant repo state for the component involved.
3. Inspect the live resource status if cluster access exists.
4. Check recent events, logs, and related dependent resources.
5. Correlate the first failing signal with its likely cause.
6. Only then decide whether remediation belongs in repo state, live ops, or both.

## Good First Surfaces

- Flux and Kustomization state for GitOps symptoms
- workload status, events, and logs for app failures
- Gateway, HTTPRoute, tunnel, and DNS resources for exposure failures
- ExternalSecret, generated Secret refs, and bootstrap flows for secret issues
- ReplicationSource, maintenance resources, and `vs:` task assumptions for backup issues

## Reasoning Rules

- separate symptom from root cause
- prefer the earliest causal signal over the loudest downstream error
- call out missing evidence instead of overcommitting
- be explicit when a likely fix belongs in repo state rather than ad-hoc cluster mutation
