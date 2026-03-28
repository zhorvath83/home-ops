---
name: taskfiles
description: Work on the Taskfile-based operational entry points in the home-ops repository. Use when Codex needs to add or modify tasks in Taskfile.yml or .taskfiles/*, adjust task namespaces, align wrappers with repo workflows, or validate how operators should run existing commands. Do not use this skill for domain logic changes when the task definitions themselves are untouched.
---

# Home Ops Taskfiles

## Overview

Use this skill for the repo's task-runner surface. It complements the root `AGENTS.md` rule that existing task wrappers are the preferred operational entry points.

## Workflow

1. Read the root guide and inspect both `Taskfile.yml` and the target file under `.taskfiles/`.
2. Decide whether the task is mainly:
   - root include and namespace wiring
   - one domain task file under `.taskfiles/`
   - command-shape or validation-flow cleanup
3. Load only the needed reference:
   - `references/catalog.md`
   - `references/authoring.md`
   - `references/validation.md`
4. Keep task wrappers aligned with the canonical repo workflow instead of reintroducing ad-hoc shell flows.

## Scope Boundaries

- Use this skill when the `task` entry points themselves are changing or need interpretation.
- If the task changes domain behavior inside Kubernetes, Terraform, Ansible, or VolSync, use the corresponding domain skill alongside this one.
