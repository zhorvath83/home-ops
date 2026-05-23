---
title: AreaReference
type: schema
permalink: home-ops/schema/area-reference
entity: AreaReference
version: 1
schema:
  area(enum): '[networking, flux-gitops, k8s-workloads, external-secrets, volsync-backup,
    resticprofile-backup, cloudflare, ovh-storage, talos-cluster, observability],
    home-ops area identifier'
  status(enum): '[current, superseded, draft], lifecycle state of this note'
  confidence(enum): '[high, medium, low], evidence-backed reliability of the content'
  verified_at: string, ISO date YYYY-MM-DD of last full validation
  summary: string, 2-4 sentence high-level description of this area
  verified_against?(array): string, repo paths or read-only commands used as primary
    evidence
  drift_risk?: string, known fragility or stale-prone aspects to re-check periodically
  supersedes?: AreaReference, predecessor note this replaces
  superseded_by?: AreaReference, successor note that replaced this one
settings:
  validation: warn
---

# AreaReference

Schema for current-state reference notes per home-ops area.

## Observations

- [convention] One AreaReference note per area, lives in `docs/areas/{area-name}`
- [convention] Both frontmatter values AND observation-form duplicates required: `[area]`, `[status]`, `[confidence]`, `[verified_at]` (frontmatter for metadata search, observations for schema validation)
- [convention] `verified_against` lists exact file paths or read-only commands — never vague references
- [convention] Each substantive claim in the body uses `[claim]` category with evidence type (repo, cluster, behavior, intent), evidence reference, and verification date
- [convention] Component inventory uses `[component]` category, drift notes use `[drift]`, gaps use `[gap]`
- [convention] Validation set to `warn` initially — escalate to `error` only when the area corpus is fully migrated and stable
- [principle] Area enum is closed — new areas require schema version bump (additive, no breaking change)
