# Validation

Use this reference after changing Cloudflare Terraform files.

## Preferred Validation Flow

1. `just cloudflare init` when initialization is needed
2. `just cloudflare plan` for behavioral validation
3. `just cloudflare apply` only when the user explicitly wants the change applied
4. `just cloudflare unlock <id>` only for state-lock recovery, never as a routine step

## Checks

- resource names and file placement remain consistent with neighboring files
- `op run` and `.env` expectations still match the edited workflow
- inline Renovate directives remain intact

If validation cannot run, say whether the blocker is missing Terraform, credentials, `op`, or remote access.
