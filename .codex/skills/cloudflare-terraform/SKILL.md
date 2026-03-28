---
name: cloudflare-terraform
description: Work on the Cloudflare Terraform area in the home-ops repository. Use when Codex needs to modify provision/cloudflare Terraform resources, file layout, task-backed Terraform workflows, or credential and validation flows tied to Cloudflare DNS, tunnel, workers, redirects, pages, or zone configuration.
---

# Home Ops Cloudflare Terraform

## Overview

Use this skill for the Terraform-backed Cloudflare area. It complements the `provision/cloudflare/AGENTS.md` guardrails with workflow and validation guidance.

## Workflow

1. Read the root guide, `provision/AGENTS.md`, and `provision/cloudflare/AGENTS.md`.
2. Inspect the existing file split before moving or adding resources.
3. Load only the needed reference:
   - `references/layout.md`
   - `references/validation.md`
4. Prefer task-backed Terraform workflows over raw commands when validation is possible.

## Scope Boundaries

- Use this skill when source files under `provision/cloudflare/` or their task-backed workflows are changing.
- Use `taskfiles` as well when the `tf:` wrappers themselves are changing.
- Use `versions-renovate` if the task changes Renovate tracking or provider annotation behavior.
- Use `security-review` as well when the task changes public exposure, Access policy, firewalling, or tunnel trust.
