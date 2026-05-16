---
name: volsync
description: Work on backup and restore behavior in the home-ops repository using VolSync and Kopia. Use when integrating non-trivial app backup settings, change shared schedule, jitter, retention, or storage defaults, inspect ReplicationSource behavior, trigger maintenance or snapshot flows, or perform or review restore workflows driven by the `just volsync` recipes. Do not use this skill for unrelated secret delivery changes.
---

# Home Ops VolSync

## Overview

Use this skill when backup policy or restore mechanics are part of the task.
It is separate from the External Secrets skill because backup timing, mover
behavior, and restore safety have different operators, different failure
modes, and different validation workflows.

## Workflow

1. Read the root guide, `kubernetes/CLAUDE.md`, and `kubernetes/apps/volsync-system/CLAUDE.md` when platform resources are involved.
2. Decide whether the task is:
   - routine app backup integration
   - cluster-wide backup policy change
   - operational inspection, snapshot, maintenance, or restore
3. Load only the needed reference:
   - `references/app-integration.md`
   - `references/platform-policy.md`
   - `references/operations.md`
   - `references/validation.md` for final checks
4. If the task also changes application manifests, use `k8s-workloads` alongside this skill.
5. If the task also touches `kubernetes/volsync/mod.just` recipe wiring or adds new operational entry points, use `just` alongside this skill.

## Scope Boundaries

- Use this skill when backup policy, restore behavior, or VolSync platform resources are part of the task.
- Use `k8s-workloads` for ordinary app manifest changes that only consume an unchanged backup model.
- Use `just` as well when the `just volsync` recipes or their wiring are changing.
