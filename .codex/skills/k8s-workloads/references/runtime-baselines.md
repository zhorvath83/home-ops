# Runtime Baselines

Use this reference for container hardening, resources, storage, and config handling.

## Security Defaults

Prefer this baseline unless live behavior proves an exception is required:

- pod-level `runAsNonRoot: true`
- aligned `runAsUser`, `runAsGroup`, and `fsGroup`
- `fsGroupChangePolicy: OnRootMismatch`
- `seccompProfile.type: RuntimeDefault`
- container-level `allowPrivilegeEscalation: false`
- container-level `readOnlyRootFilesystem: true`
- dropped capabilities
- writable paths added explicitly with `emptyDir` or PVC mounts

Keep exceptions narrow and preserve or add an inline explanation when a workload truly needs root, privilege, or a writable root filesystem.

Do not add `privileged`, `hostNetwork`, or `hostPID` unless the live sibling pattern or upstream requirement clearly justifies the exception.

## Resources And Health

Every new or substantially changed app should have:

- resource requests
- at least memory limits where appropriate
- health probes suitable for the app
- a restart trigger such as `reloader.stakater.com/auto: "true"` when ConfigMaps or Secrets are mounted

Enable a startup probe when boot time is long or readiness is noisy.

Prefer memory limits without CPU limits unless the workload has a specific need for CPU throttling.

## `APP_UID` And `APP_GID`

When the app uses VolSync or PUID and PGID style images:

- define `APP_UID` and `APP_GID` once in `ks.yaml` `postBuild.substitute`
- reuse them in pod security context
- reuse them in env vars like `PUID` and `PGID` when needed
- let the shared VolSync component inherit them for mover ownership

Do not hardcode the same numeric IDs in multiple places if `postBuild` can provide them once.

## Storage Decisions

Choose storage intentionally:

- app config or state persisted in-cluster: PVC, usually the existing claim for the app
- shared media or NAS data: NFS mounts using the established repo pattern
- temporary writable paths for hardened containers: `emptyDir`
- separate cache or special-purpose PVC: only when the shared app storage model does not cover the need

If the app should be backed up, use the shared VolSync component rather than inventing app-local backup manifests.

Do not duplicate PVC or backup patterns locally when the shared component model already covers the case.

## Config Files

For non-secret static config:

- keep files under `app/config/`
- generate a ConfigMap or Secret from `app/kustomization.yaml`
- mount them explicitly
- use an init container only when the image requires copying files into a writable target path

Do not place secrets in `config/`.
