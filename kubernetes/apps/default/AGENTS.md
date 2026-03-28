# Default Apps Guide

This guide applies to `kubernetes/apps/default/`.

## What Is Special Here

This subtree contains user-facing application workloads rather than shared platform plumbing.

Common live patterns here:

- one app per directory with a `ks.yaml` entry point
- main manifests under `app/`
- optional extra directories such as `backup/` for scheduled jobs or sidecar workloads
- a mix of app-template Helm releases and upstream charts

## Guardrails

- Inspect 2-3 sibling apps with similar exposure, storage, and auth needs before changing structure.
- Prefer official charts first, then bjw-s `app-template`, then custom manifests only when needed.
- Routes for published apps usually target `envoy-external` in namespace `networking`.
- User-facing apps that should appear on the dashboard usually carry Homepage annotations.
- App-managed secrets usually come from an `ExternalSecret` backed by the `onepassword` ClusterSecretStore.
- Backed-up apps should use the shared VolSync component in `ks.yaml` rather than app-local backup manifests.
- For storage, compare against sibling apps first; several media-oriented apps combine PVC, NFS, and `emptyDir` mounts.

## Validation

For app changes in this subtree:

1. Read `ks.yaml`, `app/kustomization.yaml`, and the main manifest set together.
2. Verify `dependsOn`, route targets, and secret names against sibling apps.
3. If the app is backed up, verify the VolSync-related substitutions and component wiring.
