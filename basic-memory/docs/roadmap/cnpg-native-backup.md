---
title: cnpg-native-backup
type: roadmap
permalink: home-ops/docs/roadmap/cnpg-native-backup
topic: Replace the pg_dumpall CronJob + NAS/resticprofile offsite copy with CNPG-native
  physical backups via the Barman Cloud plugin on OVH S3, gaining WAL archiving and
  PITR
status: planned
priority: medium
scope: One new Flux unit (plugin-barman-cloud HelmRelease), an ObjectStore CR + ExternalSecret,
  an atomic Cluster plugins change, a ScheduledBackup, one PrometheusRule with promtool
  unit tests, a Terraform bucket addition, encryption of base backups and WAL at the
  object store, and the repositioning (not removal) of the postgres-backup CronJob
  as the confidentiality-grade offsite copy after a live restore drill. The resticprofile
  /backups plane is untouched.
rationale: The pg_dumpall-to-NAS pipeline is a custom-script workaround for what CloudNativePG
  provides natively (physical base backups + WAL archiving + PITR). The in-tree barmanObjectStore
  path is deprecated and is removed in operator 1.31.0, so the CNPG-I Barman Cloud
  plugin is the only future-proof route. The cluster already runs operator 1.30.1
  with cert-manager, and the OVH S3 plane has a proven ExternalSecret pattern shared
  with the volsync and resticprofile consumers. Barman's encryption is server-side
  only (OVH-managed keys, transparent to any S3 credential holder), so the client-side-encrypted
  dump export is deliberately retained for confidentiality-grade offsite copies of
  the sensitive financial data.
related_areas:
- ovh-storage
- resticprofile-backup
- external-secrets
- observability
options:
- Barman Cloud plugin (chosen - only route that survives the 1.31.0 in-tree removal)
- In-tree barmanObjectStore (rejected - deprecated, removed in operator 1.31.0)
- VolumeSnapshot backup method (rejected - democratic-csi local-hostpath CSI snapshot
  support unverified; single-node volume snapshots add nothing over S3 offsite anyway)
- Drop the dump CronJob entirely at cutover (rejected - barman backup objects are
  transparent to any holder of the S3 credential under SSE-OMK; the restic-encrypted
  dump copy is the only client-side-encrypted offsite copy, and the DB holds sensitive
  financial data)
- pg_tde cluster-level transparent encryption (rejected for MVP - experimental Percona
  extension, custom CNPG image, in-cluster key management; would encrypt backups client-side
  but adds a large surface for a home cluster)
- Dedicated OVH S3 user for the CNPG bucket (deferred hardening - reduces cross-plane
  credential blast radius; owner decision)
tags:
- cnpg
- postgres
- backup
- barman
- pitr
- encryption
- ovh-storage
- database
---

# CNPG native backup — Barman Cloud plugin on OVH S3

Replace the daily pg_dumpall CronJob's role as the RECOVERY path (NAS /backups, 14 local
copies, resticprofile offsite) with CNPG-native physical backups: base backups + continuous
WAL archiving to a dedicated OVH S3 bucket via the CNPG-I Barman Cloud plugin, with a
recovery-window retention policy and point-in-time recovery. The dump CronJob is retained
in a reduced role as the confidentiality-grade offsite copy (client-side restic encryption),
mirroring the Paperless dual-coverage pattern. Rides existing planes only: OVH S3 Terraform
provisioning, ExternalSecrets (ovh 1Password item), cert-manager, the cnpg-postgres
PodMonitor, and the Alertmanager -> Pushover alerting plane.

## Metadata (observation-form)

- [topic] CNPG native backup — physical barman backups + PITR on OVH S3 via the Barman Cloud plugin; dump export retained as confidentiality-grade copy
- [status] planned
- [priority] medium
- [area] database / ovh-storage / observability / security
- [created] 2026-10-11
- [effort] M — one new platform unit + one Cluster change + repositioning of the dump job, with a live restore drill as the gate

## Current state (verified 2026-10-11)

