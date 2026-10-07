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
8. [ ] **Phase 7 — merge + Flux reconcile + live verification + restore drill** — PR #4489 open; final review fixes committed 2026-10-07 `← current`
9. [ ] **Local-login flip** — security commit `AUTH_LOCAL_LOGIN_ENABLED=false` after SSO is proven

## Checkpoint
- **Phase**: 8/9 — merge + live verification — awaiting push + CI + merge approval
- **State**: Phase 0 + pocket-id apply done. Final full review (2026-10-07) found 4 critical + 3 high defects, all fixed in one commit: K1 cnpg component landed in selfhosted (Flux targetNamespace overrides explicit namespace) -> separate sure-database ks targeting database; K2 dragonfly CNP blocked operator admin port 9999 (master promotion -> role=master Service selector) -> allowed; K3 dragonfly exits when maxmemory < 256MB x threads (16 CPUs) -> --proactor_threads=1; K4 postgres CNP blocked CNPG operator 8000/5432 -> allowed; M1 sure server lacked allow-gateways (Pocket ID hairpin) -> added; M2 rails server mkdir_p tmp/sockets on RO rootfs -> emptyDir /rails/tmp; M3 pg_dumpall pipe without pipefail -> bash pipefail + .partial rename. Also: dragonfly ks healthCheck (phase Ready), postgres image digest-pinned in Cluster + backup (same index digest), renovate regex digest-aware, Renovate pin allowedVersions <19 for ghcr.io/cloudnative-pg/postgresql (major = planned CNPG offline pg_upgrade), roadmap barman text marked superseded. Enable Banking (api.enablebanking.com) is covered by allow-world; credentials live in the sure DB (AR-encrypted), callback is a browser redirect.
- **Commits**: b25b3290a, f40c020de (review fixes) + the JIT link_only commit — local until owner approves push; PR #4489 runbook updated (role mapping + invitation flow)
- **Tests**: flux-local test 146/146 (2026-10-07, after fixes); just pocket-id lint OK
- **Next-Claude**: push (approval) -> wait for PR #4489 CI green -> ask merge approval -> just k8s flux-reconcile + live verification per the onboarding runbook (postgres Cluster ready, Database sure applied, dragonfly phase Ready + paperless redis OK, sure /up, first user -> super_admin -> onboarding Closed, SSO provider at /admin/sso_providers, OIDC + passkey test, Enable Banking connect, NAS dump present, restore drill to sure_restore_test) -> local-login flip commit after SSO proven.
- **Next-Human**: approve push + merge; add yourself to sure_admins (family to sure_users) in Pocket ID; create /backups/postgres on the NAS writable by uid 1000 if mkdir fails.
- **Open questions**: callback_path /auth/pocket-id/callback provisional; WEBAUTHN_RP_ID subdomain may need the bare public domain; JIT question resolved 2026-10-07 (link_only, see Decisions).
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
