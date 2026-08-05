---
title: pod-garbage-collector
type: progress-note
permalink: home-ops/docs/progress/pod-garbage-collector
---

# pod-garbage-collector

## Scope

A single kube-system CronJob (pod-garbage-collector, bjw-s app-template v5.0.1) that automates a safer gated subset of the existing `just k8s prune-pods` recipe. Schedule `*/15 * * * *`, `concurrencyPolicy: Forbid`, `successfulJobsHistory: 1`, `failedJobsHistory: 2`, `ttlSecondsAfterFinished: 3600`. RBAC is least-privilege (pods list/delete only) via a co-located rbac.yaml; the ServiceAccount is chart-generated (default name = release name). Runs non-root (uid 65532), read-only rootfs, dropped capabilities, seccomp RuntimeDefault. Image alpine/k8s:1.36.2 pinned by digest with a # renovate: annotation. Registered in kubernetes/apps/kube-system/kustomization.yaml; Flux Kustomization at kubernetes/apps/kube-system/pod-garbage-collector/ks.yaml (targetNamespace kube-system, prune true). A co-located prometheusrule.yaml alerts on stuck-Terminating pods the sweep intentionally skips.

## Sweep specification

Three sweeps, all cluster-wide via `kubectl get pods --all-namespaces -o json | jq`:

- **S1 — Failed pods older than 1h.** status.phase=Failed with status.startTime older than 3600s. Deleted (kubectl delete pod --ignore-not-found).
- **S2 — Succeeded pods older than 1h, excluding Job-owned.** status.phase=Succeeded, startTime older than 3600s, AND no ownerReferences of kind==Job (Job-owned Succeeded pods are left to Job history limits / ttlSecondsAfterFinished). Deleted.
- **S3 — Pods stuck Terminating >10min with NO finalizers.** metadata.deletionTimestamp older than 600s AND metadata.finalizers is empty. Force-deleted (kubectl delete pod --grace-period=0 --force --ignore-not-found).

## What was deliberately left out, and why

- **Pending pods excluded.** The de-facto spec (just k8s prune-pods) deletes Pending too, with no age gate. Pending pods are often legitimate workloads waiting for resources/scheduling on this single-node cluster; deleting them without an age gate risks killing real workloads mid-schedule. Pending was dropped for safety.
- **S3 finalizer filter is load-bearing.** Force-deleting a finalizer-blocked pod (VolSync replication sources, external-secrets finalizers, PVC deletes waiting on volume detach) orphans the underlying resource — the resource's controller loses its handle. On this cluster the storage backend is democratic-csi local-hostpath (not FUSE/NFS), so the upstream clouddrop root cause (FUSE D-sleep) does not apply; stuck-Terminating here is finalizer-driven, so finalizer-bearing pods are skipped on purpose and surface via the PodStuckTerminating PrometheusRule (expr: (time() - kube_pod_deletion_timestamp) > 900, for: 15m, severity warning) instead.

## null-startTime guard (PHASE 3 required fix)

Admission-rejected pods (UnexpectedAdmissionError, OutOfcpu/OutOfmemory, common after node reboots) can be phase=Failed with a null status.startTime. The original jq expression (.status.startTime | fromdateiso8601) errors on null (strptime/1 requires string inputs), and under set -eu the failed pipe aborts the entire sweep — later sweeps never run. Fix applied to both S1 and S2: a select(.status.startTime != null) guard BEFORE the age filter, plus a separate no-startTime list that is logged (skip (no startTime): $ns/$pod) and counted in the summary line, but NOT deleted without an age check. S3 is unaffected (select(.metadata.deletionTimestamp != null) already guards). Verified with a local jq unit test (mock JSON with one null-startTime and one valid startTime pod) and by the live smoke run.

## Evidence base

