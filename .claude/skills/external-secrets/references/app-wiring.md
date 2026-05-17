# App Wiring

Use this reference when a change involves app-level `ExternalSecret` resources.

## Standard Pattern

- `secretStoreRef.kind: ClusterSecretStore`
- `secretStoreRef.name: onepassword-connect`
- deterministic target Secret name
- `target.creationPolicy: Owner` for app-owned generated Secrets

## Data Mapping

- prefer `dataFrom.extract` when the source item shape maps cleanly to the app
- use `template.data` when fields need renaming or composition

## Dependency And Naming Checks

- app Flux Kustomizations that rely on the shared store should declare `dependsOn: [{ name: onepassword-connect }]` (the `onepassword-connect` Flux Kustomization applies both the 1Password Connect Deployment and the `ClusterSecretStore/onepassword-connect`, with a `ClusterSecretStore` health check)
- generated Secret names must match every mount, env var, or `envFrom` reference
- recipe-backed sync or bootstrap flows (`just k8s sync-es <name> <namespace>`, `just cluster-bootstrap cluster`) must still refer to the same secret names after the change
