---
title: Sure.am self-hosting
type: roadmap
permalink: home-ops/docs/roadmap/sure-am-self-hosting
topic: Sure.am self-hosting — shared CNPG Postgres plane + Dragonfly Redis plane +
  app-template app
status: in_progress
priority: medium
scope: New database platform (CNPG operator + shared postgres cluster + Dragonfly
  operator + shared instance in a database namespace), a reusable per-app Database/DatabaseRole
  component, NAS pg_dump Postgres backups, paperless valkey decommission, and the
  sure app itself via app-template with internal-only exposure and Pocket ID OIDC.
rationale: Sure is the first app in this cluster that needs a real SQL server and
  a non-localhost Redis; bringing the two missing platform planes once (shared CNPG
  cluster, shared Dragonfly) makes every current and future database-needing app a
  one-component addition, and gives Postgres the same offsite-backup guarantee PVCs
  already have.
related_areas:
- k8s-workloads
- external-secrets
- iam
- ovh-storage
- networking
options:
- Shared CNPG cluster + per-app Database/DatabaseRole component (chosen — eleboucher-minta)
  vs per-app CNPG clusters (vrozaksen-minta) vs official sure chart bundled subcharts
- Dragonfly operator + shared instance (chosen) vs plain shared Valkey deployment
  vs per-app Redis
- Internal-only exposure (chosen) vs also external via Cloudflare
- NAS-only pg_dump to the /backups plane, resticprofile offsite (chosen 2026-10-03,
  supersedes barmanObjectStore→OVH) vs CNPG built-in barmanObjectStore to OVH S3 vs
  barman-cloud plugin deployment
- No pgbouncer initially (chosen, revisit on growth) vs Pooler from day one
tags:
- sure
- cnpg
- postgres
- dragonfly
- redis
- k8s-workloads
---

# Sure.am self-hosting

[Sure](https://github.com/we-promise/sure) (successor of Maybe) is an open-source family/personal finance
app — Rails 8 (Puma web + Sidekiq worker), Postgres + Redis backends, optional AI features. The goal is to
run it in this cluster like every other app: bjw-s app-template HelmRelease, GitOps-managed, internal-only.
Sure is the first app here that genuinely needs a real SQL server and a non-localhost Redis, so this item
also brings the two missing platform planes: a shared CloudNativePG Postgres cluster and a shared Dragonfly
(Redis-compatible) instance in a new `database` namespace — and decommissions paperless's localhost Valkey
sidecar onto the shared plane.

Ratified design decisions (owner, 2026-10-01): shared CNPG cluster + per-app Database/DatabaseRole
component; Dragonfly operator for the Redis plane; internal-only exposure; backup superseded 2026-10-03 by NAS-only daily pg_dumpall (resticprofile carries it offsite; no PITR - worst case 1 day loss, owner-accepted).

References studied:
- sure.am docs — https://docs.sure.am/self-hosting and /self-hosting-helm (official chart exists but the
  app-template path was chosen for repo consistency)
- eleboucher/homelab — `kubernetes/apps/selfhosted/sure` (app-template deployment, shared CNPG `postgres`
  in `database` ns, shared Dragonfly, per-app Database + DatabaseRole component)
- vrozaksen/home-ops — `kubernetes/apps/self-hosted/sure` (app-template, per-app CNPG + dedicated Dragonfly,
  pgbouncer, Kanidm OIDC — considered as the alternative topology)

## Metadata (observation-form)

- [topic] Sure.am self-hosting — shared CNPG Postgres plane + Dragonfly Redis plane + app-template app
- [status] in_progress — implemented on feat/sure-self-hosting, corrections recorded in [[home-ops/docs/progress/sure-am-self-hosting]] (2026-10-03)
- [priority] medium
- [effort] L — two new platform planes + a new app + one app migration
- [progress] Tracking + session summaries will live in a docs/progress sibling once work starts; this note is the plan.

## What we gain

- A self-hosted family finance app (net worth, budgets, bank sync, rules) reachable on the LAN at
  `fin.${PUBLIC_DOMAIN}` (cluster-settings templated hostname, never a hardcoded domain), authenticated
  via Pocket ID OIDC + passkeys.
