---
title: flate-ci-adoption
type: roadmap
permalink: home-ops/docs/roadmap/flate-ci-adoption
topic: Replace the deprecated flux-local in CI (and locally) with flate, fail-closed
  on render errors
status: proposed
priority: high
scope: 'Swap the flux-local test and diff jobs in .github/workflows/flux-local.yaml
  and the pipx:flux-local pin in .mise.toml for flate (home-operations/flate), after
  measuring whether today''s CI fails open on a render error. Run flate in shadow
  mode first, then cut over. flate also becomes the render engine for route-auth-coverage-guard
  L2. Out of scope: konflate (needs a long-running service).'
rationale: flux-local 8.4.0 prints "flux-local is deprecated and has been sunsetted.
  Please migrate to flate". During the 2026-11-15 spike, flux-local build all --enable-helm
  returned exit 0 with empty output when a chart fetch failed, so a PR check built
  on it may pass on a render it never completed. flate is the maintained Go successor;
  its test command exits 1 on failure and it has --strict-substitutions.
options:
- flate via its GitHub Action, shadow then cutover — RECOMMENDED
- flate via the ghcr.io/home-operations/flate container image (same as today's docker://
  pattern)
- Stay on flux-local 8.4.0 (deprecated, observed fail-open)
related_areas:
- flux-gitops
---

# flate CI adoption

## Metadata (observation-form, schema validation)

- [topic] Replace the deprecated flux-local in CI and locally with flate, fail-closed on render errors
- [status] proposed
- [priority] high
- [researched_at] 2026-11-16
- [effort] M

## What we gain

- The PR render check fails when a render fails, instead of possibly passing on an empty or partial render.
- Unresolved `${VAR}` substitutions become a hard error (`--strict-substitutions`) instead of silently rendering as empty strings.
- A maintained tool: flux-local is sunset, so Flux/Helm/Kustomize changes will stop being tracked there.
- One render engine for CI, local use and the route-auth-coverage-guard L2 check.

## What we accept

- flate is young (0.x, release-please, AGPL-3.0). Running it as a CI tool does not trigger AGPL distribution duties.
- Its output and flags differ from flux-local, so the diff comment format and the job wiring change.

## Current state (repo, 2026-11-16)

- [evidence] `.github/workflows/flux-local.yaml`: `pull_request` on `kubernetes/**`. Jobs: `filter` (changed files), `test` (`docker://ghcr.io/allenporter/flux-local:v8.4.0` → `test --all-namespaces --enable-helm --path …/kubernetes/flux/cluster`), `diff` (matrix helmrelease/kustomization → sticky PR comment via `actions/github-script`), `success` (aggregator).
- [evidence] `.mise.toml` pins `"pipx:flux-local" = "8.4.0"`.
- [evidence] `main` has no required status checks and maintainer commits go straight to `main` ([[main-branch-protection-and-commit-signing]]); this workflow only runs on PRs (in practice, Renovate).

## Research findings

- [verified] 2026-11-15: `flux-local build all --enable-helm --skip-secrets kubernetes/flux/cluster` returned **exit 0 with 0 lines of output** twice, both times because a chart fetch failed (ghcr.io unreachable from the sandbox and from the then-current network).
- [unverified] Whether `flux-local test` (the command CI runs) also exits 0 on a chart-fetch failure. Phase 0 measures it.
- [fact] flate (README, read 2026-11-15): renders Kustomizations with postBuild substitution, HelmReleases incl. OCI charts, and source objects. Supports local checkouts. `flate test` "exit 1 on failure"; `flate diff` exits 1 when a render fails. `--strict-substitutions` fails on unresolved variables. Secrets and CRDs are excluded from output by default. GitHub Action `home-operations/flate/action` (README pins v0.7.0), image `ghcr.io/home-operations/flate`, a pre-commit hook, and `--cache-dir`.
- [caveat] With `--allow-missing-kinds Secret`, unavailable source credentials skip the source with a warning (`SourceCredentialsUnavailable`), which can exit 0. Do not use that flag unless Phase 0 proves it is needed, and then guard it.
- [unverified] The `flate build` output format/destination and the exact exit code on a chart-fetch failure are not documented. Phase 0 measures both.

## Plan

### Phase 0 — Measure (throwaway PR)
- On a scratch branch, break one chart reference (a non-existent chart version). Run today's `flux-local test` job and record the exit code and the output. This answers whether CI fails open today.
- In the same PR, run flate (`flate test`, `flate diff`, `flate build`) with `--strict-substitutions`. Record wall time, output format, the exit code on the broken chart, and whether substituteFrom ConfigMaps (cluster-settings) resolve.
- Abort criterion: if flate also exits 0 on a broken chart, stop. Report upstream, and add an output-sanity assertion (non-empty, expected object counts) to whichever tool stays.

### Phase 1 — Shadow
- Add a `flate` job beside the flux-local jobs, non-blocking in the `success` aggregator. Run on the next few Renovate PRs and compare test results and diff content.
- Pin the action by commit SHA with `persist-credentials: false` and `permissions: contents: read`. Must pass actionlint and zizmor. Cache charts with `--cache-dir` + actions/cache if wall time warrants it.

### Phase 2 — Cutover
- Replace the `test` and `diff` jobs with flate. Keep the sticky-comment contract: marker per kind, `--limit-bytes`-style truncation, strip noisy attrs. Make flate's result the input to `success`.
- Keep `pull_request` on `kubernetes/**`. Decide whether to also run `test` on `push` to `main`, so direct maintainer pushes get a (post-hoc) render check (D2).

### Phase 3 — Cleanup and docs
- Remove `pipx:flux-local` from `.mise.toml` and add flate (aqua or GitHub release) if a local entry point is wanted. Optionally a `just k8s render` recipe.
- Update the references to flux-local in CLAUDE.md files and `.claude/skills` (flux-gitops validation, k8s-workloads validation). The skills directory is write-protected in the agent sandbox: the user applies or approves that edit.
- BM: `docs/areas/flux-gitops`.

## Decisions needed

- **D1 — Packaging**: the GitHub Action (RECOMMENDED: official, pinned by SHA) or the container image (`docker://ghcr.io/home-operations/flate@sha256:…`, closest to today's pattern).
- **D2 — Push trigger**: also run `flate test` on `push` to `main` (RECOMMENDED: cheap, and the only signal for direct pushes), or keep PR-only.
- **D3 — Local tool**: install flate via mise (RECOMMENDED, for parity with CI and for route-auth-coverage-guard L2) or CI only.

## Risks & mitigations

- **flate behaves differently on an edge in this repo** (OCIRepository-templated charts, postRenderers, substituteFrom) → the shadow phase compares both tools on real PRs before cutover.
- **Strict substitutions break on a variable that is legitimately empty** → fix the manifest, or set an explicit default with `${VAR:=default}`; never drop the flag globally.
- **Supply chain**: a new third-party action → SHA pin, Renovate digest updates reviewed manually, zizmor.

## Acceptance criteria

1. Phase 0 results recorded: flux-local test exit code on a broken chart, and flate's behavior on the same.
2. On a PR with a broken chart reference, the render check is red.
3. On a PR with an unresolved `${VAR}`, the render check is red.
4. A normal Renovate PR gets a correct HelmRelease and Kustomization diff comment from flate.
5. flux-local is gone from the workflow and `.mise.toml`; the workflow passes actionlint and zizmor.

## Related

- relates_to [[route-auth-coverage-guard]] (L2 render engine, D2 there)
- relates_to [[flux-gitops]]
- relates_to [[main-branch-protection-and-commit-signing]]
