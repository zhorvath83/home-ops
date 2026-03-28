# Provision Kubernetes Guide

This guide applies to `provision/kubernetes/`.

## What Lives Here

- `inventory/`: inventory and host-specific variables
- `playbooks/`: Ansible playbooks and templates for cluster lifecycle work
- `requirements.txt` and `requirements.yml`: Python, role, and collection dependencies

## Operating Rules

- Preserve the current single-cluster assumptions unless the repo itself shows a broader topology.
- Host access and secrets are wired through 1Password lookups in inventory and related vars; keep that flow intact unless the task explicitly changes it.
- Before changing a playbook, inspect the corresponding wrapper in `.taskfiles/Ansible/Tasks.yaml`.
- Prefer existing task entry points such as `task an:list`, `task an:ping`, `task an:prepare`, and `task an:install` over ad-hoc command sequences.
- Avoid editing transient or local-only artifacts if they appear.

## Validation

- For inventory changes, prefer the smallest safe listing or connectivity check through the existing task wrappers.
- For playbook changes, prefer a syntax-adjacent or narrowly scoped task-backed command when the environment is available.
- If validation cannot run, say whether the blocker is missing tooling, credentials, SSH reachability, or cluster access.
