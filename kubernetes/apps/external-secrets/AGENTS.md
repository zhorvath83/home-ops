# External Secrets Platform Guide

This guide applies to `kubernetes/apps/external-secrets/`.

## What Is Special Here

This subtree provides the secret delivery platform used by many other applications.

Current live layers:

- `external-secrets/` deploys the operator itself
- `onepassword-connect/` deploys the 1Password Connect service
- the onepassword `ClusterSecretStore` is applied as a separate Flux Kustomization under `external-secrets/external-secrets/stores/onepassword`

## Sequencing Rules

Order matters here.

Current dependency chain:

1. External Secrets operator
2. OnePassword-backed ClusterSecretStore
3. Application `ExternalSecret` resources in other subtrees

Implication:

- if an app uses `ClusterSecretStore` `onepassword`, its Flux Kustomization should depend on `cluster-apps-onepassword-store`
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

For external-secrets platform changes, verify:

1. the operator, store, and connect service still reconcile in the correct order
2. the `onepassword` ClusterSecretStore name remains stable
3. app `dependsOn` assumptions elsewhere in the repo still make sense
4. Taskfile flows such as `task es:sync` and Flux bootstrap still reference the same secret names
