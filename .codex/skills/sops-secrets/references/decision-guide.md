# Decision Guide

Use this reference when deciding whether a secret belongs in SOPS or in External Secrets.

## Prefer SOPS When

- the secret is a cluster-wide substitution under `kubernetes/flux/vars/`
- the secret must live in git as part of steady-state desired state
- the app already uses `secret.sops.yaml` in its own tree
- the secret is part of bootstrap or recovery flow that expects a repo-encrypted file

## Prefer External Secrets When

- the value should be sourced from 1Password rather than stored in repo
- the app follows the shared `ClusterSecretStore` `onepassword` pattern
- the task is about operator ordering, store names, or templated extraction from 1Password items

## Mixed Cases

- if an app has both `ExternalSecret` output and a repo-encrypted supplemental secret, keep the responsibilities separate
- do not migrate between SOPS and External Secrets unless the task explicitly calls for that model change
