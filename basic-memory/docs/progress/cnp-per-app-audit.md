---
title: cnp-per-app-audit
type: progress
permalink: home-ops/docs/progress/cnp-per-app-audit
topic: CNP per-app audit rollout — execution progress for the V1-V5 hybrid CNP rollout
  runbook
status: in_progress
priority: medium
related_areas:
- networking
- k8s-workloads
decision_link: AD-023-cnp-threat-model-audit
roadmap_link: docs/roadmap/cnp-per-app-audit
tags:
- progress
- cnp
- cilium
- networking
- security
---

# CNP per-app audit — rollout progress

Execution log for the V1–V5 hybrid CNP rollout. The full runbook (YAML, per-app assignment, edit/verify/accept steps per phase) lives in [[cnp-per-app-audit]] (docs/roadmap). This note tracks only execution state — phase status, session summaries, and the Next pointer. Decision basis: [[AD-023-cnp-threat-model-audit]].

## Phase tracker

| Phase | State | Notes |
|---|---|---|
| V1 commit 1 — 4 vocabulary CCNPs + kustomization entries (enableDefaultDeny: false staging) | pending | zero behavior change expected |
| V1 commit 2 — V1 labels on pods (incl. kopia/mover labels — see pre-rollout resolution) | pending | per-app mechanics; verify emission per HR before merge |
| V1 commit 3 — activation: remove enableDefaultDeny + trim/delete per-app CNPs | pending | the commit that closes ingress |
| V2 — survey (results recorded into the roadmap note) | pending | residual: ovh_s3_endpoint public-IP confirmation |
| V3 — flip (ONE commit: drop world from baseline + every V3 grant + coredns CNP + isponsorblocktv LAN CNP) | pending | single revert = rollback |
| V4 — permanent Hubble policy-verdict DROPPED alert + 7-day soak | pending | |
| V5 — remainder (downloads east-west, narrow-world tightening, LB fromCIDR) | pending | |

## Pre-rollout resolutions (before V1 commit 1)

- [observation] [resolved 2026-07-04] VolSync S3 world access — CRD-verified against live v0.17.11 perfectra1n fork: ReplicationSource.spec.kopia.moverPodLabels, ReplicationDestination.spec.kopia.moverPodLabels, AND KopiaMaintenance.spec.moverPodLabels all exist. Four repo edits land in V1 commit 2 (pure allows): (1) components/volsync/replicationsource.yaml spec.kopia.moverPodLabels: {egress.home.arpa/allow-world: "true"} — covers ~21 apps; (2) components/volsync/replicationdestination.yaml same field; (3) volsync-system/volsync/maintenance/kopiamaintenance.yaml spec.moverPodLabels (top-level); (4) volsync-system/kopia/app/helmrelease.yaml defaultPodOptions.labels: allow-world + ingress.home.arpa/gateways (kopiaui Deployment, pvbackup route). volsync controller itself: nothing (in-cluster). Recorded in roadmap note Open Questions as resolved; residual V2 item: confirm ovh_s3_endpoint is a public IP.

## Branch / PR

- [observation] Feature branch `cnp-per-app-audit` created from main; the full V1–V5 rollout commits here. PR opened before V3 flip for review of the flip commit specifically.

## Session summaries

### Session 1 — 2026-07-04

- Reviewed roadmap note [[cnp-per-app-audit]] and decision [[AD-023-cnp-threat-model-audit]] against live repo/cluster state: rollout not yet started, baseline still fail-open (`toEntities: [world]` in allow-cluster-egress.yaml), 4 vocabulary CCNPs absent, per-app CNPs for migrate-convention apps still present.
- Resolved the VolSync mover-pod open question via live CRD inspection (moverPodLabels supported on all three CRDs) — see Pre-rollout resolutions above. Updated roadmap note: Open Question → resolved; kopia per-app line refined into three roles; V3 step (b) kopia reference removed (labels moved to V1 commit 2).
- Created feature branch `cnp-per-app-audit`.
- Set roadmap note status: proposed → in_progress.
- Created this progress note and cross-referenced it from the roadmap note Metadata section.

Next: Phase V1 commit 1 — add the 4 new CCNP files (allow-world-egress, ingress-from-gateways, ingress-from-prometheus, ingress-none; the 3 ingress ones with enableDefaultDeny.ingress: false staging) + netpols/kustomization.yaml entries. Validate with pre-commit + flux-local build. Push, reconcile, verify `kubectl get ccnp` shows 4 new Valid policies and zero behavior change.

## Related

- implements [[cnp-per-app-audit]]
- decided_in [[AD-023-cnp-threat-model-audit]]
- relates_to [[networking]]
- relates_to [[k8s-workloads]]
