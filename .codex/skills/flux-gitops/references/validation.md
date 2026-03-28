# Validation

Use this reference after changing shared Flux or GitOps configuration.

## Read-Back Checklist

Read the touched files together:

1. parent `ks.yaml` or Flux Kustomization objects
2. the referenced `kustomization.yaml`
3. any touched file in `kubernetes/flux/config/`, `kubernetes/flux/vars/`, or `kubernetes/apps/flux-system/`

## Consistency Checks

- verify Flux object names and `dependsOn` references still match the repo's live naming scheme
- verify shared vars still match the manifests that consume them
- verify webhook, provider, and receiver resources still agree on names and namespaces
- if bootstrap flow changed, verify `task fx:install` still points at the same secret and vars files
- if app dependencies changed, confirm the effect is intentionally cluster-wide rather than app-local

If validation cannot run, say whether the blocker is missing Flux tooling, credentials, or cluster access.
