# Cloudflare Terraform Guide

This guide applies to `provision/cloudflare/`. It captures durable guardrails for the Cloudflare Terraform area; for current-state detail (zone, tunnel, Access apps, Workers, R2, mail-stack DNS, WAF, zone settings, notifications, claims, drift risk) read the Basic Memory area-reference `docs/areas/cloudflare` via the `basic-memory` MCP.

## Scope

Terraform files here are the source of truth for Cloudflare resources. State lives in Terraform Cloud (org `zhorvath83`, workspace `cloudflare`). File splits (`dns_records.tf`, `tunnel.tf`, `access.tf`, `workers.tf`, `firewall_rules.tf`, `zone_settings.tf`, `notification.tf`, `r2_bucket.tf`, `managed_transforms.tf`) reflect the current organization and should stay stable unless there is a clear reason to reshape them.

## Operating Rules

- Prefer `just cloudflare init|plan|apply` over raw Terraform commands; use `just cloudflare unlock <id>` for state-lock recovery.
- Preserve the existing `op run --no-masking --env-file=./.env -- terraform ...` pattern that the recipes wrap unless the entire credential flow is intentionally changing.
- `.env`, `.terraform/`, `.terraform.lock.hcl`, and state files are operational artifacts — do not refactor them as source configuration.
- Keep existing inline Renovate directives intact, including the provider-specific `# renovate:disablePlugin terraform cloudflare/cloudflare` annotation in `main.tf`.
- Two `null_resource` blocks (tunnel + Access service token) write secrets back to 1Password item `cloudflare` via `op item edit` as a post-create side effect — the in-cluster consumers read those fields via ExternalSecret. Keep the field names aligned across Terraform, 1Password, and the consumer ExternalSecrets when changing either side.

## Validation

- Prefer formatting, initialization, or planning within `provision/cloudflare/` when the environment is available.
- If a change affects credentials, provider auth, or remote state behavior, verify the surrounding workflow before changing command structure.
- Use repo-local skills for detailed procedures:
  - Cloudflare Terraform workflows: `.claude/skills/cloudflare-terraform/`
  - shared recipe-runner conventions: `.claude/skills/just/`
  - public exposure or tunnel-trust changes: `.claude/skills/security-review/`
