# External Secrets Platform Guide

This guide applies to `kubernetes/apps/external-secrets/`.

## What Is Special Here

This subtree provides the secret delivery platform used by many other applications.

Current live layers:

- `external-secrets/` deploys the operator itself
- `onepassword-connect/` deploys the 1Password Connect service AND its `ClusterSecretStore/onepassword-connect` in the same Flux Kustomization (manifest at `onepassword-connect/app/clustersecretstore.yaml`); the Kustomization carries a `ClusterSecretStore` health check so dependents only proceed once the store reports `Ready=True`

## Sequencing Rules

Order matters here.

Current dependency chain:

1. External Secrets operator (`external-secrets`)
2. 1Password Connect (`onepassword-connect`)
3. OnePassword-backed ClusterSecretStore (`onepassword-connect`, applied as part of the `onepassword-connect` Flux Kustomization with a `ClusterSecretStore` health check)
4. Application `ExternalSecret` resources in other subtrees

Implication:

- if an app uses `ClusterSecretStore` `onepassword-connect`, its Flux Kustomization should depend on `onepassword-connect`
- do not collapse the store into random app trees

## OnePassword Connect Rules

Observed live behavior:

- runs in namespace `external-secrets`
- uses upstream-specific UID/GID `999`
- stores working data in an `emptyDir`
- reads credentials from the `onepassword-secret`

When editing OnePassword Connect:

- preserve the UID/GID assumptions unless upstream changes require otherwise
- keep secret key names aligned with `kubernetes/bootstrap/resources.yaml.j2` — the `just cluster-bootstrap cluster` chain renders that template through `op inject` to create the `onepassword-secret` Secret consumed by this Deployment
- verify both `api` and `sync` containers if changing ports, probes, or env vars

## ExternalSecret Rules For The Repo

Common live pattern across app trees:

- `secretStoreRef.kind: ClusterSecretStore`
- `secretStoreRef.name: onepassword-connect`
- `target.creationPolicy: Owner` for app-owned generated Secrets

When editing this platform area:

- distinguish operator configuration from app-level `ExternalSecret` usage
- preserve the shared store name `onepassword-connect` unless the entire repo is being migrated
- check whether `just k8s sync-es` and any other recipe-backed secret syncing behavior still matches the resource names

## Validation

See `.claude/skills/external-secrets/references/validation.md` for the validation procedure.
