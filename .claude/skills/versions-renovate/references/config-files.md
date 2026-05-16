# Config Files

Use this reference when changing Renovate policy.

## Entry Point

`.renovaterc.json5` at the repo root is the main config. It extends the imported fragments under `.renovate/`.

## Imported Fragments

- `.renovate/allowedVersions.json5`
- `.renovate/autoMerge.json5`
- `.renovate/customManagers.json5`
- `.renovate/disabledDatasources.json5`
- `.renovate/groups.json5`
- `.renovate/overrides.json5`
- `.renovate/prBodyNotes.json5`
- `.renovate/semanticCommits.json5`
- `.renovate/talosFactory.json5`

## Current Live Behavior To Preserve Unless Intentional

- dependency dashboard enabled
- semantic commits enabled, refined per update type and per datasource in `semanticCommits.json5` (`feat`/`fix`/`chore` × `container`/`helm`/`github-action`/`github-release`/`talos` scopes)
- `:automergeBranch` preset extended at the root — auto-merges push directly to the target branch (`automergeType: "branch"`) instead of opening a PR
- patch and digest updates auto-merge on trusted publishers (`home-operations`, `onedr0p`, `bjw-s`, `bjw-s-labs`, `coredns`)
- minor and patch Helm chart updates auto-merge
- pre-commit hook updates auto-merge
- minimum release age is 3 days with `timestamp-optional` behaviour
- `registryAliases` maps `mirror.gcr.io` → `docker.io` so version lookups hit the source of truth
- Kubernetes YAML and Talos Jinja templates under `kubernetes/` are scanned by the Flux, Helm values, Kubernetes, and custom managers (`.yaml` and `.yaml.j2`)
- `kubernetes/bootstrap/helmfile.d/*.yaml` is scanned by the helmfile manager
- Flux controller images are explicitly disabled in `disabledDatasources.json5` (managed by FluxInstance)
- Kubernetes core images and `kubernetes/kubernetes` are pinned to the `1.36.x` line in `allowedVersions.json5`
- PostgreSQL images are capped at `<=18`
- OCI URIs (`oci://...:VERSION`) are tracked by a custom regex manager
- inline `# renovate: datasource=X depName=Y` annotations are tracked in `kubernetes/**/*.yaml(.j2)` and `mise.toml`
- Talos installer images referenced by literal `factory.talos.dev/...:vX.Y.Z` URLs are tracked against the `custom.talos-factory` datasource (`https://factory.talos.dev/versions` — factory-buildable versions only, narrower than github-releases)
- `registry.k8s.io/<image>:vX.Y.Z` tags are tracked against the docker datasource

If update behavior changes, inspect both the root config and the impacted fragment together before editing.
