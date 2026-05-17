# Authoring

Use this reference when adding or modifying Just recipes.

## File Layout

- root `.justfile` holds globals (`set lazy`, `set positional-arguments`, `set quiet`, bash interpreter with `-euo pipefail`) and the mod-group import block
- each domain owns a `mod.just` co-located with the area it operates on (e.g. `kubernetes/mod.just`, `provision/cloudflare/mod.just`)
- shared helpers (`log`, `template`) are defined in the root `.justfile` as `[private]` `[script]` recipes and reused across mods

## Recipe Conventions

- always include a one-line doc comment immediately above the recipe header — `just --list` renders it as the description
- arguments are positional only; document positional defaults in the doc comment when the recipe has more than 2 args
- prefer `[script]` recipes when the body needs multi-line bash; plain recipes are fine for single-command wrappers
- read env values from `.mise.toml` rather than redefining them inside the recipe (e.g. `TALOS_VERSION`, `KUBERNETES_VERSION`, `KUBECONFIG`, `NAS_MOUNT_SCRIPT`); inside `mod.just` use `env_var('NAME')` to surface them as justfile variables
- group related recipes in the same `mod.just` with `[group: 'name']` labels for `--list` ordering

## Adding A New Mod Group

1. Create the `mod.just` next to the area it operates on
2. Add `mod <name> "<path>"` (with optional `[group: '<label>']`) to the root `.justfile` in alphabetical order
3. Verify the group shows up in `just --list`
4. Document any new external CLI dependency in `.mise.toml` first; do not assume the operator has it installed

## What Not To Do

- do not introduce `key=value` named-argument syntax — it does not work in Just
- do not chain shell commands across recipe boundaries; if two steps belong together, put them in one recipe and call it from elsewhere
- do not duplicate logic across mods; factor shared scripts into a dedicated `_<purpose>.sh` file next to the primary mod and invoke it from each consumer (precedent: `kubernetes/talos/_resolve-controller.sh` shared by `kubernetes/talos/mod.just` and `kubernetes/bootstrap/mod.just`)
- do not bypass `op run` / `op inject` for credentials when the existing recipe already uses them

## Common Pitfalls

- **Subshell `exit` swallowed by `$(…)`**: a helper that calls `exit 1` from inside `$(fn …)` only kills the subshell, not the recipe. Use `return 1` in the helper and `value=$(fn …) || exit 1` at each call site. Precedents in-repo: `kubernetes/talos/mod.just` `gen-secrets extract()` (commit a63d5a710) and `provision/ovh/mod.just` `apply` output-fetch (commit 90a38cae3).
- **`set -e` does not propagate through `local`**: `local var=$(cmd)` always returns 0 because `local` itself succeeds. Split into `local var; var=$(cmd) || exit 1` when failure must propagate.
- **mise template functions ≠ Just functions**: `.mise.toml` `[env]` blocks use Tera with `get_env(name="HOME")` (mise's name); Just `mod.just` files use `env_var('HOME')`. The Just builtin does not work in mise.toml, and vice versa.
- **`pipefail` and `tail`**: `cmd 2>&1 | tail -N` fails if `cmd` fails (with `pipefail` on); use `|| true` only when `cmd` failure is genuinely tolerable, not as a reflex.
