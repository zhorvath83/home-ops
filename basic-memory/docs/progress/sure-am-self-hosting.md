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

## Session 1 — 2026-10-03

- Plan mode: full repo + BM area research (3 explorers), Plan-agent design pass, owner decisions
  on branch scope (full item), 1P ownership (AI via op CLI), apply/deploy depth (AI with approval
  gates), and backup destination (NAS-only pg_dump).
- Branch feat/sure-self-hosting created from main.
- Pre-flight research started (chart tags, image digests, CRD fields, sure env vars).

### Next: pre-flight research, then Phase 0 (1P items sure + dragonfly) and Phase 1 (database ns group + CNPG operator).