PHASE 1 (read-only):
- E1 — Reference manifest: clouddrop pod-garbage-collector (3 sweeps, every 10min, cluster-wide list/delete). Adapted, not copied.
- E2 — Live cluster: no dead pods at observation time (0 Failed/Succeeded/stuck-Terminating); consistent with native Job/CronJob TTL cleanup holding the steady state. Not disproof — dead pods accumulate after node reboots.
- E3 — Storage backend is democratic-csi local-hostpath; stuck-Terminating root cause is finalizer-driven, not FUSE D-sleep.
- E4 — kube_pod_deletion_timestamp metric confirmed present in live Prometheus (kube-state-metrics emits it for pods with a deletionTimestamp); the PrometheusRule expr is valid.
- E5 — Image alpine/k8s:1.36.2 has no USER / WorkingDir /apps / Cmd /bin/sh; runs non-root under runAsUser 65532 + readOnlyRootFilesystem + HOME=/tmp (writable emptyDir). Risk closed (Maestro-verified from registry config blob).

PHASE 1B (gap analysis):
- T1 — Upstream clouddrop manifest enumerated: 3 sweeps (Failed>1h, Succeeded>1h non-Job, stuck-Terminating>10min force-delete), schedule */10, Forbid, history 1/2, ttl 3600.
- T2 — Existing just k8s prune-pods recipe (kubernetes/mod.just) is the de-facto spec: deletes Failed/Pending/Succeeded cluster-wide with NO age gate, NO Job exclusion, NO force. More aggressive than upstream.
- T3 — Gap analysis: this CronJob is a safer gated subset of prune-pods (adds age gates + Job exclusion + finalizer safety + Pending drop).
- T4 — Reboot-after-evidence: admission-rejected Failed pods with null startTime are the post-reboot accumulation case the sweep must handle (drove the PHASE 3 null-guard fix).

## Smoke run (live, 2026-08-05T15:36:12Z)

Job pgc-smoke-1 created from the CronJob, completed successfully (succeeded=1, non-root uid 65532 verified from pod securityContext: runAsNonRoot=true, runAsUser=65532, readOnlyRootFilesystem=true, allowPrivilegeEscalation=false, capabilities drop ALL, seccompProfile RuntimeDefault). Full log:

```
=== pod-garbage-collector run 2026-08-05T15:36:12Z ===
S1 Failed>1h: found=0 (no-startTime skipped=0)
S2 Succeeded>1h (non-Job): found=1 (no-startTime skipped=0)
  delete default/node-debugger-k8s-cp0-9qhcx
pod "node-debugger-k8s-cp0-9qhcx" deleted from default namespace
S3 stuck-Terminating>10m (no finalizers): found=0
=== cleanup complete ===
```

S2 deleted one real dead pod (default/node-debugger-k8s-cp0-9qhcx, a Succeeded >1h non-Job-owned node-debugger pod from a prior debug session). The (no-startTime skipped=N) format in the S1/S2 summary lines confirms the null-guard code path executed in production. S1/S3 found 0, consistent with E2.

## Deploy state

- Flux Kustomization pod-garbage-collector (kube-system): READY=True, Applied revision refs/heads/main@sha1:366c273e.
- HelmRelease pod-garbage-collector (kube-system): READY=True, Helm install succeeded ... app-template@5.0.1.
- CronJob pod-garbage-collector (kube-system): schedule */15 * * * *, ACTIVE 0.
- RBAC: ClusterRole pod-garbage-collector (pods list/delete) + ClusterRoleBinding to chart-generated SA pod-garbage-collector.

## Follow-up — pre-existing orphan RBAC (NOT introduced by this work; needs Maestro decision)

Verify-don't-trust surfaced a leftover from a prior (~2026-05-18) experiment with the same release name: ClusterRole system:controller:pod-garbage-collector + ClusterRoleBinding system:controller:pod-garbage-collector (the system:controller: prefix is NOT a Kubernetes built-in — it is a false-controller orphan). The binding references the same chart-generated SA, so the CronJob pod currently also holds this leftover role's permissions: pods watch, nodes get/list/watch, pods/status patch (on top of the intended pods list/delete). Impact is low (read-only on nodes + pods watch + a pods/status patch write; no secrets, no node mutation, no pod delete beyond the intended role), but it violates least-privilege. This is a pre-existing cluster condition, not introduced by this commit. Recommended cleanup (separate, Maestro-approved, cluster-mutating): kubectl delete clusterrole system:controller:pod-garbage-collector clusterrolebinding system:controller:pod-garbage-collector. Not done here (out of commit scope, cluster-mutating).

## Relations

- implements [[pod-garbage-collector]]
- relates_to [[observability]]
- relates_to [[kubelet-gc-and-flux-deadman-alerts]]
