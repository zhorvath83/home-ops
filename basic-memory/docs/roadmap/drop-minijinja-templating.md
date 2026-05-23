---
title: drop-minijinja-templating
type: roadmap
permalink: home-ops/docs/roadmap/drop-minijinja-templating
topic: Drop minijinja templating — replace with envsubst + op inject
status: proposed
priority: low
scope: Eliminate all .yaml.j2 files and the minijinja-cli dependency. Replace the
  only meaningful Jinja constructs (env var substitution + a single {% if IS_CONTROLPLANE
  %} block) with envsubst and an inlined controlplane body. op inject keeps its current
  role for 1Password secret refs.
rationale: 'No current Jinja construct is strictly required: variable substitution
  is shell-replaceable, the {% if %} branch is dead code on a single-node CP-only
  cluster, and two .j2 files carry zero directives at all. Removing minijinja shrinks
  the toolchain and makes file extensions truthful.'
related_areas:
- talos-cluster
- flux-gitops
- external-secrets
---

## Metadata (observation-form, schema validation)

- [topic] Drop minijinja templating — replace with envsubst + op inject
- [status] proposed
- [priority] low

## Scope

Eliminate all `.yaml.j2` files and the `minijinja-cli` dependency from the repository. Replace the only meaningful Jinja constructs (env var substitution + a single `{% if IS_CONTROLPLANE %}` block) with `envsubst` and an inlined controlplane body. `op inject` keeps its current role for 1Password secret refs. The two `.j2` files that contain zero Jinja directives are simply renamed to `.yaml`.

## Rationale

Audit of the three in-tree `.yaml.j2` files and the inline `gen-talosconfig` heredoc shows that today no Jinja construct is strictly required to support current behavior: variable substitution is shell-replaceable, the `{% if %}` branch is dead code (cluster is single-node controlplane, `IS_CONTROLPLANE` always `true`), and two files carry zero directives at all. Removing minijinja shrinks the toolchain by one CLI, removes `.minijinja.toml`, removes the `(?:\.j2)?` regex suffix from Renovate path filters, and makes file extensions truthful (`.yaml` means YAML, no render step needed beyond `op inject`).

## Current Jinja inventory

- [file] `kubernetes/talos/machineconfig.yaml.j2` — only true Jinja user. Uses `{{ ENV.TALOS_VERSION }}`, `{{ ENV.KUBERNETES_VERSION }}`, `{{ ENV.TALOS_SCHEMATIC_ID }}` for version pinning and `{% if ENV.IS_CONTROLPLANE == "true" %}` blocks around CP-only fields (apiServer, controllerManager, scheduler, etcd, aggregatorCA, secretboxEncryptionSecret, serviceAccount, CA private keys).
- [file] `kubernetes/talos/nodes/k8s-cp0.yaml.j2` — zero Jinja directives, zero `op://` refs. `.j2` extension is convention only.
- [file] `kubernetes/bootstrap/resources.yaml.j2` — zero Jinja directives, only `op://` refs. `.j2` extension is misleading.
- [file] `kubernetes/talos/mod.just` lines 106-131 (`gen-talosconfig`) — inline heredoc named `secrets.yaml.j2`, processed only by `op inject`. Misleading name.

## Callers and references

- [recipe] `.justfile:45-46` — `just template` helper: `minijinja-cli {{ file }} {{ args }} | op inject`
- [recipe] `kubernetes/bootstrap/mod.just:91-95` — `stage-resources` calls `just template resources.yaml.j2 | kubectl apply --server-side -f -`
- [recipe] `kubernetes/talos/mod.just:256-270` — `render-config` runs `minijinja-cli --env machineconfig.yaml.j2 | op inject` and `minijinja-cli --env nodes/<node>.yaml.j2`
- [recipe] `kubernetes/talos/mod.just:18` and `kubernetes/bootstrap/mod.just:17` — node discovery globs `find ... -name '*.yaml.j2'`
- [config] `.mise.toml:5` (`MINIJINJA_CONFIG_FILE`), `:28` (`aqua:mitsuhiko/minijinja` pin)
- [config] `.minijinja.toml` (3-line config: `trim-blocks`, `lstrip-blocks`, `autoescape = "none"`)
- [config] `.renovaterc.json5:45,50,55` and `.renovate/customManagers.json5:8,19,32`, `.renovate/talosFactory.json5:19` — regex path filter `/^kubernetes/.+\.yaml(?:\.j2)?$/`
- [doc] `README.md:38,108,110,131`, `kubernetes/CLAUDE.md:10`, `kubernetes/bootstrap/readme.md:13,36`, `kubernetes/apps/external-secrets/CLAUDE.md:27`, `.claude/skills/versions-renovate/references/config-files.md:31`, `.claude/skills/flux-gitops/references/layout.md:7,16`, `.claude/skills/flux-gitops/references/validation.md:17`, `.claude/skills/just/references/catalog.md:36`, `kubernetes/talos/_resolve-controller.sh:20`

## Migration plan

### Phase 1 — low-risk renames (no Jinja inside, safe to start)

