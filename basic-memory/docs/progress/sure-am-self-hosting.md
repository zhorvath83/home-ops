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
- [decision] Sure SSO JIT = link_only (owner, 2026-10-07): SSO accounts are created only from a pending
  Sure invitation (joins the inviting family); create_and_link would give every new SSO user a separate
  family (oidc_accounts_controller.rb#create_user, v0.7.5). Role mapping is set in the admin UI (db-sourced
  provider): super_admin: [sure_admins], member: [sure_users] — never map sure_admins to admin, the mapping
  re-applies on every login and would demote the owner (oidc_identity.rb#apply_role_mapping!).
- [decision] Dragonfly persistence = cache-only, no snapshot/tiering PVC (owner, 2026-10-03):
  a restart drops in-flight sidekiq/cache state; add spec.snapshot.persistentVolumeClaimSpec
  later if job loss becomes a problem.

## Phases

Ratified plan (owner, 2026-10-03) — 9 phases (roadmap Phases 0-7 + local-login flip). The active phase is marked `← current`.

1. [x] **Phase 0 — 1Password items** — `sure` + `dragonfly` created 2026-10-07 as API Credential items in HomeOps (field names/lengths read back)
2. [x] **Phase 1 — database ns group + CNPG operator** — f3b091c3d, ee953928f
3. [x] **Phase 2 — postgres cluster + NAS dump cronjob** — b967c6022, 004684032
4. [x] **Phase 3 — dragonfly operator + shared instance (cache-only)** — 501053151, 19759aa9f
5. [x] **Phase 4 — paperless valkey decommission** — fcd6263fa
6. [x] **Phase 5 — components/cnpg/database** — 188952040
7. [x] **Phase 6 — sure app + Pocket ID client manifests** — 838ccccee, 29eb72766, b25b3290a (sure_users group); `just pocket-id apply` done 2026-10-07 (3 added: sure client, sure_admins, sure_users; secrets synced; audit 24/24 group-restricted)
8. [ ] **Phase 7 — merge + Flux reconcile + live verification + restore drill** — merged 2026-10-07 (b920b9dce, squash); live + 6 hotfixes on main; SSO proven; remaining: NAS dump + restore drill + Enable Banking connect `← current`
9. [x] **Local-login flip** — 1a204ca9e pure SSO-only (local login, admin override and standalone Sure passkey off); verified login page shows only /auth/pocketid

## Checkpoint
- **Phase**: 8/9 — live verification — stack live, SSO-only proven; backup verification pending
- **State**: PR #4489 squash-merged 2026-10-07 01:30Z (b920b9dce). Rollout needed 6 follow-up commits on main: bc4d67782 healthCheckExprs is spec-level (was nested -> API server rejected, blocked ALL of cluster-apps) + Dragonfly API group is dragonflydb.io; a4c2578f4 escape bash ${out} as $${out} for Flux strict envsubst; f2d44b3e8 databaseRoleReclaimPolicy enum is lowercase; 1cd27fb50 Ruby Dir.tmpdir rejects world-writable non-sticky emptyDir -> owner-only /tmp/app via bash wrapper + TMPDIR; eb9b6c392 POSTHOG_FEEDBACK_ENABLED=false + HOME=/tmp/app; 7db2bdf40 sure SSO provider names only allow [a-z0-9_] -> provider pocketid, callback /auth/pocketid/callback (Pocket ID applied). Sure loads DB SSO providers only at boot (OmniAuth builder) -> restart sure-server after adding/renaming a provider. 1a204ca9e pure SSO-only. Live: postgres-1, dragonfly-0 (master), paperless on dragonfly db1, sure server+worker Ready, owner super_admin linked to pocketid, 1 family.
- **Commits**: all pushed to main (last 1a204ca9e)
- **Tests**: live-verified (Flux ks Ready x7, sure login page SSO-only, DB 152 tables). Lesson: flux-local does not schema-validate; also run kubectl apply --dry-run=server on ks/CRs and flux envsubst --strict before merge.
- **Next-Claude**: verify first nightly pg_dumpall lands in NAS /backups/postgres (00:17) + resticprofile carries it; restore drill into sure_restore_test; confirm role mapping on a sure_users member via invitation flow; optional: stash@{0} review with owner.
- **Next-Human**: Enable Banking connect in Sure (application id + certificate in the UI); invite family members (link_only) and add them to Pocket ID sure_users; check /backups/postgres permissions (uid 1000) if the first dump fails; decide on stash@{0} (mixed pre-hotfix state from a parallel branch switch, incl. mise.lock).
- **Open questions**: WEBAUTHN_* env now only relevant for Sure-level passkey registration (standalone passkey login is off).
- **Maestro**: n/a — human-attended Maestri-canvas session, no delegation
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
