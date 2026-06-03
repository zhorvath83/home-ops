---
title: zizmor-gh-actions-security-audit
type: note
permalink: home-ops/docs/progress/zizmor-gh-actions-security-audit
tags:
- security
- zizmor
- github-actions
- ci
- audit
- completed
---

# Zizmor GitHub Actions Security Audit — Remediation Complete

> zizmor v1.25.2 scan identified 7 active findings across 3 workflow files.
> All 7 findings remediated. Rescan confirms 0 active, 20 suppressed.

## Status: completed

## Metadata

- [topic] zizmor GitHub Actions security audit and remediation
- [created_at] 2026-05-25
- [completed_at] 2026-05-25
- [scope] .github/workflows, pre-commit, CI security

## Findings Summary

| # | Finding | Severity | Confidence | File | Auto-fix | Status |
|---|---------|----------|------------|------|----------|--------|
| 1 | template-injection | Info | Low | linter.yaml:72 | Yes | Fixed |
| 2 | template-injection | Info | Low | linter.yaml:73 | Yes | Fixed |
| 3 | artipacked | Medium | Low | scanning-deprecated-kube-resources.yaml:14-17 | Yes | Fixed |
| 4 | excessive-permissions | Medium | Medium | scanning-deprecated-kube-resources.yaml (job) | No | Fixed |
| 5 | superfluous-actions | Info | High | scanning-deprecated-kube-resources.yaml:29 | Yes | Fixed |
| 6 | artipacked | Medium | Low | update-cloudflare-networks.yaml:14-17 | Yes | Fixed |
| 7 | excessive-permissions | Medium | Medium | update-cloudflare-networks.yaml (job) | No | Fixed |

## Remediation Applied

### linter.yaml — template-injection (P3)

Moved `${{ steps.cpr.outputs.* }}` from `run:` block to `env:` block, referenced as `${PR_NUMBER}` / `${PR_URL}` shell variables.

### scanning-deprecated-kube-resources.yaml — artipacked (P2)

Added `persist-credentials: false` to checkout step.

### scanning-deprecated-kube-resources.yaml — excessive-permissions (P1)

Added workflow-level `permissions: { contents: read, issues: write }` block.

### scanning-deprecated-kube-resources.yaml — superfluous-actions (P4)

Replaced `dacbd/create-issue-action` with native `gh issue create`. Moved all `${{ }}` template expressions to `env:` vars. Added `# shellcheck disable=SC2016` for printf format string.

### update-cloudflare-networks.yaml — artipacked (P2)

Added `persist-credentials: false` to checkout step.

### update-cloudflare-networks.yaml — excessive-permissions (P1)

Added workflow-level `permissions: { contents: write, pull-requests: write }` block.

## Decisions

- **FairwindsOps/pluto/github-action kept**: Not flagged by zizmor, Renovate pins SHA, replacement adds maintenance burden.
- **No `.zizmor.yml` config**: 18 suppressed findings handled by default severity thresholds; no config overhead.
- **flux-local.yaml not touched**: Its template-injection was suppressed (GitHub-controlled values); modifying clean workflows violates minimum-change principle. *Superseded 2026-06-03 — see [[flate-migration]]: `.github/workflows/flux-local.yaml` was deleted and replaced by `.github/workflows/flate.yaml` and `.github/workflows/validate-images.yaml`. The replacement workflows need a fresh zizmor scan before they can be considered security-reviewed.*
- **`secrets.PAT` kept for checkout**: Some workflows need PAT for cross-repo or write ops; fallback harmless.
- **`GITHUB_TOKEN` for issue creation**: With explicit `issues: write` permission, PAT fallback unnecessary for `gh issue create`.

## Follow-up (post-migration)

- [ ] Re-run zizmor on `.github/workflows/flate.yaml` and `.github/workflows/validate-images.yaml`. The new workflows use `home-operations/flate/action@<sha>` with a `version:` input (avoids the SHA-to-tag lookup token failure seen in the prior setup) and a `permissions:` block scoped to the job (not step-level, which actionlint rejected on `actions/github-script`). Verify no new findings are introduced.
- [ ] Confirm `pull-requests: write` at the job level on both new workflows is acceptable per zizmor `excessive-permissions`. If not, the alternative is splitting into two jobs (one for test, one for comment).

## Verification

- `zizmor .` — 0 active findings, 20 suppressed (was 7 active, 18 suppressed)
- `pre-commit run` — all hooks pass (yamlfmt, yamllint, actionlint, zizmor, gitleaks)

## References

- zizmor docs: <https://docs.zizmor.sh/>
- artipacked: <https://docs.zizmor.sh/audits/#artipacked>
- excessive-permissions: <https://docs.zizmor.sh/audits/#excessive-permissions>
- template-injection: <https://docs.zizmor.sh/audits/#template-injection>
- superfluous-actions: <https://docs.zizmor.sh/audits/#superfluous-actions>

## Relations

- implements [[progress/pre-commit-linter-ci]]
- relates_to [[zizmor]]
