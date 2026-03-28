---
name: security-review
description: Review security posture and hardening changes in the home-ops repository. Use when Codex needs to assess real exploitability, blast radius, exposure surface, detection gaps, or hardening regressions across Kubernetes, Flux, secrets, networking, Cloudflare, or task-backed workflows. Do not use this skill for open-ended destructive testing or for ordinary implementation work with no explicit security angle.
---

# Home Ops Security Review

## Overview

Use this skill for security-focused review and hardening analysis. Focus on realistic risk, containment, and observability of misuse rather than theoretical findings.

## Workflow

1. Confirm whether the task is a design-time review, a change review, or an operational investigation with a security angle.
2. Rebuild the relevant local pattern before judging the risk.
3. Load only the needed reference:
   - `references/scope-and-safety.md`
   - `references/checklists.md`
   - `references/output.md`
4. Evaluate exploitability, blast radius, and detection gaps together.
5. Prefer concrete remediation over generic best-practice advice.

## Scope Boundaries

- Use this skill for hardening review, exposure review, and security-sensitive change analysis.
- Do not use it as permission for destructive testing, credential exfiltration, denial-of-service, or ad-hoc live mutation.
- If the issue is primarily a design tradeoff, combine with `architecture-review`.
- If the issue is primarily an operational failure, combine with `sre`.
- If the user wants the fix implemented, switch to the relevant domain skill after the review is clear.
