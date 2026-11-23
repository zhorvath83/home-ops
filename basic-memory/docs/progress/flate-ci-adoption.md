---
title: flate-ci-adoption
type: roadmap
permalink: home-ops/docs/progress/flate-ci-adoption
topic: Replace the deprecated flux-local in CI (and locally) with flate, fail-closed
  on render errors
status: done
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
- [status] done (PR #4787, squash-merged 2026-11-16)
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
- [measured] `flux-local test` (the command CI runs) exits 1 on a chart-fetch failure — see Phase 0 results.
- [fact] flate (README, read 2026-11-15): renders Kustomizations with postBuild substitution, HelmReleases incl. OCI charts, and source objects. Supports local checkouts. `flate test` "exit 1 on failure"; `flate diff` exits 1 when a render fails. `--strict-substitutions` fails on unresolved variables. Secrets and CRDs are excluded from output by default. GitHub Action `home-operations/flate/action` (README pins v0.7.0), image `ghcr.io/home-operations/flate`, a pre-commit hook, and `--cache-dir`.
- [caveat] With `--allow-missing-kinds Secret`, unavailable source credentials skip the source with a warning (`SourceCredentialsUnavailable`), which can exit 0. Do not use that flag unless Phase 0 proves it is needed, and then guard it.
- [unverified] The `flate build` output format/destination and the exact exit code on a chart-fetch failure are not documented. Phase 0 measures both.

## Phase 0 results (measured locally, 2026-11-16)

Method: flate v0.7.3 darwin_arm64 (release checksum verified) and flux-local 8.4.0 (mise pipx install, with flux 2.10.0, helm 4.3.2, kustomize 5.7.0) run against a throwaway clone of main @ 30fc9802b under $TMPDIR. Broken inputs were edited in the clone only.

- [measured] Clean tree: `flate test -p kubernetes/flux/cluster --strict-substitutions` → exit 0, 195 passed (80 Kustomization, 68 HelmRelease, sources), 7.0s cold / ~2s warm cache. flux-local test → 148 passed, ~37s in CI, ~70s locally.
- [measured] The missing `GitRepository flux-system` manifest (it is created by the FluxInstance) is NOT a problem: flate resolves the root `cluster-apps` from the local checkout with the `kubernetes/flux/cluster` entry. Both root patches apply; every cluster-settings variable (PUBLIC_DOMAIN, LAN_SUBNET, NAS_IP, ENVOY_INTERNAL_IP, CLUSTER_DNS_IP) is substituted, 0 literals left. The remaining literal `${...}` strings in the render are escaped or substitution-disabled and pass strict mode.
- [measured] Broken chart (metrics-server OCIRepository tag → non-existent): `flate test` exit 1 (1 failed, 1 blocked), `flate diff hr` exit 1 with `DiffSuppressed`. **flux-local test ALSO exit 1** (1 failed, 147 passed, helm FetchReference not found). So today's CI test job is NOT fail-open on a chart fetch failure; the 2026-11-15 fail-open observation applies to `flux-local build all` only.
- [measured] flate reports the non-existent ghcr tag as "machine credential acquisition failed" (ghcr answers an unknown tag with an auth error). Consequence: `--allow-missing-kinds Secret` would turn this real failure into a skipped source (SourceCredentialsUnavailable). Never set that flag.
- [measured] Unresolved `${FLATE_UNDEFINED_PROBE}` in a HelmRelease value: flate --strict-substitutions exit 1 ("postBuild: variable not set (strict mode)"); flate without strict exit 0 and renders an empty string; **flux-local test exit 0** (148 passed). This is the real fail-open gap that flate closes.
- [measured] `flate diff hr|ks -o github` gives a compact semantic diff (dyff-style, per-field `@@ path @@` blocks) that fits the existing sticky-comment pattern. There is no `--limit-bytes` equivalent; truncation must happen in the comment script. Default `--strip-attr` matches today's list.
- [measured] `flate build ks <name> -n <ns>` emits the same kinds as `flux-local build ks` (checked metrics-server, external-dns); output differs only in ordering, dropped kustomize-internal index annotations and added `kustomize.toolkit.fluxcd.io/*` labels (closer to what kustomize-controller applies). The repo has no raw Secret/CRD manifests, so flate's default Secret/CRD output exclusion does not change `just k8s apply-ks`.
- [fact] The official action exports `FLATE_BASE=<default branch>` (changed-only mode). A push-to-main run must unset/override it to render the full tree.
- [gap-fixed] Missed by the original plan: `kubernetes/mod.just` `render-local-ks` (used by `apply-ks`/`delete-ks`) and the `mise.lock` entry also depend on flux-local.

## Decisions taken (2026-11-16)

- D1+D3: mise — `aqua:home-operations/flate` in `.mise.toml`, installed in CI by `jdx/mise-action` (SHA-pinned, install_args limited to flate). One version pin for CI and local.
- D2: also run `flate test` on `push` to `main`, full tree (no FLATE_BASE).
- Phase 0 run locally instead of a throwaway PR.

## CI validation on PR #4787 (2026-11-16)

- [verified] Clean run (664a08947): all four jobs green, `flate test` 195 passed in 5.4s, whole workflow ~23s (flux-local was ~70s).
- [verified] AC2 — temporary broken metrics-server chart tag (0336ec7c6): Flate - Test failure ("machine credential acquisition failed"), Diff (hr) failure, Flate - Success failure.
- [verified] AC3 — temporary unresolved `${FLATE_UNDEFINED_PROBE}`: Test, Diff (hr), Diff (ks) and Success all failure ("postBuild: variable not set (strict mode)").
- [verified] AC4 — temporary benign value change (d2406534b): green, and both sticky comments (HelmRelease → Deployment args, Kustomization → HelmRelease values) posted in the expected format. Real Renovate PR comparison happens on the first Renovate PR after merge.
- [verified] AC5 — flux-local is gone from the workflows, .mise.toml and mise.lock; actionlint, zizmor (auditor persona) and the full pre-commit suite pass.
- [verified] All temporary changes reverted; net PR diff = .github/workflows/flate.yaml (+), flux-local.yaml (-), .mise.toml, mise.lock, kubernetes/mod.just.
- [known] A sticky comment is not removed when a later push makes that diff empty (same behaviour as the flux-local workflow), so PR #4787 still shows the temporary metric-resolution diff.
- [verified] `.claude/skills/k8s-workloads/references/app-scaffolding.md:92` now points at `flate test --strict-substitutions` (commit 99e32e321, approved by the user); no flux-local reference is left outside BM.
- [follow-up] onedr0p/home-ops uses `flate diff images` to pre-pull changed images onto the Talos node before merge. Not in scope here; candidate idea.

## Reference repos (checked 2026-11-16)

- onedr0p/cluster-template: `flate test -p ./kubernetes/apps` via jdx/mise-action + FLATE_BASE (changed-only). Not usable as-is here: skipping the root would drop our two cluster-apps patches.
- onedr0p/home-ops: flate only for `diff images` (image pre-pull), FLATE_PATH in mise env, no render test in CI.
- bjw-s-labs/home-ops (Forgejo): no flate in CI, in-cluster konflate instead; locally `github:home-operations/flate = latest`, FLATE_PATH, and render-local-ks via `flate build ks` (same shape as ours). We pin the version and add --strict-substitutions on purpose.


## Follow-ups from the reference review (PR #4788, 2026-11-16)

- [fact] `.github/workflows/workflow-lint.yaml` — actionlint + online zizmor (`--format github`, GH_TOKEN) on `.github/workflows/**` and `.mise.toml` changes, PR and push to main; tool versions from .mise.toml via jdx/mise-action (`mise install --locked`). Closes the gap that Renovate action bumps never ran zizmor's online audits (impostor-commit, known-vulnerable-actions). Verified on the PR: a temporary unpinned `jdx/mise-action@v5` turned the job red (exit 14, unpinned-uses annotation), reverted.
- [fact] `flate-test` pre-commit hook — `flate test --path kubernetes/flux/cluster --base HEAD --strict-substitutions` on `^kubernetes/` changes; ~2s idle, ~2.7s for one HelmRelease change (full tree would be ~4.7s). Verified: unresolved ${VAR} → Failed, benign change → Passed, non-kubernetes file → Skipped. Needs network for chart fetches.
- [decision] Not adopted: onedr0p image pre-pull (`flate diff images` + talosctl on an in-cluster runner — no self-hosted runner here), bjw-s AI upgrade-impact review (needs an LLM key and the long-running konflate), CI yamllint (Renovate does not change YAML structure).

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

## Update — 2026-11-23: flate 0.8.0 `test --base` livelocks

- [evidence] `flate test --path kubernetes/flux/cluster --base HEAD` (the `flate-test` pre-commit hook) never finishes on 0.8.0: after 2 kustomize builds it loops on `discovery: loaded objects count=0 rounds=1` for both snapshots (~8 events/s, 140-170% CPU, no network) until killed. Same with `--path-orig` and even with an identical baseline tree, so the repo content is not the trigger.
- [evidence] Without a baseline, 0.8.0 `flate test` takes 7 s and `flate build all` 9 s. flate 0.7.3 `test --base HEAD` on the same tree: 198 passed in 10 s. The regression arrived with the Renovate bump 0.7.3 → 0.8.0 (#4809, 2026-11-20); the 15-minute CI cap (#4825, 2026-11-22) is likely the same symptom.
- [todo] Fix options: pin flate to 0.7.3 in `.mise.toml` (+ Renovate hold) until upstream fixes it, and report upstream with the debug log; separately consider moving the hook to `pre-push`.
