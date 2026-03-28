---
name: sre
description: Debug operational issues in the home-ops repository and cluster. Use when Codex needs to investigate failed reconciliations, unhealthy workloads, routing failures, secret sync issues, backup or restore problems, or other Kubernetes and infrastructure symptoms where evidence and root cause matter more than immediate implementation. Do not use this skill for planned code changes without an active debugging angle.
---

# Home Ops SRE Debugging

## Overview

Use this skill for evidence-first troubleshooting. The goal is to explain what is wrong and why, then outline the safest remediation path.

## Workflow

1. Confirm the symptom, affected area, and whether the user wants diagnosis only or also a fix.
2. Gather evidence from the smallest relevant surfaces first: resource status, events, logs, config, and recent related changes.
3. Load only the needed reference:
   - `references/investigation.md`
   - `references/output.md`
4. Correlate signals across systems before concluding.
5. State the root cause when supported, or give ranked hypotheses with confidence.

## Scope Boundaries

- Do not jump straight to mutation when the task is diagnostic.
- Prefer read-only investigation unless the user explicitly wants an operational action.
- If the issue turns into a design choice, use `architecture-review`.
- If the user wants the fix implemented in repo state, switch to the appropriate domain skill after the diagnosis is clear.
