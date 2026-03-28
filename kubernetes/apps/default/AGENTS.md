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
- Do not assume VolSync is the only backup layer for an app. Some workloads also write a curated export into the shared `/backups/...` tree so `resticprofile` can capture a second copy in B2.
- Preserve app-specific export jobs, NFS backup mounts, and export paths when they already exist for a critical workload. Paperless is the reference pattern.
- For storage, compare against sibling apps first; several media-oriented apps combine PVC, NFS, and `emptyDir` mounts.
- User-facing app resource baseline:
  - set explicit `resources.requests.cpu`, `resources.requests.memory`, and `resources.limits.memory`
  - do not add CPU limits by default; use them only when a specific app needs throttling protection
  - size requests from live usage or close sibling apps instead of copying large generic values

## Validation

For app changes in this subtree:

1. Read `ks.yaml`, `app/kustomization.yaml`, and the main manifest set together.
2. Verify `dependsOn`, route targets, and secret names against sibling apps.
3. If the app is backed up, verify the VolSync-related substitutions and component wiring.
4. If the app also has an export path or backup job, verify the export mount, schedule, and destination path still match the shared `/backups/...` model.
