# Bootstrap And App Secrets

Use this reference to understand where repo-encrypted secrets are consumed.

## Cluster-Wide Secrets

- `kubernetes/flux/vars/cluster-secrets.sops.yaml` holds sensitive cluster-wide substitutions
- `kubernetes/flux/vars/cluster-settings.yaml` remains the non-secret counterpart
- if one changes, inspect the other when substitution keys or naming are involved

## Bootstrap Flow

`just cluster-bootstrap cluster` runs the full chain. The secret-relevant stages, rendered from `kubernetes/bootstrap/resources.yaml.j2` through `minijinja-cli | op inject`, are:

1. creates `sops-age` in `flux-system` (Age key fetched from 1Password)
2. creates the `onepassword-secret` bootstrap secret in `external-secrets` (1Password Connect credentials + token)
3. decrypts and applies `kubernetes/flux/vars/cluster-secrets.sops.yaml` via the `cluster-vars` Flux Kustomization (managed by `FluxInstance`)
4. lets `cluster-apps` reconcile the rest of the tree

If a secret name or file path changes, inspect `kubernetes/bootstrap/resources.yaml.j2`, the `kubernetes/bootstrap/mod.just` `resources` stage, and the consuming manifests together.

## App-Level Secrets

- app-local repo-encrypted secrets usually live beside the workload under `app/secret.sops.yaml`
- they must be registered in `app/kustomization.yaml`
- mounted or referenced Secret names must stay aligned with `helmrelease.yaml` and any sibling manifests

## Helper Recipes

The repo provides Just recipes under the `sops` group:

- `just sops re-encrypt`
- `just sops fix-mac`
- `just sops encrypt-file <path>`
- `just sops decrypt-file <path>`
