# App Scaffolding

Use this reference when adding a new workload or reshaping directory structure.

## Start Here

1. Inspect the target subtree guide and nearby sibling apps.
2. Confirm whether the app belongs in `selfhosted/` or a platform namespace.
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
    └── config/               # for non-secret static config only
```

For scheduled sidecar work, a sibling directory such as `backup/` is acceptable when the repo already uses that pattern.

## `ks.yaml`

- `ks.yaml` is the Flux entry point.
- Flux Kustomization names follow the simple `<app>` convention (e.g. `paperless`, `plex`, `backrest`). The Kustomization lives in the `flux-system` namespace but its workloads target `selfhosted` or another app namespace.
- `path` should point to the concrete child directory being applied.
- `dependsOn` must declare real startup dependencies; never rely on creation order.
- Use `postBuild.substitute` for repeated app-local values when the sibling pattern already does that.
- Do not add app-local `volsync.yaml` for normal backups; use the shared component model.

## Dependency Heuristics

- PVC-backed app: add the CSI dependency used by sibling apps (typically `democratic-csi`).
- App secrets from 1Password: add `dependsOn: [{ name: onepassword-connect }]` (the Kustomization that applies the 1Password Connect Deployment and the `ClusterSecretStore/onepassword-connect`).
- App needs another in-cluster service on startup: depend on that app's Flux Kustomization.
- Child or sidecar workload: depend on the parent app when ordering matters.

Always verify sibling apps in the same subtree before copying a dependency pattern.

## `app/kustomization.yaml`

- List only resources physically present in the directory.
- Keep resource ordering close to the live repo pattern.
- **Do NOT add a top-level `namespace:` field.** The Flux Kustomization in `ks.yaml` `spec.targetNamespace` is the single source of truth for namespace placement; duplicating it in the kustomize layer was repo-wide noise and was dropped. Bare `resources:` list is the canonical shape.
- **Do NOT add `labels:` / `commonLabels:` blocks.** The Flux Kustomization in `ks.yaml` already injects `app.kubernetes.io/name` through `spec.commonMetadata.labels` for every child resource — duplicating it in the kustomize layer is redundant and was dropped repo-wide.
- `configMapGenerator` is allowed (homepage + paperless use it). Pair it with `generatorOptions.disableNameSuffixHash: true` and, when the data contains `${...}` literals that must not be substituted by Flux postBuild, `annotations.kustomize.toolkit.fluxcd.io/substitute: disabled`.

Typical resource order:

1. `ocirepository.yaml`
2. `externalsecret.yaml` if present
3. `helmrelease.yaml`
4. extra resources after that (`ciliumnetworkpolicy.yaml`, `pvc.yaml`, custom config, etc.)

## Common Manifest Rules (all kinds under `app/`)

- **Do NOT add `metadata.namespace` to any app manifest** (`helmrelease.yaml`, `externalsecret.yaml`, `httproute.yaml`, `ocirepository.yaml`, `ciliumnetworkpolicy.yaml`, `pvc.yaml`, etc.). The Flux Kustomization `spec.targetNamespace` in `ks.yaml` is the single authoritative source of namespace placement; Flux injects it at apply time. Repeating it on every manifest was K3s-era noise and was dropped repo-wide.
- Schema annotation comments (`# yaml-language-server: $schema=...`) belong on the second line of each manifest when a stable schema URL exists for the kind.

## `ocirepository.yaml`

- Every HelmRelease should have a matching `ocirepository.yaml` in the same directory.
- `OCIRepository.metadata.name` must match `HelmRelease.metadata.name`.
- Keep `interval` and URL patterns aligned with sibling apps and live repo conventions.

## `helmrelease.yaml`

HelmRelease `spec` is intentionally minimal — see `kubernetes/CLAUDE.md` "HelmRelease minimal-spec policy" for the authoritative rule. In short:

- Allowed top-level `spec` fields: `chartRef`, `interval`, `values` (and very rarely `postRenderers` when an upstream chart leaves no other way to patch a manifest field — `nextcloud`-style).
- The cluster-root `Kustomization` (`kubernetes/flux/cluster/ks.yaml`) injects `install`, `rollback`, `timeout`, `upgrade` defaults into every HelmRelease through a kustomize patch. **Never repeat or override those fields per-app.** Adding `install.createNamespace`, `install.remediation.retries`, `upgrade.remediation.{strategy,retries}`, or `uninstall.keepHistory` to a HelmRelease is no-op drift at best and a maintenance trap at worst — it was historical noise from the K3s era and has been dropped repo-wide.
- If a future app genuinely needs a different remediation profile, change the root patch in `kubernetes/flux/cluster/ks.yaml` instead of re-introducing per-HR drift.
- YAML anchors in HelmRelease values are allowed for **scalar values reused multiple times** (`&port`, `&httpPort`, `&host`, `&tz`, `&exportDir`, `&resources`, `&probes`, `&image`). Anchors on `metadata.name` or as map keys for `controllers`/`persistence`/`serviceAccount`/`bindings` are forbidden — see `kubernetes/CLAUDE.md` "YAML anchor policy" for examples and rationale.

## `externalsecret.yaml`

- `spec.refreshInterval: 12h` is the repo-wide default. The ESO chart default is `1h`, which generates unnecessary load on 1Password Connect for secrets that change only on rotation; the Reloader annotation on consuming pods triggers restarts on the actual Secret rewrite, independent of polling cadence.
- `spec.secretStoreRef.kind: ClusterSecretStore`, `spec.secretStoreRef.name: onepassword-connect` — this is the only store in the repo.
- `spec.target.creationPolicy: Owner` for ESO-owned generated Secrets.
- Prefer `spec.dataFrom.extract` (single-extract from a 1Password item) over `spec.data[].remoteRef` when the entire item is consumed; use the explicit `data[]` form only when cherry-picking specific fields.
- For config-as-secret content (templated multi-line config files, e.g. homepage), use `spec.target.template.data` to render the file from 1Password fields. Multi-line text in 1Password works directly.