- [observation] The shared CNPG cluster runs operator 1.30.1 (live: ghcr.io/cloudnative-pg/cloudnative-pg:1.30.1 in database ns; chart 0.29.1 at apps/database/cloudnative-pg/app/ocirepository.yaml:14), one Cluster 'postgres', one instance, 10Gi democratic-csi-local-hostpath PVC, enableSuperuserAccess (apps/database/postgres/app/cluster.yaml).
- [observation] Only one database exists today: 'sure' (live Database CR, 4d9h old, applied) — family/personal finance app, sensitive data by definition. New app DBs arrive as CNPG Database CRs on the same Cluster (components/cnpg/database/database.yaml), so an instance-level physical backup automatically covers future DBs.
- [observation] Current backup: postgres-backup CronJob, daily 00:17 Europe/Budapest, pg_dumpall | gzip -> NAS /backups/postgres/postgres-YYYY-MM-DD.sql.gz, atomically via .partial, keeps the newest 14 files (apps/database/postgres/app/backup/helmrelease.yaml:29,49-55). Explicitly no PITR — worst case 1 day of data loss, restore is manual (manifest comment, helmrelease.yaml:3-4).
- [observation] Confidentiality posture of the current planes: the NAS /backups dumps are PLAINTEXT on NFS (local plane, LAN trust boundary); the offsite copies are CLIENT-SIDE encrypted — restic encrypts with RESTIC_PASSWORD and kopia with KOPIA_PASSWORD before upload, so OVH only ever stores ciphertext. The 1Password 'ovh' item's S3 credential is shared by all three consumer planes (volsync, resticprofile, and the future CNPG bucket).
- [observation] Offsite copy: resticprofile backs up the whole /backups NFS tree daily 01:00 to OVH S3 with GFS retention 1h/7d/4w/12m + prune (apps/selfhosted/resticprofile/app/config/profiles.yaml:65-75). This plane stays; it serves the other curated exports.
- [observation] OVH S3: buckets provisioned from the S3_BUCKET_NAMES list (op://Private/OVHcloud/list_of_s3_buckets via provision/ovh/.env), region DE, endpoint s3.de.io.cloud.ovh.net; the s3:* policy iterates the same list (provision/ovh/user.tf:12-29), so a new bucket is automatically in scope. 'just ovh apply' re-syncs credentials into the HomeOps/ovh 1Password item (provision/ovh/mod.just).
- [observation] Credentials pattern: both existing consumers template AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_S3_ENDPOINT from the ovh 1Password item via ExternalSecret (components/volsync/externalsecret.yaml:17-26, apps/selfhosted/resticprofile/app/externalsecret.yaml:19-21).
- [observation] Monitoring: the instance manager exporter (port 9187) is scraped by the cnpg-postgres PodMonitor (apps/database/postgres/app/podmonitor.yaml). PrometheusRules carry a mandatory promtool unit-test suite (kubernetes/CLAUDE.md bar).

## Research findings (all verified against live cluster or official sources)

- [observation] In-tree barmanObjectStore is deprecated and REMOVED in operator 1.31.0; the recommended target is the Barman Cloud plugin (CNPG 1.30 release notes, docs/src/release_notes/v1.30.md). Building on the in-tree path now would force a second migration within one operator minor.
- [observation] Barman Cloud plugin 0.15.1: requires operator >=1.26 (recommends >=1.27 — we run 1.30.1), cert-manager for operator<->plugin TLS (deployed in-cluster), and a Deployment in the SAME namespace as the operator (database here). Chart: cnpg/plugin-barman-cloud, HTTP index https://cloudnative-pg.github.io/charts; images ghcr.io/cloudnative-pg/plugin-barman-cloud{,-sidecar}; certificate defaults createClientCertificate/createServerCertificate/createIssuer: true, duration 2160h.
- [observation] Plugin architecture: object store configuration lives in a NEW ObjectStore CR (barmancloud.cnpg.io/v1, same namespace as the Cluster) — destinationPath, endpointURL, s3Credentials, wal settings, and retentionPolicy all move there; the Cluster gains spec.plugins: [{name: barman-cloud.cloudnative-pg.io, isWALArchiver: true, parameters: {barmanObjectName: <store>}}]. The migration guide requires the Cluster change (remove spec.backup + add plugins) to be ATOMIC and warns it triggers a rolling update.
- [observation] ScheduledBackup with the plugin: method: plugin + pluginConfiguration.name: barman.cloud.cloudnative-pg.io; on-demand Backup CR or 'kubectl cnpg backup --method=plugin' also work.
- [observation] PITR: restore = new Cluster with bootstrap.recovery.source -> externalClusters[].plugin (barmanObjectName + serverName of the source cluster). Including spec.plugins on the restored cluster re-enables WAL archiving for it.
- [observation] Retention: recovery-window only (retentionPolicy e.g. "30d" -> barman-cloud-backup-delete --retention-policy "RECOVERY WINDOW OF 30 DAYS"). PoR = now - window; the first valid backup before PoR anchors deletion; obsolete backups are removed after the NEXT backup completes. GFS-style keep-weekly/keep-monthly granularity is NOT available.
- [observation] ENCRYPTION — barman is SERVER-SIDE ONLY: barman-cloud's --encryption accepts AES256 (SSE-S3 style, provider-managed keys) or aws:kms (SSE-KMS, AWS-only); there is NO client-side encryption option in barman-cloud, unlike restic/kopia which encrypt with a locally-held password before upload. CNPG's schema exposes exactly data.encryption / wal.encryption with enum AES256 | aws:kms (operator 1.30 CRD) — the newer barman SSE-C support (aws_sse_customer_key) is NOT reachable through the CNPG/plugin configuration surface.
- [observation] OVH Object Storage SSE matrix (official OVH docs): SSE-OMK/SSE-S3 (AES256 header, OVH-managed per-object AES-256 keys, can be set as bucket default via put-bucket-encryption) — SUPPORTED in all regions; SSE-C (customer-provided keys) — supported by OVH but not wired in CNPG; SSE-KMS (aws:kms) — NOT supported. Consequence: the reachable config for this cluster is data.encryption: AES256 + wal.encryption: AES256 -> OVH SSE-OMK.
- [observation] THREAT MODEL of SSE-OMK vs the current planes: OVH-managed keys encrypt at rest (protects against physical disk loss/disposal) but decryption is TRANSPARENT to any holder of the S3 credential — a leaked ovh item reads the bucket in plaintext. The restic offsite copy is ciphertext to the same attacker. The NAS dumps are already plaintext today, so the local plane's exposure is unchanged either way; the decision is about the offsite copy's confidentiality grade.
- [observation] Plugin metrics (via the instance manager exporter, so scraped by the existing PodMonitor): barman_cloud_cloudnative_pg_io_last_failed_backup_timestamp, barman_cloud_cloudnative_pg_io_last_available_backup_timestamp, barman_cloud_cloudnative_pg_io_first_recoverability_point.
- [observation] Coverage parity: a physical backup is instance-level (whole PGDATA + WAL), so it covers all databases including future ones AND global objects (roles) that pg_dumpall captured — no per-DB wiring, same as today's pg_dumpall behavior.
- [observation] Restore tooling surface: barman backups are restorable only through CNPG recovery (or barman-cli) — unlike today's human-readable .sql.gz. Mitigation: the live restore drill is the cutover gate, and the dump CronJob is retained (not removed), keeping readable copies on NAS and client-side-encrypted copies in restic history.

## Design

1. **Route: CNPG-I Barman Cloud plugin, not in-tree.** The in-tree path dies in 1.31.0; starting on the plugin avoids a second migration and is the officially supported future. The plugin is a small Deployment (database ns) + ObjectStore CRD.
2. **Dedicated bucket.** New bucket appended to S3_BUCKET_NAMES (Terraform + policy follow automatically via 'just ovh apply'). Physical backups are not compatible with the kopia/restic bucket layout; a dedicated bucket keeps the backup contract clean per plane.
3. **Secret wiring follows the ovh-item pattern.** ExternalSecret in database ns rendering ACCESS_KEY_ID/ACCESS_SECRET_KEY from ovh_s3_* fields — identical in shape to the volsync and resticprofile templates. Non-secret identifiers (endpoint URL, bucket path) enter the manifest via the existing Flux cluster-settings substitution pattern (the ${NAS_IP} mechanism, kubernetes/flux/cluster/ks.yaml:16-19) — exact variable split decided at implementation.
4. **Encryption: SSE-OMK (AES256) on base backups and WAL — mandatory, plus retained dump export for confidentiality.** ObjectStore configuration.data.encryption and configuration.wal.encryption set to AES256 (OVH SSE-OMK; aws:kms is unsupported by OVH, SSE-C is unreachable through the CNPG schema). Because SSE-OMK is transparent to any S3-credential holder, the pg_dumpall CronJob is NOT decommissioned: it stays as the confidentiality-grade offsite copy (restic client-side encryption), the Paperless dual-coverage pattern applied to the DB plane. Recovery moves to barman/PITR; the dump's remaining role is confidentiality + human-readable fallback.
5. **Retention: recovery window "30d" (recommended).** Supersedes the current 14 local dumps and exceeds the restic 7-daily coverage for the DB; PITR window = any point in the last 30 days. Storage cost is negligible (sure-only DB on a 10Gi PVC, mostly empty). Alternatives: 14d (mirrors today's local horizon) or 90d.
6. **Cadence: daily base backup, continuous WAL, daily dump export.** ScheduledBackup daily around the current 00:17 local window, immediate: true on rollout so the first base backup lands without waiting a day. WAL is archived continuously -> the data-loss window drops from 1 day to minutes. The dump CronJob keeps its daily cadence (recommended; weekly is the alternative) — its cost is trivial (5m CPU request) and it feeds the 01:00 restic run.
7. **Alerting: PrometheusRule on the plugin metrics.** CnpgBackupStale (time() - last_available_backup_timestamp > 26h, plus absent-case) severity critical; CnpgBackupFailed (failed timestamp more recent than available timestamp) severity warning. Routed by the existing Alertmanager -> Pushover plane; promtool unit-test suite per the repo bar, run via 'just k8s test-prom-rules'.
8. **Rollout is additive-first.** The dump CronJob is never the rollback plane that gets removed — it is part of the steady-state design, so the cutover risk is limited to the barman plane itself.

## Implementation phases

### Phase 0 — OVH S3 provisioning (Terraform)
- Append the new bucket name to the 1Password list op://Private/OVHcloud/list_of_s3_buckets (the source of TF_VAR_S3_BUCKET_NAMES), then 'just ovh apply'. The bucket resource and the s3:* policy entry are created by the existing for_each (provision/ovh/buckets.tf:6-11, user.tf:12-29); credentials re-sync unchanged.
- Optional hardening (owner decision): a dedicated OVH S3 user for the CNPG bucket so the barman credential cannot read the kopia/restic buckets and vice versa (new user.tf resource + separate 1Password item + ExternalSecret).
- Verify: terraform plan shows only the additive bucket (or bucket+user); bucket reachable with the existing ovh credentials.

### Phase 1 — plugin deployment (new Flux unit)
- New unit kubernetes/apps/database/plugin-barman-cloud/ (ks.yaml + app/: helmrelease.yaml + chart source) targeting database ns, dependsOn cloudnative-pg.
- Chart source: verify OCI artifact availability first (repo convention is OCIRepository, e.g. oci://ghcr.io/cloudnative-pg/charts/plugin-barman-cloud); fall back to an HTTP HelmRepository — the repo already has one precedent (components/common/alerts/alertmanager).
- Values: minimal — resources per the user-workload baseline (explicit cpu/memory requests, memory limit), default cert-manager certificate block left on, crds.create true (the root patch injects install.crds CreateReplace anyway).
- Verify: Deployment healthy in database; ObjectStore CRD registered.

### Phase 2 — object store wiring
- ExternalSecret (database ns) from the ovh 1Password item rendering the S3 credential keys for s3Credentials.
- ObjectStore CR (database ns): configuration.destinationPath s3://<bucket>/, endpointURL https://s3.de.io.cloud.ovh.net, s3Credentials -> the ExternalSecret-owned Secret, configuration.data.encryption: AES256, configuration.wal.compression: gzip, configuration.wal.encryption: AES256; spec.retentionPolicy "30d".
- Verify: ObjectStore status reconciled; no secret material in manifests (repo non-negotiable).

### Phase 3 — atomic Cluster change
- Single change to apps/database/postgres/app/cluster.yaml: add the plugins entry (isWALArchiver: true, barmanObjectName). Nothing else in the same edit — atomic per the plugin migration guide. Expect a rolling restart of the postgres pod (brief sure downtime; do it in a maintenance window).
- Network policy check: verify the plugin pod's egress to S3 and the operator/instance gRPC path against the existing policies (postgres CNP is ingress-only today, apps/database/postgres/app/ciliumnetworkpolicy.yaml; decide whether the plugin needs its own CNP).
- Verify: WAL files appear in the bucket (wal/ prefix); first_recoverability_point metric appears on the 9187 exporter.

### Phase 4 — scheduled backups
- ScheduledBackup CR: daily schedule around 00:17 local intent, method: plugin, pluginConfiguration, immediate: true, backupOwnerReference: none. Verify the operator's cron timezone interpretation (the operator pod gets k8tz-injected Europe/Budapest) before pinning the exact string — do not assume; test.
- Verify: first Backup reaches completed; base backup visible in the bucket.

### Phase 5 — restore drill (gate)
- Out-of-band scratch Cluster (documented GitOps exception, like bootstrap/recovery): bootstrap.recovery + externalClusters[].plugin pointing at the ObjectStore (serverName: postgres), targetTime shortly before the drill.
- Verify: cluster Ready, sure DB present, row counts match source, pgvector extension intact. Capture evidence in the progress note, then delete the scratch cluster + PVC.
- This gate must pass before the cutover is declared done.

### Phase 6 — alerting
- PrometheusRule (postgres app or plugin unit, sibling _test.yaml) per design point 7; confirm the metric series are live before finalizing expressions.
- Verify: 'just k8s test-prom-rules' green (positive/negative/boundary/annotation cases per the promtool bar).

### Phase 7 — cutover declaration + docs
- The dump CronJob STAYS (design point 4) — only its runbook role changes: recovery path is PITR/barman, the dump is the confidentiality-grade + human-readable fallback. Update its manifest comment to say so.
- Docs: ADR for the model change (barman PITR as recovery path; dump export retained for confidentiality — including the SSE-OMK transparency rationale); new/updated BM area reference covering the CNPG backup plane (cnpg-backup); resticprofile-backup area note unchanged in scope.
- Encryption verification: base backup and WAL objects in the bucket are SSE-OMK encrypted (x-amz-server-side-encryption: AES256 on upload; or bucket default encryption via put-bucket-encryption).

## Acceptance criteria

1. ObjectStore CR reports ready/configured; no plaintext credentials anywhere in the repo.
2. ScheduledBackup produced at least one completed Backup; bucket contains base backup + WAL.
3. barman_cloud_cloudnative_pg_io_first_recoverability_point advances and is scraped by the cnpg-postgres PodMonitor.
4. Restore drill passed: scratch cluster Ready, sure data matches source (the cutover gate).
5. CnpgBackupStale and CnpgBackupFailed rules pass the promtool suite; one forced-failure path exercised or justified.
6. Encryption verified: base and WAL objects carry server-side encryption (AES256/SSE-OMK); a GET through an S3 client confirms the encryption metadata.
7. Dump export still lands daily in /backups/postgres and rides the 01:00 restic run (client-side-encrypted offsite copy intact).
8. PITR: any point within the retention window is recoverable (recovery-window semantics).

## Open decisions (for the owner)

- Bucket name: the current bucket list was not readable this session (1Password CLI offline); read op://Private/OVHcloud/list_of_s3_buckets at implementation and pick a name following the existing convention (proposed: something like cnpg-postgres-backup, final name owner's call).
- Retention window: 30d recommended; 14d or 90d are the alternatives. GFS granularity is not available — recovery window only.
- Dump CronJob cadence in its new role: DAILY recommended (trivial cost, maximal confidentiality freshness — feeds the same-night restic run); WEEKLY alternative if the daily job is felt to be noise.
- Dedicated OVH S3 user for the CNPG bucket (credential blast-radius reduction across the three backup planes) — optional hardening, owner decision.
- destinationPath/endpointURL injection: Flux cluster-settings substitution (like ${NAS_IP}) vs literal in the ObjectStore manifest. Verify where the cluster-settings ConfigMap is defined during implementation; substitution is the pattern-faithful option.
- Chart distribution: OCI vs HTTP HelmRepository (Phase 1 verification decides).
- ScheduledBackup cron string: verify operator TZ interpretation first (k8tz injects Europe/Budapest into the operator pod; CNPG schedule parsing timezone must be tested, not assumed).
- Whether the plugin pod needs its own CiliumNetworkPolicy (direction of operator<->plugin<->instance traffic).

## Risks and rollback

- Rolling restart of postgres during Phase 3: brief sure downtime — schedule it.
- Single-instance backups run on the primary: I/O overhead on the only instance. Measured reality: sure-only DB, 10Gi PVC, negligible.
- CONFIDENTIALITY: barman objects are transparent to the S3 credential holder under SSE-OMK — weaker than the restic plane. Accepted deliberately: the retained daily dump export keeps a client-side-encrypted offsite copy of the sensitive data, and the local plane was plaintext-on-NAS before this item anyway.
- Restore surface narrows to CNPG/barman tooling: mitigated by the Phase 5 drill as a hard gate plus the retained readable .sql.gz dumps (NAS + restic history).
- New moving part (plugin Deployment + cert-manager certificates): certificates are operator-managed with 2160h duration / 360h renewBefore defaults; alerting covers backup failure, and the plugin pod is a standard Flux-reconciled workload.
- Rollback: barman plane removal is always non-destructive — delete the plugins entry (atomic) and the new Flux unit; the dump pipeline was never touched, so the pre-item recovery capability survives any phase unchanged.

## Sources (retrieved 2026-10-11)

- Live cluster: operator image 1.30.1 (kubectl, database ns); Database CR 'sure'; ObjectStore CRD absent; cronjob postgres-backup last scheduled 13h before the check.
- CNPG 1.30 release notes — in-tree barman removal deferred to 1.31.0, plugin encouraged (github.com/cloudnative-pg/cloudnative-pg, release-1.30 docs/src/release_notes/v1.30.md).
- Operator 1.30 CRD — barmanObjectStore data/wal encryption enum AES256 | aws:kms (releases/cnpg-1.30.0.yaml, release-1.30 branch).
- Barman cloud docs — --encryption AES256 (SSE-S3) / aws:kms (SSE-KMS) only, server-side; newer SSE-C (aws_sse_customer_key) exists in barman core config but not in the CNPG/plugin surface (docs.pgbarman.org release 3.19 barman_cloud + configuration pages).
- OVH docs — S3 compliance and SSE: SSE-OMK/SSE-S3 (AES256) supported all regions, SSE-C supported, SSE-KMS NOT supported (docs.ovhcloud.com s3-s3-compliancy + s3-encrypt-your-objects-with-sse-c).
- Plugin docs 0.15.1 — intro (requirements), installation, usage, retention, migration, observability (cloudnative-pg.io/plugin-barman-cloud/docs/).
- Plugin chart values (github.com/cloudnative-pg/charts, charts/plugin-barman-cloud/values.yaml).
- Repo evidence: apps/database/postgres/app/{cluster.yaml,backup/helmrelease.yaml,podmonitor.yaml,ciliumnetworkpolicy.yaml}, components/cnpg/database/database.yaml, components/volsync/externalsecret.yaml, apps/selfhosted/resticprofile/app/{externalsecret.yaml,config/profiles.yaml}, provision/ovh/{buckets.tf,user.tf,mod.just,.env}, kubernetes/flux/cluster/ks.yaml.
