---
name: versions-renovate
description: Work on Renovate tracking and dependency update behavior in the home-ops repository. Use when Codex needs to modify .github/renovate.json5 or its imported fragments, preserve or add inline # renovate annotations in manifests, adjust allowed-version or grouping policy, or reason about why a dependency is or is not being tracked. Do not use this skill for routine app or infrastructure changes when dependency update behavior is unchanged.
---

# Home Ops Versions And Renovate

## Overview

Use this skill when the change is about dependency-tracking behavior rather than the runtime logic of the workload itself. It complements the repo rule that inline Renovate annotations are part of the live maintenance model.

## Workflow

1. Read the root guide and inspect `.github/renovate.json5` together with any touched fragment under `.github/renovate/`.
2. Inspect the touched manifest or config file alongside neighboring examples before changing annotation shape.
3. Load only the needed reference:
   - `references/annotations.md`
   - `references/config-files.md`
   - `references/validation.md`
4. Preserve existing annotation and grouping patterns unless the task explicitly changes update behavior.

## Scope Boundaries

- Use this skill when Renovate behavior, grouping, or tracking is part of the task.
- If you are only changing the dependency value inside an otherwise standard workload edit, use the domain skill for that area and keep Renovate behavior intact.
