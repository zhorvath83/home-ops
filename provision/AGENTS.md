# Provisioning Agent Guide

This guide applies to everything under `provision/`.

## Structure

- `provision/kubernetes/`: Ansible-based host preparation and cluster lifecycle workflows
- `provision/cloudflare/`: Terraform-managed Cloudflare resources

## Subtree Guides

Use the more specific guide for the target area:

- Kubernetes provisioning: [kubernetes/AGENTS.md](kubernetes/AGENTS.md)
- Cloudflare Terraform: [cloudflare/AGENTS.md](cloudflare/AGENTS.md)

## Traversal Rule

For any work under `provision/`, apply guides in this order:

1. [../AGENTS.md](../AGENTS.md)
2. [AGENTS.md](AGENTS.md)
3. the nearest subtree `AGENTS.md`

## Operating Rules

- Treat this directory as the imperative and provider-facing side of the repo.
- Keep operational commands aligned with `Taskfile.yml` and `.taskfiles/*/Tasks.yaml` instead of inventing ad-hoc command flows.
- Prefer editing source configuration over generated state or local cache directories.
- If a task wrapper already exists, use that workflow as the canonical entry point.

## Validation

- For provisioning changes, run the smallest relevant task-backed validation step available for the touched area.
- If a change touches credentials or secret sourcing, inspect the existing `op run`, `.env`, or 1Password lookup flow before changing command structure.
