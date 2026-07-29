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
