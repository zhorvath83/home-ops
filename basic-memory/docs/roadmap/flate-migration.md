---
title: flate-migration
type: note
permalink: home-ops/docs/roadmap/flate-migration
tags:
- roadmap
- flux-gitops
- ci
- tooling
- flate
- flux-local
---

# Flate migration — replace flux-local CI + local recipe with home-operations/flate

## Metadata (observation-form, schema validation)

- [topic] Migrate from `flux-local` to `home-operations/flate` for cluster-manifest validation and PR diff
- [status] done
- [priority] medium
- [completed_at] 2026-06-03
- [scope] Replace the pipx-managed `flux-local` binary and the `ghcr.io/allenporter/flux-local` Docker image in CI with `github:home-operations/flate`. Touch: `.mise.toml`, `.github/workflows/flux-local.yaml` (rename + rewrite to match bjw-s sticky-comment pattern), and `kubernetes/mod.just` (`render-local-ks` recipe). Update the `pre-commit-linter-ci` progress note's Phase 4 and Phase 11 blocks to reflect the reversal of the prior "flux-local over flate" decision. Out of scope: a separate image-diff workflow, dufs-based diff hosting, and pre-commit hook changes.
- [rationale] The two reference repos (bjw-s-labs/home-ops, onedr0p/home-ops) have both completed a full migration to flate; `rg flux-local` returns zero hits in either of them, and `flate` is now at 0.2.7 with an actively maintained install action (`home-operations/flate/action`). Our `pre-commit-linter-ci` progress note captures the prior reversal ("flux-local over flate — flux-local is mature (v8.2.0), already in mise; flate is newer but less mature"); that rationale no longer matches the ecosystem. Adopting flate consolidates the validation surface to the same tool the reference repos standardize on, and removes one Python dependency from local mise and from CI.
- [options] (1) **Sticky PR comment, bjw-s pattern** — chosen. Renders the diff inline in a collapsed `<details>` block on the PR, updated in place by `github-script` keyed by a sticky-comment marker. (2) External dufs upload (onedr0p pattern) — rejected: would require a new dufs workload in-cluster plus a 1Password-sourced password secret; scope-creep for a one-tool swap. (3) Pipeline artifact only, no PR comment — rejected: weakens reviewer signal; today reviewers see a flate-style diff in the PR thread.
- [related_areas] flux-gitops
- [blocked_by] none

## Background

The current flux-local footprint is small and confined to four files:

- `.mise.toml:57` — `"pipx:flux-local" = "8.2.0"`
- `.github/workflows/flux-local.yaml` — 4 jobs (filter → test → diff matrix [helmrelease, kustomization] → success), uses `ghcr.io/allenporter/flux-local:v8.2.0` Docker image
- `kubernetes/mod.just:166-167` — `render-local-ks name ns` recipe that shells out to `flux-local build ks --namespace "{{ ns }}" --path "{{ kubernetes_dir }}/flux/cluster" "{{ name }}"`
- `basic-memory/docs/progress/pre-commit-linter-ci.md` — Phase 4 records the workflow creation; Phase 11 records the Docker image migration; both include the explicit "flux-local over flate" decision line

`flate` is a Go CLI from `home-operations/flate` that supersedes `flux-local` for the GitOps manifest validation + PR diff use case. It speaks the same commands (`build ks`, `test`, `diff`) and adds first-class support for image-only diffs. The reference repos have already adopted it as a hard standard.

## Reference-repo evidence (as of 2026-06-03)

Both reference repos were shallow-cloned to `$TMPDIR/bjw-s-labs__home-ops` and `$TMPDIR/onedr0p__home-ops` and searched with `rg -n -i 'flate|flux-local'`.

**bjw-s-labs/home-ops** (Forgejo-hosted):
- `.mise.toml:15` — `"github:home-operations/flate" = "latest"` (replaces `pipx:flux-local`)
- `.mise.toml:3` — `FLATE_PATH = '{{config_root}}/kubernetes/flux/cluster'`
- `kubernetes/mod.just:93` — `flate build ks --namespace "{{ ns }}" --output yaml "{{ ks }}"`
- `.forgejo/workflows/flate.yaml` — uses `https://github.com/home-operations/flate/action@2df83493...` (pinned by commit SHA, comment notes 0.1.38), runs `flate test all --base ${{ forgejo.event.repository.default_branch }}` and `flate diff all`, then sticky PR comment via `actions/github-script`
- `.forgejo/workflows/validate-images.yaml` — uses the same flate action plus `flate diff images` with `FLATE_OUTPUT: json`, then `yq --prettyPrint` for the changed-image list
- No `flux-local` references remain

