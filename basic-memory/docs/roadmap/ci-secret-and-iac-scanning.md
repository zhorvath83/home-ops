---
title: ci-secret-and-iac-scanning
type: roadmap
permalink: home-ops/docs/roadmap/ci-secret-and-iac-scanning
topic: Server-side secret + IaC scanning in CI
status: proposed
priority: low
scope: Add gitleaks and an IaC security scanner (trivy config / tfsec) as CI jobs
  so secret and misconfiguration checks are enforced server-side, not only in local
  pre-commit.
rationale: A CI backstop makes the existing local checks non-bypassable and adds Terraform/Kubernetes
  misconfiguration detection, catching issues that a --no-verify commit or a fresh
  clone would otherwise miss.
related_areas:
- flux-gitops
---

# Server-side secret + IaC scanning in CI

## Metadata (observation-form, schema validation)

- [topic] Server-side secret + IaC scanning in CI
- [status] proposed
- [priority] low

## What we gain

- Secret and IaC checks run on every PR regardless of local hooks — durable for a potentially-public repo.
- Automated detection of risky IaC patterns (open buckets, missing versioning, over-broad policies) before merge.
- Reinforces the required-checks gate on main.

## What to do

1. Add a gitleaks CI job (PR-diff and/or full-history scan).
2. Add trivy config (or tfsec/checkov) over provision/ and kubernetes/.
3. Wire these as required checks (ties into main-branch-protection-and-commit-signing).
4. Verify: a planted test secret or misconfig fails CI.

## Related

- relates_to [[flux-gitops]]
- relates_to [[main-branch-protection-and-commit-signing]]
