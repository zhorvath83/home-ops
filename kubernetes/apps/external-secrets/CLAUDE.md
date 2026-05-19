# External Secrets Platform Guide

This guide applies to `kubernetes/apps/external-secrets/`. It captures durable guardrails for the secret-delivery platform; for current-state detail (components, claims, drift risk, gaps) read the Basic Memory area-reference `docs/areas/external-secrets` via the `basic-memory` MCP.

## Scope

This subtree provides the secret delivery platform used by every other application — the External Secrets operator and 1Password Connect with the cluster-wide `ClusterSecretStore/onepassword-connect`. It is platform, not app workload.

## Sequencing Rules

Order matters here. Dependency chain:

1. External Secrets operator (`external-secrets`)
2. 1Password Connect (`onepassword-connect`)
3. OnePassword-backed `ClusterSecretStore` (applied as part of the `onepassword-connect` Flux Kustomization with a `ClusterSecretStore` health check)
4. Application `ExternalSecret` resources in other subtrees

Implications:

- If an app uses the `onepassword-connect` ClusterSecretStore, its Flux Kustomization should depend on `onepassword-connect`.
- Do not collapse the store into random app trees — it is intentionally co-located with the Connect Kustomization.

## OnePassword Connect Rules

- Runs in namespace `external-secrets` with upstream-specific UID/GID `999`, working data on `emptyDir`, credentials from `onepassword-secret`.
- Preserve UID/GID assumptions unless upstream changes require otherwise.
- Keep bootstrap secret names aligned across four places: `kubernetes/bootstrap/resources.yaml.j2`, the Connect HelmRelease `credentialsName`, the ClusterSecretStore `connectTokenSecretRef`, and the runtime ExternalSecrets. Renaming any one silently breaks the bootstrap chain.
- Verify both `api` and `sync` containers when changing ports, probes, or env vars.

## Canonical ExternalSecret Pattern

Every app `ExternalSecret` in this repo uses:

- `spec.refreshInterval: 12h` (ESO chart default is `1h`; the 12h cadence reduces load on 1Password Connect for slowly-rotated secrets — Reloader on consumer Pods still triggers restarts on actual Secret rewrites)
- `spec.secretStoreRef.kind: ClusterSecretStore`
- `spec.secretStoreRef.name: onepassword-connect`
- `spec.target.creationPolicy: Owner` for app-owned generated Secrets
- no `metadata.namespace` — the owning Flux Kustomization `spec.targetNamespace` places the ES at apply time

## Guardrails For Edits Here

- Distinguish operator configuration from app-level `ExternalSecret` usage.
- Preserve the shared store name `onepassword-connect` unless the entire repo is being migrated.
- Check whether `just k8s sync-es` and any other recipe-backed flows still match the resource names after a rename.

## Validation

See `.claude/skills/external-secrets/references/validation.md`.