**onedr0p/home-ops** (GitHub-hosted):
- `.mise/config.toml:3` — `FLATE_PATH = '{{config_root}}/kubernetes/flux/cluster'`
- `kubernetes/mod.just:90` — `flate build ks --namespace "{{ ns }}" --output yaml "{{ ks }}"`
- `.github/workflows/flate.yaml` — uses `jdx/mise-action` with `tool_versions: github:home-operations/flate 0.2.7`, runs `flate diff all -p ./kubernetes/flux/cluster -o html > diff.html`, uploads the HTML to an in-cluster dufs instance, posts a PR comment with a link to the diff URL and a sticky marker `<!-- flate -->`
- Has a separate `prune` job that deletes the dufs-stored diff when the PR is closed
- No `flux-local` references remain

The bjw-s pattern is the closer match for our existing CI surface (sticky comment, no extra in-cluster dependency) and is what we will mirror.

## Migration Plan

### Phase 1 — Tooling swap (mise, local recipe)

1. **`~/.mise.toml`** — remove `"pipx:flux-local" = "8.2.0"` (line 57), add `"github:home-operations/flate" = "0.2.7"` (pin to a specific version, matching onedr0p's `tool_versions` block; renovate will keep it current once the `github:` aqua/mise backend is recognized by our Renovate config — out of scope to fix that here). Add `FLATE_PATH = '{{config_root}}/kubernetes/flux/cluster'` to the `[env]` block.
2. **`kubernetes/mod.just`** (lines 164-167) — update `render-local-ks name ns` from `flux-local build ks --namespace "{{ ns }}" --path "{{ kubernetes_dir }}/flux/cluster" "{{ name }}"` to `flate build ks --namespace "{{ ns }}" --output yaml "{{ ks }}"` (drop `--path`, because `FLATE_PATH` is now exported from mise).
3. Run `just --fmt` and `mise lock` to keep `.justfile` / `mod.just` formatted and `mise.lock` current.
4. **Local verification**: `mise install`, then `just k8s render-local-ks <some-ks> <some-ns>` to confirm the recipe resolves. Spot-check `flate test all --path ./kubernetes/flux/cluster` to make sure the current manifests validate under flate's stricter checks (flate enforces `apiextensions.k8s.io/v1` CRD schema conformance for the embedded `flux-system` CRDs more strictly than flux-local did — expect a few noisy warnings on first run; address only blocking errors, log the rest as follow-ups).

### Phase 2 — CI workflow rewrite

5. **Rename** `.github/workflows/flux-local.yaml` → `.github/workflows/flate.yaml` (the on-disk filename becomes the workflow's name and the trigger reference in any docs/MR template). Preserve the `on: pull_request` and `concurrency` semantics.
6. **Rewrite** the workflow to mirror the bjw-s pattern:
   - Single `flate` job (replaces our 4 jobs: filter + test + diff matrix [2 kinds] + success). The `filter` step can stay as a separate `filter` job that gates the main `flate` job on `kubernetes/**/*` changes — this preserves our existing PR-noise reduction.
   - `steps:` — checkout, then install flate via the GitHub composite action `home-operations/flate/action@<pinned-sha>` (no Python, no Docker-in-Docker; faster cold start than the `ghcr.io/allenporter/flux-local` image swap we did in Phase 11).
   - Run `flate test all --path ./kubernetes/flux/cluster --enable-helm` (matches the current flux-local `test --all-namespaces --enable-helm` intent).
   - Run `flate diff all --path ./kubernetes/flux/cluster -o diff.txt`; if non-empty, post a sticky PR comment with a collapsed `<details>` block keyed by a marker like `<!-- Sticky Pull Request Comment{{ issue_number }}/flate -->`, using the same `actions/github-script` idiom already in the current workflow.
   - Drop the matrix (`helmrelease` + `kustomization`) — flate `diff all` already groups by kind in its output, so a single job produces the same reviewer signal without the matrix fan-out.
7. **Permissions** stay minimal: `contents: read` on the main job, `pull-requests: write` only on the diff step (or the whole job — match the current workflow, which scopes it to the `diff` job).
8. Validate by opening a throwaway PR with a known manifest change and confirming (a) the workflow runs, (b) the diff appears as a sticky comment, (c) re-pushing the same commit updates the comment in place rather than creating a duplicate.

### Phase 3 — Documentation supersede

9. **`basic-memory/docs/progress/pre-commit-linter-ci.md`** — the existing "Deliberate Decisions" block contains the line `**flux-local over flate** — flux-local is mature (v8.2.0), already in mise; flate is newer but less mature`. Edit that line to record the reversal: "**flate over flux-local** (superseded 2026-06-03) — both reference repos have completed the migration; flate is now at 0.2.7, has a maintained install action, and removes the Python 3.13+ runtime requirement. See [[flate-migration]] for the migration context." Also add a "Supersedes / Reversed decisions" section at the bottom of the note pointing back to [[flate-migration]] so the döntéstörténet is grep-able.
10. **`basic-memory/docs/areas/flux-gitops.md`** — add a one-line `- [drift] Pre-commit/CI tooling was migrated from flux-local to flate on 2026-06-03 (see [[flate-migration]]); area-reference does not yet reflect the swap` so future area-reference readers don't trip on the now-stale `pre-commit-linter-ci` mention. Update the area-reference body if it directly references the flux-local workflow name; current text does not.
11. **`README.md`** — do not edit. It does not mention flux-local or flate today (verified via `grep`).
12. **`kubernetes/CLAUDE.md` / `kubernetes/apps/*/CLAUDE.md`** — do not edit. None mention flux-local.

## Acceptance Criteria

- [ ] `mise install` succeeds and `mise exec -- flate --version` returns `0.2.7` (or current pinned version).
- [ ] `rg flux-local` in the repo returns zero hits across `*.md`, `*.yaml`, `*.yml`, `*.json5`, `*.just`, `*.toml`, `Makefile`, `*.sh`, excluding `basic-memory/` history entries that are intentionally retained (the `pre-commit-linter-ci` note's superseded block, if we choose to retain it as a döntéstörténet artifact).
- [ ] `just k8s render-local-ks <ks> <ns>` resolves a Kustomization under `kubernetes/flux/cluster/` to YAML, end-to-end, using the flate binary.
- [ ] The renamed `.github/workflows/flate.yaml` runs green on a test PR that touches a single `kubernetes/apps/**` manifest, and the diff lands as a sticky comment that updates in place on `git push`.
- [ ] `pre-commit run --all-files` is unchanged (no new hooks added, no existing hooks removed) — verified by running it before and after the migration.
- [ ] `pre-commit-linter-ci` progress note explicitly records the reversal of the Phase 4 / Phase 11 decision.

## Success Criteria (verification commands)

- `rg -n 'flux-local' --hidden --glob '!basic-memory/**' .` → 0 lines
- `mise exec -- flate --version` → exits 0
- `just k8s render-local-ks apps default` → renders the root `kubernetes/apps/default` Kustomization to YAML without error
- On a test PR: GitHub Actions UI shows `.github/workflows/flate.yaml` running; PR has exactly one comment containing the `<!-- Sticky Pull Request Comment{{n}}/flate -->` marker

## Out of Scope (deliberate non-goals)

- **Image-diff subcommand** (`flate diff images`) — would mirror the bjw-s `validate-images.yaml` workflow and surface changed container image tags as a separate PR comment. Useful, but not part of the swap. Logged below as a follow-up.
- **dufs-based HTML diff hosting** (onedr0p pattern) — would require deploying dufs in-cluster and wiring an 1Password-sourced password secret. Scope-creep for a one-tool migration. Logged below as a follow-up.
- **Pre-commit hook integration** — neither reference repo runs flate as a pre-commit hook; it is exclusively a CI-time tool. We keep the pre-commit surface unchanged.
- **Renovate coverage for `github:home-operations/flate`** — the mise `github:` backend may not be recognized by our Renovate config today. Investigate separately; if Renovate does not pick it up, add a manual pin in `.renovaterc.json5` or move the dependency to `.renovate/overrides.json5`.
- **Re-pinning the GitHub composite action SHA** — the bjw-s workflow pins `home-operations/flate/action@<sha>` with a trailing comment noting the version. We will mirror that pattern in Phase 2 step 6.

## Follow-ups (after the migration lands)

- [ ] Adopt `flate diff images` as a separate `.github/workflows/validate-images.yaml` workflow, mirroring bjw-s `.forgejo/workflows/validate-images.yaml`. Emits a yq-formatted list of changed image references to a sticky PR comment. Independent deliverable; can land in its own MR.
- [ ] Investigate Renovate coverage of `github:home-operations/flate` and the `home-operations/flate/action` composite action (separate Renovate rule fragments likely needed under `.renovate/overrides.json5` or `.renovate/customManagers.json5`).
- [ ] (Optional, much later) If reviewer feedback favors HTML diffs over text diffs, revisit the onedr0p dufs pattern — but that requires the in-cluster dufs workload to be added to the cluster first.

## Relations

- relates_to [[docs/areas/flux-gitops]]
- supersedes [[docs/progress/pre-commit-linter-ci#phase-4]] — the original "flux-local over flate" CI decision
- supersedes [[docs/progress/pre-commit-linter-ci#phase-11]] — the Docker image migration that doubled down on flux-local
- continues [[docs/progress/pre-commit-linter-ci]] — same author/area, swap-out of the same tool chain
