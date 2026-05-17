# Cloudflare Terraform Guide

This guide applies to `provision/cloudflare/`.

## What Lives Here

- Terraform files in this directory are the source of truth for Cloudflare resources.
- File splits such as `dns_records.tf`, `tunnel.tf`, `workers.tf`, and related files reflect the current repository organization and should stay stable unless there is a clear reason to reshape them.

## Operating Rules

- Prefer `just cloudflare init`, `just cloudflare plan`, and `just cloudflare apply` over raw Terraform commands when documenting or validating changes. Use `just cloudflare unlock <id>` for state-lock recovery.
- Preserve the existing `op run --env-file=./.env -- terraform ...` pattern that the recipes wrap unless the entire credential flow is intentionally changing.
- `.env`, `.terraform/`, `.terraform.lock.hcl`, and state files are operational artifacts; do not refactor them as if they were source configuration.
- Keep existing inline Renovate directives intact, including provider-specific comments in `main.tf`.

## Validation

- Prefer formatting, initialization, or planning within `provision/cloudflare/` when the environment is available.
- If a change affects credentials, provider auth, or remote state behavior, verify the surrounding workflow before changing command structure.
- Use repo-local skills for detailed procedures:
  - Cloudflare Terraform workflows: `.claude/skills/cloudflare-terraform/`
  - shared recipe-runner conventions: `.claude/skills/just/`
  - public exposure or tunnel-trust changes: `.claude/skills/security-review/`
