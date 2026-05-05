# Layout

Use this reference to rebuild the Flux and GitOps control-plane layout before editing.

## Main Areas

- `kubernetes/bootstrap/flux/`: initial Flux bootstrap resources
- `kubernetes/flux/config/`: shared Git source and Kustomization configuration
- `kubernetes/flux/vars/`: cluster-wide non-secret and secret substitutions
- `kubernetes/flux/apps.yaml`: Flux entry point for the app tree
- `kubernetes/apps/flux-system/`: Flux add-ons such as providers and GitHub webhooks

## Change Placement

- bootstrap/install flow changes usually land under `bootstrap/flux/` or `flux/config/`
- shared substitution changes belong in `flux/vars/`
- notification, receiver, or provider changes belong in `apps/flux-system/`
- app-local `ks.yaml` edits stay in the app subtree unless they alter shared dependency or naming conventions

If a task only changes one app's `ks.yaml` or manifests, use `k8s-workloads` instead.
