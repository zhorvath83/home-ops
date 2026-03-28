---
name: architecture-review
description: Review high-level design choices in the home-ops repository. Use when Codex needs to evaluate tradeoffs, compare implementation approaches, assess whether a proposed change fits existing repo principles, or recommend a direction before any manifests, Terraform, or task wrappers are edited. Do not use this skill for direct implementation work.
---

# Home Ops Architecture Review

## Overview

Use this skill for design review, not implementation. Focus on fit with repo principles, operational burden, failure modes, and reuse of existing patterns.

## Workflow

1. Read the root guide and the nearest subtree guide for the area being discussed.
2. Rebuild the current local pattern before proposing anything new.
3. Load only the needed reference:
   - `references/evaluation.md`
   - `references/output.md`
4. Present 2-3 viable options when the decision is non-trivial.
5. Recommend one option and explain why.

## Scope Boundaries

- Do not write the implementation as part of this skill.
- Use this skill before editing when the user is asking what should be built, not how to patch the files.
- When the user wants the change carried out, switch to the appropriate domain skill after the design is settled.
