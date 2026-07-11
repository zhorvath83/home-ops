---
title: renovate-github-actions-merge-gate
type: roadmap
permalink: home-ops/docs/roadmap/renovate-github-actions-merge-gate
topic: Test-gated auto-merge for GitHub Actions bumps
status: proposed
priority: medium
scope: Require PR checks to pass before Renovate auto-merges GitHub Actions updates
  (drop ignoreTests), keeping the convenient auto-merge but behind the same test gate
  as every other change.
rationale: Gating action-bump auto-merges on CI gives supply-chain updates the same
  tested, reversible path as everything else — automation stays, but nothing merges
  unverified.
related_areas:
- flux-gitops
---

# Test-gated auto-merge for GitHub Actions bumps

## Metadata (observation-form, schema validation)

- [topic] Test-gated auto-merge for GitHub Actions bumps
- [status] proposed
- [priority] medium

## What we gain

- Action updates land only after CI validates them — no unverified supply-chain changes.
- Hands-off dependency maintenance is retained without lowering the bar for one ecosystem.
- Consistent merge policy across container, Helm, and Actions updates.

## What to do

1. Remove ignoreTests:true from the github-actions rules in .renovate/autoMerge.json5.
2. Keep a sensible minimumReleaseAge soak for actions.
3. Ensure the relevant CI check is required on those PRs (ties into main-branch-protection-and-commit-signing).
4. Verify: an action-bump PR waits for green CI before auto-merging.

## Related

- relates_to [[flux-gitops]]
- relates_to [[main-branch-protection-and-commit-signing]]

## Execution plan (research-backed)

### Current state
- `.renovate/autoMerge.json5` has two `github-actions` rules that skip the test gate:
  - lines 40-48: minor/patch, `minimumReleaseAge: "3 days"`, **`ignoreTests: true`** (line 47)
  - lines 49-58: `actions/*` fast-track, `minimumReleaseAge: "1 minute"`, **`ignoreTests: true`** (line 57)
- Container/Helm/pre-commit auto-merge rules (lines 6-39) do **not** set ignoreTests — already correct.
- Global `:automergePr` (per the file's header comment) means Renovate waits for required checks then merges — so once `ignoreTests` is gone, the flux-local check gates these too.

### Target state
- GitHub Actions bumps auto-merge only after the required CI check passes; the convenient soak stays.

### Implementation steps
1. Edit `.renovate/autoMerge.json5`: **delete line 47** (`ignoreTests: true,`) from the 3-day rule and **delete line 57** from the fast-track rule. Leave `automerge: true`, `minimumReleaseAge`, and the matchers intact.
2. Optionally bump the fast-track `minimumReleaseAge` from `"1 minute"` to something like `"1 hour"` for a minimal soak (comment already admits 1 min is effectively none).
3. Ensure the flux-local check is a **required** status check on `main` — that is the actual gate (see `main-branch-protection-and-commit-signing`). Without a required check, dropping ignoreTests has no effect because there's nothing to wait for.
4. Commit: `🔒 fix(renovate): gate github-actions auto-merge on CI`.

### Verification
- `just cloudflare`-style dry check not applicable; validate JSON5 with `renovate-config-validator .renovate/autoMerge.json5` (or the repo's renovate CI).
- Next Renovate GitHub-Actions PR: confirm it does **not** merge until the flux-local check is green (watch the PR's checks/timeline).

### Rollback & safety
- Re-add the two `ignoreTests: true` lines. Zero cluster impact — this only affects PR merge behavior.
- Risk: if no required check exists, action-bump PRs may sit unmerged waiting for a check that isn't enforced — that's why step 3 matters.

### Gotchas & dependencies
- Hard dependency on `main-branch-protection-and-commit-signing` (the required check).

### Effort
S (~15 min + the branch-protection prerequisite).
