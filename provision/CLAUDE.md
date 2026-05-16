# Provisioning Agent Guide

This guide applies to everything under `provision/`.

## Structure

- `provision/cloudflare/`: Terraform-managed Cloudflare resources
- `provision/ovh/`: Terraform-managed OVH Cloud Project Storage (S3 backup buckets and the dedicated S3 user) used by the cluster backup planes
- `provision/openmediavault/`: `mod.just` recipes for the bare-metal OMV host; Ansible playbooks land here during Phase 10

## Subtree Guides

Use the more specific guide for the target area:

- Cloudflare Terraform: [cloudflare/CLAUDE.md](cloudflare/CLAUDE.md)
- OVH Terraform: [ovh/CLAUDE.md](ovh/CLAUDE.md)

## Traversal Rule

For any work under `provision/`, apply guides in this order:

1. [../CLAUDE.md](../CLAUDE.md)
2. [CLAUDE.md](CLAUDE.md)
3. the nearest subtree `CLAUDE.md`

## Operating Rules

- Treat this directory as the imperative and provider-facing side of the repo.
- Keep operational commands aligned with `Taskfile.yml` and `.taskfiles/*/Tasks.yaml` instead of inventing ad-hoc command flows.
- Prefer editing source configuration over generated state or local cache directories.
- If a task wrapper already exists, use that workflow as the canonical entry point.

## Validation

- For provisioning changes, run the smallest relevant task-backed validation step available for the touched area.
- If a change touches credentials or secret sourcing, inspect the existing `op run`, `.env`, or 1Password lookup flow before changing command structure.
- Use repo-local skills for detailed procedures:
  - Cloudflare Terraform: `.claude/skills/cloudflare-terraform/`
  - shared task wrapper conventions: `.claude/skills/taskfiles/`
