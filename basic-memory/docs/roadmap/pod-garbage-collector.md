---
title: pod-garbage-collector
type: roadmap
permalink: home-ops/docs/roadmap/pod-garbage-collector
topic: Periodic cleanup of dead (Failed/Succeeded) and stuck (Terminating) pods via
  a kube-system CronJob, adapted from the clouddrop pod-garbage-collector reference
status: proposed
priority: low
scope: A single kube-system CronJob that reclaims accumulated dead pods and force-deletes
  pods stuck in Terminating past a threshold, reducing etcd/object-store noise and
  unblocking controllers on the single-node cluster. The design must decide which
  of the three upstream cleanup functions are actually needed here (given that CronJobs
  and Jobs already self-clean via history limits and ttlSecondsAfterFinished), what
  thresholds and schedule fit this cluster, and whether force-delete of stuck-Terminating
  pods is safe given the storage backend is democratic-csi local-hostpath (not FUSE/NFS)
  and the node is Talos. Not a mindless port of the clouddrop manifest.
rationale: 'Dead pod objects accumulate in etcd from failed CronJobs, crashed standalone
  pods, and orphaned workloads; on a single bare-metal node these cost memory in the
  API server and clutter debugging. Pods stuck Terminating (usually waiting on a finalizer
  or a hung volume detach) can block VolSync replications, PVC reclaims, and node
  maintenance. The clouddrop pod-garbage-collector packages three cleanup jobs into
  one CronJob with cluster-wide list/delete RBAC. The question here is which of those
  three are net-positive in this cluster''s regime: the Failed/Succeeded sweeps overlap
  with native Job/CronJob TTL cleanup, while the stuck-Terminating force-delete targets
  a real operational pain but carries a stale-state risk on Talos that must be weighed
  before adoption.'
options:
- CronJob in kube-system (direct manifest, Recommended baseline) — A raw CronJob with
  ServiceAccount/ClusterRole/ClusterRoleBinding, image alpine/k8s, shell+jq logic.
  Matches the upstream reference and the repo's GitOps model; simple to review and
  reason about. Renovate-pinned via
- bjw-s app-template HelmRelease — The repo's canonical workload shape. Heavier for
  a one-shot batch job; considered only if it composes better with the existing kube-system
  HelmRelease set (reloader, metrics-server).
- Rely on native cleanup only (Live option) — Set ttlSecondsAfterFinished on Jobs
  and tune CronJob history limits cluster-wide; skip the custom CronJob entirely.
  Sufficient if dead-pod accumulation is not observed in practice.
- Adopt only the stuck-Terminating force-delete — Keep the single highest-value function,
  drop the Failed/Succeeded sweeps as redundant with native Job TTL.
related_areas:
- sre
- observability
---

# pod-garbage-collector

## Metadata (observation-form)

- [topic] Periodic cleanup of dead (Failed/Succeeded) and stuck (Terminating) pods via a kube-system CronJob
- [status] proposed
- [priority] low
- [source] Reference manifest: clouddrop pod-garbage-collector — https://github.com/cyberglitchlabs/clouddrop/blob/main/kubernetes/apps/kube-system/pod-garbage-collector/app/cronjob.yaml (cyberglitchlabs/clouddrop, kubernetes/apps/kube-system/pod-garbage-collector/app/cronjob.yaml). Not copied; adapted.
- [related] [[kubelet-gc-and-flux-deadman-alerts]] (progress) — adjacent GC/alerting work.

## Context

The reference (clouddrop) defines a kube-system CronJob running every 10 minutes that performs three sweeps with cluster-wide list/delete RBAC on pods:

