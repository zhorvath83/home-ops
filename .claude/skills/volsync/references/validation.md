# Validation

Use this reference after changing VolSync platform resources or app-level backup wiring.

## Platform Checks

1. Inspect the shared component defaults (`kubernetes/components/volsync/`) and the platform subtree together.
2. Verify that operator, maintenance, and Kopia resources still refer to the same names and namespaces.
3. Check whether `.taskfiles/VolSync/Tasks.yaml` still matches the resource names and expectations after the change.

## App-Level Checks

- `dependsOn` still points at the shared store and platform Kustomizations the app actually needs
- VolSync substitutions and the shared component wiring still match the app's UID/GID model
- if the app keeps a parallel curated export under `/backups/...` for `resticprofile`, that path and schedule still match the live model

## Useful Commands

- `task vs:list`, `task vs:status`, `task vs:last-backups` for snapshot inspection
- standard Flux and Kubernetes inspection tasks for reconcile state
