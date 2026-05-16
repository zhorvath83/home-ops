# Catalog

Use this reference to rebuild the current Just surface before editing.

## Entry Point

`.justfile` at the repo root is the command index. It imports mod-groups from sibling directories:

| Group | Module file |
|---|---|
| `k8s` | `kubernetes/mod.just` |
| `cluster-bootstrap` | `kubernetes/bootstrap/mod.just` |
| `talos` | `kubernetes/talos/mod.just` |
| `volsync` | `kubernetes/volsync/mod.just` |
| `omv` | `provision/openmediavault/mod.just` |
| `cloudflare` | `provision/cloudflare/mod.just` |
| `ovh` | `provision/ovh/mod.just` |
| `sops` | `provision/sops/mod.just` |
| `openwrt` | `provision/openwrt/mod.just` |

`just` (no args) prints the top-level group list. `just --list <group>` prints the recipes inside a group.

## Recipe Conventions

- Recipe arguments are **positional only** (`set positional-arguments`). Defaults shown in `--list` like `restore app ns="default"` are positional defaults, not named arguments.
- Shared globals at the top of `.justfile`: `set lazy`, `set quiet`, `set positional-arguments`, bash interpreter with `-euo pipefail`.
- Two private helpers (`log`, `template`) are reusable across mods via the `log` and `template` recipes.
- Env values come from `.mise.toml` (`TALOS_VERSION`, `KUBERNETES_VERSION`, `KUBECONFIG`, `TALOSCONFIG`, etc.) — recipes read them, do not redefine them.

## Domain Surface To Preserve Unless Intentional

- `cluster-bootstrap cluster` — full Talos + Kubernetes platform bootstrap entry point. Replaces the historical `task fx:install` flow.
- `k8s flux-reconcile` / `k8s flux-check` / `k8s sync-hr` / `k8s sync-ks` / `k8s sync-es` / `k8s sync <resource>` — Flux operations.
- `k8s restart-failed-hrs`, `k8s list-failed-hrs`, `k8s apply-ks` / `delete-ks` — Flux recovery.
- `k8s mount-pvc`, `k8s browse-pvc`, `k8s node-shell`, `k8s view-secret`, `k8s prune-pods` — debug helpers.
- `talos apply-node`, `talos render-config`, `talos upgrade-node`, `talos upgrade-k8s` — Talos lifecycle. `upgrade-node` and `upgrade-k8s` read the target version from `.mise.toml` (`TALOS_VERSION`, `KUBERNETES_VERSION`), no positional version arg.
- `talos get-kubeconfig`, `talos gen-secrets`, `talos gen-talosconfig`, `talos gen-schematic-id`, `talos bootstrap` — one-time setup.
- `talos diag`, `talos status`, `talos reset-cluster`, `talos reset-node`, `talos reboot-node`, `talos shutdown-node` — diagnostics + recovery.
- `volsync restore`, `volsync snapshot`, `volsync snapshot-all`, `volsync list-snapshots`, `volsync rs-status`, `volsync last-backups`, `volsync state`, `volsync kopia-maintenance` — backup plane operations.
- `cloudflare init|plan|apply|unlock`, `ovh init|plan|apply|unlock` — Terraform per provider, credentials injected via `op run`.
- `sops re-encrypt|fix-mac|encrypt-file|decrypt-file` — repo SOPS helpers.
- `omv install|check|update|update-host`, `openwrt maintain|upgrade|reinstall-packages` — provisioning entry points.

If a recipe needs renaming, removing, or splitting, inspect the root `.justfile` group label, the parent `mod.just`, and any inline `# renovate:` annotations together before editing.
