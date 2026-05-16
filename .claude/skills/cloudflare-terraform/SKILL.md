---
name: cloudflare-terraform
description: Work on the Cloudflare Terraform area in the home-ops repository. Use when modifying provision/cloudflare Terraform resources, file layout, the `just cloudflare` recipes, or credential and validation flows tied to Cloudflare DNS, tunnel, workers, redirects, pages, or zone configuration.
---

# Home Ops Cloudflare Terraform

## Overview

Use this skill for the Terraform-backed Cloudflare area. It complements the `provision/cloudflare/CLAUDE.md` guardrails with workflow and validation guidance.

## Workflow

1. Read the root guide, `provision/CLAUDE.md`, and `provision/cloudflare/CLAUDE.md`.
2. Inspect the existing file split before moving or adding resources.
3. Load only the needed reference:
   - `references/layout.md`
   - `references/validation.md`
4. Prefer the `just cloudflare` recipes over raw Terraform commands when validation is possible.

## Scope Boundaries

- Use this skill when source files under `provision/cloudflare/` or the `just cloudflare` recipes are changing.
- Use `just` as well when `provision/cloudflare/mod.just` itself is changing.
- Use `versions-renovate` if the task changes Renovate tracking or provider annotation behavior.
- Use `security-review` as well when the task changes public exposure, Access policy, firewalling, or tunnel trust.
