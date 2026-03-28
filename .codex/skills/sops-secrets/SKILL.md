---
name: sops-secrets
description: Work on SOPS-encrypted secret material in the home-ops repository. Use when Codex needs to modify kubernetes/flux/vars/cluster-secrets.sops.yaml, app-level secret.sops.yaml files, the repo's SOPS helper tasks, or bootstrap secret flows that depend on repo-encrypted values. Do not use this skill for ExternalSecret and 1Password delivery changes unless repo-encrypted secret material is also part of the task.
---

# Home Ops SOPS Secrets

## Overview

Use this skill when secret data is stored in git in SOPS-encrypted form. It complements the repo guardrails that plaintext secrets must never enter the repository.

## Workflow

1. Read the root guide, then inspect the nearest subtree guide for the target secret.
2. Decide whether the task is mainly:
   - cluster-wide secret substitutions under `kubernetes/flux/vars/`
   - app-level `secret.sops.yaml` material
   - bootstrap or task-backed SOPS workflow changes
3. Load only the needed reference:
   - `references/decision-guide.md`
   - `references/bootstrap-and-app-secrets.md`
   - `references/validation.md`
4. Keep secret values encrypted in repo state; do not introduce plaintext or alternate secret stores by accident.

## Scope Boundaries

- Use `external-secrets` when the main change is 1Password or `ClusterSecretStore` delivery.
- Use this skill when the repo-encrypted file itself or the SOPS workflow changes.
- If both SOPS material and External Secrets wiring change together, use both skills.
