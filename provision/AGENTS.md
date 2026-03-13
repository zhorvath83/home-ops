# Provisioning Agent Guide

This guide applies to everything under `provision/`.

## Structure

- `provision/kubernetes/`: Ansible configuration, inventory, and playbooks for host preparation and cluster lifecycle operations
- `provision/cloudflare/`: Terraform configuration for Cloudflare-managed infrastructure

## Operating Rules

- Treat this directory as the imperative and provider-facing side of the repo.
- Keep operational commands aligned with `Taskfile.yml` and `.taskfiles/*/Tasks.yaml` instead of inventing ad-hoc command flows.
- Prefer editing the source configuration, not generated state or local cache directories.

## Ansible Area

For `provision/kubernetes/`:

- Inventory is under `inventory/`; playbooks are under `playbooks/`.
- Host access and secrets are wired through 1Password lookups in inventory and group vars.
- Before changing a playbook, inspect the corresponding task wrapper in `.taskfiles/Ansible/Tasks.yaml`.
- Preserve the current single-cluster assumptions unless the repo itself shows a broader topology.
- Use the existing task entry points such as `task an:list`, `task an:ping`, `task an:prepare`, and `task an:install` as the canonical workflows.

Avoid editing transient or local-only artifacts if they appear.

## Terraform Area

For `provision/cloudflare/`:

- Terraform files in this directory are the source of truth for Cloudflare resources.
- Prefer `task tf:init:cloudflare`, `task tf:plan:cloudflare`, and `task tf:apply:cloudflare` workflows over raw commands when documenting or validating changes.
- `.env`, `.terraform/`, `terraform.tfstate`, and similar local state files are operational artifacts, not configuration patterns to refactor.
- Keep resource naming and file split conventions consistent with the existing files such as `dns_records.tf`, `tunnel.tf`, and `workers.tf`.
- Keep existing inline Renovate directives intact, such as the provider disable comment in [cloudflare/main.tf](cloudflare/main.tf).

## Validation

- For Ansible edits, run the smallest relevant listing or syntax-adjacent command available through the existing task wrappers when feasible.
- For Terraform edits, prefer formatting or planning in `provision/cloudflare/` if the environment is available.
- If a change touches credentials or secret sourcing, verify whether the workflow depends on `op run`, `.env`, or 1Password inventory lookups before editing command structure.
