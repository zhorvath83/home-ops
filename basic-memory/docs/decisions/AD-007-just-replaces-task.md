---
title: AD-007-just-replaces-task
type: decision
permalink: home-ops/docs/decisions/ad-007-just-replaces-task
decision_id: AD-007
topic: Just (justfile) replaces Task, with a redesigned command surface
status: active
decided_at: '2025-10-01'
decision: Complete Task → Just migration with no coexistence. The current `.taskfiles/`
  is removed and replaced with `justfile` + `kubernetes/mod.just` + sibling mod files.
rationale: 'All three reference repositories use Just with a `mod` group structure
  Half of the current `an: / es: / fx: / hm: / ku: / pc: / so: / tf: / vs:` task namespaces
  lose their purpose (Ansible K3s tasks disappear) Just script blocks (`#!/usr/bin/env
  bash` shebang) are more structured than Task `cmds:` lists `gum` integration provides
  consistent logger output'
tradeoffs: Full command-surface rebuild (~30+ recipes) New tool in the stack (Just),
  but pinned via `mise`
---

# AD-007 — Just (justfile) replaces Task, with a redesigned command surface

## Metadata (observation-form, schema validation)
- [decision_id] AD-007
- [status] active
- [decided_at] 2025-10-01
- [topic] Just (justfile) replaces Task, with a redesigned command surface

## Decision
Complete Task → Just migration with no coexistence. The current `.taskfiles/` is removed and replaced with `justfile` + `kubernetes/mod.just` + sibling mod files.

## Rationale
- All three reference repositories use Just with a `mod` group structure
- Half of the current `an: / es: / fx: / hm: / ku: / pc: / so: / tf: / vs:` task namespaces lose their purpose (Ansible K3s tasks disappear)
- Just script blocks (`#!/usr/bin/env bash` shebang) are more structured than Task `cmds:` lists
- `gum` integration provides consistent logger output

## Tradeoffs
- Full command-surface rebuild (~30+ recipes)
- New tool in the stack (Just), but pinned via `mise`

## Related
_No AreaReference link — repo-tooling level decision._
