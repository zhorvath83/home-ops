# Validation

Use this reference after changing SOPS-encrypted secret files or their workflows.

## Read-Back Checklist

Read together:

1. the touched `.sops.yaml`-managed secret file
2. the referencing `kustomization.yaml` or Flux vars file
3. the workload or bootstrap manifest that consumes the Secret

## Consistency Checks

- verify no plaintext secret material was introduced
- verify generated Secret names still match all mounts, env refs, or substitutions
- verify app-local `secret.sops.yaml` files are still listed in `kustomization.yaml`
- verify cluster-wide key names still match the manifests that use them
- if bootstrap flow changed, verify `just k8s-bootstrap cluster` (rendered from `kubernetes/bootstrap/resources.yaml.j2`) and the `just sops` recipes still line up with the manifests

## Useful Commands

- `just sops re-encrypt` for broad refresh after structural edits
- `just sops encrypt-file <path>` for newly added secret files
- `just sops fix-mac` when a MAC mismatch needs repair

If validation cannot run, say whether the blocker is missing `sops`, Age keys, or other local credentials.
