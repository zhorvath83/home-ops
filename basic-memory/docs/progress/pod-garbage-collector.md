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

## Follow-up — SA collision with the in-tree KCM pod-GC controller (resolved)
The first diagnosis recorded here — that `system:controller:pod-garbage-collector` ClusterRole/Binding was a "false-controller orphan from a prior ~2026-05-18 experiment" to be cleaned up with `kubectl delete` — was WRONG. Acting on it would have deleted live Kubernetes bootstrap RBAC and disrupted the in-tree kube-controller-manager pod-GC (podgc) controller. This section corrects the record to protect future sessions from the same mistake.

**Real facts:**
- `system:controller:pod-garbage-collector` ClusterRole + ClusterRoleBinding are Kubernetes BOOTSTRAP RBAC, not experiment leftovers. They carry the `kubernetes.io/bootstrapping: rbac-defaults` label and the `rbac.authorization.kubernetes.io/autoupdate: true` annotation — the apiserver re-creates them if deleted. They belong to the in-tree KCM podgc controller.
- The KCM runs with `--use-service-account-credentials`, so the podgc controller authenticates as the `kube-system/pod-garbage-collector` ServiceAccount (bound to that bootstrap ClusterRole). The `system:controller:` prefix IS a Kubernetes built-in convention for controller identities, not a false-controller marker.
- The bjw-s app-template chart generates a default ServiceAccount named after the release. The release name `pod-garbage-collector` matched the pre-existing KCM bootstrap SA name, so Helm ADOPTED the bootstrap SA instead of creating a fresh one. The CronJob pod therefore inherited the bootstrap-bound privileges (nodes get/list/watch, pods watch, pods/status patch) on top of the intended pods list/delete — the least-privilege violation the original note correctly surfaced, but mis-attributed to a "prior experiment".
- Prune risk: with `prune: true` on the Flux Kustomization, removing the HelmRelease would have told Helm to delete the adopted SA, invalidating the KCM podgc controller's bound token until KCM restart.

**2-step fix (no control-plane blip):**
- LÉPÉS 1 (commit `0e9bf606d`): `helm.sh/resource-policy: keep` annotation on the adopted `pod-garbage-collector` SA, so Helm cannot delete it on upgrade/removal. Live-verified: `kubectl -n kube-system get sa pod-garbage-collector -o jsonpath={.metadata.annotations}` includes `helm.sh/resource-policy:keep`.
- LÉPÉS 2 (commit `0c6728593`): dedicated, non-colliding SA `pod-gc-sweeper` (chart-generated via `forceRename`, since with >1 SA the chart appends the identifier to the fullname). CronJob `serviceAccountName: pod-gc-sweeper`; rbac.yaml ClusterRoleBinding subject → `pod-gc-sweeper`; ClusterRole unchanged (pods list/delete only). The adopted `pod-garbage-collector` SA is kept (not bound) and protected by the keep-policy.

**can-i evidence (live, 2026-08-05)** — `kubectl auth can-i --as=system:serviceaccount:kube-system:pod-gc-sweeper`:
- `delete pods -A`: **yes** (intended)
- `get nodes`: **no**
- `patch pods/status -A`: **no**
- `watch pods -A`: **no**

The new SA is least-privilege; the bootstrap-inherited privileges are gone. Smoke run `pgc-smoke-2` (2026-08-05T20:06:34Z) completed cleanly with the new SA (S1/S2/S3 ran, no auth errors). The `pod-garbage-collector` SA still exists (AGE 79d, keep-policy protected) — the KCM podgc controller keeps its identity.

**EXPLICIT PROHIBITION — never delete:** the `system:controller:pod-garbage-collector` ClusterRole/ClusterRoleBinding and the `kube-system/pod-garbage-collector` ServiceAccount are in-tree KCM podgc controller identity. They must NEVER be deleted. The apiserver autoupdate re-creates the RBAC, but deleting the SA invalidates the bound token until KCM restart. The `helm.sh/resource-policy: keep` annotation on the SA is the guardrail — do not remove it.
## Relations

- implements [[pod-garbage-collector]]
- relates_to [[observability]]
- relates_to [[kubelet-gc-and-flux-deadman-alerts]]