- [step] Rename `kubernetes/bootstrap/resources.yaml.j2` → `resources.yaml`. Update `bootstrap/mod.just:95` to skip `just template`: `op inject -i kubernetes/bootstrap/resources.yaml | kubectl apply --server-side -f -`.
- [step] Rename `kubernetes/talos/nodes/k8s-cp0.yaml.j2` → `k8s-cp0.yaml`. Update discovery globs in `kubernetes/talos/mod.just:18` and `kubernetes/bootstrap/mod.just:17` from `'*.yaml.j2'` to `'*.yaml'`. Update `talos/mod.just:269` to read the patch file without minijinja (`cat` or direct path arg to `talosctl machineconfig patch`).
- [step] Rename the inline heredoc target in `talos/mod.just` `gen-talosconfig` recipe from `secrets.yaml.j2` to `secrets.yaml`.
- [verification] `just talos render-config k8s-cp0` produces byte-identical output to pre-rename run.

### Phase 2 — the actual Jinja removal in machineconfig.yaml.j2

- [step] Pin `envsubst` as a tool dependency. Options: `aqua:a8m/envsubst` (Go reimplementation, easiest mise pin) OR rely on system `gettext`. Recommendation: aqua pin for reproducibility across dev machines.
- [step] Edit `machineconfig.yaml.j2`:
  - replace `{{ ENV.TALOS_VERSION }}` → `${TALOS_VERSION}`, `{{ ENV.KUBERNETES_VERSION }}` → `${KUBERNETES_VERSION}`, `{{ ENV.TALOS_SCHEMATIC_ID }}` → `${TALOS_SCHEMATIC_ID}`
  - remove the `{% if ENV.IS_CONTROLPLANE == "true" %} ... {% endif %}` wrappers and keep the controlplane body inline (current operational reality: single-node CP-only cluster)
- [step] Rename `machineconfig.yaml.j2` → `machineconfig-controlplane.yaml` (truthful naming — file is CP-only after the `{% if %}` inlining; symmetric with the future `machineconfig-worker.yaml` if a worker is ever added; renaming now avoids a second rename round under live conditions).
- [step] Update `talos/mod.just:268` to `envsubst < "{{ talos_dir }}/machineconfig-controlplane.yaml" | op inject > "${base}"` (hardcoded base — single-CP reality; role-aware base selection deferred until a second role actually exists). Drop the `IS_CONTROLPLANE` env line from `render-config` since the variable is no longer referenced.
- [verification] Diff rendered output between old (`minijinja-cli`) and new (`envsubst`) pipeline — must be byte-identical aside from Jinja whitespace artifacts (`trim-blocks`/`lstrip-blocks`). Use `talosctl machineconfig patch` to also verify final merge with the node patch.

### Phase 3 — cleanup

- [step] Remove `just template` helper recipe from `.justfile` if no remaining callers.
- [step] Drop `aqua:mitsuhiko/minijinja` from `.mise.toml [tools]` and delete the `MINIJINJA_CONFIG_FILE` line under `[env]`. Add `envsubst` pin if Phase 2 chose mise/aqua.
- [step] Delete `.minijinja.toml` from repo root.
- [step] Update Renovate regex path filters in `.renovaterc.json5` and `.renovate/customManagers.json5`, `.renovate/talosFactory.json5`: drop the `(?:\.j2)?` suffix from `/^kubernetes/.+\.yaml(?:\.j2)?$/`. This must happen AFTER all `.j2` files are renamed, otherwise Renovate stops scanning mid-migration.
- [step] Update documentation: `README.md` (Templating tools section + bootstrap-time secrets paragraph), `kubernetes/CLAUDE.md`, `kubernetes/bootstrap/readme.md`, `kubernetes/apps/external-secrets/CLAUDE.md`, `.claude/skills/versions-renovate/references/config-files.md`, `.claude/skills/flux-gitops/references/layout.md` and `validation.md`, `.claude/skills/just/references/catalog.md`, `kubernetes/talos/_resolve-controller.sh:20` comment.
- [verification] `git grep -i 'minijinja\|\.yaml\.j2'` returns no matches outside the BM roadmap note itself and the (now stale) basic-memory worktree if any.

## Risks and design decisions

- [decision] Phase 2 renames the (now CP-only) base file directly to `machineconfig-controlplane.yaml` instead of a generic `machineconfig.yaml`. Truthful naming today (file IS controlplane-only after the `{% if %}` inlining), and if a worker node is ever added the path forward is simply adding `machineconfig-worker.yaml` alongside — no second rename, no Jinja conditionals reintroduced. The minor speculation cost (one extra word in the filename even if a worker never materialises) is accepted as the trade for avoiding a rename under live conditions later.
- [risk] `envsubst` from GNU `gettext` and `a8m/envsubst` (Go) differ in default behavior around undefined variables. Use the strict mode equivalent and verify both versions produce identical output for the machineconfig before committing.
- [risk] Renaming Talos config files mid-migration could break `just talos apply-node` if a node operation is in flight. Schedule Phases 1 and 2 during a quiet window (no upgrade/reset planned), or commit each phase separately so rollback is single-commit revert.
- [decision] Keep `op inject` unchanged — it solves a real problem (secret-free git) that envsubst cannot.
- [decision] Do NOT migrate to a different templating tool (yq eval-all, gomplate, etc.). The minimum-tools direction is the whole point.

## Related

- relates_to [[talos-cluster]]
- relates_to [[flux-gitops]]
- relates_to [[external-secrets]]
