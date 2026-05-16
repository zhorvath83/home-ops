---
name: just
description: Work on the Just-based operational entry points in the home-ops repository. Use when adding or modifying recipes in the root `.justfile` or any `**/mod.just`, adjusting mod-group wiring, aligning command flows with repo workflows, or validating how operators should run existing commands. Do not use this skill for domain logic changes when the recipe definitions themselves are untouched.
---

# Home Ops Just

## Overview

Use this skill for the repo's command-runner surface. It complements the root `CLAUDE.md` rule that existing `just` recipes are the preferred operational entry points. The repo uses Just (`.justfile` + `**/mod.just`) — no Task / Taskfile is present.

## Workflow

1. Read the root guide and inspect both the root `.justfile` and the target `mod.just` for the touched area.
2. Decide whether the task is mainly:
   - root mod-group wiring (`mod x "path"` entries)
   - one domain `mod.just` file
   - command-shape, positional-arg, or validation-flow cleanup
3. Load only the needed reference:
   - `references/catalog.md`
   - `references/authoring.md`
   - `references/validation.md`
4. Keep recipes aligned with the canonical repo workflow instead of reintroducing ad-hoc shell flows.
5. Recipe arguments are **positional only** (`set positional-arguments` is set globally); never document `key=value` named-argument call shapes — that syntax does not work in Just.

## Scope Boundaries

- Use this skill when the `just` entry points themselves are changing or need interpretation.
- If the task changes domain behavior inside Kubernetes, Terraform, Ansible, or VolSync, use the corresponding domain skill alongside this one.
- For dependency-version changes, use `versions-renovate`.
- For tool-version changes, edit `.mise.toml`, not `mod.just`.
