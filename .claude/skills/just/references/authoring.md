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
- read env values from `.mise.toml` rather than redefining them inside the recipe (e.g. `TALOS_VERSION`, `KUBERNETES_VERSION`, `KUBECONFIG`)
- group related recipes in the same `mod.just` with `[group: 'name']` labels for `--list` ordering

## Adding A New Mod Group

1. Create the `mod.just` next to the area it operates on
2. Add `mod <name> "<path>"` (with optional `[group: '<label>']`) to the root `.justfile` in alphabetical order
3. Verify the group shows up in `just --list`
4. Document any new external CLI dependency in `.mise.toml` first; do not assume the operator has it installed

## What Not To Do

- do not introduce `key=value` named-argument syntax — it does not work in Just
- do not chain shell commands across recipe boundaries; if two steps belong together, put them in one recipe and call it from elsewhere
- do not duplicate logic across mods; factor shared scripts into the helper recipes or a dedicated `scripts/` file invoked from a recipe
- do not bypass `op run` / `op inject` for credentials when the existing recipe already uses them
