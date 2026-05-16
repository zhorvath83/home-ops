# Operations

Use this reference when choosing Flux-related commands or recipes.

## Canonical Entry Points

The cluster runs Flux through the Flux Operator + `FluxInstance` pattern. There is no classic `flux bootstrap`; the platform is brought up by `just k8s-bootstrap cluster`.

For everyday Flux work, prefer the `just k8s` recipes (group `flux` and `sync`):

- `just k8s flux-reconcile` — refresh the Git source and reconcile both root Kustomizations (`cluster-vars` + `cluster-apps`)
- `just k8s flux-check` — `flux check --pre`
- `just k8s sync-hr <ns> <name>` — sync a single HelmRelease
- `just k8s sync-ks <ns> <name>` — sync a single Kustomization
- `just k8s sync-es <ns> <name>` — sync a single ExternalSecret
- `just k8s sync <resource>` — polymorphic cluster-wide sync (`hr|ks|gitrepo|ocirepo|es`)
- `just k8s list-failed-hrs` / `just k8s restart-failed-hrs`
- `just k8s apply-ks <ns> <name>` / `just k8s delete-ks <ns> <name>` — local-only Kustomization apply/delete

Use the upstream CLI directly when no recipe wraps the operation:

- `flux get sources git -A` / `flux get sources oci -A`
- `flux get ks -A` / `flux get hr -A`
- `flux events --watch`
- `flux logs --all-namespaces --follow --level=error`

## Reconcile Rules

- `just k8s flux-reconcile` and `flux reconcile ...` only help with committed state that Flux can fetch.
- Do not present reconcile as if it applied the local working tree.
- Bootstrap-time concerns (Flux Operator install, `FluxInstance` config, `cluster-secrets.sops.yaml` substitutions) live in `kubernetes/bootstrap/` and `kubernetes/apps/flux-system/flux-instance/`; inspect those together when the change affects the control-plane install.

## Cross-Skill Routing

- bootstrap or repo-encrypted secret changes: use `sops-secrets`
- app-local workload changes: use `k8s-workloads`
- webhook or provider secrets delivered by External Secrets: use `external-secrets`
- recipe-wiring changes in the root `.justfile` or `kubernetes/mod.just`: use `just`
