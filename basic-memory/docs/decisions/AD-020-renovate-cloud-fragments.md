---
title: AD-020-renovate-cloud-fragments
type: decision
permalink: home-ops/docs/decisions/ad-020-renovate-cloud-fragments
decision_id: AD-020
topic: Renovate stays cloud-based with refactored fragment config
status: active
decided_at: '2025-10-01'
decision: 'Renovate stays cloud-based (Mend Renovate or the GitHub App); NOT self-hosted.
  The config is refactored to the bjw-s / onedr0p pattern: `.renovaterc.json5` at
  the repo root + `.renovate/*.json5` fragments.'
rationale: Self-hosted Renovate is extra cluster workload with no benefit for a single-developer
  project Cloud Renovate is free for public repos and reliable Fragments (`autoMerge.json5`,
  `groupPackages.json5`, `packageRules.json5`) are more organized than a 500-line
  monolith
tradeoffs: Cloud Renovate scheduling is less customizable (but the `schedule` key
  inside fragments is enough)
---

# AD-020 — Renovate stays cloud-based with refactored fragment config

## Metadata (observation-form, schema validation)
- [decision_id] AD-020
- [status] active
- [decided_at] 2025-10-01
- [topic] Renovate stays cloud-based with refactored fragment config

## Decision
Renovate stays cloud-based (Mend Renovate or the GitHub App); NOT self-hosted. The config is refactored to the bjw-s / onedr0p pattern: `.renovaterc.json5` at the repo root + `.renovate/*.json5` fragments.

## Rationale
- Self-hosted Renovate is extra cluster workload with no benefit for a single-developer project
- Cloud Renovate is free for public repos and reliable
- Fragments (`autoMerge.json5`, `groupPackages.json5`, `packageRules.json5`) are more organized than a 500-line monolith

## Tradeoffs
- Cloud Renovate scheduling is less customizable (but the `schedule` key inside fragments is enough)

## Related
_No AreaReference link — repo-tooling level decision._
