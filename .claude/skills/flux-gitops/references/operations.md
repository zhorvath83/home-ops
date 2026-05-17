# Operations

Use this reference when choosing Flux-related commands or recipes.

## Canonical Entry Points

The cluster runs Flux through the Flux Operator + `FluxInstance` pattern. There is no classic `flux bootstrap`; the platform is brought up by `just cluster-bootstrap cluster`.

For everyday Flux work, prefer the `just k8s` recipes (group `flux` and `sync`):

- `just k8s flux-reconcile` — refresh the Git source and reconcile the root `cluster-apps` Kustomization
- `just k8s flux-check` — `flux check --pre`
- `just k8s sync-hr <name> <namespace>` — sync a single HelmRelease
- `just k8s sync-ks <name> <namespace>` — sync a single Kustomization
- `just k8s sync-es <name> <namespace>` — sync a single ExternalSecret
- `just k8s sync <resource>` — polymorphic cluster-wide sync (`hr|ks|gitrepo|ocirepo|es`)
- `just k8s list-failed-hrs` / `just k8s restart-failed-hrs` — both use JSON detection on the HelmRelease `Ready` condition (immune to kubectl/flux column-output drift); `list-failed-hrs` prints `NAMESPACE/NAME`, `READY`, and the Ready reason column-aligned
- `just k8s apply-ks <name> <namespace>` / `just k8s delete-ks <name> <namespace>` — local-only Kustomization apply/delete

Use the upstream CLI directly when no recipe wraps the operation:

- `flux get sources git -A` / `flux get sources oci -A`
- `flux get ks -A` / `flux get hr -A`
- `flux events --watch`
- `flux logs --all-namespaces --follow --level=error`

## Reconcile Rules

- `just k8s flux-reconcile` and `flux reconcile ...` only help with committed state that Flux can fetch.
- Do not present reconcile as if it applied the local working tree.
- Bootstrap-time concerns (Flux Operator install, `FluxInstance` config) live in `kubernetes/bootstrap/` and `kubernetes/apps/flux-system/flux-instance/`; inspect those together when the change affects the control-plane install.

## Cross-Skill Routing

- app-local workload changes: use `k8s-workloads`
- webhook or provider secrets delivered by External Secrets: use `external-secrets`
- recipe-wiring changes in the root `.justfile` or `kubernetes/mod.just`: use `just`
