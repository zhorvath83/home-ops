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

## Execution plan (research-backed)

### Current state
- gitleaks runs only as a **local** pre-commit hook: `.pre-commit-config.yaml:32-36` (`gitleaks protect --staged`, `pass_filenames: false`). Bypassable with `--no-verify`; no server-side enforcement (no gitleaks job in `.github/workflows/`).
- IaC security scanning is absent: only `tflint` (`.pre-commit-config.yaml:69-75`) which checks provider correctness, not security policy. No tfsec/checkov/trivy anywhere.
- Existing workflows: `.github/workflows/{flux-local,label-sync,labeler,scanning-deprecated-kube-resources,update-ai-bots,update-cloudflare-networks}.yaml`. Convention (from the audit): third-party actions SHA-pinned with `# vX` comment, top-level `permissions: contents: read`, `persist-credentials: false`.

### Target state
- Every PR runs a gitleaks scan and an IaC misconfiguration scan server-side; both are required checks on `main`.

### Implementation steps
1. Create `.github/workflows/security-scan.yaml`:
   ```yaml
   ---
   name: security-scan
   on:
     pull_request: {}
     push:
       branches: ["main"]
   permissions:
     contents: read
   jobs:
     gitleaks:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@<PIN_SHA>  # v5  (with-fetch-depth 0 for full history)
           with: { fetch-depth: 0, persist-credentials: false }
         - uses: gitleaks/gitleaks-action@<PIN_SHA>  # v2
     trivy-config:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@<PIN_SHA>  # v5
           with: { persist-credentials: false }
         - uses: aquasecurity/trivy-action@<PIN_SHA>  # v0.x
           with:
             scan-type: config
             scan-ref: .
             severity: HIGH,CRITICAL
             exit-code: "1"
   ```
   Pin each action to a full commit SHA with the version in a trailing comment (repo convention). Look up the latest SHAs via `gh api repos/<owner>/<action>/commits/<tag>`.
2. Scope trivy to `provision/` and `kubernetes/` (it auto-discovers Terraform + K8s manifests). Add a `.trivyignore` for accepted findings if noisy.
3. Add both job names as **required status checks** on `main` (same mechanism as flux-local).
4. Keep the local gitleaks pre-commit hook (defense-in-depth) — this adds the server-side backstop.
5. Commit: `👷 ci(security): add gitleaks + trivy config scanning`.

### Verification
- Open a PR that adds a dummy secret (e.g. a fake AWS key) → gitleaks job fails.
- Add a deliberately public S3 bucket / missing versioning in a scratch `.tf` → trivy-config flags HIGH/CRITICAL and fails.
- `actionlint` + `zizmor` (already in pre-commit) pass on the new workflow.

### Rollback & safety
- Delete the workflow file / remove the required checks. No cluster impact.
- Risk: initial trivy run may surface pre-existing findings (e.g. backup-immutability, cloudflare token) — expected; triage into `.trivyignore` with a comment or fix via the related roadmap items rather than suppressing silently.

### Gotchas & dependencies
- Would have auto-flagged `backup-immutability-object-lock` (s3:*, no versioning) and `cloudflare-api-token-migration`.
- Required-check wiring depends on `main-branch-protection-and-commit-signing`.
- Pin actions to SHA and run zizmor locally before pushing (repo convention).

### Effort
S–M (~2–3h incl. finding SHAs and triaging first-run findings).
