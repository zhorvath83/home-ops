# Operations

Use this reference when choosing Flux-related commands or task wrappers.

## Canonical Entry Points

Prefer the existing `fx:` tasks:

- `task fx:verify`
- `task fx:install`
- `task fx:reconcile`
- `task fx:kustomizations`
- `task fx:helmreleases`
- `task fx:gitrepositories`
- `task fx:gateways`

## Reconcile Rules

- `task fx:reconcile` and `flux reconcile ...` only help with committed state that Flux can fetch.
- Do not present reconcile as if it applied the local working tree.
- If the change affects bootstrap secrets or `cluster-secrets.sops.yaml`, inspect `task fx:install` together with the relevant secret files.

## Cross-Skill Routing

- bootstrap or repo-encrypted secret changes: use `sops-secrets`
- app-local workload changes: use `k8s-workloads`
- webhook or provider secrets delivered by External Secrets: use `external-secrets`
