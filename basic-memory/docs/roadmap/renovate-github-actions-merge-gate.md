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
