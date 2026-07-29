---
title: workload-token-and-rootless-hygiene
type: progress-note
permalink: home-ops/docs/progress/workload-token-and-rootless-hygiene
status: in-progress
roadmap: home-ops/docs/roadmap/workload-token-and-rootless-hygiene
related_areas:
- k8s-workloads
- observability
---

# Progress — Token + rootless hygiene for the remaining workloads

Roadmap: [[workload-token-and-rootless-hygiene]] (proposed, low).

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
