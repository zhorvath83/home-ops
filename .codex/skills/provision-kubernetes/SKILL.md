---
name: provision-kubernetes
description: Work on the Ansible-based cluster provisioning area in the home-ops repository. Use when Codex needs to modify inventory, playbooks, templates, Ansible dependency files, or task-backed workflows under provision/kubernetes for host preparation, cluster installation, reboot, or lifecycle operations.
---

# Home Ops Provision Kubernetes

## Overview

Use this skill for the Ansible-driven provisioning area. It complements the `provision/kubernetes/AGENTS.md` guardrails with workflow-specific guidance.

## Workflow

1. Read the root guide, `provision/AGENTS.md`, and `provision/kubernetes/AGENTS.md`.
2. Decide whether the task is mainly inventory, playbook, or task-wrapper related.
3. Load only the needed reference:
   - `references/layout.md`
   - `references/workflows.md`
4. Prefer the smallest task-backed validation step available after edits.

## Scope Boundaries

- Use this skill for inventory, playbooks, templates, and dependency files under `provision/kubernetes/`.
- Use `taskfiles` as well when the `an:` wrappers themselves are changing.
