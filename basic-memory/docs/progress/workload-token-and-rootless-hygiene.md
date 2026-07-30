---
title: workload-token-and-rootless-hygiene
type: progress-note
permalink: home-ops/docs/progress/workload-token-and-rootless-hygiene
status: done
roadmap: home-ops/docs/roadmap/workload-token-and-rootless-hygiene
related_areas:
- k8s-workloads
- observability
---

# Progress — Token + rootless hygiene for the remaining workloads

Roadmap: [[workload-token-and-rootless-hygiene]] (done, low).

## Scope recap

1. `automountServiceAccountToken: false` on API-less platform pods (onepassword-connect, victoria-logs-server, kopia-maint).
2. Scoped `capabilities.drop` for wallos (keep only SETGID/SETUID/CHOWN php-fpm needs).
3. Non-root path for calibre-web-automated; `readOnlyRootFilesystem` on maintainerr.
4. Verify each app still runs; re-check under PSS warn.

## Session 2026-07-29 — victoria-logs-collector (vlagent) hardened to rootless baseline

### What was done

The vlagent DaemonSet was moved from a root pod to a **rootless baseline** profile in
`kubernetes/apps/observability/victoria-logs/collector/helmrelease.yaml`:

- podSecurityContext: `runAsNonRoot: true`, uid/gid/fsGroup 10001, seccomp `RuntimeDefault`.
- securityContext: `capabilities.drop: [ALL]`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`.
- `persistence.volume: { emptyDir: {} }` + `extraArgs.tmpDataPath: /vlagent-data` — the chart default
  `/var/lib/vl-collector` sits under the read-only `/var/lib` hostPath mount and held the old root pod's
  root-owned persistent queue (EACCES purge loop); moved to a clean writable path.
- `supplementalGroups: [0]` — host container logs are **0640 root:root**; a non-root uid 10001 cannot read
  them, so the pod joins group 0 to read group-root-owned files via group-read. Keeps `runAsNonRoot: true`
  (uid 10001 != 0) — PSS non-root satisfied. Standard pattern (Fluent Bit / Promtail do the same).

### Why the SA token stays mounted

`--kubernetesCollector` enriches logs via the K8s API; the collector SA RBAC is minimal
(get/list/watch on nodes/namespaces/pods). Disabling `automountServiceAccountToken` would break log
collection, so vlagent is intentionally NOT on the tokenless list — unlike the three API-less platform
pods in scope item 1.

### PSS ceiling

vlagent mounts readOnly hostPath (`/var/log`, `/var/lib`) — hostPath is forbidden by `restricted` PSS,
so the ceiling is **baseline** (not restricted). This is an inherent property of any node log collector,
not a gap to close.

### Verification (live)

- `flux reconcile helmrelease victoria-logs-collector --force` → applied revision 0.3.7.
- `kubectl rollout status daemonset/victoria-logs-collector` → successfully rolled out.
- Pod Running, 0 restarts; logs show `started Kubernetes log collector for node "k8s-cp0"`, no FATAL/EACCES.
- Live spec confirmed: podSC `runAsNonRoot:true, runAsUser:10001, supplementalGroups:[0], seccomp RuntimeDefault`;
  containerSC `drop:[ALL], APE:false, readOnlyRootFilesystem:true`.
- Ingestion confirmed: vlserver query API returned a real record
  (`kubernetes.container_name="connect-api"`, `_time=2026-07-29T19:55:45Z`, after the 19:54:22 restart)
  — vlagent reads host logs and ships them.

### Commits (on main — repo norm; Flux watches refs/heads/main)

- `4fdcfaf55` rootless baseline (podSC + containerSC + emptyDir persistence).
- `ee85c080f` `extraArgs.tmpDataPath: /vlagent-data` (fix: tmpDataPath under readOnly /var/lib hostPath).
- `1a80c8bf0` `supplementalGroups: [0]` (fix: non-root uid cannot read 0640 root:root host logs).

### Rootless node-log-collector tension (finding)

Host containerd log files are `0640 root:root`; the symlink in `/var/log/containers` is 0777 but points
to the real file. A uid-10001 collector needs group-0 membership to read them. `supplementalGroups: [0]`
grants read on root-group-readable files under the two readOnly hostPath trees (`/var/log`, `/var/lib`) —
a modest, intended privilege expansion for a log collector. Documented for any future node log collector.

## Next (remaining roadmap items)

- onepassword-connect: chart does not expose `automountServiceAccountToken`; create a dedicated
  tokenless SA and reference via `connect.serviceAccount.name`.
- kopia-maint (KopiaMaintenance CR): no direct automount field on the CRD spec; dedicated tokenless SA.
- wallos: re-add `capabilities: { drop: [ALL], add: [SETGID, SETUID, CHOWN] }`; test php-fpm setgid(82).
- maintainerr: flip `readOnlyRootFilesystem: true` (already rootless; has /tmp + logs emptyDir).
- calibre-web-automated: decision pending — try PUID/PGID non-root, else isolate namespace exception.

## Related

- relates_to [[workload-token-and-rootless-hygiene]]
- relates_to [[pod-security-admission-enforcement]]
- relates_to [[k8s-workloads]]


## Session 2026-07-29 (b) — onepassword-connect token-hygiene (roadmap item 1b)

### What was done

`kubernetes/apps/external-secrets/onepassword-connect/app/helmrelease.yaml` — stopped mounting the
unused default-SA API token on the Connect pod via a Flux `postRenderers` kustomize patch.

- Survey: the connect chart (v2.4.1, source-verified) exposes **no** `automountServiceAccountToken`
  value (neither SA- nor pod-level), and sets `serviceAccountName` only when
  `connect.serviceAccount.create: true` (default false → pod uses `default` SA). A dedicated SA
  can't be made tokenless through values; creating one standalone + `create: true` would duplicate-
  manage the SA object (Helm vs kustomize drift). So the only clean path is a pod-level override via
  postRenderer — the HelmRelease minimal-spec policy's explicit exception ("chart leaves no other way").
- Patch: strategic-merge on the rendered Deployment setting
  `spec.template.spec.automountServiceAccountToken: false` (repo's first Flux postRenderer; styled
  after the flux-instance full-resource patch). Validated independently by the weisssrv reference repo,
  which applies the identical patch with the same rationale.

### Why tokenless is safe

Connect (connect-api + connect-sync) serves ESO from its local encrypted cache and never calls the K8s
API. The default-SA token it mounted was unused.

### Verification (live)

- `flux reconcile helmrelease onepassword-connect --force` → applied revision 2.4.1 (UpgradeSucceeded).
- New pod `onepassword-connect-ffd4f99f5-cc2jb` rolled out (new template hash; old pod replaced).
- Live: pod `automountServiceAccountToken=false`; pod volumes are only `shared-data`,
  `credentials`, `k8tz` — the auto-injected `kube-api-access-*` projected volume is **gone**; no
  `serviceaccount` mount path in any container (token file no longer exists).
- ClusterSecretStore `onepassword-connect` Ready=True, Valid; ESO ExternalSecrets across namespaces
  (cert-manager, crowdsec, …) remain Ready=True — secret delivery unaffected.

### Commit (main)

- `28192be75` `🔒 fix(onepassword-connect): stop mounting unused API token` (postRenderers patch).

## Updated roadmap status

- 1a victoria-logs-server — done (already hardened).
- **1b onepassword-connect — done (this session).**
- 1c kopia-maint — TODO (dedicated tokenless SA for the KopiaMaintenance CR job).
- 2 wallos scoped caps — TODO.
- 3 calibre-web-automated non-root — decision pending.
- 4 maintainerr roRoot — TODO.


## Session 2026-07-29 (c) — kopia-maint token-hygiene (roadmap item 1c)

### What was done

`kubernetes/apps/volsync-system/volsync/maintenance/` — stopped mounting the unused default-SA
API token on Kopia maintenance job pods via a dedicated tokenless SA, referenced through the
CRD-native `spec.serviceAccountName`.

- New `serviceaccount.yaml`: `ServiceAccount/kopia-maintenance` in `volsync-system` with
  `automountServiceAccountToken: false`; added to `maintenance/kustomization.yaml`.
- `kopiamaintenance.yaml`: set `spec.serviceAccountName: kopia-maintenance`.

### Source-verified operator behavior (perfectra1n/volsync fork)

Before editing I confirmed the CRD field is honored — the CRD schema having a field does NOT
guarantee the operator consumes it:

- `api/v1alpha1/kopiamaintenance_types.go`: `KopiaMaintenanceSpec.ServiceAccountName *string`
  (optional), doc "allows specifying a custom ServiceAccount for maintenance jobs".
- `internal/controller/kopiamaintenance_controller.go` has TWO paths:
  - **CronJob path** (`buildMaintenanceCronJob` + `ensureCronJob`): reads
    `maintenance.Spec.ServiceAccountName`, defaults to `"default"` when nil, sets it on the pod
    template, and updates an existing CronJob when it differs. ✅ honored.
  - **manual Job path** (`ensureMaintenanceJob`): does NOT set ServiceAccountName — manual-trigger
    jobs always use `default`, ignoring `spec.serviceAccountName`. ❌
- Our CR uses `trigger.schedule` (not `trigger.manual`), so it goes through the CronJob path and
  the field is honored. **Caveat logged**: if a future CR switches to `trigger.manual`, the SA field
  would be silently ignored — keep schedule triggers for this hardening to hold.

### Why tokenless is safe

Kopia maintenance jobs talk to OVH S3 + the Kopia repo (auth from the `volsync-secret`
ExternalSecret), never the K8s API. The default-SA token they mounted was unused; the job needs no
RBAC (no RoleBinding required).

### Verification (live)

- Flux KS `volsync-maintenance` auto-reconciled on push → Applied revision @sha1 367a6b8e0.
- `ServiceAccount/kopia-maintenance` present with `automount=false`; CR
  `spec.serviceAccountName=kopia-maintenance`; the operator updated the CronJob's pod template
  `ServiceAccountName` from `default` → `kopia-maintenance` (automount stays null on the template —
  no pod-level override, so the pod inherits the SA's false).
- Triggered a one-off verify job via `kubectl create job --from=cronjob/...`:
  - Verify pod `serviceAccountName=kopia-maintenance`; volumes only `tmp`, `kopia-cache`, `k8tz` —
    **no `kube-api-access-*` projected volume**, no `serviceaccount` mount path (token gone).
  - Job ran real maintenance (logs: quick → full) and completed **Complete 1/1 in 3m5s** —
    maintenance function fully intact under the tokenless SA.
- Verify job deleted after (own mess); SA retained.

### Commit (main)

- `367a6b8e0` `🔒 fix(kopia-maint): stop mounting unused API token` (SA + kustomization + CR field).

## Updated roadmap status

- 1a victoria-logs-server — done.
- 1b onepassword-connect — done.
- **1c kopia-maint — done (this session).**
- 2 wallos scoped caps — TODO.
- 3 calibre-web-automated non-root — decision pending.
- 4 maintainerr roRoot — TODO.

Roadmap item 1 (disable automount on API-less platform pods) is now **fully complete** across all
three targets (1a/1b/1c). Remaining work is items 2–4 (rootless/caps hardening, not token hygiene).


## Session 2026-07-29 (d) — wallos scoped caps: accepted exception (roadmap item 2)

Investigated then **dropped as a won't-do** per operator + community evidence. The roadmap step 2
(scoped `capabilities: { drop: [ALL], add: [SETGID,SETUID,CHOWN] }`) is a dead end: php-fpm's www pool
drops to gid 82 at startup needing CAP_SETGID, and dropping ALL caps (even with scoped re-adds)
crashloops the container. Confirmed empirically ("már próbáltam, más is próbálta, gyakorlatilag semmiben
nem lehet") and by the manifest's own inline error note at
`kubernetes/apps/selfhosted/wallos/app/helmrelease.yaml:58`
(`ERROR: [pool www] failed to setgid(82): Operation not permitted (1)`).

No manifest change — wallos is already at its hardening floor: root (runAsUser 0) but tokenless
(`automountServiceAccountToken: false`), seccomp `RuntimeDefault`, `allowPrivilegeEscalation: false`,
`readOnlyRootFilesystem: false` required (php-fpm writes /var/log/startup.log). The existing inline
comment is the accurate record. Recorded as an accepted exception in the roadmap note.

## Updated roadmap status

- 1a victoria-logs-server — done.
- 1b onepassword-connect — done.
- 1c kopia-maint — done.
- **2 wallos scoped caps — accepted exception / won't-do (root + default caps required by php-fpm setgid(82)).**
- 3 calibre-web-automated non-root — decision pending.
- 4 maintainerr roRoot — TODO (next, clean win).


## Session 2026-07-29 (e) — maintainerr roRoot + calibre-web-automated: accepted exceptions; roadmap closed

Both remaining items are **accepted exceptions** per operator experience — no manifest changes:

- **4 maintainerr readOnlyRootFilesystem** — won't-do. The image does not support a read-only rootfs
  even with the existing emptyDir mounts for `/tmp` and `/opt/data/logs`; the app writes elsewhere and
  crashloops under roRoot. maintainerr stays at its floor: rootless (runAsUser 10001), tokenless,
  `drop: [ALL]`, APE false, seccomp RuntimeDefault, `readOnlyRootFilesystem: false` (required).
  Corrects my earlier survey claim ("roRoot biztonságosan beállítható") — that was an unverified
  assumption; the image does not support it.
- **3 calibre-web-automated non-root** — won't-do ("cwa nem szigorítható"). S6-overlay root image
  (runAsUser 0, APE=true, caps add [CHOWN,SETUID,SETGID,FOWNER,DAC_OVERRIDE]); cannot run non-root.
  This is the roadmap's documented-exception option. cwa is the `media` namespace PSS blocker.

## Final roadmap status — RESOLVED

- 1a victoria-logs-server — done.
- 1b onepassword-connect — done.
- 1c kopia-maint — done.
- 2 wallos scoped caps — accepted exception (php-fpm setgid(82)).
- 3 calibre-web-automated non-root — accepted exception (S6-overlay root).
- 4 maintainerr roRoot — accepted exception (no roRoot support).

Token-hygiene goal fully achieved (no API-less workload mounts an unused token). Rootless achieved
where images allow; wallos, cwa, maintainerr at image-imposed floors with documented rationale. These
three are the PSS-enforcement blockers tracked in `docs/roadmap/pod-security-admission-enforcement`.

## Session 2026-07-29 (f) — cluster seccomp sweep: volsync movers + kopia-maint + 4 chart gaps

### Trigger: the user asked to re-scan the cluster for anything NOT covered by the earlier survey

The earlier survey (sessions a–e) focused on **root / token / caps** of app Deployments. A new
cluster-wide scan with a **refined detector** (pod- AND container-level seccomp/runAs, not pod-only)
surfaced a different hardening dimension: **seccomp**. Pod-only checking had produced false-positive
"widespread NO-SECCOMP" on external-secrets / flux / envoy / grafana / prometheus-adapter — those set
seccomp at container level, which pod-only checking missed. After refining, the genuine gaps were:

- **VolSync mover pods** (all `volsync-src-*` kopia movers) — operator-spawned, not covered by the
  earlier app-Deployment survey. Root cause: the shared `components/volsync/` component's
  `moverSecurityContext` set runAsUser/Group/fsGroup but **no seccompProfile**. The fork CRD supports
  `kopia.moverSecurityContext.seccompProfile` (source-verified).
- **4 chart-level workloads** with no seccomp: victoria-logs-server, grafana-operator,
  prometheus-blackbox-exporter, kopia UI.
- System/inherent pods (cilium, coredns, democratic-csi, control plane, node-exporter, vlagent
  hostPath) — out of scope; accepted exceptions (wallos/cwa/maintainerr) confirmed still standing.

### A — volsync mover seccomp (shared component, one place, whole fleet)

`kubernetes/components/volsync/replicationsource.yaml` + `replicationdestination.yaml` — added
`seccompProfile: { type: RuntimeDefault }` to `moverSecurityContext`. **seccomp only — no
runAsNonRoot**: backrest overrides `APP_UID=0` (verified in `backrest/ks.yaml`), so a pod-level
non-root gate would reject the backrest mover; RuntimeDefault is root-safe. Verified live: backrest
ReplicationSource `moverSecurityContext={runAsUser:0,runAsGroup:0,fsGroup:0,seccompProfile:RuntimeDefault}`
— confirms the no-runAsNonRoot decision was correct.

### B — kopia-maint seccomp + re-verification of the token fix

`kopiamaintenance.yaml` — added `podSecurityContext` with `seccompProfile: RuntimeDefault` +
replicated operator defaults (`runAsNonRoot: true, runAsUser: 1000, fsGroup: 1000`). **Replace
semantics** (source-verified in `kopiamaintenance_controller.go` `ensureCronJob`: CR
podSecurityContext is used as-is when set, else operator defaults) — so the defaults must be
replicated alongside seccomp to avoid regress. Container secctx left at operator defaults.

**Live verification (triggered job `kopia-maint-seccomp-test` from the CronJob):**
- pod secctx: `{fsGroup:1000, runAsNonRoot:true, runAsUser:1000, seccompProfile:{type:RuntimeDefault}}` ✅
- container secctx: operator defaults preserved (drop ALL / APE false / roRoot true / runAsNonRoot) ✅
- SA=`kopia-maintenance`; volumes only `tmp, kopia-cache, k8tz` — **no `kube-api-access-*` token** ✅
- job **Succeeded** — seccomp did not break kopia maintenance ✅
- contrast: a pre-change scheduled job pod (`...297552m4rr`) had SA=default + `kube-api-access-wvzpb`.

### Clarification on the kopia-maint token fix (honest correction of a mid-turn misread)

Mid-turn I flagged the token fix as "committed but unverified live" because the in-cluster **scheduled**
completed jobs (12:30 / 18:30 UTC) still showed SA=default + a mounted token. That was a **misreading**:
those scheduled jobs ran **before** the SA commit (`367a6b8e0` = 20:23 UTC; the 18:30 UTC job predates it)
— they are historical completed jobs that the next scheduled run (00:30 UTC) will supersede. Session (c)
verified the fix via a **triggered** one-off job (post-commit), which is the correct verification path, and
**today's triggered job re-confirms it** (kopia-maintenance + no token). The fix was and is verified; the
pre-change scheduled jobs are expected history, not a fix failure. Test job deleted after (own mess).

### Commits (main)

- `ae50b4452` `🔒 security(volsync): add seccompProfile to kopia mover pods` (shared component).
- `4df63fff6` `🔒 security(kopia-maint): add seccompProfile to maintenance jobs` (CR podSecurityContext).

### C — chart-level seccomp (implemented + live-verified)

All 4 are **values-fixable** (no postRenderer needed), each a small `seccompProfile` add to the HR:

- **kopia UI** (`volsync-system/kopia`, bjw-s app-template): add to existing
  `controllers.kopia.pod.securityContext` (already has pod secctx).
- **prometheus-blackbox-exporter**: add to existing top-level `securityContext` (chart applies at pod
  level); keeps the NET_RAW add for ICMP probing.
- **victoria-logs-single**: chart exposes `server.podSecurityContext` (default
  `{enabled:true, fsGroup:2000, runAsNonRoot:true, runAsUser:1000}`) — set it with defaults + seccomp.
- **grafana-operator** (5.24.0, `helm show values`-verified): chart exposes `podSecurityContext: {}`
  (default empty) and `securityContext` (container) — set `podSecurityContext: {seccompProfile:{type:RuntimeDefault}}`.

### Roadmap status note

This seccomp dimension was discovered **after** the token/rootless roadmap was closed (session e). It is a
related but separate hardening theme (PSS `restricted` requires seccomp). C is surveyed for a follow-on
decision; A, B, and C are all done and live-verified.

### C — implementation + live verification

Implemented as one commit (`cf478ad97` `🔒 security(observability): add seccompProfile to 4 chart-managed
workloads`) — all 4 are values-fixable, no postRenderer. Each edit:

- **kopia UI** (bjw-s app-template 5.0.1): `controllers.kopia.pod.securityContext.seccompProfile` (pod-level).
- **prometheus-blackbox-exporter** (11.16.0): container `securityContext.seccompProfile` — the chart applies its
  top-level `securityContext` at **container** level (live: pod secctx empty, container secctx holds caps+runAs);
  keeps the `NET_RAW` add for ICMP probing.
- **victoria-logs-single** (0.13.9): `server.podSecurityContext` replicating the chart default
  (`enabled: true, fsGroup: 2000, runAsNonRoot: true, runAsUser: 1000`) + seccomp.
- **grafana-operator** (5.24.0, `helm show values`-verified top-level `podSecurityContext: {}`): set
  `podSecurityContext: {seccompProfile: RuntimeDefault}`; container secctx stays at chart defaults
  (drop ALL / APE false / roRoot true / runAsNonRoot).

**Live verification** (after `flux reconcile` of all 4 HRs + rollout):

| workload | seccomp location | live value | pod health |
|---|---|---|---|
| kopia | pod | RuntimeDefault | Running, 0 restarts |
| prometheus-blackbox-exporter | container | RuntimeDefault | Running, 0 restarts |
| victoria-logs-server | pod | RuntimeDefault | Running, 0 restarts |
| grafana-operator | pod | RuntimeDefault | Running, 0 restarts |

All rollouts succeeded; seccomp did not break any workload. The 4 chart-level gaps are closed.


## Session (g) — node-exporter full container hardening (2026-07-29)

Follow-on to the cluster seccomp sweep (session f, option C). The user approved "full container
hardening" for node-exporter: seccomp RuntimeDefault + drop ALL + APE false + readOnlyRootFilesystem.

**File**: `kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml` — added a
`containerSecurityContext` block under `prometheus-node-exporter:` (replace semantics: the
subchart 4.56.1 renders `.Values.containerSecurityContext` via `with/toYaml`, so the block
replaces the chart default of `{readOnlyRootFilesystem:true}` with commented-out caps).

```yaml
containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
```

node-exporter needs no caps (nobody uid 65534, port 9100); the `permissionInitContainer`
(root init) still chowns powercap/slabinfo host files for the energy/slab collectors, so the
main container's dropped caps don't affect those collectors.

**Commit**: `11e29040d` 🔒 security(observability): harden node-exporter container.

**Gotcha (recorded for future sweeps)**: the first `flux reconcile helmrelease` re-applied
revision 87.21.0 with the OLD values because the `flux-system` GitRepository had not yet
fetched the new commit — the DaemonSet pod template was unchanged and the 7d-old pod stayed.
The fix is to `flux reconcile source git flux-system` FIRST (fetches the new commit), THEN
`flux reconcile helmrelease`. After that the DS template updated and a fresh pod rolled.

**Live verification**:
- DS template container secctx: `{allowPrivilegeEscalation:false, drop[ALL], readOnlyRootFilesystem:true, seccompProfile:RuntimeDefault}`
- Running pod spec matches exactly.
- New pod `...-dd77g` Running, 0 restarts; `rollout status` = successfully rolled out.
- `node_uname_info` scraped from Prometheus = 3 series, value 1 → collector alive and scraping
  post-hardening (seccomp + drop ALL did not break the collector).

**Result**: node-exporter is now full container-hardened (rootless + tokenless already in place;
seccomp + drop ALL + APE false + roRoot now added). The cluster seccomp sweep (sessions f–g) is
complete: A (volsync mover), B (kopia-maint), C (4 charts), and node-exporter all done + live-verified.
