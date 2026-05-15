# External Secrets Platform Guide

This guide applies to `kubernetes/apps/external-secrets/`.

## What Is Special Here

This subtree provides the secret delivery platform used by many other applications.

Current live layers:

- `external-secrets/` deploys the operator itself
- `onepassword-connect/` deploys the 1Password Connect service
- the onepassword `ClusterSecretStore` is applied as a separate Flux Kustomization under `onepassword-connect/stores/onepassword` (co-located with the 1Password Connect app, since the store is functionally useless without it)

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
- keep secret key names aligned with the Taskfile bootstrap flow
- verify both `api` and `sync` containers if changing ports, probes, or env vars

## ExternalSecret Rules For The Repo

Common live pattern across app trees:

- `secretStoreRef.kind: ClusterSecretStore`
- `secretStoreRef.name: onepassword`
- `target.creationPolicy: Owner` for app-owned generated Secrets

When editing this platform area:

- distinguish operator configuration from app-level `ExternalSecret` usage
- preserve the shared store name `onepassword` unless the entire repo is being migrated
- check whether task-based secret syncing behavior still matches the resource names

## Validation

See `.claude/skills/external-secrets/references/validation.md` for the validation procedure.
