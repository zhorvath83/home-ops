# Validation

Use this reference after changing platform or app-level secret delivery.

## Platform Checks

1. operator, store, and Connect service still reconcile in the intended order
2. `onepassword-connect` ClusterSecretStore name remains stable unless the entire repo migration is intentional
3. recipe-backed flows such as `just k8s sync-es <name> <namespace>` and the `just cluster-bootstrap cluster` chain still match the secret names in the repo

## App-Level Checks

- mounted Secret refs match the generated Secret name
- any `dependsOn` assumptions still point to the shared store Kustomization
- sibling apps in the same subtree still reflect the same secret delivery model
