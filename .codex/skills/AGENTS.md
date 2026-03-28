# Codex Skills Guide

This guide applies to everything under `.codex/skills/`.

## Purpose

- Treat this subtree as the repo-local source of truth for home-ops Codex skills.
- Skills here should complement repo `AGENTS.md` files, not replace them.
- Keep path-based guardrails in `AGENTS.md`; keep reusable workflows and decision trees in skills.

## Skill Boundary

- `AGENTS.md` files hold durable repo facts, guardrails, and anti-patterns.
- `SKILL.md` files hold procedural workflows, routing hints, and step ordering.
- `references/` files hold detailed examples, checklists, and domain notes that should load only when needed.
- If a fact belongs to one path and is mostly declarative, keep it in the nearest `AGENTS.md`, not in a skill.

## Role Bundles

- This repo does not assume a static repo-local agent runtime like `.claude/agents/`.
- When an agent-like specialization is useful, express it as:
  - explicit task framing in the user request
  - a focused skill
  - a documented bundle of skills for that role
- Keep the bundle map in `references/role-bundles.md` instead of duplicating role definitions across many skills.

## Structure

- one directory per skill
- required `SKILL.md`
- recommended `agents/openai.yaml`
- optional `references/`, `scripts/`, and `assets/`

## Authoring Rules

- Use the system `skill-creator` workflow when adding or reshaping a skill.
- Keep `SKILL.md` concise and imperative.
- Put detailed procedures, examples, and domain notes in `references/` files rather than in `SKILL.md`.
- Do not create extra documentation files such as `README.md`, `CHANGELOG.md`, or similar sidecar docs.
- Do not duplicate volatile repo facts in multiple skills if the live repo files already provide the authoritative answer.
- When a skill depends on current repo state, tell the reader which repo files to inspect first.

## Three-Tier Targets

- `AGENTS.md`: high-level context, constraints, and durable path-based facts
- `SKILL.md`: workflow shape, routing rules, and decision points
- `references/*.md`: templates, checklists, and detailed implementation notes
- Prefer moving detail out of always-on guides before trimming skill metadata or removing real guardrails.

## Skill Boundaries

- Prefer one skill per domain workflow, not one giant repo skill.
- Split skills when the workflows have different operators, failure modes, or validation paths.
- Keep cross-skill overlap minimal. If two skills touch the same files, make their scopes explicit in the description and body.

## When To Add Or Split

- Add a new skill when the repo has a repeated workflow with 5+ steps, real decision points, or its own task namespace or subtree.
- Split a skill when two workflows touch different operators, credentials, or failure modes even if both live under the same top-level directory.
- Do not add a skill for one-off reminders, short file-format notes, or facts that already belong in the nearest `AGENTS.md`.

## Validation

For skill edits:

1. Ensure `SKILL.md` frontmatter contains only `name` and `description` unless the validator allows more.
2. Regenerate or update `agents/openai.yaml` if the skill name or UI-facing summary changes.
3. Run the validator:

   ```bash
   python3 "${CODEX_HOME:-$HOME/.codex}/skills/.system/skill-creator/scripts/quick_validate.py" .codex/skills/<skill-name>
   ```

4. If the skill is meant to be auto-discovered by Codex, mirror or symlink it into `${CODEX_HOME:-$HOME/.codex}/skills/`.
