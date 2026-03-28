# Validation

Use this reference after changing Cloudflare Terraform files.

## Preferred Validation Flow

1. `task tf:init:cloudflare` when initialization is needed
2. `task tf:plan:cloudflare` for behavioral validation
3. `task tf:apply:cloudflare` only when the user explicitly wants the change applied

## Checks

- resource names and file placement remain consistent with neighboring files
- `op run` and `.env` expectations still match the edited workflow
- inline Renovate directives remain intact

If validation cannot run, say whether the blocker is missing Terraform, credentials, `op`, or remote access.
