# OVH Terraform Guide

This guide applies to `provision/ovh/`.

## What Lives Here

- Terraform files in this directory are the source of truth for OVH Cloud Project Storage resources used by the cluster backup planes.
- Current resources: S3 backup buckets (`buckets.tf`), the dedicated `objectstore_operator` cloud project user with its S3 credential and bucket-scoped policy (`user.tf`), provider and remote state wiring (`main.tf`), and input variables (`variables.tf`).
- The provisioned S3 endpoint, user, and credentials are consumed downstream by the VolSync/Kopia plane (`kubernetes/components/volsync/` and `kubernetes/apps/volsync-system/`) and by the file-level resticprofile plane (`kubernetes/apps/default/resticprofile/`).

## Operating Rules

- Prefer `task tf:init:ovh`, `task tf:plan:ovh`, and `task tf:apply:ovh` over raw Terraform commands when documenting or validating changes.
- Preserve the existing `op run --env-file=./.env -- terraform ...` pattern unless the entire credential flow is intentionally changing.
- `task tf:apply:ovh` also syncs the freshly issued S3 credentials and metadata back into the `ovh` 1Password item; keep that side effect intact when touching the apply flow.
- Use `task tf:unlock:ovh` for state unlock operations rather than calling `terraform force-unlock` directly.
- `.env`, `.terraform/`, `.terraform.lock.hcl`, and state files are operational artifacts; do not refactor them as if they were source configuration.
- Treat the bucket name list (`S3_BUCKET_NAMES`) and the bound S3 policy as part of the cluster backup contract: renaming or removing a bucket affects live VolSync/Kopia and resticprofile consumers and must be coordinated with their ExternalSecret wiring.
- Keep existing inline Renovate directives intact, including provider-version comments in `main.tf`.

## Validation

- Prefer formatting, initialization, or planning within `provision/ovh/` when the environment is available.
- If a change affects credentials, provider auth, the 1Password sync block, or remote state behavior, verify the surrounding workflow before changing command structure.
