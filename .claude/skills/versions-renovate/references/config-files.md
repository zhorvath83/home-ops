# Config Files

Use this reference when changing Renovate policy.

## Entry Point

`.github/renovate.json5` is the main config. It extends the imported fragments under `.github/renovate/`.

## Imported Fragments

- `allowedVersions.json`
- `autoMerge.json`
- `disabledDatasources.json`
- `groupPackages.json`
- `packageRules.json`
- `prBodyNotes.json`

## Current Live Behavior To Preserve Unless Intentional

- dependency dashboard enabled
- semantic commits enabled
- patch updates auto-merge
- docker digest updates auto-merge
- major Docker and Helm updates are labeled for review
- minimum release age is 3 days
- Kubernetes YAML under `kubernetes/` is scanned by Flux, Helm values, Kubernetes, and custom regex managers
- Flux controller images are explicitly ignored in `ignoreDeps`
- pre-commit dependency updates are enabled
- some packages are grouped or version-constrained in the imported fragments

If update behavior changes, inspect both the root config and the impacted fragment together before editing.
