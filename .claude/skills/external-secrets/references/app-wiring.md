# App Wiring

Use this reference when a change involves app-level `ExternalSecret` resources.

## Standard Pattern

- `secretStoreRef.kind: ClusterSecretStore`
- `secretStoreRef.name: onepassword`
- deterministic target Secret name
- `target.creationPolicy: Owner` for app-owned generated Secrets

## Data Mapping

- prefer `dataFrom.extract` when the source item shape maps cleanly to the app
- use `template.data` when fields need renaming or composition

## Dependency And Naming Checks

- app Flux Kustomizations that rely on the shared store should depend on `cluster-apps-onepassword-store`
- generated Secret names must match every mount, env var, or `envFrom` reference
- task-backed sync or bootstrap flows must still refer to the same secret names after the change
