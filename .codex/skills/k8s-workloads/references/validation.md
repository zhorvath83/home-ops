# Validation

Use this reference after changing an app workload.

## Read-Back Checklist

Read the touched files together:

1. `ks.yaml`
2. `app/kustomization.yaml`
3. `helmrelease.yaml`
4. any `externalsecret.yaml`, `secret.sops.yaml`, route, or extra manifest files

## Consistency Checks

- verify `dependsOn` against sibling apps
- verify namespace and naming consistency across Kustomization, HelmRelease, Secret refs, and routes
- if secrets are involved, confirm the generated Secret name matches all mounts and env references
- if backups are involved, verify VolSync substitutions and component wiring
- if publication is involved, verify parent refs and hostnames against the current networking model

## Useful Commands

- search sibling patterns with `rg`
- inspect task-backed entry points in `Taskfile.yml`
- use Flux and Kubernetes task wrappers when the environment is available

If validation cannot run, say whether the blocker is missing tooling, credentials, or cluster access.
