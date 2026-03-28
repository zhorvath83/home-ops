---
name: external-secrets
description: Work on shared secret delivery in the home-ops repository. Use when Codex needs to modify the external-secrets platform, 1Password Connect, the onepassword ClusterSecretStore, or non-routine app-level ExternalSecret wiring and validation patterns that depend on the shared secret delivery model. Do not use this skill for unrelated SOPS-only changes or routine app edits that merely consume an unchanged Secret.
---

# Home Ops External Secrets

## Overview

Use this skill when the shared 1Password and External Secrets model is part of the change. Keep simple app workload work in `k8s-workloads`, but switch here when secret-delivery semantics or platform ordering matter.

## Workflow

1. Read the root guide, `kubernetes/AGENTS.md`, and `kubernetes/apps/external-secrets/AGENTS.md`.
2. Decide whether the change is:
   - platform topology or sequencing
   - app-level `ExternalSecret` wiring
3. Load only the needed reference:
   - `references/platform-topology.md`
   - `references/app-wiring.md`
   - `references/validation.md`
4. If the task also changes repo-encrypted secret material, use `sops-secrets` as well.
5. If the task also changes workload routing or backup behavior, use the dedicated networking or VolSync skill as well.

## Scope Boundaries

- Use this skill when the shared 1Password and `ClusterSecretStore` delivery model matters.
- Do not use this skill for SOPS-only app secrets, Flux bootstrap secret files, or other repo-encrypted secret material that does not involve External Secrets. Use `sops-secrets` for that work.
- If the task is mainly about secret exposure, token scope, or hardening review, use `security-review` as well.
