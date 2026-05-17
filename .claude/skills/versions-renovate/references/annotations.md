# Annotations

Use this reference when editing inline `# renovate:` comments in repo files.

## General Rules

- preserve existing inline `# renovate:` comments when touching versioned manifests
- match the local neighboring pattern before inventing a new annotation form
- keep the annotation immediately above the field or resource it describes

## Live Examples In This Repo

- the `TALOS_VERSION` and `KUBERNETES_VERSION` env values in `.mise.toml` (annotated with `# renovate: datasource=...`)
- container image tags in `kubernetes/**/*.yaml(.j2)` HelmRelease values and raw manifests
- OCI URIs (`oci://...:VERSION`) tracked by the OCI custom manager
- Talos installer image URLs (`factory.talos.dev/...:vX.Y.Z`) tracked against the `custom.talos-factory` datasource
- Kustomize remote resources in `kustomization.yaml`
- Grafana dashboard revision tracking comments in Helm values
- provider-level disable directives in Terraform such as `# renovate:disablePlugin ...`

## Current Coverage Notes

- built-in Renovate managers already scan Kubernetes YAML under `kubernetes/`
- the custom regex managers in `.renovate/customManagers.json5` also scan `kubernetes/**/*.yaml(.j2)` and `mise.toml` for the inline annotation pattern; `.renovate/talosFactory.json5` handles literal Talos factory URLs separately
- other repo areas may rely on different manager behavior or manual review, so inspect current examples before assuming a new annotation will be discovered automatically

When a dependency cannot be discovered automatically, add the smallest annotation pattern already used nearby.
