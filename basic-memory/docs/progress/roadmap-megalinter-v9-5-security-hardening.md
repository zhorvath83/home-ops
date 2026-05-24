---
title: roadmap-megalinter-v9-5-security-hardening
type: progress
permalink: home-ops/docs/progress/roadmap-megalinter-v9-5-security-hardening
tags:
- roadmap
- megalinter
- security
- ci-cd
- completed
---

# Roadmap: MegaLinter v9.5.0 Security Hardening

## Status: completed

## Priority: high

## Area: ci-security

## Created: 2026-05-23

## Completed: 2026-05-23

## Context

MegaLinter v9.5.0 announced supply-chain security hardening (zizmor, osv-scanner) and breaking changes (Docker Hub deprecation, PAT discouragement). Assessment found the repo was already on v9.5.0 (SHA matched the tag) and the action.yml already pulls from ghcr.io internally — no image migration needed. The actionable change was PAT removal and credential hardening.

Phase 2 (zizmor + osv-scanner) and Phase 3 (Checkov) were assessed as low practical value for this home-lab repo and dropped.

## Changes Made (Phase 1)

| Change | File | Detail |
|--------|------|--------|
| PAT removed from checkout | .github/workflows/linter.yaml:32 | secrets.PAT or secrets.GITHUB_TOKEN → secrets.GITHUB_TOKEN |
| PAT removed from create-pull-request | .github/workflows/linter.yaml:66 | secrets.PAT or secrets.GITHUB_TOKEN → secrets.GITHUB_TOKEN |
| persist-credentials: false added | .github/workflows/linter.yaml:33 | Prevents credential leakage to subsequent steps |
| Version comment updated | .github/workflows/linter.yaml:38 | # v9 → # v9.5.0 (SHA was already correct) |

## Assessment Summary

| Item | Finding | Action |
|------|---------|--------|
| Docker Hub to ghcr.io | Already on v9.5.0 SHA; action.yml pulls ghcr.io internally | No change needed |
| PAT removal | secrets.PAT was supply-chain risk | Removed |
| persist-credentials | Was missing, credential leak risk | Added false |
| zizmor (Phase 2) | 3 simple workflows, PAT removed = low blast radius | Dropped |
| osv-scanner (Phase 2) | Renovate already handles version updates; CVE alerts add little | Dropped |
| Checkov (Phase 3) | 90% noise for home-lab; more skip-list work than value | Dropped |

## Trade-off: GITHUB_TOKEN vs PAT

Using GITHUB_TOKEN means auto-fix PRs will not trigger other workflows (e.g., CI on the fix PR itself). This is acceptable — manual re-run or empty commit is preferred over PAT supply-chain risk, per v9.5.0 guidance.

## Relations

- implements [[docs/areas/flux-gitops]] — CI pipeline hardening
- relates_to [[docs/areas/external-secrets]] — credential delivery model

## Observations

- The repo was already running v9.5.0 — Renovate had pinned the latest v9 tag SHA. The only real migration work was PAT removal and credential hardening.
- Phase 2-3 assessment: home-lab repos have different security calculus than enterprise. zizmor adds value when workflows are complex; osv-scanner adds value when you can act on CVEs faster than Renovate; Checkov adds value when compliance matters. None apply here.
