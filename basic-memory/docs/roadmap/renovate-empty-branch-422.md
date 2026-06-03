---
title: renovate-empty-branch-422
type: roadmap
permalink: home-ops/docs/roadmap/renovate-empty-branch-422
topic: Renovate 422 'No commits between' - squash-merge + auto-rebase interaction
  on the terraform-monorepo group
status: proposed
scope: 'Apply rebaseWhen automerging (per-group or global) so Renovate does not create
  an empty head branch that triggers GitHub 422 Validation Failed on PR creation.
  Optionally turn on GitHub auto-delete head branches. Touchpoints: .renovate/overrides.json5,
  .renovaterc.json5, possibly an upstream issue or PR on home-operations/renovate-presets.'
priority: medium
rationale: 'On 2026-06-03 the Renovate run failed to create PR for renovate/terraform-monorepo
  with 422 ''No commits between main and renovate/terraform-monorepo''. Root cause:
  PR #3794 (terraform 1.15.4 to 1.15.5) was squash-merged on 2026-06-01, but the Renovate
  branch was not deleted (no GitHub auto-delete enabled). On the next run Renovate
  rebased the branch onto main, but the tree was already identical so no new commit
  was created and GitHub rejected the PR. The bug is known in the Renovate tracker
  (#11481) and the underlying 36.20.1+ fix (PR #23480) is shipped in the current image
  (Renovate 43.209.4), but the pattern can still bite with rebaseWhen auto + squash-merge
  + manual branch preservation. Future incidents will keep surfacing 422s in the Renovate
  log until a global default or per-group override changes the rebase behavior.'
options:
- Per-group rebaseWhen automerging in .renovate/overrides.json5 - targeted fix for
  the terraform-monorepo group, minimal blast radius, uses the new Renovate 2024 option
  (commit ea816f8)
- Global rebaseWhen automerging in .renovaterc.json5 - fixes all squash-merge 422s
  at once; safe because home-operations/renovate-presets does not set rebaseWhen,
  so the local default wins
- GitHub repo setting Automatically delete head branches - single UI toggle; fixes
  the symptom but affects every branch in the repo
- Manual git push origin --delete renovate/stale-branch - ad-hoc symptom relief; does
  not prevent recurrence
related_areas:
- flux-gitops
- cloudflare
- ovh-storage
- k8s-workloads
tags:
- renovate
- renovate-presets
- roadmap
- gitops
---

# Renovate 422 'No commits between' - squash-merge + auto-rebase interaction

## Metadata (observation-form, schema validation)

- [topic] Renovate 422 'No commits between' - squash-merge + auto-rebase interaction on the terraform-monorepo group
- [status] proposed
- [priority] medium

## Symptom (observed 2026-06-03)

Renovate log shows on every run while the stale branch is alive:

```
DEBUG: POST https://api.github.com/repos/zhorvath83/home-ops/pulls = (code=ERR_NON_2XX_3XX_RESPONSE, statusCode=422 retryCount=0, ...)
DEBUG: 422 Error thrown from GitHub (branch="renovate/terraform-monorepo")
DEBUG: Pull request creation error (branch="renovate/terraform-monorepo")
{
  "message": "Validation Failed",
  "errors": [{ "resource": "PullRequest", "code": "custom", "message": "No commits between main and renovate/terraform-monorepo" }]
}
```

The branch is non-empty in the sense that it has a tip SHA (9f00d83, the same as the squash-merged commit on PR #3794), but a fresh rebase against main produces no diff.

## Root Cause

`rebaseWhen: "auto"` (the current global default, set in .renovaterc.json5:32 and inherited from config:recommended) is intended to behave like behind-base-branch when automerge is configured. The interaction with squash-merge and preserved branches is:

1. Renovate opens PR #3794 with branch tip at 9f00d83 (terraform 1.15.4 to 1.15.5)
2. User squash-merges PR #3794 - main gets the file content with a new SHA (7f7110c)
3. The Renovate branch renovate/terraform-monorepo is NOT deleted (GitHub auto-delete is OFF, and Renovate does not delete on its own)
4. Renovate's next run sees the branch, rebases it onto main, gets an empty diff
5. PR creation API call returns 422 - the GitHub-side check rejects branches that have no commit distance from the base
6. Renovate log floods with the same 422 until the branch is deleted

The Renovate-side fix for the silent empty branch case (PR #23480, "Remote branch existence check", shipped in 36.20.1) is already in the current image (43.209.4). The 422 here is a NEW branch being created from scratch by ensurePr (not a replacement), so the existence-check fix does not apply.

## Scope

Apply one or both of:

1. Per-group override in .renovate/overrides.json5:

   ```json5
   {
     packageRules: [
       {
         description: "Use automerging rebaseWhen for the terraform-monorepo group to avoid empty-branch 422 after squash merge",
         matchPackageNames: ["hashicorp/terraform"],
         rebaseWhen: "automerging",
       },
     ],
   }
   ```

2. Global default in .renovaterc.json5:

   ```json5
   {
     rebaseWhen: "automerging",
   }
   ```

   The home-operations/renovate-presets bundle (.renovaterc.json5:3-22) does NOT set rebaseWhen, so the local default wins. Switching to automerging (a Renovate 2024 addition, see commit ea816f8) means: rebase only when the branch is queued for automerge, leave manual-review branches untouched after squash merge. Exact behavior:
   - branch with automerge true - behaves like behind-base-branch
   - branch with automerge false - behaves like never - no rebase, no 422

3. GitHub UI: Settings - General - Automatically delete head branches - fixes the symptom by ensuring the branch disappears at squash-merge time, but it is a repo-wide setting that affects every branch, not just Renovate's.

## Reproduction

The state at the time of observation (2026-06-03):

```bash
$ git log --oneline origin/main..origin/renovate/terraform-monorepo
(empty - exit 0)
$ git log --oneline origin/renovate/terraform-monorepo -1
9f00d8300 fix(deps): update dependency aqua:hashicorp/terraform ( 1.15.4 to 1.15.5 )
```

The branch tip is a commit that is already in main (via PR #3794 squash merge - 7f7110c9d). Reproducible by:

1. Let Renovate create a PR on a renovate/ branch
2. Squash-merge the PR (do not delete the branch)
3. Wait for the next Renovate run
4. Observe the 422 in the log

## Rationale

The 422 is purely cosmetic (the existing PR #3794 is already merged), but the noise floods the Renovate log and makes real PR-creation failures harder to spot. It also blocks future legitimate PRs in the same group: as long as the empty renovate/terraform-monorepo branch exists, any new terraform version bump will collide with it.

Switching to rebaseWhen automerging is the upstream-recommended pattern (Renovate community, discussion #33876, maintainer rarkins) for repositories that use squash-merge + branch preservation. It is a 2024-era feature (commit ea816f8) that the home-operations/renovate-presets bundle does not yet adopt, so we would be ahead of the upstream curve.

## Options

1. Per-group override only - minimal blast radius, touches only the terraform-monorepo group. Preserves the current global default for all other Renovate PRs.
2. Global rebaseWhen automerging - fixes the problem everywhere, but is a behavior change for every Renovate branch in the repo. Verify with the dependencyDashboard that no current PRs depend on the old auto semantics.
3. GitHub auto-delete head branches - single UI toggle, fixes the symptom. Trade-off: every branch in the repo disappears on merge, which may surprise other workflows.
4. Upstream PR on home-operations/renovate-presets - propose changing the bundle's default. Lowest direct impact, highest community value. Combine with local option 1 or 2 for the home-ops repo in the meantime.

## Validation

- Before: grep -c 'No commits between' /var/log/renovate.log counts > 0 after a Renovate run that touches a squash-merged branch
- After (per-group override): same grep counts 0 for the terraform-monorepo group, unchanged for other groups
- After (global override): grep counts 0 across all groups
- Manual: trigger a Renovate run (renovate --dry-run=full) and confirm no 422 in the output for branches that are already merged

## Related

- relates_to [[flux-gitops]]
- relates_to [[cloudflare]]
- relates_to [[ovh-storage]]
- relates_to [[k8s-workloads]]