- The cluster's first shared SQL plane: CNPG operator + one shared `postgres` cluster in `database`,
  with daily barman backups to OVH S3 (offsite, consistent with the volsync plane) — reusable by any
  future app that needs Postgres instead of embedded SQLite.
- A shared Dragonfly instance replacing paperless's pod-local Valkey sidecar; sure's Sidekiq queues get
  persistence and both apps share one Redis plane with per-app DB indexes.
- A reusable per-app database component (`Database` + `DatabaseRole` + password secret wiring), so
  "app needs a database" becomes a one-component ks.yaml addition, like volsync is for PVCs.

## What to do

1. Provision prerequisites: 1Password items - `sure` (SECRET_KEY_BASE, three AR-encryption keys, postgres_password) and `dragonfly` (requirepass); the NAS-only backup decision (2026-10-03) removed the OVH S3 bucket, object-store user and `cnpg-backup` item.
2. Create the `database` namespace group under `kubernetes/apps/` and deploy the CloudNativePG operator
   (chart `cloudnative-pg` 1.30.x).
3. Deploy the shared `postgres` Cluster: 1 instance (single node — AD-011 logic), PG 18 standard image
   pinned by digest, 10Gi democratic-csi-local-hostpath, NAS-only nightly pg_dumpall CronJob (dump to the shared /backups plane, resticprofile carries it offsite; no PITR by decision), manual PodMonitor (the chart's monitoring.enablePodMonitor is deprecated; pod labels go on inheritedMetadata), CNP ingress allow-list.
4. Deploy the Dragonfly operator (OCI chart oci://ghcr.io/dragonflydb/dragonfly-operator/helm, v1.7.0 - the earlier "no published chart" finding was wrong) and a shared `dragonfly` instance in `database` (1 replica, cache-only - no snapshot PVC, owner decision 2026-10-03; dbnum stays default 16 so SELECT 1/2 work; passwordFromSecret), ingress CNP allow-list from consuming apps.
5. Migrate paperless off its localhost Valkey sidecar to the shared instance (own DB index), remove the
   sidecar and its emptyDir, update paperless's CNP.
6. Author the reusable `kubernetes/components/cnpg/database` component: per-app `Database` +
   `DatabaseRole` with a passwordSecret (basic-auth Secret created by External Secrets from 1Password).
7. Create the Pocket ID OIDC client for sure (Terraform, `provision/pocket-id`) and the 1Password
   `sure` item: SECRET_KEY_BASE, the three Active Record encryption keys, Postgres + Dragonfly passwords.
8. Deploy sure with app-template in `selfhosted`: web + worker controllers (db:prepare runs on web boot - no initContainer),
   `sure` PVC on /rails/storage (volsync-backed), internal-only route on envoy-internal, native OIDC
   (db-backed SSO provider configured in the admin UI — Phase 6), passkey config, onboarding opened
   for the first registration then closed in the admin UI (Settings → Self-Hosting → Onboarding).
9. Verify: cluster ready, first dump in the NAS /backups/postgres tree (and the next resticprofile run carrying it offsite), OIDC + passkey login, paperless healthy post-migration; run a restore drill of the latest dump into a scratch DB.

## Options

1. Postgres topology — shared CNPG cluster + per-app Database/DatabaseRole component (chosen,
   eleboucher-minta) vs per-app CNPG clusters in each app ns (vrozaksen-minta) vs the official sure
   chart's bundled subcharts. Chosen: one cluster, one backup plane, reusable; a single node gains
   nothing from per-app cluster isolation at this scale.
2. Redis plane — Dragonfly operator + shared `dragonfly` (chosen) vs a plain shared Valkey
   app-template deployment vs keeping per-app instances. Chosen: operator-native CR with status/health
   checks; paperless's sidecar model is decommissioned either way.
3. Exposure — internal-only (chosen): `fin.${PUBLIC_DOMAIN}` on envoy-internal + k8s-gateway; no public
   surface for financial data.
4. Postgres backup — SUPERSEDED (owner, 2026-10-03): NAS-only daily pg_dumpall into the shared /backups plane with resticprofile as the offsite leg (no PITR - worst case 1 day loss, owner-accepted); the original barmanObjectStore-to-OVH option remains as history
   vs the separate barman-cloud plugin deployment (eleboucher; extra deployment, same destination) vs
   volume snapshots only (snapshot-controller exists, but snapshots stay on the same disk — no offsite,
   AD-011 makes that weak). Volume snapshots can be added later as a fast local layer.
5. Connection pooling — none initially (Rails web = 1 process x 3 threads + worker, tiny connection
   count) vs pgbouncer Pooler from day one (both references have it). Deferred: add a Pooler only if a
   future app or replica count justifies it.

## Related

- relates_to [[home-ops/docs/areas/k8s-workloads]]
- relates_to [[home-ops/docs/areas/external-secrets]]
- relates_to [[home-ops/docs/areas/iam]]
- relates_to [[home-ops/docs/areas/ovh-storage]]
- relates_to [[home-ops/docs/decisions/ad-011-democratic-csi-storage]]
- relates_to [[home-ops/docs/roadmap/egress-fqdn-allowlisting]]

## Execution plan (research-backed)

### Current state

- No `database` namespace exists; no Postgres operator or CNPG resources anywhere under `kubernetes/`.
- No shared Redis: the only Redis-compatible component is paperless's pod-local Valkey sidecar
  (`kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml`, `PAPERLESS_REDIS: redis://localhost:6379`,
  ephemeral emptyDir, no auth), reachable by nothing else; its CNP states "no in-cluster or world egress".
- All SQL-needing apps today run embedded SQLite on their PVCs (paperless, actual, mealie) — there is no
  pattern yet for an app needing a real SQL server.
- app-template chart 5.2.1 is shared via `kubernetes/components/common`; apps reference it by
  `chartRef: OCIRepository app-template`; the canonical app shape is ks.yaml + app/{helmrelease,
  externalsecret, ciliumnetworkpolicy}.yaml with `route:` rendered by app-template onto envoy-internal /
  envoy-external.
- Backup plane today: VolSync + Kopia to OVH S3 (per-app component, 1Password keys `volsync-template` +
  `ovh`); snapshot-controller is installed in kube-system. No database-dump-style backup exists.
- Single control-plane Talos node — single-instance Postgres is the honest topology (replication onto the
  same disk is theater; AD-011).
- sure requirements (docs + compose): Postgres 16-era or newer (PG 18 is supported by CNPG 1.30 and Rails 8),
  Redis (Sidekiq), port 3000, persistence only at `/rails/storage`, health endpoint `/up`, first registered
  user becomes super_admin, Active Record encryption keys required for bank-sync credential storage.

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

### Implementation steps (PR-sized phases)

**Phase 0 — prerequisites (1Password only — NAS-only backup removed the OVH/Terraform part)**
1. 1Password: item `sure` with
   SECRET_KEY_BASE (`openssl rand -hex 64`), ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY / _DETERMINISTIC_KEY /
   _KEY_DERIVATION_SALT (`openssl rand -hex 32` each — set once, never regenerated casually: rotation
   needs the `security:backfill_encryption` rake task), postgres_password; item `dragonfly` with requirepass (`openssl rand -hex 24`).

**Phase 1 — database namespace + CNPG operator**
1. New `kubernetes/apps/database/` group (kustomization + ks.yaml per app, like the other namespaces);
   register it in `kubernetes/apps/kustomization.yaml`.
2. `kubernetes/apps/database/cnpg/`: HelmRelease for the operator — chart `cloudnative-pg` (v1.30.x,
   the release that introduced the DatabaseRole CRD; Renovate-managed), CRDs via the chart, resources
   small; CNP for the operator per the default-deny posture.

**Phase 2 — shared postgres cluster**
1. `kubernetes/apps/database/postgres/`: Cluster `postgres` — instances: 1; image
   `ghcr.io/cloudnative-pg/postgresql:18.x-standard-trixie` pinned by digest; storage 10Gi
   `democratic-csi-local-hostpath`; minimal initdb bootstrap (no default app db needed — per-app
   `Database` CRs own that).
2. `spec.backup.barmanObjectStore`: destinationPath `s3://home-ops-postgres/postgres`, OVH endpoint,
   credentials from ExternalSecret `cnpg-backup` (ClusterSecretStore `onepassword-connect`),
   AES-256 encryption on both data and WAL, key from the same ExternalSecret — backups hold financial
   data and (per Phase 6) an OIDC client secret, and the volsync plane's offsite backups are
   client-side-encrypted, so barman must match that guarantee. WAL compression zstd, data
   compression, retentionPolicy 14d; ScheduledBackup `postgres-backup` daily at an off-round hour
   (e.g. 03:17).
3. PodMonitor into kube-prometheus-stack (CNPG exposes metrics natively); healthChecks on the Cluster
   in the ks.yaml (pattern: `status.readyInstances >= 1`).
4. CNPs: ingress allow TCP 5432 from consuming app namespaces (label-based); egress DNS + OVH S3
   endpoint (align with the egress-fqdn-allowlisting model, or allow-world initially).

**Phase 3 — Dragonfly plane**
1. `kubernetes/apps/database/dragonfly/`: Dragonfly operator HelmRelease (chart
   `dragonfly-operator`) + Dragonfly CR `dragonfly` — replicas 1, small PVC (~2Gi, democratic-csi),
   `--requirepass` from an ExternalSecret (1P `dragonfly` item), healthCheck on phase=ready.
2. CNPs: ingress allow TCP 6379 from paperless + sure pods only.

**Phase 4 — paperless valkey decommission (independent, can precede sure)**
1. Point `PAPERLESS_REDIS` at `redis://:<pass>@dragonfly.database.svc:6379/1`; drop the valkey sidecar
   container and its emptyDir; extend paperless's CNP with egress to database/dragonfly:6379.
2. Verify consume/task flows still run (paperless queues are rebuildable caches — losing them is
   tolerable; verify no functional regression).

**Phase 5 — reusable per-app database component**
1. `kubernetes/components/cnpg/database/`: Database (`name: <APP>`, owner <APP>, cluster postgres) +
   DatabaseRole (login, passwordSecret) + ExternalSecret creating `<APP>-postgres-app` — a
   `kubernetes.io/basic-auth` Secret (username + password keys, `cnpg.io/reload: "true"` label) in
   `database` ns from the per-app 1P item.
2. Component wired per-app via ks.yaml (`components:` + `postBuild.substitute: {APP: sure}`), with
   dependsOn the cnpg cluster Kustomization and a healthCheck on the Database CR.
3. App-side wiring: ExternalSecret in the app ns assembles `DATABASE_URL`
   (`postgresql://sure:<pass>@postgres-rw.database.svc:5432/sure`) from the same 1P item.

**Phase 6 — sure app**
1. `provision/pocket-id` Terraform: OIDC client `sure`, redirect URI
   `https://fin.${PUBLIC_DOMAIN}/auth/<provider-id>/callback` — the exact path depends on the provider
   id chosen in sure's admin UI, which displays the value to copy; allowed groups per the family-ACL
   decision; client secret into 1Password `pocket-id-clients`. Note: sure keeps SSO providers in its
   database, so the secret is entered in the admin UI too and ends up in Postgres — one more reason
   the Phase 2 backup encryption is mandatory.
2. `kubernetes/apps/selfhosted/sure/`: ks.yaml (components: volsync + cnpg/database; dependsOn
   postgres cluster, dragonfly, onepassword-connect, pocket-id; substitute APP=sure, VOLSYNC_CAPACITY=2Gi)
   + app/{helmrelease,externalsecret,ciliumnetworkpolicy}.yaml.
3. HelmRelease (app-template): two controllers — `server` (web, port 3000, /up liveness+readiness+startup
   probes) and `worker` (sidekiq), shared env anchor: RAILS_ENV=production, SELF_HOSTED=true,
   RAILS_ASSUME_SSL=true (TLS terminates at Envoy), no APP_DOMAIN env (it does not exist in sure); DB_HOST/DB_PORT/POSTGRES_USER/POSTGRES_DB plain env, POSTGRES_PASSWORD + REDIS_URL in the ES template (dragonfly SELECT 2 - paperless takes 1), WEBAUTHN_RP_ID=fin.${PUBLIC_DOMAIN},
   WEBAUTHN_ALLOWED_ORIGINS=https://fin.${PUBLIC_DOMAIN}, SECRET_KEY_BASE + AR-encryption keys envFrom
   sure-secret. SSO is NOT env-configured: sure uses db-backed SSO providers (AUTH_PROVIDERS_SOURCE=db)
   created in the admin UI (/admin/sso_providers) with the Pocket ID issuer, client id/secret and the
   redirect URI from step 1; harden with AUTH_LOCAL_LOGIN_ENABLED=false (SSO-only, removes the local
   password-reset path) and pick AUTH_JIT_MODE deliberately (create_and_link vs link_only, given the
   Pocket ID group ACL). db:prepare runs on web boot (no initContainer - the image entrypoint runs it);
   persistence `sure` existingClaim mounted at /rails/storage by both controllers; resources web
   100m/384Mi→1Gi, worker 50m/256Mi→768Mi (reference-measured).
4. Route: envoy-internal only, hostname `fin.${PUBLIC_DOMAIN}` (k8s-gateway serves it on LAN);
   homepage annotations; CNP: custom-egress label + egress to database (5432, 6379) + allow-world for
   bank/provider syncs initially (the set of FQDNs is open-ended — tighten per egress-fqdn-allowlisting
   once the provider list settles).
5. Onboarding is NOT an env var — it is a DB-stored app setting (Settings → Self-Hosting → Onboarding:
   Open / Invite-only / Closed), so it cannot be flipped via the HelmRelease. Register immediately after
   the rollout lands (the first user becomes super_admin; a DB lock guards the race), then close it in
   the admin UI — mandatory security step, do not leave open.

**Phase 7 — verification + restore drill**
See Verification below.

### Verification

- `kubectl -n database get cluster postgres` → 1 ready instance; nightly dump present in the NAS /backups/postgres tree and the next resticprofile run carries it offsite (there is no Backup CR - barman is gone).
- Restore drill: load the latest dump into a scratch DB (`sure_restore_test`), verify tables, then drop it.
- sure: /up probes pass through a full reconcile; db:prepare completed; first user registered and
  promoted to super_admin; onboarding shows Closed in the admin UI (DB setting, not an env);
  Pocket ID login works; passkey registration works; local login form absent
  (AUTH_LOCAL_LOGIN_ENABLED=false).
- paperless: post-migration consume + scheduled tasks healthy, Hubble shows no POLICY_DENIED on the new
  redis egress path.
- Renovate: cnpg chart + PG image, dragonfly operator + image, sure image (ghcr.io/we-promise/sure, tag
  pinned by digest) all tracked.

### Open questions / risks

- [question] Dragonfly multi-DB support: the references successfully use DB indexes (`SELECT`) against
  Dragonfly, but verify at implementation; fallback is key-prefix isolation on db 0.
- [question] SMTP: no in-cluster mail relay exists today. Email is needed only for local password resets
  and notifications; with AUTH_LOCAL_LOGIN_ENABLED=false there is no local login and no password reset
  at all — likely deferrable entirely, decide at implementation.
- [risk] First-user bootstrap race: between rollout and closing onboarding in the admin UI the app is
  open to the LAN (internal-only, still). Register immediately after the rollout lands, before
  sharing the URL.
- [risk] Active Record encryption keys are load-bearing for bank-sync credentials: generate once into
  1Password, never casually rotate (rotation requires the documented backfill rake task).
- [note] Market-data provider keys (TwelveData/Tiingo/etc.) and AI features are optional add-ons; the
  app degrades gracefully without them — out of scope for the first cut.
- [note] Phases 1-5 are reusable platform work benefiting any future Postgres/Redis app; only phase 6-7
  are sure-specific. If sequencing matters, phases 1-4 can land and soak independently of sure itself.
