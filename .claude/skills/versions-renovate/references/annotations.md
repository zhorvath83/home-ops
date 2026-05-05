# Annotations

Use this reference when editing inline `# renovate:` comments in repo files.

## General Rules

- preserve existing inline `# renovate:` comments when touching versioned manifests
- match the local neighboring pattern before inventing a new annotation form
- keep the annotation immediately above the field or resource it describes

## Live Examples In This Repo

- Kubernetes plan version fields such as `version: "v1.35.2+k3s1"`
- Kustomize remote resources in `kustomization.yaml`
- Grafana dashboard revision tracking comments in Helm values
- provider-level disable directives in Terraform such as `# renovate:disablePlugin ...`

## Current Coverage Notes

- built-in Renovate managers already scan Kubernetes YAML under `kubernetes/`
- the custom regex manager in `.github/renovate.json5` also scans `kubernetes/` YAML for the existing inline annotation pattern
- other repo areas may rely on different manager behavior or manual review, so inspect current examples before assuming a new annotation will be discovered automatically

When a dependency cannot be discovered automatically, add the smallest annotation pattern already used nearby.
