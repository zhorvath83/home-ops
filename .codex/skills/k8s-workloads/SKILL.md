---
name: k8s-workloads
description: Plan and implement non-platform Flux-managed application workloads in the home-ops repository. Use when Codex needs to add a new app under kubernetes/apps/default or another non-platform app subtree, reshape ks.yaml or app manifests, choose chart, dependency, security, storage, or routing patterns, wire routine app-level ExternalSecret or VolSync settings into a workload, or validate application changes that do not redesign the networking, external-secrets, or volsync-system platforms.
---

# Home Ops K8s Workloads

## Overview

Use this skill for non-platform application work under `kubernetes/apps/`. Keep repo guardrails in the `AGENTS.md` chain, then load only the reference file needed for the workload shape.

## Workflow

1. Read the root guide, `kubernetes/AGENTS.md`, and the nearest subtree guide.
2. Inspect the target app plus 2-3 sibling apps with similar exposure, storage, and auth.
3. Load only the reference file needed for the task:
   - `references/app-scaffolding.md` for new apps, folder shape, and dependency wiring
   - `references/runtime-baselines.md` for security, resources, storage, and config handling
   - `references/publication-and-jobs.md` for routes, Homepage, media patterns, and CronJobs
   - `references/validation.md` for final checks
4. If the change crosses into platform ownership, also use the dedicated skill:
   - `networking-platform`
   - `external-secrets`
   - `sops-secrets`
   - `volsync`
   - `flux-gitops`
   - `security-review` when the task is mainly hardening or exposure review
5. Treat local edits as Git state only; do not imply live cluster change without commit, push, and reconcile.

## Scope Boundaries

- Use this skill for app workloads, not for networking platform internals, the external-secrets platform, or the VolSync platform itself.
- If app-level secret wiring is routine, this skill is enough. If the store, operator, or template model changes, switch to `external-secrets`.
- If the task adds or changes repo-encrypted `secret.sops.yaml` material or shared Flux secret substitutions, use `sops-secrets` as well.
- If app-level backup wiring is routine, this skill is enough. If schedule, jitter, restore flow, or VolSync platform resources change, switch to `volsync`.
- If the task changes `kubernetes/flux/`, Flux bootstrap, webhook receivers, or shared GitOps wiring, switch to `flux-gitops`.
