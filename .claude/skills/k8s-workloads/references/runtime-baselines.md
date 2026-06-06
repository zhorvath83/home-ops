# Runtime Baselines

Use this reference for container hardening, resources, storage, and config handling.

## Security Defaults

Both blocks below are **mandatory** on every new app workload. Deviate only when the image truly cannot be made to run with them; document the reason inline next to the relaxed field.

Pod level — under `spec.values.defaultPodOptions`:

```yaml
defaultPodOptions:
  automountServiceAccountToken: false
  enableServiceLinks: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    fsGroupChangePolicy: OnRootMismatch
    seccompProfile:
      type: RuntimeDefault
```

Container level — under each `containers.<name>`:

```yaml
securityContext:
  privileged: false
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities: {drop: ["ALL"]}
```

`automountServiceAccountToken: true` is allowed only when the workload calls the Kubernetes API with an explicit ServiceAccount and bound RBAC.

UID/GID may diverge from `10001` only when the image hardcodes ownership to a different id and overriding breaks the workload. Match it then to the image's native id and align `APP_UID` / `APP_GID` in `ks.yaml` `postBuild.substitute`.

Writable paths must be added explicitly as `emptyDir` or PVC mounts. Do not add `privileged`, `hostNetwork`, or `hostPID` without a clear upstream or live-sibling justification.

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
