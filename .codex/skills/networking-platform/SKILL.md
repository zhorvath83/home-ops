---
name: networking-platform
description: Modify shared networking platform resources in the home-ops repository. Use when Codex needs to change Envoy Gateway, Gateway API resources, Cloudflare Tunnel, ExternalDNS, MetalLB, networking Flux ordering, or shared ingress behavior in kubernetes/apps/networking. Do not use this skill for routine application routes that do not alter the platform exposure chain.
---

# Home Ops Networking Platform

## Overview

Use this skill when a change touches the shared ingress and public exposure chain. It complements the networking subtree `AGENTS.md` with workflow and validation guidance.

## Workflow

1. Read the root guide, `kubernetes/AGENTS.md`, and `kubernetes/apps/networking/AGENTS.md`.
2. Inspect the parent `ks.yaml` plus any split child directories such as `app/`, `config/`, or `certificate/`.
3. Load only the needed reference:
   - `references/topology.md` for platform layout and ownership
   - `references/change-patterns.md` for common change types
   - `references/validation.md` for final checks
4. If the change only adds a routine app route and does not touch shared networking resources, use `k8s-workloads` instead.

## Scope Boundaries

- Use this skill for shared ingress, tunnel, DNS, and Gateway resources under `kubernetes/apps/networking/`.
- Use `k8s-workloads` for ordinary app route manifests that do not change the platform exposure chain.
- If the task also changes shared Flux ordering or `flux-system` resources, use `flux-gitops` as well.
- If the task is primarily about exposure risk, trust boundaries, or hardening review, use `security-review` as well.
