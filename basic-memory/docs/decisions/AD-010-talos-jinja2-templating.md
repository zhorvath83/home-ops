---
title: AD-010-talos-jinja2-templating
type: decision
permalink: home-ops/docs/decisions/ad-010-talos-jinja2-templating
decision_id: AD-010
topic: Talos config built with minijinja2 + op inject, not talhelper
status: active
decided_at: '2025-10-01'
decision: The Talos `machineconfig.yaml.j2` is rendered with minijinja2 templates
  and secret values injected via `op inject`. NOT talhelper.
rationale: All three reference repositories use the jinja2 + op inject pattern; talhelper
  is not used talhelper would add a tool to the stack and is only half-declarative
  — it does not mix cleanly with the `op inject` pattern For a single node a jinja2
  template + per-node patch is overkill, but the pattern is future-proof (scales to
  many nodes too)
tradeoffs: talhelper is sometimes more convenient (fully declarative cluster config)
  — accepted as the cost of stack consistency
related_areas:
- talos-cluster
---

# AD-010 — Talos config built with minijinja2 + op inject, not talhelper

## Metadata (observation-form, schema validation)
- [decision_id] AD-010
- [status] active
- [decided_at] 2025-10-01
- [topic] Talos config built with minijinja2 + op inject, not talhelper

## Decision
The Talos `machineconfig.yaml.j2` is rendered with minijinja2 templates and secret values injected via `op inject`. NOT talhelper.

## Rationale
- All three reference repositories use the jinja2 + op inject pattern; talhelper is not used
- talhelper would add a tool to the stack and is only half-declarative — it does not mix cleanly with the `op inject` pattern
- For a single node a jinja2 template + per-node patch is overkill, but the pattern is future-proof (scales to many nodes too)

## Tradeoffs
- talhelper is sometimes more convenient (fully declarative cluster config) — accepted as the cost of stack consistency

## Related
- relates_to [[talos-cluster]]
