# Layout

Use this reference to rebuild the Cloudflare Terraform structure before editing.

## Source Files

Terraform configuration is split by concern, for example:

- `dns_records.tf`
- `tunnel.tf`
- `workers.tf`
- `redirects.tf`
- `zone_settings.tf`
- supporting files such as `variables.tf`, `main.tf`, templates, and resource assets

Keep new resources aligned with the existing split unless there is a strong reason to reshape the layout.

## Credential And Runtime Model

- the repo uses `op run --env-file=./.env -- terraform ...`
- `.env`, `.terraform/`, and state files are operational artifacts, not source patterns
- preserve inline Renovate directives in provider files
