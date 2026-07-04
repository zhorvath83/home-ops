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
| V1 commit 1 — 4 vocabulary CCNPs + kustomization entries (enableDefaultDeny: false staging) | done — reconciled + verified | kubectl get ccnp: 6/6 Valid (4 new); cilium-netpols KS Ready=True @297a0ec27 |
| V1 commit 2 — V1 labels on pods (incl. kopia/mover labels — see pre-rollout resolution) | pending | per-app mechanics; verify emission per HR before merge |
| V1 commit 3 — activation: remove enableDefaultDeny + trim/delete per-app CNPs | pending | the commit that closes ingress |
| V2 — survey (results recorded into the roadmap note) | pending | residual: ovh_s3_endpoint public-IP confirmation |
| V3 — flip (ONE commit: drop world from baseline + every V3 grant + coredns CNP + isponsorblocktv LAN CNP) | pending | single revert = rollback |
| V4 — permanent Hubble policy-verdict DROPPED alert + 7-day soak | pending | |
| V5 — remainder (downloads east-west, narrow-world tightening, LB fromCIDR) | pending | |

## Pre-rollout resolutions (before V1 commit 1)

- [observation] [resolved 2026-07-04] VolSync S3 world access — CRD-verified against live v0.17.11 perfectra1n fork: ReplicationSource.spec.kopia.moverPodLabels, ReplicationDestination.spec.kopia.moverPodLabels, AND KopiaMaintenance.spec.moverPodLabels all exist. Four repo edits land in V1 commit 2 (pure allows): (1) components/volsync/replicationsource.yaml spec.kopia.moverPodLabels: {egress.home.arpa/allow-world: "true"} — covers ~21 apps; (2) components/volsync/replicationdestination.yaml same field; (3) volsync-system/volsync/maintenance/kopiamaintenance.yaml spec.moverPodLabels (top-level); (4) volsync-system/kopia/app/helmrelease.yaml defaultPodOptions.labels: allow-world + ingress.home.arpa/gateways (kopiaui Deployment, pvbackup route). volsync controller itself: nothing (in-cluster). Recorded in roadmap note Open Questions as resolved; residual V2 item: confirm ovh_s3_endpoint is a public IP.

## Workflow strategy

- [observation] [decided 2026-07-05] Working directly on `main` (no feature branch). Each commit pushes to origin/main, Flux reconciles, read-only `kubectl` verifies. Abandoned the earlier feature-branch+PR plan — simpler GitOps, each phase reconciled+verified before the next. The flip (V3) still lands as one commit so rollback = single revert.

## Session summaries

### Session 1 — 2026-07-04

- Reviewed roadmap note [[cnp-per-app-audit]] and decision [[AD-023-cnp-threat-model-audit]] against live repo/cluster state: rollout not yet started, baseline still fail-open (`toEntities: [world]` in allow-cluster-egress.yaml), 4 vocabulary CCNPs absent, per-app CNPs for migrate-convention apps still present.
- Resolved the VolSync mover-pod open question via live CRD inspection (moverPodLabels supported on all three CRDs) — see Pre-rollout resolutions above. Updated roadmap note: Open Question → resolved; kopia per-app line refined into three roles; V3 step (b) kopia reference removed (labels moved to V1 commit 2).
- Created feature branch `cnp-per-app-audit`.
- Set roadmap note status: proposed → in_progress.
- Created this progress note and cross-referenced it from the roadmap note Metadata section.

Next: Phase V1 commit 1 — add the 4 new CCNP files (allow-world-egress, ingress-from-gateways, ingress-from-prometheus, ingress-none; the 3 ingress ones with enableDefaultDeny.ingress: false staging) + netpols/kustomization.yaml entries. Validate with pre-commit + flux-local build. Push, reconcile, verify `kubectl get ccnp` shows 4 new Valid policies and zero behavior change.

### Session 2 — 2026-07-05

