---
title: sure-am-self-hosting
type: progress-note
permalink: home-ops/docs/progress/sure-am-self-hosting
tags:
- sure
- cnpg
- postgres
- dragonfly
- progress
status: done
priority: medium
branch: feat/sure-self-hosting
closed: 2026-10-11
---

# sure-am-self-hosting

**Sure.am self-hosting — completed item.** Merged 2026-10-11: the roadmap plan
(`docs/roadmap/sure-am-self-hosting`) and this execution progress note were consolidated into one
closed record; the roadmap note was absorbed (its content lives here) and removed.

## Metadata (observation-form)

- [topic] Sure.am self-hosting — shared CNPG Postgres plane + Dragonfly Redis plane + app-template app
- [status] done — closed 2026-10-11 (owner): implemented on feat/sure-self-hosting, squash-merged as b920b9dce (PR #4489, 2026-10-07), live with 6 hotfixes on main, SSO-only proven
- [priority] medium
- [effort] L — two new platform planes + a new app + one app migration
- [area] k8s-workloads, database (new), external-secrets, iam, networking, ovh-storage
- [created] 2026-10-03
- [closed] 2026-10-11

## Overview

[Sure](https://github.com/we-promise/sure) (successor of Maybe) is an open-source family/personal finance app — Rails 8 (Puma web + Sidekiq worker), Postgres + Redis backends, optional AI features. The goal was to run it in this cluster like every other app: bjw-s app-template HelmRelease, GitOps-managed, internal-only. Sure was the first app here that genuinely needed a real SQL server and a non-localhost Redis, so the item also brought the two missing platform planes: a shared CloudNativePG Postgres cluster and a shared Dragonfly (Redis-compatible) instance in a new `database` namespace — and decommissioned paperless's localhost Valkey sidecar onto the shared plane.

Ratified design decisions (owner, 2026-10-01): shared CNPG cluster + per-app Database/DatabaseRole component; Dragonfly operator for the Redis plane; internal-only exposure; backup superseded 2026-10-03 by NAS-only daily pg_dumpall (resticprofile carries it offsite; no PITR — worst case 1 day loss, owner-accepted).

References studied:
- sure.am docs — https://docs.sure.am/self-hosting and /self-hosting-helm (official chart exists but the app-template path was chosen for repo consistency)
- eleboucher/homelab — `kubernetes/apps/selfhosted/sure` (app-template deployment, shared CNPG `postgres` in `database` ns, shared Dragonfly, per-app Database + DatabaseRole component — the chosen topology)
- vrozaksen/home-ops — `kubernetes/apps/self-hosted/sure` (app-template, per-app CNPG + dedicated Dragonfly, pgbouncer, Kanidm OIDC — considered as the alternative topology)

## What we gained (delivered)

- A self-hosted family finance app (net worth, budgets, bank sync, rules) reachable on the LAN at `fin.${PUBLIC_DOMAIN}` (cluster-settings templated hostname, never a hardcoded domain), authenticated via Pocket ID OIDC.
- The cluster's first shared SQL plane: CNPG operator + one shared `postgres` cluster in `database`, with a daily pg_dumpall to the NAS /backups plane (resticprofile carries it offsite; no PITR) — reusable by any future app that needs Postgres instead of embedded SQLite.
- A shared Dragonfly instance replacing paperless's pod-local Valkey sidecar; sure's Sidekiq queues and paperless share one Redis plane with per-app DB indexes (paperless db 1, sure db 2).
- A reusable per-app database component (`Database` + `DatabaseRole` + password secret wiring), so "app needs a database" becomes a one-component ks.yaml addition, like volsync is for PVCs.

## Design options (ratified 2026-10-01; backup option superseded 2026-10-03)

1. Postgres topology — shared CNPG cluster + per-app Database/DatabaseRole component (chosen, eleboucher-minta) vs per-app CNPG clusters in each app ns (vrozaksen-minta) vs the official sure chart's bundled subcharts. One cluster, one backup plane, reusable; a single node gains nothing from per-app cluster isolation at this scale.
2. Redis plane — Dragonfly operator + shared `dragonfly` (chosen) vs a plain shared Valkey app-template deployment vs per-app instances. Chosen for the operator-native CR with status/health checks; paperless's sidecar model is decommissioned either way.
3. Exposure — internal-only (chosen): `fin.${PUBLIC_DOMAIN}` on envoy-internal + k8s-gateway; no public surface for financial data.
4. Postgres backup — SUPERSEDED (owner, 2026-10-03): NAS-only daily pg_dumpall into the shared /backups plane with resticprofile as the offsite leg (no PITR — worst case 1 day loss, owner-accepted). The original barmanObjectStore-to-OVH option (S3 destination, cnpg-backup 1P item, WAL archiving, AES-256) remains as history; volume snapshots (snapshot-controller exists, but snapshots stay on the same disk — AD-011) can be added later as a fast local layer.
5. Connection pooling — none initially (Rails web = 1 process x 3 threads + worker, tiny connection count) vs pgbouncer Pooler from day one. Deferred: add a Pooler only if a future app or replica count justifies it.

## Execution decisions & corrections (superseding the plan)

- [decision] Postgres backup is **NAS-only pg_dump** (owner, 2026-10-03): daily pg_dumpall cronjob to the NAS /backups NFS export; the existing resticprofile plane carries it offsite. Supersedes the ratified "barmanObjectStore to OVH S3" option: no new OVH bucket/user, no cnpg-backup 1P item, no SSE question. Tradeoff accepted: **no PITR** — worst case 1 day data loss, manual dump restore.
- [decision] Dump auth via CNPG enableSuperuserAccess + operator-generated <cluster>-superuser Secret (no 1Password item needed for the backup path).
- [correction] CNPG operator chart is 0.29.x (operator 1.30.x); Database/DatabaseRole CRD is postgresql.cnpg.io/v1; barman client-side AES-256 does not exist (SSE-S3 only) — moot under NAS-only.
- [correction] Dragonfly: dragonflydb project, authentication via spec.authentication.passwordFromSecret; dbnum stays default (16) so SELECT 1/2 work — do not set --dbnum.
- [correction] Sure: no APP_DOMAIN env; db:prepare runs on boot (no initContainer); OIDC provider is db-sourced (AUTH_PROVIDERS_SOURCE=db), registered in admin UI; AUTH_LOCAL_LOGIN_ENABLED flips to false only after SSO is proven (separate commit).
- [correction] dragonfly-operator IS published as an OCI chart: oci://ghcr.io/dragonflydb/dragonfly-operator/helm/dragonfly-operator (v1.7.0) — the earlier "no published chart" finding was wrong (registry path probe stopped one segment short).
- [decision] Sure SSO JIT = link_only (owner, 2026-10-07): SSO accounts are created only from a pending Sure invitation (joins the inviting family); create_and_link would give every new SSO user a separate family (oidc_accounts_controller.rb#create_user, v0.7.5). Role mapping is set in the admin UI (db-sourced provider): super_admin: [sure_admins], member: [sure_users] — never map sure_admins to admin, the mapping re-applies on every login and would demote the owner (oidc_identity.rb#apply_role_mapping!).
- [decision] Dragonfly persistence = cache-only, no snapshot/tiering PVC (owner, 2026-10-03): a restart drops in-flight sidekiq/cache state; add spec.snapshot.persistentVolumeClaimSpec later if job loss becomes a problem.

## Phases (execution record — all complete)

Ratified plan (owner, 2026-10-03) — 9 phases (roadmap Phases 0-7 + local-login flip).

1. [x] **Phase 0 — 1Password items** — `sure` + `dragonfly` created 2026-10-07 as API Credential items in HomeOps (field names/lengths read back)
2. [x] **Phase 1 — database ns group + CNPG operator** — f3b091c3d, ee953928f
3. [x] **Phase 2 — postgres cluster + NAS dump cronjob** — b967c6022, 004684032
4. [x] **Phase 3 — dragonfly operator + shared instance (cache-only)** — 501053151, 19759aa9f
5. [x] **Phase 4 — paperless valkey decommission** — fcd6263fa
6. [x] **Phase 5 — components/cnpg/database** — 188952040
7. [x] **Phase 6 — sure app + Pocket ID client manifests** — 838ccccee, 29eb72766, b25b3290a (sure_users group); `just pocket-id apply` done 2026-10-07 (3 added: sure client, sure_admins, sure_users; secrets synced; audit 24/24 group-restricted)
8. [x] **Phase 7 — merge + Flux reconcile + live verification + restore drill** — merged 2026-10-07 (b920b9dce, squash); live + 6 hotfixes on main; SSO proven; NAS dump verification, restore drill and Enable Banking connect moved to Follow-ups at item closure (2026-10-11)
9. [x] **Local-login flip** — 1a204ca9e pure SSO-only (local login, admin override and standalone Sure passkey off); verified login page shows only /auth/pocketid

## Final live state (2026-10-07)

- PR #4489 squash-merged 2026-10-07 01:30Z (b920b9dce). The rollout needed 6 follow-up commits on main: bc4d67782 healthCheckExprs is spec-level (was nested — API server rejected, blocked ALL of cluster-apps) + Dragonfly API group is dragonflydb.io; a4c2578f4 escape bash ${out} as $${out} for Flux strict envsubst; f2d44b3e8 databaseRoleReclaimPolicy enum is lowercase; 1cd27fb50 Ruby Dir.tmpdir rejects world-writable non-sticky emptyDir → owner-only /tmp/app via bash wrapper + TMPDIR; eb9b6c392 POSTHOG_FEEDBACK_ENABLED=false + HOME=/tmp/app; 7db2bdf40 sure SSO provider names only allow [a-z0-9_] → provider pocketid, callback /auth/pocketid/callback (Pocket ID applied).
- Sure loads DB SSO providers only at boot (OmniAuth builder) → restart sure-server after adding/renaming a provider.
- Live: postgres-1, dragonfly-0 (master), paperless on dragonfly db1, sure server+worker Ready, owner super_admin linked to pocketid, 1 family.

## Verification results

- Flux ks Ready x7; sure login page SSO-only (local login form absent); DB 152 tables; owner registered and super_admin.
- Lesson: flux-local does not schema-validate — also run kubectl apply --dry-run=server on ks/CRs and flux envsubst --strict before merge.
- Not completed before closure — recorded as follow-ups below: first nightly NAS pg_dumpall verification, restore drill into a scratch DB, Enable Banking connect.

## Follow-ups recorded at closure (outside this item)

- Enable Banking connect in Sure (application id + certificate in the UI) — owner action, in-app.
- Invite family members (link_only JIT) and add them to Pocket ID sure_users.
- Verify the first nightly pg_dumpall lands in NAS /backups/postgres (00:17) and the next resticprofile run carries it offsite; check /backups/postgres permissions (uid 1000) if the dump fails.
- Restore drill of the latest dump into a scratch DB (`sure_restore_test`) if still wanted.
- stash@{0} review decision (mixed pre-hotfix state from a parallel branch switch, incl. mise.lock).
- Dropped earlier: Healthchecks.io ping for the dump job; CNPG Grafana dashboard (chart ships a plain ConfigMap, the repo uses the GrafanaDashboard CRD).

## Plan as ratified (historical reference, 2026-10-03)

### Pre-work state

- No `database` namespace existed; no Postgres operator or CNPG resources anywhere under `kubernetes/`.
- No shared Redis: the only Redis-compatible component was paperless's pod-local Valkey sidecar (`PAPERLESS_REDIS: redis://localhost:6379`, ephemeral emptyDir, no auth), reachable by nothing else.
- All SQL-needing apps ran embedded SQLite on their PVCs (paperless, actual, mealie) — no pattern yet for an app needing a real SQL server.
- app-template chart 5.2.1 shared via `kubernetes/components/common`; canonical app shape: ks.yaml + app/{helmrelease,externalsecret,ciliumnetworkpolicy}.yaml with `route:` rendered by app-template onto envoy-internal / envoy-external.
- Backup plane: VolSync + Kopia to OVH S3 (per-app component, 1Password keys `volsync-template` + `ovh`); snapshot-controller installed in kube-system; no database-dump-style backup existed.
- Single control-plane Talos node — single-instance Postgres is the honest topology (replication onto the same disk is theater; AD-011).
- sure requirements (docs + compose): Postgres 16-era or newer (PG 18 supported by CNPG 1.30 and Rails 8), Redis (Sidekiq), port 3000, persistence only at /rails/storage, health endpoint /up, first registered user becomes super_admin, Active Record encryption keys required for bank-sync credential storage.

### Target state

```
database ns:  cnpg operator ── Cluster postgres (1x PG18, 10Gi) ── nightly pg_dumpall → NAS /backups
              dragonfly operator ── Dragonfly dragonfly (1x, cache-only, passwordFromSecret)
selfhosted ns:  sure (app-template: web + worker, db:prepare on web boot, PVC /rails/storage)
                └─ postgres-rw.database.svc:5432/sure  (Database sure + DatabaseRole sure)
                └─ REDIS_URL → redis://:<pass>@dragonfly.database.svc:6379/2
selfhosted ns:  paperless └─ PAPERLESS_REDIS → redis://:<pass>@dragonfly.database.svc:6379/1 (sidecar gone)
Route:         fin.${PUBLIC_DOMAIN} → envoy-internal (k8s-gateway LAN DNS), native OIDC via Pocket ID
```

### Implementation steps (PR-sized phases, as planned)

**Phase 0 — prerequisites (1Password only — NAS-only backup removed the OVH/Terraform part)**
1. 1Password: item `sure` with SECRET_KEY_BASE (`openssl rand -hex 64`), ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY / _DETERMINISTIC_KEY / _KEY_DERIVATION_SALT (`openssl rand -hex 32` each — set once, never regenerated casually: rotation needs the `security:backfill_encryption` rake task), postgres_password; item `dragonfly` with requirepass (`openssl rand -hex 24`).

**Phase 1 — database namespace + CNPG operator**
1. New `kubernetes/apps/database/` group (kustomization + ks.yaml per app, like the other namespaces); registered in `kubernetes/apps/kustomization.yaml`.
2. `kubernetes/apps/database/cnpg/`: HelmRelease for the operator — chart `cloudnative-pg` (v1.30.x, the release that introduced the DatabaseRole CRD; Renovate-managed), CRDs via the chart, resources small; CNP for the operator per the default-deny posture.

**Phase 2 — shared postgres cluster**
1. `kubernetes/apps/database/postgres/`: Cluster `postgres` — instances: 1; image `ghcr.io/cloudnative-pg/postgresql:18.x-standard-trixie` pinned by digest; storage 10Gi `democratic-csi-local-hostpath`; minimal initdb bootstrap (no default app db needed — per-app `Database` CRs own that).
2. SUPERSEDED 2026-10-03 by the NAS-only pg_dumpall CronJob (see Execution decisions) — original barmanObjectStore-to-OVH plan kept as history only.
3. PodMonitor into kube-prometheus-stack (CNPG exposes metrics natively); healthChecks on the Cluster in the ks.yaml (pattern: `status.readyInstances >= 1`).
4. CNPs: ingress allow TCP 5432 from consuming app namespaces (label-based); egress DNS.

**Phase 3 — Dragonfly plane**
1. `kubernetes/apps/database/dragonfly/`: Dragonfly operator HelmRelease + Dragonfly CR `dragonfly` — replicas 1, cache-only (no snapshot PVC, owner decision 2026-10-03), passwordFromSecret, healthCheck on phase=ready.
2. CNPs: ingress allow TCP 6379 from paperless + sure pods only.

**Phase 4 — paperless valkey decommission (independent, preceded sure)**
1. Point `PAPERLESS_REDIS` at `redis://:<pass>@dragonfly.database.svc:6379/1`; drop the valkey sidecar container and its emptyDir; extend paperless's CNP with egress to database/dragonfly:6379.
2. Verify consume/task flows still run (paperless queues are rebuildable caches — losing them is tolerable).

**Phase 5 — reusable per-app database component**
1. `kubernetes/components/cnpg/database/`: Database (`name: <APP>`, owner <APP>, cluster postgres) + DatabaseRole (login, passwordSecret) + ExternalSecret creating `<APP>-postgres-app` — a `kubernetes.io/basic-auth` Secret (username + password keys, `cnpg.io/reload: "true"` label) in `database` ns from the per-app 1P item.
2. Component wired per-app via ks.yaml (`components:` + `postBuild.substitute: {APP: sure}`), with dependsOn the cnpg cluster Kustomization and a healthCheck on the Database CR.
3. App-side wiring: ExternalSecret in the app ns assembles `DATABASE_URL` (`postgresql://sure:<pass>@postgres-rw.database.svc:5432/sure`) from the same 1P item.

**Phase 6 — sure app**
1. `provision/pocket-id` Terraform: OIDC client `sure`, redirect URI `https://fin.${PUBLIC_DOMAIN}/auth/<provider-id>/callback`; allowed groups per the family-ACL decision; client secret into 1Password `pocket-id-clients`. Sure keeps SSO providers in its database (AUTH_PROVIDERS_SOURCE=db), created in the admin UI (/admin/sso_providers) — the secret ends up in Postgres, one more reason the backup plane matters.
2. `kubernetes/apps/selfhosted/sure/`: ks.yaml (components: volsync + cnpg/database; dependsOn postgres cluster, dragonfly, onepassword-connect, pocket-id; substitute APP=sure, VOLSYNC_CAPACITY=2Gi) + app/{helmrelease,externalsecret,ciliumnetworkpolicy}.yaml.
3. HelmRelease (app-template): two controllers — `server` (web, port 3000, /up liveness+readiness+startup probes) and `worker` (sidekiq); shared env: RAILS_ENV=production, SELF_HOSTED=true, RAILS_ASSUME_SSL=true (TLS terminates at Envoy), no APP_DOMAIN env, DB_HOST/DB_PORT/POSTGRES_USER/POSTGRES_DB plain env, POSTGRES_PASSWORD + REDIS_URL in the ES template (dragonfly SELECT 2 — paperless takes 1), SECRET_KEY_BASE + AR-encryption keys envFrom sure-secret. SSO is db-backed (configured in the admin UI); hardened with AUTH_LOCAL_LOGIN_ENABLED=false (SSO-only, removes the local password-reset path) and AUTH_JIT_MODE=link_only (owner, 2026-10-07). db:prepare runs on web boot (image entrypoint, no initContainer); `sure` existingClaim mounted at /rails/storage by both controllers; resources web 100m/384Mi→1Gi, worker 50m/256Mi→768Mi (reference-measured).
4. Route: envoy-internal only, hostname `fin.${PUBLIC_DOMAIN}` (k8s-gateway serves it on LAN); homepage annotations; CNP: custom-egress label + egress to database (5432, 6379) + allow-world for bank/provider syncs initially (tighten per egress-fqdn-allowlisting once the provider list settles).
5. Onboarding is a DB-stored app setting (Settings → Self-Hosting → Onboarding: Open / Invite-only / Closed), not an env var. Register immediately after the rollout lands (first user becomes super_admin; a DB lock guards the race), then close it in the admin UI — mandatory security step.

**Phase 7 — verification + restore drill** — see Verification results and Follow-ups.

### Open questions / risks (from planning, resolved where noted)

- [question] Dragonfly multi-DB support — validated live: paperless (db 1) and sure (db 2) both work against the shared instance.
- [question] SMTP — deferrable: with AUTH_LOCAL_LOGIN_ENABLED=false there is no local login and no password reset at all; no in-cluster mail relay exists.
- [risk] First-user bootstrap race — handled: owner registered immediately after rollout, onboarding closed in the admin UI.
- [risk] Active Record encryption keys are load-bearing for bank-sync credentials: generated once into 1Password, never casually rotated (rotation requires the documented backfill rake task).
- [note] Market-data provider keys (TwelveData/Tiingo/etc.) and AI features are optional add-ons; the app degrades gracefully without them — out of scope for the first cut.
- [note] WEBAUTHN_* env is now only relevant for Sure-level passkey registration (standalone passkey login is off since the local-login flip).
- [note] Phases 1-5 were reusable platform work benefiting any future Postgres/Redis app; only phases 6-7 were sure-specific.

## Session history

### Session 1 — 2026-10-03 (planning + implementation)

- Plan mode: full repo + BM area research (3 explorers), Plan-agent design pass, owner decisions on branch scope (full item), 1P ownership (AI via op CLI), apply/deploy depth (AI with approval gates), and backup destination (NAS-only pg_dump).
- Branch feat/sure-self-hosting created from main.
- Pre-flight research complete: chart tags (CNPG 0.29.1, dragonfly-operator v1.7.0), image digests (PG18 18-standard-trixie, dragonfly v2.0.0, sure 0.7.5-hotfix.1), CRD fields (no storageSize on Dragonfly, no podTemplate on Cluster — inheritedMetadata.labels instead, enablePodMonitor deprecated → manual PodMonitor), sure env contract (DB_HOST/DB_PORT/POSTGRES_*), renovate customManagers regex manager for CNPG imageName + Dragonfly CR image.
- Commits 1-3 landed: f3b091c3d (database ns group), ee953928f (cloudnative-pg operator), b967c6022 (postgres cluster + PodMonitor + CNP + renovate customManager).
- Phases 2-6 manifests complete in the working tree: postgres NAS dump cronjob (staged, commit 4 blocked on signing), dragonfly-operator, dragonfly instance (cache-only), paperless valkey decommission (4 files), components/cnpg/database (Database + DatabaseRole + first basic-auth ES), sure app (ks + HR + ES + CNP, internal-only fin.${PUBLIC_DOMAIN} route, cnpg+volsync components), clients.yaml (sure_admins group + sure native OIDC client, provisional callback).
- Validation green: just pocket-id lint OK; pre-commit hooks OK (mise-lock fails on pre-existing tool-version drift in the working tree — owner's in-progress work; mise.lock reverted, not committed); flux-local test 145/145 passed after fixing sure readiness probe httpGet port.
- OPEN then (owner action, resolved 2026-10-06/07): op CLI 2.39.0 "No accounts configured" — desktop "Connect with 1Password CLI" integration; plain `op signin` not yet run. Phase 0 (op item create sure + dragonfly) and just pocket-id apply were gated on this.
- Working tree note: mise.lock drift (config has newer tool versions, e.g. hubble 1.20.2 vs lock 1.19.4) is the owner's in-progress work, deliberately left uncommitted; `mise lock` closes it.

### Session 2 — 2026-10-06/07 (merge, hotfixes, live verification, SSO-only)

- Commit-signing resolved 2026-10-06 (app unlocked): commits 4-10 + docs landed and pushed; PR #4489 open (https://github.com/zhorvath83/home-ops/pull/4489), CI green (7/7 checks: Flux Local Diff/Test, Gitleaks, Labeler).
- op CLI desktop integration resolved → Phase 0 items created 2026-10-07; `just pocket-id apply` done (sure client, sure_admins, sure_users; audit 24/24 group-restricted).
- PR #4489 squash-merged 2026-10-07 01:30Z (b920b9dce); 6 hotfix commits landed on main (see Final live state); live verification: stack Ready, SSO proven.
- Local-login flip 1a204ca9e: pure SSO-only, applied after SSO was proven.

## Relations

- relates_to [[home-ops/docs/areas/k8s-workloads]]
- relates_to [[home-ops/docs/areas/external-secrets]]
- relates_to [[home-ops/docs/areas/iam]]
- relates_to [[home-ops/docs/areas/networking]]
- relates_to [[home-ops/docs/areas/ovh-storage]]
- relates_to [[home-ops/docs/decisions/ad-011-democratic-csi-storage]]
- relates_to [[home-ops/docs/roadmap/egress-fqdn-allowlisting]]
