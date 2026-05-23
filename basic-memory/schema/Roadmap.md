---
title: Roadmap
type: schema
permalink: home-ops/schema/roadmap
entity: Roadmap
version: 1
schema:
  topic: string, short descriptive title
  status(enum): '[proposed, accepted, in-progress, done, dropped], lifecycle state'
  priority?(enum): '[low, medium, high], coarse priority hint'
  scope: string, what this covers in 1-3 sentences
  rationale?: string, why this is on the roadmap
  options?(array): string, distinct approaches under consideration when a choice is
    open
  related_areas?(array): string, AreaReference areas this touches
  decision_link?: Decision, the ADR that closes this roadmap item once decided
  blocked_by?: Roadmap, prior roadmap item this depends on
settings:
  validation: warn
---

# Roadmap

Schema for planned/proposed work items in home-ops.

## Observations

- [convention] One Roadmap note per item, lives in `docs/roadmap/{slug}.md`
- [convention] Lifecycle: `proposed` (surfaced, not committed) → `accepted` (decided to do) → `in-progress` → `done` OR `dropped`
- [convention] When a roadmap item closes with an architectural choice, link the resulting ADR via `decision_link`; the roadmap item moves to `done` (or stays `in-progress` while the ADR is being implemented)
- [convention] Operational caveats and drift risks do NOT belong here — they live as `[gap]` or `[drift]` observations in AreaReference notes
- [convention] Validation set to `warn` initially
- [principle] Roadmap items can be `dropped` without shame — explicit dropping (with rationale in scope/rationale fields) is preferable to silent disappearance
