---
title: Decision
type: schema
permalink: home-ops/schema/decision
entity: Decision
version: 1
schema:
  decision_id: string, AD-NNN canonical identifier
  topic: string, short descriptive title of what is being decided
  status(enum): '[active, superseded, deprecated], lifecycle state of this decision'
  decided_at: string, ISO date YYYY-MM-DD when the decision was made or recorded
  decision: string, the actual choice made (single concise sentence)
  rationale: string, key reasons supporting the choice (multi-line summary)
  tradeoffs?: string, what is given up or accepted in exchange
  superseded_at?: string, ISO date YYYY-MM-DD when this decision was superseded
  superseded_by?: Decision, the decision that replaced this one
  supersedes?: Decision, the prior decision this one replaces
  related_areas?(array): string, AreaReference areas this decision touches (forward-references
    allowed)
  verified_against?(array): string, repo paths or commands demonstrating the live
    state matches the decision (active only)
settings:
  validation: warn
---

# Decision

Schema for architectural decision records (ADRs) in home-ops.

## Observations
- [convention] One Decision note per ADR, lives in `docs/decisions/AD-NNN-{slug}.md`
- [convention] Title format is `AD-NNN-{slug}` (id + lowercased slug from the topic) so filename, permalink, and identifier align
- [convention] `decision_id` in frontmatter holds the canonical `AD-NNN` form (the slug-free identifier)
- [convention] Both frontmatter values AND observation-form duplicates required for: `[decision_id]`, `[status]`, `[decided_at]`, `[topic]` (frontmatter for metadata search, observations for schema validation)
- [convention] Body sections follow the source pattern: Decision (one sentence), Rationale (bullets), Tradeoffs (bullets), Related (relations)
- [convention] `related_areas` lists AreaReference identifiers this decision touches — forward-references are allowed (BM links them when the target note exists)
- [convention] When a decision is superseded, set status=superseded, fill superseded_at, and add a relation `superseded_by [[AD-NNN-...]]` if a successor ADR exists; if the new state is documented in prose without a successor ADR, note this in the body under "Superseded by" with a reference
- [convention] Validation set to `warn` initially — escalate to `error` only when the decision corpus is stable
- [principle] ADRs are write-once-then-supersede; never edit the decision text after status leaves active — write a new ADR or annotate via supersession
