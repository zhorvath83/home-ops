# OVH Terraform Guide

This guide applies to `provision/ovh/`. It captures durable guardrails for the OVH Cloud Project Storage Terraform area; for current-state detail (buckets, object-store user, S3 policy, 1Password sync, claims, drift risk) read the Basic Memory area-reference `docs/areas/ovh-storage` via the `basic-memory` MCP.

## Scope

Terraform files here are the source of truth for the OVH Cloud Project Storage resources used by the cluster backup planes:

- S3 backup buckets (`buckets.tf`)
- the dedicated `objectstore_operator` cloud project user with its S3 credential and bucket-scoped policy (`user.tf`)
- provider + remote state wiring (`main.tf`)
- input variables (`variables.tf`)

The provisioned S3 endpoint, user, and credentials are consumed downstream by the VolSync/Kopia plane (`kubernetes/components/volsync/` + `kubernetes/apps/volsync-system/`) and by the file-level resticprofile plane (`kubernetes/apps/selfhosted/resticprofile/`).

## Operating Rules

- Prefer `just ovh init|plan|apply` over raw Terraform commands; use `just ovh unlock <id>` for state-unlock operations.
- Preserve the existing `op run --env-file=./.env -- terraform ...` pattern unless the credential flow is intentionally changing.
- `just ovh apply` also syncs the freshly issued S3 credentials and metadata back into the `HomeOps/ovh` 1Password item — keep that side effect intact when touching the apply flow. Running raw `terraform apply` skips the sync and leaves in-cluster consumers stale.
- `.env`, `.terraform/`, `.terraform.lock.hcl`, and state files are operational artifacts — do not refactor them as source configuration.
- Treat the bucket name list (`S3_BUCKET_NAMES`) and the bound S3 policy as part of the cluster backup contract: renaming or removing a bucket affects live VolSync/Kopia and resticprofile consumers and must be coordinated with their ExternalSecret wiring.
- Keep existing inline Renovate directives intact, including provider-version comments in `main.tf`.

## Validation

- Prefer formatting, initialization, or planning within `provision/ovh/` when the environment is available.
- If a change affects credentials, provider auth, the 1Password sync block, or remote state behavior, verify the surrounding workflow before changing command structure.
- Use repo-local skills for detailed procedures:
  - shared recipe-runner conventions: `.claude/skills/just/`
  - downstream backup contract impact: `.claude/skills/volsync/`
