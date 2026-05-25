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
