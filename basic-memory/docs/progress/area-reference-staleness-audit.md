---
title: area-reference-staleness-audit
type: progress_note
permalink: home-ops/docs/progress/area-reference-staleness-audit
area: docs
status: done
confidence: high
summary: All 11 docs/areas/* area-references were re-verified against the live repo
  and corrected on 2026-08-03. Seven arrived MAJOR-DRIFT, four MINOR-DRIFT. The headline
  finding is that verified_at measures effort rather than correctness — the observability
  note, re-verified two days earlier, still carried the exact defect that created
  this roadmap item. The human decided against building any recurring freshness mechanism.
---

# area-reference-staleness-audit — delivered

All 11 `docs/areas/*` area-references re-verified against the live repo and corrected.
This note absorbs the former `docs/roadmap/area-reference-staleness-audit` item, deleted on closure.

## Metadata (observation-form, schema validation)

- [topic] Re-verify every docs/areas/* area-reference against the live repo and correct the drift
- [status] done
- [priority] medium
- [created] 2026-08-01 — split out of [[observability-probes-and-disk-health]]
- [closed] 2026-08-03
- [roadmap] merged into this note — docs/roadmap/area-reference-staleness-audit deleted on closure

## Execution model

- [decision] Scope: **all 11 notes deep** (human choice over a prioritised subset). Justified in
  hindsight: even the freshest notes carried real drift.
- [decision] **No recurring freshness mechanism will be built** (human decision, 2026-08-03). The
  roadmap open question — "should a cheap recurring report list notes whose verified_at is older
  than N weeks?" — is answered NO. The audit produced a stronger reason than convenience:
  `verified_at` does not measure what such a report would assume it measures (finding 1).
- [decision] Maestro/worker split: each area's read-only drift report was delegated to the local
  Ollama-hosted agent (glm-5.2:cloud) under a fixed written protocol; every report was reviewed and
  its load-bearing claims re-verified independently by the Maestro before any note was edited. All
  Basic Memory writes stayed with the Maestro — the `basic-memory-access` safety protocol
  (read-back verification, the `edit_note` silent-no-op trap) is not delegable to a weaker model.
- [decision] Delivery: direct commits to `main`, one commit per area note (repo norm; docs-only,
  zero cluster impact).

## Results

| area | previous verified_at | verdict on arrival |
|---|---|---|
| talos-cluster | 2026-05-22 | MAJOR-DRIFT (12 wrong) |
| volsync-backup | 2026-05-22 | MAJOR-DRIFT (5 wrong) |
| resticprofile-backup | 2026-05-22 | MAJOR-DRIFT (5 wrong, all 9 paths dead) |
| cloudflare | 2026-05-22 | MAJOR-DRIFT (1 wrong, 2 obsolete) |
| external-secrets | 2026-05-23 | MINOR-DRIFT (1 wrong) |
| ovh-storage | 2026-06-20 | MINOR-DRIFT (0 wrong) |
| flux-gitops | 2026-07-05 | MAJOR-DRIFT (1 wrong, 6 uncovered) |
| k8s-workloads | 2026-07-05 | MAJOR-DRIFT (4 wrong — the inventory itself) |
| iam | 2026-07-26 | MINOR-DRIFT (2 wrong) |
| networking | 2026-07-28 | MINOR-DRIFT (4 wrong — in the security model) |
| observability | 2026-08-01 | MAJOR-DRIFT (8 wrong) |

Every note now reads `verified_at: 2026-08-03` and carries an `## Update 2026-08-03` section
recording exactly what was wrong, so the corrections are auditable rather than silently applied.

## The systemic findings (these matter more than the individual fixes)

### 1. `verified_at` measures effort, not correctness — the roadmap premise was wrong

- [finding] The roadmap item concluded that `status` carries no staleness information and
  "`verified_at` does". The audit refutes the second half. `observability` was re-verified on
  2026-08-01 — two days before this audit — and arrived at MAJOR-DRIFT with 8 wrong claims,
  **including the exact defect that created this roadmap item**: its frontmatter `summary` still
  said the namespace "splits into four workloads" while the kustomization lists eight. Its
  `verified_against` still pointed at two files deleted in the 2026-07-10 grafana-operator migration.
- [observation] That pass bumped the date and appended narrative without reconciling the frontmatter
  or the Claims section. A fresh `verified_at` therefore proves only that someone touched the note,
  not that the note is right. This is precisely why a "notes older than N weeks" report would have
  been the wrong instrument: it would have rated `observability` the healthiest note in the set on
  the very day it was the worst.

### 2. Append-only updates leave two contradictory answers inside one note

- [finding] The dominant failure mode is not "nobody updated the note" but "someone appended a dated
  Update section and left the Components/Claims sections asserting the old fact". `networking` had
  three such contradictions (the `envoy` BTP, the `security-response-headers` EEP and
  `SecurityPolicy/envoy-internal-rfc1918` all gained features only the Update sections knew about).
  `external-secrets` contradicted itself about pushover. `observability` contradicted itself about
  grafana.
- [consequence] A reader who stops at Components gets the stale answer; a reader who reads to the end
  gets the current one. Dated-Update-only maintenance produced most of the drift this audit fixed.

### 3. Stale docs mis-state security posture in BOTH directions

- [finding] Drift is not uniformly "the note is behind on features". Several corrections were
  security-relevant, cutting both ways:
  - **Overstated protection**: `volsync-backup` and `resticprofile-backup` both credited Cloudflare
    Access as the containment for a full-read-write backup surface (Kopia UI, Backrest). Both are
    `envoy-internal` only now — that control is not in the path, so residual risk was described as
    mitigated when it is not. Backrest's `/backups` NFS mount also turned out to be read-WRITE, not
    read-only as documented, so it can modify the backup SOURCE tree.
  - **Understated protection**: `cloudflare` still recorded a service-token policy on the wildcard
    `Private Cloud` Access app and a 720h session. Both were hardened away (token scoped to two
    hosts, session 24h), and a non-Hungary country-block WAF rule had been added that the note never
    mentioned.
  - **Actively misleading**: `networking` documented the retired `ingress.home.arpa/gateways` label
    after the CCNP split into per-gateway labels — following the note would produce a pod with no
    policy at all. `iam` said the rate limit was "600 req/min, effectively global"; it is 3000/min
    per client, the opposite property. `observability` claimed Grafana was exposed on both gateways
    when it is deliberately LAN-only.

### 4. Refactors, not features, are what break these notes

- [observation] The two largest drifts each trace to one unpropagated refactor: the Talos
  machineconfig refactor (substitution variables became hardcoded literals — the note described
  `${LAN_SUBNET}`/`${POD_CIDR}`/`${SVC_CIDR}`/`${CONTROLPLANE_IP}` that do not exist), and the
  `kubernetes/apps/default/` -> `apps/selfhosted/` move (all 9 `verified_against` paths dead, 37
  stale path references inside one note).
- [observation] `${TIMEZONE}` was documented as a cluster-settings substitution variable in TWO notes
  (`flux-gitops`, `networking`). It has never existed since k8tz took over timezone — the same wrong
  fact had been copied.

## Repo-side defects found and deliberately NOT fixed here

Out of scope for a documentation audit (`working-principles` 3 — clean up only your own mess).

- [followup] `.claude/skills/volsync/references/app-integration.md:20` documents a `VOLSYNC_SCHEDULE`
  substitution variable that does not exist anywhere in the repo. Anyone following that doc sets a
  variable with no effect; the ReplicationSource trigger is a hardcoded `"0 * * * *"`.
- [followup] `provision/cloudflare/CLAUDE.md` still lists `r2_bucket.tf`; the file and the whole R2
  stack were deleted.
- [followup] `kubernetes/apps/media/suggestarr/` is a fully shaped app directory (wires volsync and
  gateway-oidc, and a `suggestarr` Pocket ID client exists in Terraform) that is commented out of
  `kubernetes/apps/media/kustomization.yaml:15`. Intentional park or stalled rollout cannot be
  derived from the manifests — needs a human decision.
- [followup] The KopiaMaintenance CR is still named `kopia-daily-maintenance` but runs 4x/day
  (`30 */6 * * *`). Cosmetic, but the name actively misleads.
- [followup] `home-gallery` holds a standalone PVC with no VolSync wiring and no recorded
  "intentionally no backup" decision — the only one of the four unwired apps without an obvious reason.
- [followup] `crowdsec-web-ui` is a native OIDC client carrying no `egress.home.arpa` labels, so
  whether its token-exchange hairpin survives its own CNP posture is unknown without cluster
  observation.
- [followup] `arfolyam` proxied A/AAAA placeholder DNS records in `provision/cloudflare` are dangling
  — no Worker and no Access app back them, and the explanatory comment is stale.

## Verification

- [criterion] Every one of the 11 notes re-read against its live subtree — MET.
- [criterion] Every `verified_against` path list checked for dead entries and completed — MET (dead
  entries found in resticprofile-backup, flux-gitops, cloudflare, observability).
- [criterion] Each note's corrections recorded in a dated Update section rather than applied silently
  — MET.
- [criterion] Every Basic Memory edit verified by read-back before moving on — MET. One `edit_note`
  no-op was caught this way (an `ovh-storage` citation fix whose `find_text` did not match).
- [criterion] No note left with a `verified_at` newer than its actual content — MET.
- [gap] Live cluster state was deliberately excluded from the whole audit (repo-only reconciliation).
  Every note keeps its own "no live verification in this pass" gap.

## Relations

- continues [[observability-probes-and-disk-health]]
- relates_to [[observability]]
- relates_to [[talos-cluster]]
- relates_to [[networking]]
- relates_to [[resticprofile-backup]]
- relates_to [[volsync-backup]]
