---
title: pushover-provider-model-unify
type: roadmap
permalink: home-ops/docs/roadmap/pushover-provider-model-unify
topic: Pushover provider model unification — per-namespace component vs global app
status: proposed
priority: low
scope: 'Trace and unify the two parallel Pushover delivery surfaces: per-namespace
  flux-alerts Kustomize component (kubernetes/components/flux-alerts/) and standalone
  flux-provider-pushover app (kubernetes/apps/flux-system/flux-provider-pushover/).
  Decide on a single source-of-truth model or document both as intentional with clear
  roles.'
rationale: The cross-tie is an open gap in two area-references (flux-gitops and external-secrets),
  each deferring to the other. Operationally Pushover works, so this is doc+possible
  small refactor, not a fix — but it affects credential rotation, namespace bootstrap,
  and any future alert routing change.
options:
- Per-namespace only — drop the standalone global app, every namespace owns its Provider+Alert
  via the component
- Global Provider only — drop Provider duplication from the component, keep Alert+ExternalSecret
  per namespace pointing to a single global Provider
- Keep both, document the split — pure doc patch to flux-gitops area-reference
related_areas:
- flux-gitops
- external-secrets
---

# Pushover provider model unification — per-namespace component vs global app

## Metadata (observation-form, schema validation)
- [topic] Pushover provider model unification — per-namespace component vs global app
- [status] proposed
- [priority] low

## Scope
Trace and unify the two parallel Pushover delivery surfaces currently coexisting in the cluster:

1. **Per-namespace Kustomize component** — `kubernetes/components/flux-alerts/` — pulled in per namespace (e.g. `kubernetes/apps/external-secrets/kustomization.yaml:10-11`) bundling an Alert + Provider + ExternalSecret triple
2. **Standalone global app** — `kubernetes/apps/flux-system/flux-provider-pushover/` — a single cluster-scoped Pushover Provider deployment in `flux-system`

Open questions:
- Which is the source of truth for the Pushover credential? Both pull from 1Password via their own ExternalSecret path
- Are alerts duplicated (delivered through both) or only one path actually fires per event?
- On namespace creation, is the per-namespace component required, or does the global Provider cover the new namespace automatically through some default routing?
- Which path is reconciled first on credential rotation, and what is the cluster behavior in the gap between rotations?

Possible end-states:
- Drop the standalone global app; rely on per-namespace component only (every namespace owns its Provider + Alert)
- Drop the per-namespace component; rely on a single global Provider + per-namespace Alert resources that target it
- Document both as intentional with clear roles and a routing diagram (no code change)

## Rationale
The cross-tie is an open gap in two area-reference notes: `docs/areas/flux-gitops` ("Pushover provider model split ... deferred to a follow-up or to the external-secrets AreaReference") and `docs/areas/external-secrets` ("The Pushover/flux-alerts cross-tie deserves its own review under the flux-gitops area"). Each note defers to the other, so the question has never landed anywhere.

Operationally Pushover works today, so this is **doc-and-possibly-small-refactor work**, not a fix. But the ambiguity affects credential rotation, namespace bootstrap, and any future change to alert routing — including the orthogonal AlertManager-enable decision tracked in [[alertmanager-enable]].

## Options
1. **Per-namespace only** — drop `kubernetes/apps/flux-system/flux-provider-pushover/`; every namespace declares its own Provider via the component. Minimum-surprise model.
2. **Global Provider only** — drop the Alert+Provider duplication from `kubernetes/components/flux-alerts/`, keep only Alert+ExternalSecret per namespace, point Alerts to the single global Provider. DRY model.
3. **Keep both, document the split** — no code change; the note becomes purely a doc patch to `docs/areas/flux-gitops` explaining which path serves what.

## Related
- relates_to [[flux-gitops]]
- relates_to [[external-secrets]]
- relates_to [[alertmanager-enable]]
