# Bootstrap And App Secrets

Use this reference to understand where repo-encrypted secrets are consumed.

## Cluster-Wide Secrets

- `kubernetes/flux/vars/cluster-secrets.sops.yaml` holds sensitive cluster-wide substitutions
- `kubernetes/flux/vars/cluster-settings.yaml` remains the non-secret counterpart
- if one changes, inspect the other when substitution keys or naming are involved

## Bootstrap Flow

`task fx:install` currently:

1. creates `sops-age` in `flux-system`
2. creates the `onepassword-secret` bootstrap secret in `external-secrets`
3. decrypts `kubernetes/flux/vars/cluster-secrets.sops.yaml`
4. applies the Flux config under `kubernetes/flux/config/`

If a secret name or file path changes, inspect that task flow together with the manifests.

## App-Level Secrets

- app-local repo-encrypted secrets usually live beside the workload under `app/secret.sops.yaml`
- they must be registered in `app/kustomization.yaml`
- mounted or referenced Secret names must stay aligned with `helmrelease.yaml` and any sibling manifests

## Helper Tasks

The repo already provides:

- `task so:re-encrypt`
- `task so:fix-mac`
- `task so:encrypt-file file=...`
- `task so:decrypt-file file=...`
