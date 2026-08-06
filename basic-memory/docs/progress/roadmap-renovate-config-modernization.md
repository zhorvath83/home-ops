---
title: roadmap-renovate-config-modernization
type: note
permalink: home-ops/docs/progress/roadmap-renovate-config-modernization
tags:
- renovate
- roadmap
- config
- completed
---

# Renovate Config Modernization — Completed

## Status: completed
## Priority: medium
## Area: renovate
## Created: 2026-05-25
## Completed: 2026-05-25

## Summary

Surveyed 6 reference repos (buroa, szinn, billimek, onedr0p, heavybullets, bjw-s-labs) and aligned our Renovate config with community patterns. Made 4 user decisions converging toward bjw-s-labs defaults.

## Changes Made

| Change | Before | After |
|--------|--------|-------|
| `:separatePatchReleases` preset | In extends array | Removed — only Helm charts get separateMinorPatch |
| `minimumReleaseAge` | Global 3-day cooldown | Removed — per-rule cooldowns on GitHub Actions |
| `rebaseWhen` | `"conflicted"` | `"auto"` — aligns with bjw-s-labs |
| Helm chart automerge | All minor/patch automerged | Selective: only kube-prometheus-stack |
| GitHub Actions automerge | None | Minor/patch with 3-day cooldown; actions/* fast-track at 1 min |
| Container automerge rules | Digest rule + minor/patch rule (4 prefixes each) | Merged: digest+minor+patch for 3 trusted prefixes; coredns minor+patch separately |
| Labels | renovate/image + dep/major/minor/patch | type/major/minor/patch/digest + renovate/container/helm/github-action/github-release (composable) |
| GitHub labels | No Renovate labels | 5 labels: renovate/container, renovate/helm, renovate/github-action, renovate/github-release, renovate/talos |
| commitBodyTable | Not set | true |
| suppressNotifications | prIgnoreNotification only | + prEditedNotification |
| automergeType | Repeated per rule in autoMerge.json5 | Set globally via :automergeBranch preset — removed per-rule overrides |

## Bug Fix (second commit)

- GHA fast-track rule used matchPackageNames (regex) — both GHA rules matched actions/*, Renovate took the most restrictive minimumReleaseAge (3 days). Fixed by: adding excludePackagePrefixes to general rule + using matchPackagePrefixes for fast-track.
- Deduplicated trusted container prefixes (merged digest + minor/patch rules into one, separate coredns-only rule).
- Removed redundant ghcr.io/bjw-s-labs prefix (ghcr.io/bjw-s already matches it).

## Files Modified

- `.renovaterc.json5` — root config
- `.renovate/autoMerge.json5` — automerge rules
- `.renovate/overrides.json5` — labels and overrides
- `.github/labels.yaml` — GitHub labels

## Deferred

- home-operations/renovate-presets adoption — revisit after changes stabilize
- Grafana dashboard custom manager — add when repo has GrafanaDashboard CRs
- platformAutomerge — only meaningful with PR-based automerge
- helpers:pinGitHubActionDigestsToSemver upgrade

## Survey Reference

Full 6-repo comparison tables are preserved in the original roadmap note.

## Relations

- implements [[AD-020-renovate-cloud-fragments]]
- relates_to [[docs/areas/flux-gitops]]
- relates_to [[docs/areas/k8s-workloads]]
## Follow-up (2026-08-06) — talos-group renovate/artifacts false negative fix

- [problem] Every talos-group PR failed the `renovate/artifacts` check (state=failure, "Artifact file update failure") — a structural false negative, not a content defect (PR #4112 merged correct).
- [mechanism] The talos group bumps `siderolabs/talos` via two managers in one branch: `mise` (aqua tool, github-tags) and `regex` custom (`custom.talos-factory` datasource — `.mise.toml` TALOS_VERSION + `talosupgrade.yaml` version). A git-tracked `mise.lock` exists, so `mise.updateArtifacts` runs `mise lock`, which fails in Renovate's temp env ("mise trust"). The existing `matchManagers:["mise"]` `skipArtifactsUpdate:true` rule covered only the mise upgrade; Renovate reads `skipArtifactsUpdate` at branch level (`get-updated.ts`; `patchConfigForArtifactsUpdate` does not re-derive per manager), so the mixed branch's skip was non-uniform → `mise lock` ran → `artifactError` → check failed.
- [fix] commit c6d4ef3b2 — added `matchDatasources:["custom.talos-factory"], skipArtifactsUpdate:true` to `.renovate/overrides.json5`, so every upgrade in the talos branch skips → branch-level skip uniform → `mise.lock` regen no longer runs.
- [why-not-repo-wide] A repo-root `skipArtifactsUpdate:true` would also disable terraform `.terraform.lock.hcl` updates (PRs #4130/#4131 pass today with lock updates). The `custom.talos-factory` match is targeted — docker/helm/terraform unaffected.
- [evidence] talos PRs #4112/#4044/#3979 all show the failure; pure mise-manager tool PRs #4122/#4113/#4109/#4096 do not (skip uniform there). The exact `mise lock` stderr is Mend-hosted-log-only (auth-gated); mise attribution triangulated from the repo's own skip-rule comment + Renovate source + behavior.
- [open-verification] End-to-end green only observable on the NEXT talos bump or a manual Renovate dry-run — not yet confirmed.
- [follow-up out-of-scope] `renovate-config-validator` reports 5 pre-existing version-skew errors in `.renovaterc.json5` root (`baseBranchPatterns` + `flux`/`helm-values`/`helmfile`/`kubernetes` `managerFilePatterns`); orthogonal, separate task.
### Correction (2026-08-06)

The `[follow-up out-of-scope]` bullet above is SUPERSEDED - it framed the 5 `renovate-config-validator` errors as "version-skew ... orthogonal, separate task". Verified verdict: FALSE POSITIVE, not a real config error.

- [cause] The 5 errors (`baseBranchPatterns` + `flux`/`helm-values`/`helmfile`/`kubernetes` `managerFilePatterns`) came from a stale npx-cached validator `renovate@37.440.7`. `managerFilePatterns` is the current name since Renovate v40.2.0 (PR #34615, renamed from `fileMatch`); `baseBranchPatterns` since v41.34.0 (PR #35579, renamed from `baseBranches`). The stale validator predates both renames -> "Invalid configuration option" x5.
- [confirm] `renovate@44.14.1` validates the same config with 0 errors; Mend hosted Renovate accepts it (Dependency Dashboard #631 active 2026-08-06, no open "Fix Renovate Configuration" issue; PRs generate correctly).
- [warning] Do NOT revert to the old names `baseBranches`/`fileMatch` - they are the deprecated predecessors; the current names are correct and the hosted Renovate expects them.
- [durable fix] A pre-commit hook now validates `.renovaterc.json5` + all `.renovate/*.json5` fragments on every change (commit 55bb8fd56). Three findings shaped it:
  1. The root validator does NOT read local fragments - root-only validation is false security; the hook validates every fragment standalone (proven: a broken fragment passes root validation but fails standalone).
  2. Validation is offline-capable and deterministic with GITHUB_TOKEN unset (the validator skips `github>` preset resolution without a token - no network dependency, no secret in the repo).
  3. The hook uses `language: node` (not mise-pinned `npm:renovate`): mise aube npm backend refuses to install renovate on a `@yarnpkg/libzip@3.2.2` provenance downgrade. Bypassing aube (`npm.shell_out=true` or `trust_policy_excludes`) would weaken supply-chain trust repo-wide for a lint hook - rejected. The pre-commit node env installs `renovate@44.14.1` via plain npm, sidestepping both aube and the node-engine constraint.
- [open] Auto-bump of the pinned `renovate@44.14.1` is deferred: the existing customManagers regex captures the whole `package@version` string as `currentValue` (verified), so a new matchStrings/manager is needed for the `# renovate:` annotation - separate follow-up (no new machinery built without approval).
