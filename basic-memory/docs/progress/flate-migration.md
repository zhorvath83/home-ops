---
title: flate-migration
type: note
permalink: home-ops/docs/progress/flate-migration
tags:
- flux-gitops
- ci
- tooling
- flate
- supersedes-flux-local
---

# Flate migration — replace flux-local CI + local recipe with home-operations/flate

## Metadata

- [topic] Migrate from `flux-local` to `home-operations/flate` for cluster-manifest validation and PR diff
- [status] completed
- [created_at] 2026-06-03
- [completed_at] 2026-06-03
- [scope] Replace the pipx-managed `flux-local` binary and the `ghcr.io/allenporter/flux-local` Docker image in CI with `github:home-operations/flate`. Touch: `.mise.toml`, `.github/workflows/flux-local.yaml` (rename + rewrite to match bjw-s sticky-comment pattern), and `kubernetes/mod.just` (`render-local-ks` recipe). Update the `pre-commit-linter-ci` progress note's Phase 4 and Phase 11 blocks to reflect the reversal of the prior "flux-local over flate" decision. Out of scope: a separate image-diff workflow, dufs-based diff hosting, and pre-commit hook changes.
- [supersedes] the "flux-local over flate" decision in [[pre-commit-linter-ci#phase-4]] and [[pre-commit-linter-ci#phase-9--11]] — see [[pre-commit-linter-ci]] for the full reversal record

---

## Background

The pre-migration flux-local footprint was small and confined to four files:

- `.mise.toml` (pre-migration line 57) — `"pipx:flux-local" = "8.2.0"`
- `.github/workflows/flux-local.yaml` — 4 jobs (filter → test → diff matrix [helmrelease, kustomization] → success), used the `ghcr.io/allenporter/flux-local:v8.2.0` Docker image
- `kubernetes/mod.just` (pre-migration lines 164-167) — `render-local-ks name ns` recipe that shelled out to `flux-local build ks --namespace "{{ ns }}" --path "{{ kubernetes_dir }}/flux/cluster" "{{ name }}"`
- `basic-memory/docs/progress/pre-commit-linter-ci.md` — Phase 4 records the workflow creation; Phase 9 and Phase 11 record the Python 3.13 / Docker image migrations; all three include the explicit "flux-local over flate" decision line

`flate` is a Go CLI from `home-operations/flate` that supersedes `flux-local` for the GitOps manifest validation + PR diff use case. It speaks the same commands (`build ks`, `test`, `diff`) and adds first-class support for image-only diffs. The reference repos have already adopted it as a hard standard.

## Reference-repo evidence (as of 2026-06-03)

Both reference repos were shallow-cloned to `$TMPDIR/bjw-s-labs__home-ops` and `$TMPDIR/onedr0p__home-ops` and searched with `rg -n -i 'flate|flux-local'`.

**bjw-s-labs/home-ops** (Forgejo-hosted):

- `.mise.toml:15` — `"github:home-operations/flate" = "latest"` (replaces `pipx:flux-local`)
- `.mise.toml:3` — `FLATE_PATH = '{{config_root}}/kubernetes/flux/cluster'`
- `kubernetes/mod.just:93` — `flate build ks --namespace "{{ ns }}" --output yaml "{{ ks }}"`
- `.forgejo/workflows/flate.yaml` — uses `https://github.com/home-operations/flate/action@2df83493...` (pinned by commit SHA), runs `flate test all --base ${{ forgejo.event.repository.default_branch }}` and `flate diff all`, then sticky PR comment via `actions/github-script`
- `.forgejo/workflows/validate-images.yaml` — uses the same flate action plus `flate diff images` with `FLATE_OUTPUT: json`, then `yq --prettyPrint` for the changed-image list
- No `flux-local` references remain

**onedr0p/home-ops** (GitHub-hosted):

- `.mise/config.toml:3` — `FLATE_PATH = '{{config_root}}/kubernetes/flux/cluster'`
- `kubernetes/mod.just:90` — `flate build ks --namespace "{{ ns }}" --output yaml "{{ ks }}"`
- `.github/workflows/flate.yaml` — uses `jdx/mise-action` with `tool_versions: github:home-operations/flate 0.2.7`, runs `flate diff all -p ./kubernetes/flux/cluster -o html > diff.html`, uploads the HTML to an in-cluster dufs instance, posts a PR comment with a link to the diff URL and a sticky marker `<!-- flate -->`
- Has a separate `prune` job that deletes the dufs-stored diff when the PR is closed
- No `flux-local` references remain

The bjw-s pattern was the closer match for the existing CI surface (sticky comment, no extra in-cluster dependency) and is what we mirrored.

## Completed Phases

### Phase 1 — Tooling swap (mise, local recipe) ✅

- Removed `"pipx:flux-local" = "8.2.0"` from `.mise.toml`
- Added `FLATE_PATH = '{{config_root}}/kubernetes/flux/cluster'` to the `[env]` block
- Added `"github:home-operations/flate" = "0.2.7"` to the `[tools]` block (with the standard `# renovate: datasource=github-releases depName=home-operations/flate` annotation)
- Updated `render-local-ks name ns` in `kubernetes/mod.just` (lines 164-167) from `flux-local build ks --namespace "{{ ns }}" --path "{{ kubernetes_dir }}/flux/cluster" "{{ name }}"` to `flate build ks --namespace "{{ ns }}" --output yaml "{{ name }}"` (dropped `--path` because `FLATE_PATH` is now exported from mise)
- Ran `just --fmt` and `mise lock` to keep `.justfile` / `mod.just` formatted and `mise.lock` current
- Verified locally: `mise install`, then `just k8s render-local-ks <some-ks> <some-ns>` resolves a Kustomization to YAML end-to-end

### Phase 2 — CI workflow rewrite ✅

- Renamed `.github/workflows/flux-local.yaml` → `.github/workflows/flate.yaml`
- Rewrote the workflow to mirror the bjw-s pattern:
  - Single `flate` job (replaces the previous 4 jobs: filter + test + diff matrix [2 kinds] + success). The `filter` step stays as a separate `filter` job that gates the main `flate` job on `kubernetes/**/*` changes — preserves the existing PR-noise reduction
  - `steps:` — checkout, then install flate via the GitHub composite action `home-operations/flate/action@2df8349356dd1b40a56be5bce8bc4b2b4a951962` with `version: "0.2.7"` (the action's `version:` input overrides the SHA-pinned default; no Python, no Docker-in-Docker, faster cold start than the previous `ghcr.io/allenporter/flux-local` image)
  - Runs `flate test all --path ./kubernetes/flux/cluster` (no `--enable-helm` — flate's default test mode already covers the embedded `flux-system` CRDs)
  - Runs `flate diff all --path ./kubernetes/flux/cluster --output-file diff.txt`; if non-empty, posts a sticky PR comment with a collapsed `<details>` block keyed by the marker `<!-- Sticky Pull Request Comment{{ issue_number }}/flate -->`, using the `actions/github-script` idiom from the bjw-s pattern
  - Dropped the matrix (`helmrelease` + `kustomization`) — flate `diff all` already groups by kind in its output, so a single job produces the same reviewer signal without the matrix fan-out
- Permissions stayed minimal: `contents: read` on the main job, `pull-requests: write` at the job level (actionlint rejected the step-level `permissions` block on the `actions/github-script` step — this is a GitHub Actions syntax limitation, not a pattern choice)

### Phase 3 — Image-diff workflow ✅

- Added `.github/workflows/validate-images.yaml` mirroring bjw-s `.forgejo/workflows/validate-images.yaml`
- Same filter + job structure as `flate.yaml`, but the diff step runs `flate diff images --path "$FLATE_PATH"` with `FLATE_OUTPUT: json` and pipes through `yq --prettyPrint` for the changed-image list
- Sticky marker: `<!-- Sticky Pull Request Comment{{ issue_number }}/flate-images -->`
- This was originally logged as a follow-up in the migration plan; it was promoted to a phase and shipped in the same MR because the workflow shape is identical to `flate.yaml` and the review cost was negligible

### Phase 4 — Documentation supersede ✅

- `basic-memory/docs/progress/pre-commit-linter-ci.md` — edited Phase 4, Phase 8, Phase 9/11 headers to mark them as superseded; added a "Reversed decision (2026-06-03)" bullet at the end of each phase; replaced the "flux-local over flate" line in Deliberate Decisions with "flate over flux-local" pointing at [[flate-migration]]; added `- [superseded_by] [[flate-migration]]` to the metadata block
- `basic-memory/docs/progress/zizmor-gh-actions-security-audit.md` — the "flux-local.yaml not touched" decision is marked as superseded with a "Follow-up (post-migration)" section that re-audits `flate.yaml` and `validate-images.yaml` against the original zizmor findings
- `README.md` — not edited; it does not mention flux-local or flate (verified via `grep`)
- `kubernetes/CLAUDE.md` / `kubernetes/apps/*/CLAUDE.md` — not edited; none mention flux-local

## Deliberate Decisions

- **Sticky PR comment (bjw-s pattern) over dufs upload (onedr0p pattern)** — renders the diff inline in a collapsed `<details>` block on the PR, updated in place by `github-script` keyed by a sticky-comment marker. The dufs pattern would have required a new dufs workload in-cluster plus a 1Password-sourced password secret; scope-creep for a one-tool swap.
- **Pinned to 0.2.7 with explicit `# renovate: datasource=github-releases depName=home-operations/flate` annotation** — matches onedr0p's `tool_versions` block. Renovate will keep it current once the `github:` mise backend is recognized by our Renovate config (out of scope to fix that here; logged as a follow-up).
- **Composite action SHA-pinned, version input overrides** — `home-operations/flate/action@2df8349356dd1b40a56be5bce8bc4b2b4a951962` with `version: "0.2.7"`. The SHA pins the action's source code (security), the input pins the runtime version (functional). This matches the bjw-s pattern.
- **Image-diff as a separate workflow, not a job in `flate.yaml`** — keeps each workflow focused on one signal (manifest diff vs container image diff). The shared filter job shape made this a near-zero-cost split.
- **Job-level `pull-requests: write`, not step-level** — actionlint rejects the step-level `permissions` block on the `actions/github-script` step. Job-level is the lowest scope that passes actionlint and is what both reference repos use.

## Out of Scope (deliberate non-goals)

- **dufs-based HTML diff hosting** (onedr0p pattern) — would require deploying dufs in-cluster and wiring an 1Password-sourced password secret. Scope-creep for a one-tool migration. Logged below as a follow-up.
- **Pre-commit hook integration** — neither reference repo runs flate as a pre-commit hook; it is exclusively a CI-time tool. The pre-commit surface was kept unchanged.
- **Re-audit `flate.yaml` / `validate-images.yaml` with zizmor** — the original zizmor audit explicitly skipped `flux-local.yaml`. Now that those workflows are rewritten, a fresh zizmor pass is the natural follow-up; logged in [[zizmor-gh-actions-security-audit#follow-up-post-migration]].

## Follow-ups (after the migration lands)

- [ ] Investigate Renovate coverage of `github:home-operations/flate` and the `home-operations/flate/action` composite action. The `# renovate: datasource=github-releases depName=home-operations/flate` annotation is in place on the `[tools]` entry; confirm Renovate picks it up. The composite action SHA is already handled by the standard `helpers:pinGitHubActionDigestsToSemver` preset.
- [ ] (Optional, much later) If reviewer feedback favors HTML diffs over text diffs, revisit the onedr0p dufs pattern — but that requires the in-cluster dufs workload to be added to the cluster first.

## Commits (chronological)

1. ♻️ refactor(tools): replace flux-local with home-operations/flate
2. 👷 ci: rewrite flux-local workflow as flate.yaml (bjw-s sticky-comment pattern)
3. 👷 ci: add validate-images workflow (flate diff images)
4. 🐛 fix(ci): actionlint rejects step-level permissions on github-script
5. 📝 docs(progress): mark flux-local phases as superseded, point at flate-migration
6. 📝 docs(progress): move flate-migration from docs/roadmap to docs/progress

## Success Criteria (verification)

- `rg -n 'flux-local' --hidden --glob '!basic-memory/**' .` → 0 lines
- `mise exec -- flate --version` → exits 0
- `just k8s render-local-ks apps default` → renders the root `kubernetes/apps/default` Kustomization to YAML without error
- `pre-commit run --all-files` → unchanged pass/fail profile vs pre-migration
- On a test PR: GitHub Actions UI shows `.github/workflows/flate.yaml` and `.github/workflows/validate-images.yaml` running; PR has exactly one comment containing each sticky marker (flate and flate-images)

relates_to [[pre-commit-linter-ci]]
relates_to [[zizmor-gh-actions-security-audit]]
relates_to [[docs/areas/flux-gitops]]
