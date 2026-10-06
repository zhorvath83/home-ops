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
- Commit-signing resolved 2026-10-06 (app unlocked): commits 4-10 + docs landed and pushed; PR #4489
  open (https://github.com/zhorvath83/home-ops/pull/4489), CI green (7/7 checks: Flux Local Diff/Test,
  Gitleaks, Labeler). Latest commit on branch: a3e2548e0.
- OPEN (owner action): op CLI 2.39.0 still reports "No accounts configured" — app running (PID seen),
  daemon socket live (~/.config/op/op-daemon.sock), ~/.config/op/config has accounts: null. The desktop
  "Connect with 1Password CLI" global toggle was switched on but no account is integrated. `op signin
  -t` does not exist in 2.39 (-t unknown flag); plain `op signin` was NOT run yet (user interrupted it —
  it may need interactive approval). Next attempt: owner runs `! op signin` interactively or checks
  Settings -> Developer for a per-account integration toggle. Phase 0 (op item create sure +
  dragonfly) and just pocket-id apply (uses op run + op item edit) remain gated on this.
- Working tree note: mise.lock drift (config has newer tool versions, e.g. hubble 1.20.2 vs lock 1.19.4)
  is the owner's in-progress work, deliberately left uncommitted; `mise lock` closes it.
- Follow-ups recorded: Healthchecks.io ping for the dump job (dropped for now), CNPG Grafana
  dashboard (dropped — chart ships a plain ConfigMap, the repo uses the GrafanaDashboard CRD),
  NFS /backups/postgres mkdir + permissions on the OMV side, resticprofile /backups coverage
  check at verification, restore drill to a scratch DB.

### Next: owner enables the 1Password CLI desktop integration -> Phase 0 (op item create sure + dragonfly) -> just pocket-id apply -> merge PR #4489 (approval) -> Flux reconcile + live verification (onboarding runbook in the PR description) -> local-login flip commit after SSO is proven.
