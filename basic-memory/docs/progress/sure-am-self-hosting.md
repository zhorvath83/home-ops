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

## Phases

Ratified plan (owner, 2026-10-03) — 9 phases (roadmap Phases 0-7 + local-login flip). The active phase is marked `← current`.

1. [ ] **Phase 0 — 1Password items** — `op item create` vault HomeOps: `sure` (secret_key_base hex64, 3x AR-encryption keys hex32, postgres_password hex24) + `dragonfly` (requirepass hex24) `← current` — BLOCKED on op CLI integration (owner action)
2. [x] **Phase 1 — database ns group + CNPG operator** — f3b091c3d, ee953928f
3. [x] **Phase 2 — postgres cluster + NAS dump cronjob** — b967c6022, 004684032
4. [x] **Phase 3 — dragonfly operator + shared instance (cache-only)** — 501053151, 19759aa9f
5. [x] **Phase 4 — paperless valkey decommission** — fcd6263fa
6. [x] **Phase 5 — components/cnpg/database** — 188952040
7. [x] **Phase 6 — sure app + Pocket ID client manifests** — 838ccccee, 29eb72766; `just pocket-id apply` still pending, gated on Phase 0
8. [ ] **Phase 7 — merge + Flux reconcile + live verification + restore drill** — PR #4489 open, CI 7/7 green; onboarding runbook in the PR description
9. [ ] **Local-login flip** — security commit `AUTH_LOCAL_LOGIN_ENABLED=false` after SSO is proven

## Checkpoint

- **Phase**: 0/9 — 1Password items — blocked on owner action (op CLI account integration)
- **State**: all repo-side work finished and pushed — Phases 1-6 committed (14 branch commits, remote in sync, PR #4489 open, CI 7/7 green). Phase 0 blocked: op CLI 2.39.0 reports "No accounts configured" (~/.config/op/config has accounts: null; desktop global CLI toggle on but no account integrated; plain `op signin` NOT run — owner interrupted it, may need interactive approval). `just pocket-id apply` gated on the same (uses op run + op item edit). Working tree: only mise.lock drift — owner's in-progress tool versions, deliberately uncommitted (`mise lock` closes it).
- **Commits**: aa14a5fbe (last pushed) — all 14 branch commits on the remote; the docs commit carrying this checkpoint is LOCAL by owner decision (2026-10-06) — push before handover to another machine
- **Tests**: green — flux-local test (all-namespaces, enable-helm, path kubernetes/flux/cluster) 145/145 passed in this session (2026-10-06), no source change since (only BM docs commits); just pocket-id lint OK; PR #4489 CI 7/7 green
- **Next-Claude**: after the op CLI is unblocked, run Phase 0 (approval gate): op item create --category=password --vault HomeOps --title sure with fields secret_key_base[password] (openssl rand -hex 64), active_record_encryption_primary_key[password] / _deterministic_key[password] / _key_derivation_salt[password] (openssl rand -hex 32 each), postgres_password[password] (openssl rand -hex 24); same for --title dragonfly with requirepass[password] (openssl rand -hex 24). AR-encryption keys generated once, NEVER casually rotated. Then: just pocket-id apply (approval gate) -> ask approval to merge PR #4489 -> just k8s flux-reconcile + live verification per the onboarding runbook in the PR description (postgres Cluster/Database/DatabaseRole ready; paperless without sidecar; sure /up green; first user -> super_admin -> onboarding Closed; SSO provider at /admin/sso_providers, issuer https://idm.${PUBLIC_DOMAIN}, secret from 1P pocket-id-clients/sure_client_secret; OIDC + passkey test; NAS dump; restore drill to sure_restore_test) -> local-login flip commit after SSO is proven.
- **Next-Human**: enable per-account 1Password CLI integration (1Password Settings -> Developer) or run `! op signin` interactively; then approve the gated steps (Phase 0 item creates, just pocket-id apply, PR #4489 merge). Separately: `mise lock` for own tool-version drift.
- **Open questions**: callback_path /auth/pocket-id/callback is provisional — admin UI dictates the exact URI (clients.yaml fix + re-apply if it differs); WEBAUTHN_RP_ID as subdomain fin.${PUBLIC_DOMAIN} may need drop to ${PUBLIC_DOMAIN} if passkey registration fails.
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
