---
name: flux-gitops
description: Work on Flux and shared GitOps wiring in the home-ops repository. Use when Codex needs to modify kubernetes/flux resources, Flux bootstrap files, Flux-managed cluster variables, flux-system add-ons such as GitHub webhooks, or shared Kustomization dependency wiring that sits above one specific app. Do not use this skill for routine app manifest edits that stay inside a single application subtree.
---

# Home Ops Flux GitOps

## Overview

Use this skill when a task changes the repo's GitOps control plane rather than one workload. It complements the `kubernetes/AGENTS.md` guardrails with workflow and validation guidance for Flux bootstrap, shared vars, and cluster-wide apply ordering.

## Workflow

1. Read the root guide, `kubernetes/AGENTS.md`, and the nearest subtree guide for the target path.
2. Decide whether the task is mainly:
   - Flux bootstrap or install flow
   - shared `kubernetes/flux/` configuration or vars
   - `kubernetes/apps/flux-system/` add-ons or webhooks
   - shared Kustomization dependency or naming work
3. Load only the needed reference:
   - `references/layout.md`
   - `references/operations.md`
   - `references/validation.md`
4. Prefer the existing `fx:` task wrappers for inspection or reconcile steps when the environment is available.
5. Treat local edits as Git state only; do not imply live cluster change without commit, push, and reconcile.

## Scope Boundaries

- Use `k8s-workloads` for ordinary app manifests under `kubernetes/apps/<group>/<app>/`.
- Use this skill when the change touches shared Flux variables, bootstrap resources, `flux-system` add-ons, or dependency wiring that affects more than one app.
- If the task also changes repo-encrypted secret material such as `cluster-secrets.sops.yaml`, use `sops-secrets` as well.
- If the task is mainly about webhook exposure, provider secrets, or cluster-wide blast radius review, use `security-review` as well.
