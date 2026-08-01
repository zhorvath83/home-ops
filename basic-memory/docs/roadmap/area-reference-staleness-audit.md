---
title: area-reference-staleness-audit
type: roadmap
permalink: home-ops/docs/roadmap/area-reference-staleness-audit
topic: Re-verify the docs/areas/* area-references against the live repo, oldest first
status: proposed
priority: medium
scope: Audit all 11 docs/areas/* notes against the current repo state and refresh
  summary, verified_against and verified_at where they have drifted. Start with docs/areas/observability
  (proven wrong) and the five notes last verified 2026-05-22/23. Split out of docs/roadmap/observability-probes-and-disk-health
  on 2026-08-01, where the observability drift was discovered while closing the smartctl-exporter
  work.
rationale: 'The root CLAUDE.md makes the area-reference the mandatory step-4 read
  before touching any subtree, so a stale one does not merely go unread — it actively
  misleads the reader into editing against a world that no longer exists. The failure
  is systemic rather than incidental: every one of the 11 notes carries status current,
  including one that is demonstrably wrong, so status conveys no staleness information
  at all and verified_at is the only real signal.'
options:
- Oldest-first sweep (the five 2026-05-22/23 notes plus observability) — smallest
  useful batch
- Full 11-note re-verification in one pass
- Add a cheap recurring freshness check so drift surfaces before it misleads someone
related_areas:
- observability
- talos-cluster
- resticprofile-backup
---

# Re-verify the docs/areas/* area-references against the live repo

## Metadata (observation-form, schema validation)

- [topic] Re-verify the docs/areas/* area-references against the live repo, oldest first
- [status] proposed
- [priority] medium
- [created] 2026-08-01 — split out of [[observability-probes-and-disk-health]]

## The proven case: docs/areas/observability

- [evidence] Its `summary` still says observability "splits into four workloads": kube-prometheus-stack,
  grafana, speedtest-exporter, victoria-logs. The live
  `kubernetes/apps/observability/kustomization.yaml` lists **eight** sub-Kustomizations — the four
  above plus `blackbox-exporter`, `smartctl-exporter`, `prometheus-adapter` and
  `silence-operator`.
- [evidence] The note does not contain the string `smartctl` at all, although
  `smartctl-exporter` is deployed and live (see [[observability-probes-and-disk-health]]).
- [evidence] `verified_at: '2026-07-11'`, yet `status: current`.

## The systemic finding

- [observation] All 11 area-references report `status: current`, including the observability note
  proven wrong above. So `status` does not degrade and carries no staleness information — only
  `verified_at` does, exactly as the root CLAUDE.md warns ("do not assume the BM area-reference is
  fully current — the `verified_at` field in each note is the staleness signal").
- [observation] Measured `verified_at` spread on 2026-08-01:

| area | verified_at | age |
|---|---|---|
| talos-cluster | 2026-05-22 | ~10 weeks |
| volsync-backup | 2026-05-22 | ~10 weeks |
| resticprofile-backup | 2026-05-22 | ~10 weeks |
| cloudflare | 2026-05-22 | ~10 weeks |
| external-secrets | 2026-05-23 | ~10 weeks |
| ovh-storage | 2026-06-20 | ~6 weeks |
| flux-gitops | 2026-07-05 | ~4 weeks |
| k8s-workloads | 2026-07-05 | ~4 weeks |
| observability | 2026-07-11 | ~3 weeks (proven wrong) |
| iam | 2026-07-26 | fresh |
| networking | 2026-07-28 | fresh |

- [observation] At least one other note has known drift: `talos-cluster` was last verified
  2026-05-22, but [[talos-config-refactor]] landed 2026-07-29. `resticprofile-backup` (2026-05-22)
  covers the NAS `/backups` plane that the Phase 10 OMV cutover will change.

## Scope of the work

- Re-read each area's actual files and reconcile `summary`, `verified_against` and the body
  observations against them; bump `verified_at`; downgrade `status` where a note cannot be
  fully re-verified rather than leaving a false `current`.
- Suggested order: `observability` first (proven wrong), then the five 2026-05-22/23 notes,
  then the 2026-07-05 pair. `iam` and `networking` are fresh and can be spot-checked only.
- [question] Should a cheap recurring freshness signal exist (e.g. a report of notes whose
  `verified_at` is older than N weeks) so drift surfaces before someone edits against it, rather
  than being found by accident as it was here? Decide as part of this item.

## Related

- relates_to [[observability]]
- relates_to [[talos-cluster]]
- relates_to [[resticprofile-backup]]
- continues [[observability-probes-and-disk-health]]
