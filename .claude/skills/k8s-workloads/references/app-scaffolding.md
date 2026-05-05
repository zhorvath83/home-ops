# App Scaffolding

Use this reference when adding a new workload or reshaping directory structure.

## Start Here

1. Inspect the target subtree guide and nearby sibling apps.
2. Confirm whether the app belongs in `default/` or a platform namespace.
3. Decide chart strategy in this order:
   - official chart
   - bjw-s `app-template`
   - custom manifests only when needed

## Standard Shape

For a normal app under `kubernetes/apps/<group>/<app>/`:

```text
kubernetes/apps/<group>/<app>/
├── ks.yaml
└── app/
    ├── kustomization.yaml
    ├── ocirepository.yaml
    ├── helmrelease.yaml
    ├── externalsecret.yaml   # if app-managed secrets are needed
    ├── secret.sops.yaml      # if repo-encrypted secret data is needed
    └── config/               # for non-secret static config only
```

For scheduled sidecar work, a sibling directory such as `backup/` is acceptable when the repo already uses that pattern.

## `ks.yaml`

- `ks.yaml` is the Flux entry point.
- Flux Kustomization names follow `cluster-apps-<app>`.
- `path` should point to the concrete child directory being applied.
- `dependsOn` must declare real startup dependencies; never rely on creation order.
- Use `postBuild.substitute` for repeated app-local values when the sibling pattern already does that.
- Do not add app-local `volsync.yaml` for normal backups; use the shared component model.

## Dependency Heuristics

- PVC-backed app: add the CSI dependency used by sibling apps.
- App secrets from 1Password: add `cluster-apps-onepassword-store`.
- App needs another in-cluster service on startup: depend on that app's Flux Kustomization.
- Child or sidecar workload: depend on the parent app when ordering matters.

Always verify sibling apps in the same subtree before copying a dependency pattern.

## `app/kustomization.yaml`

- List only resources physically present in the directory.
- Keep resource ordering close to the live repo pattern.
- Preserve labels and namespace conventions already used by siblings.

Typical resource order:

1. `ocirepository.yaml`
2. `externalsecret.yaml` if present
3. `secret.sops.yaml` if present
4. `helmrelease.yaml`
5. extra resources after that

## `ocirepository.yaml`

- Every HelmRelease should have a matching `ocirepository.yaml` in the same directory.
- `OCIRepository.metadata.name` must match `HelmRelease.metadata.name`.
- Do not add `namespace` to OCIRepository metadata or to the HelmRelease `chartRef` block.
- Keep `interval` and URL patterns aligned with sibling apps and live repo conventions.
