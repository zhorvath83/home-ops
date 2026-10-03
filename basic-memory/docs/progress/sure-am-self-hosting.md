---
title: sure-am-self-hosting
type: progress_note
permalink: home-ops/docs/progress/sure-am-self-hosting
tags:
- sure
- cnpg
- postgres
- dragonfly
- progress
---

# sure-am-self-hosting — execution progress

## Metadata (observation-form)

- [topic] Sure.am self-hosting — execution of [[home-ops/docs/roadmap/sure-am-self-hosting]]
- [status] IN_PROGRESS — branch feat/sure-self-hosting, session 1
- [branch] feat/sure-self-hosting
- [area] k8s-workloads, database (new), external-secrets, iam, networking
- [created] 2026-10-03

## Scope (plan approved by owner, 2026-10-03)

Full roadmap item on one branch (Phases 0-7), one PR: database namespace group, CNPG operator
+ shared postgres cluster, Dragonfly operator + shared instance, paperless valkey decommission,
reusable components/cnpg/database, sure app with native Pocket ID OIDC, verification + restore drill.

## Decisions made during execution (superseding the roadmap plan)

- [decision] Postgres backup is **NAS-only pg_dump** (owner, 2026-10-03): daily pg_dumpall cronjob
  to the NAS /backups NFS export; the existing resticprofile plane carries it offsite. Supersedes
  the ratified "barmanObjectStore to OVH S3" option: no new OVH bucket/user, no cnpg-backup 1P item,
  no SSE question. Tradeoff accepted: **no PITR** — worst case 1 day data loss, manual dump restore.
- [decision] Dump auth via CNPG enableSuperuserAccess + operator-generated <cluster>-superuser Secret
  (no 1Password item needed for the backup path).
- [correction] CNPG operator chart is 0.29.x (operator 1.30.x); Database/DatabaseRole CRD is
  postgresql.cnpg.io/v1; barman client-side AES-256 does not exist (SSE-S3 only) — moot under NAS-only.
- [correction] Dragonfly: dragonflydb project, authentication via spec.authentication.passwordFromSecret;
  dbnum stays default (16) so SELECT 1/2 work — do not set --dbnum.
- [correction] Sure: no APP_DOMAIN env; db:prepare runs on boot (no initContainer); OIDC provider
  is db-sourced (AUTH_PROVIDERS_SOURCE=db), registered in admin UI; AUTH_LOCAL_LOGIN_ENABLED flips
  to false only after SSO is proven (separate commit).
- [correction] dragonfly-operator IS published as an OCI chart:
  oci://ghcr.io/dragonflydb/dragonfly-operator/helm/dragonfly-operator (v1.7.0) — the earlier
  "no published chart" finding was wrong (registry path probe stopped one segment short).
- [decision] Dragonfly persistence = cache-only, no snapshot/tiering PVC (owner, 2026-10-03):
  a restart drops in-flight sidekiq/cache state; add spec.snapshot.persistentVolumeClaimSpec
  later if job loss becomes a problem.

## Session 1 — 2026-10-03
- Plan mode: full repo + BM area research (3 explorers), Plan-agent design pass, owner decisions
  on branch scope (full item), 1P ownership (AI via op CLI), apply/deploy depth (AI with approval
  gates), and backup destination (NAS-only pg_dump).
- Branch feat/sure-self-hosting created from main.
- Pre-flight research complete: chart tags (CNPG 0.29.1, dragonfly-operator v1.7.0), image digests
  (PG18 18-standard-trixie, dragonfly v2.0.0, sure 0.7.5-hotfix.1), CRD fields (no storageSize on
  Dragonfly, no podTemplate on Cluster — inheritedMetadata.labels instead, enablePodMonitor
  deprecated -> manual PodMonitor), sure env contract (DB_HOST/DB_PORT/POSTGRES_*), renovate
  customManagers regex manager for CNPG imageName + Dragonfly CR image.
- Commits 1-3 landed: f3b091c3d (database ns group), ee953928f (cloudnative-pg operator),
  b967c6022 (postgres cluster + PodMonitor + CNP + renovate customManager).
- Phases 2-6 manifests complete in the working tree: postgres NAS dump cronjob (staged, commit 4
  blocked on signing), dragonfly-operator, dragonfly instance (cache-only), paperless valkey
  decommission (4 files), components/cnpg/database (Database + DatabaseRole + first basic-auth
  ES), sure app (ks + HR + ES + CNP, internal-only fin.${PUBLIC_DOMAIN} route, cnpg+volsync
  components), clients.yaml (sure_admins group + sure native OIDC client, provisional callback).
- Validation green: just pocket-id lint OK; pre-commit hooks OK (mise-lock fails on pre-existing
  tool-version drift in the working tree — owner's in-progress work; mise.lock reverted, not
  committed); flux-local test 145/145 passed after fixing sure readiness probe httpGet port.
- BLOCKER: git commit signing via op-ssh-sign fails ("1Password: failed to fill whole buffer") —
  the 1Password desktop app is not running/unlocked. Commits 4-10, Phase 0 (op item create sure +
  dragonfly) and just pocket-id apply are all blocked on it.
- Follow-ups recorded: Healthchecks.io ping for the dump job (dropped for now), CNPG Grafana
  dashboard (dropped — chart ships a plain ConfigMap, the repo uses the GrafanaDashboard CRD),
  NFS /backups/postgres mkdir + permissions on the OMV side, resticprofile /backups coverage
  check at verification, restore drill to a scratch DB.

### Next: unblock 1Password (owner) -> commits 4-10 as pathspec-isolated atomic commits -> Phase 0 (op item create sure + dragonfly) -> just pocket-id apply (approval) -> push + PR (approval).
