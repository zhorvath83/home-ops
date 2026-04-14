# Bootstrap

## Prerequisites

- `kubectl` configured for the target cluster
- [1Password CLI](https://developer.1password.com/docs/cli/) (`op`) installed and signed in
- [SOPS](https://github.com/getsops/sops) installed
- [Task](https://taskfile.dev/) installed

## Bootstrap the cluster

Run the Flux install task from the repository root:

```sh
task fx:install
```

This single command performs the following steps in order:

1. Installs Flux controllers and CRDs (`kubernetes/bootstrap/flux`)
2. Applies the `cluster-settings` ConfigMap (`kubernetes/flux/vars/cluster-settings.yaml`)
3. Creates the `sops-age` secret in `flux-system` (Age key from 1Password)
4. Creates the `onepassword-secret` in `external-secrets` (1Password Connect credentials and token)
5. Decrypts and applies `cluster-secrets` from SOPS (`kubernetes/flux/vars/cluster-secrets.sops.yaml`)
6. Applies the Flux configuration that starts the GitOps reconciliation loop (`kubernetes/flux/config`)

After the task completes, Flux picks up the repository and reconciles the full cluster state.

## Force reconciliation

```sh
task fx:reconcile
```