1. **Failed pods older than 1h** — delete pods with `status.phase=Failed` whose `status.startTime` is >3600s old.
2. **Succeeded pods older than 1h (excluding Job-owned)** — delete `status.phase=Succeeded` pods older than 1h, but only those NOT owned by a Job (Job-owned Succeeded pods are left to the Job controller / the Job's `ttlSecondsAfterFinished`).
3. **Pods stuck Terminating >10min** — force-delete (`--grace-period=0 --force`) pods with a `deletionTimestamp` older than 600s. Upstream root cause: a hung FUSE/NFS mount putting the container in uninterruptible (D) sleep, which kubelet cannot kill and just retries forever.

Schedule `*/10 * * * *`, `concurrencyPolicy: Forbid`, `successfulJobsHistoryLimit: 1`, `failedJobsHistoryLimit: 2`, `ttlSecondsAfterFinished: 3600`, image `alpine/k8s:1.36.2`, requests 10m/32Mi, limit 64Mi.

## Relevance to this cluster

- **CronJob/Job self-cleanup already exists.** CronJobs clean their own job/pod history via `successfulJobsHistoryLimit`/`failedJobsHistoryLimit`; Jobs support `ttlSecondsAfterFinished` natively. The Failed and Succeeded sweeps therefore overlap with native mechanisms and mainly add value for standalone/orphaned pods (directly-created pods, deleted-with-finalizer pods, controllers that do not set TTL). Open question: does this cluster actually accumulate such pods?
- **Storage backend differs.** The cluster uses democratic-csi local-hostpath (hostpath, not FUSE) plus VolSync/restic for backups. The upstream's stated root cause for stuck-Terminating (FUSE/NFS D-sleep) likely does not apply. Stuck-Terminating here is more plausibly finalizer-driven (VolSync replication sources, external-secrets finalizers, PVC deletes waiting on volume detach). Force-deleting a finalizer-blocked pod can leave the underlying resource orphaned — the risk profile is different from the FUSE case and must be assessed before adoption.
- **Talos + single node.** Force-deleting a pod whose container is genuinely stuck leaves kubelet with stale state on an immutable OS; the blast radius is the whole node. The upstream 10-minute threshold before force-delete is a guess that may be too aggressive or too conservative for this cluster's workloads.
- **Adjacent work.** [[kubelet-gc-and-flux-deadman-alerts]] already touches kubelet GC and deadman alerting. This item should compose with, not duplicate, that effort (e.g. alerting on cleanup volume or on stuck-Terminating count could live there).

## Open decisions (to resolve before implementation)

1. **Which functions to adopt.** All three, only stuck-Terminating, or native-only? Decision needs evidence: a short observation of current Failed/Succeeded/stuck-Terminating pod counts on the live cluster.
2. **Thresholds and schedule.** Keep 1h / 10min / every-10min, or tune to this cluster's churn? The stuck-Terminating threshold especially must reflect observed finalizer-resolution time, not the upstream FUSE heuristic.
3. **Force-delete safety.** Is force-deleting stuck-Terminating pods acceptable on Talos given the finalizer (not D-sleep) root cause? Should we instead alert-and-skip, or only force-delete pods matching known-safe patterns (e.g. exclude pods with specific finalizers)?
4. **Placement and image.** Direct CronJob manifest vs. bjw-s app-template; image choice and Renovate pinning (`# renovate:` annotation) consistent with repo norms.
5. **RBAC scope.** Cluster-wide list/delete on pods (matches upstream) vs. narrower. Cluster-wide is the simple choice for a cleanup job; confirm it is acceptable under the repo's security posture.
6. **Observability.** Emit cleanup counts/logs to VictoriaLogs? Alert on stuck-Terminating volume? Coordinate with the deadman-alerts work.
7. **GitOps delivery.** Direct commits to `main` (repo norm; Flux watches `refs/heads/main`).

## Out of scope

- Changing kubelet/Talos-level GC knobs (kube-controller-manager flags, Kubelet config) — that belongs to bootstrap/talos config, not a workload CronJob.
- Modifying existing workload finalizers or VolSync wiring to reduce stuck-Terminating at the source — separate concern.

## Next step

Gather live evidence (current counts of Failed/Succeeded/stuck-Terminating pods, observed finalizer types on stuck pods) and decide functions/thresholds; then produce the implementation plan.
