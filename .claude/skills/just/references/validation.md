# Validation

Use this reference after editing the root `.justfile` or any `**/mod.just`.

## Read-Back Checklist

Read the touched files together:

1. root `.justfile` (group declarations, helpers)
2. the touched `mod.just`
3. `.mise.toml` if any env-driven value or tool version changed

## Static Checks

- `just --list` parses every recipe and prints all groups; a parse error fails here first
- `just --list <group>` prints recipe descriptions; verify the recipe shows up where expected
- `just --dry-run <group> <recipe> [args]` prints the rendered command without executing
- verify the group label is included in the root `.justfile` (the recipe stays invisible without it)

## Behavioral Checks

- run the smallest available real recipe in the touched mod when the environment supports it (e.g. `just k8s flux-check`, `just cloudflare plan`)
- if the recipe shells out to an external tool, confirm the tool is declared in `.mise.toml`
- if the recipe reads an env var (e.g. `TALOS_VERSION`, `KUBECONFIG`), confirm the value is set in `.mise.toml` or the operator's shell

## Pre-Commit

Run `pre-commit run --all-files` before pushing — the hook list lives in `.pre-commit-config.yaml`. There is no `just`-namespaced wrapper for this; use the `pre-commit` CLI directly.

If validation cannot run, say whether the blocker is missing tooling, credentials, or cluster access.