- Implemented Phase V1 commit 1: created the 4 vocabulary CCNP files under kubernetes/apps/kube-system/cilium/netpols/ (allow-world-egress with the flux-system/cert-manager infra-namespace grant spec; ingress-from-gateways; ingress-from-prometheus; ingress-none). The 3 ingress CCNPs carry enableDefaultDeny.ingress: false (V1 staging). allow-world-egress is label-gated (inert until pods carry egress.home.arpa/allow-world).
- Convention decisions: used k8s:io.kubernetes.pod.namespace (Cilium k8s: prefix) consistently in fromEndpoints selectors, matching the repo's existing CNP convention (pocket-id, external-secrets, onepassword-connect) rather than the runbook's prefix-less form. Verified live envoy proxy pods carry app.kubernetes.io/name=envoy + gateway.envoyproxy.io/owning-gateway-name in {envoy-external, envoy-internal}, and prometheus pod carries app.kubernetes.io/name=prometheus in observability — selectors match reality.
- Validation: pre-commit run on the 5 touched files — all green (yamlfmt, yamllint, gitleaks, k8s-secrets check). flux-local build of the cilium-netpols KS via `just k8s render-local-ks` — exit 0, render contains all 6 CCNPs (2 existing + 4 new). flux-local emitted non-fatal warnings (deprecation notice; postBuild cluster-settings substitute reference unresolvable — known flux-local limitation that does not affect static YAML CCNPs; dependsOn name format quirk) — none block.
- Committed as dd93c4255 on branch cnp-per-app-audit. mise.lock was touched by the flux-local pipx install side effect — restored it and staged only the 5 V1 commit 1 files (explicit pathspecs per repo rule).

- Pushed main to origin (e8e7b24a2..297a0ec27); Flux reconciled cilium-netpols KS — Ready=True @297a0ec27. `kubectl get ccnp`: 6/6 Valid (allow-cluster-egress, allow-dns-egress + 4 new allow-world-egress, ingress-from-gateways, ingress-from-prometheus, ingress-none). Zero behavior change confirmed by inert design (allow-world-egress label-gated; 3 ingress CCNPs carry enableDefaultDeny.ingress: false).

## V1 commit 2 — resume checklist (next session)

Edit set, grouped by mechanic. CNP deletes/trims are V1 commit 3, NOT here — commit 2 is labels only (zero behavior change: ingress CCNPs still staged with enableDefaultDeny false; allow-world additive with the pre-flip baseline that still carries toEntities: world).

1. selfhosted gateways label (bjw-s app-template): actual, home-gallery, pingvin-share-x, paperless (main pod ONLY via controllers.paperless.pod.labels — backup CronJob stays label-free), homepage, mealie, wallos, paperless-gpt, backrest, calibre-web-automated. Add ingress.home.arpa/gateways: "true" via defaultPodOptions.labels (or controllers.<name>.pod.labels for paperless main). actual/home-gallery/pingvin-share-x already carry custom-egress — add gateways alongside.
2. security: tinyauth (gateways + prometheus if ServiceMonitor exists; check), pocket-id (gateways).
3. observability: grafana (gateways + prometheus), speedtest-exporter (prometheus only). victoria-logs server: NO V1 labels (V5). kube-prometheus-stack: nothing (Class P).
4. networking: echo (gateways).
5. external-secrets: onepassword-connect (prometheus label via defaultPodOptions.labels), external-secrets x3 (per-component podLabels prometheus: controller / webhook / certController).
6. kopia/mover (4 files from Session 1 resolution): components/volsync/replicationsource.yaml spec.kopia.moverPodLabels; components/volsync/replicationdestination.yaml same; volsync-system/volsync/maintenance/kopiamaintenance.yaml spec.moverPodLabels (top-level); volsync-system/kopia/app/helmrelease.yaml defaultPodOptions.labels (allow-world + ingress.home.arpa/gateways).
7. Verify label emission per edited HR: flux-local/helm template, grep the rendered pod template for the label BEFORE push.
8. pre-commit + commit (labels only) + push + Flux reconcile + Hubble FORWARDED on the new labels + update this progress note.

Next: Phase V1 commit 2 — start from the resume checklist above. Per-chart mechanics per the runbook reference (How to set pod labels). Verify label emission per HR via flux-local/helm template before push. Push, Flux reconcile, Hubble FORWARDED check on the new labels.

## Related

- implements [[cnp-per-app-audit]]
- decided_in [[AD-023-cnp-threat-model-audit]]
- relates_to [[networking]]
- relates_to [[k8s-workloads]]
