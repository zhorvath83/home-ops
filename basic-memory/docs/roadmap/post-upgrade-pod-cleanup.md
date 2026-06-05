---
title: post-upgrade-pod-cleanup
type: roadmap
permalink: home-ops/docs/roadmap/post-upgrade-pod-cleanup
topic: Stranded pod cleanup after Tuppr-driven Talos upgrade on single-node
status: in-progress
priority: medium
related_areas:
- system-upgrade
- flux-gitops
- k8s-workloads
- talos-cluster
blocked_by: null
decision_link: null
tags:
- roadmap
- tuppr
- talos
- kubernetes
- gitops
- single-node
- drain
- self-healing
---

# Stranded pod cleanup after Tuppr-driven Talos upgrade - revised analysis

## Status

- [topic] Stranded pod cleanup after Tuppr-driven Talos upgrade on single-node
- [status] in-progress (Phase 1 change staged 2026-06-05; awaits next upgrade)
- [priority] medium
- [supersedes_hypothesis] kubelet GC after powercycle - incomplete; manual reboot with -m powercycle is observed clean

## Scope

After a Tuppr TalosUpgrade on the single-node cluster, terminated pods whose
owner Deployment / StatefulSet / DaemonSet was running before the reboot end
up visible in `kubectl get pods` as Failed or Succeeded indefinitely, even
though a fresh ReplicaSet pod is Running. The original hypothesis (kubelet
GC after powercycle) was incomplete - manual `just talos reboot-node`
(which also uses `-m powercycle`) does not produce stranded pods. The
actual trigger is the Tuppr controller's own `kubectl drain` step against
the single node, which on a one-node cluster has nowhere to drain to and
leaves the node cordoned with partially evicted pods when the reboot fires.
Phase 1 of the fix is to disable that kubectl drain step explicitly in the
TalosUpgrade CR. Phase 2 (in-cluster cleanup hook) is deferred behind
Phase 1 verification.

## Root cause (revised)

The Tuppr controller performs a `kubectl drain` against the target node
before queueing the upgrade Job. On a single-node cluster the drain cordons
the only node and tries to evict its pods, but there is no other node for
them to move to, so:

1. Old pods are torn down by eviction (graceful termination starts).
2. New replacement pods spawned by Deployment / StatefulSet / DaemonSet
   controllers cannot be scheduled because the node is cordoned - they sit
   Pending.
3. The drain timeout elapses (or "completes" with stuck pods); Tuppr
   queues the talosctl upgrade Job.
4. talosctl runs the upgrade with `--drain=false` (Tuppr 0.2.1 PR #310
   forces this on self-hosted runs) and triggers the configured reboot.
5. Powercycle reboot kills the partially-evicted pods abruptly. On the
   way up, the kubelet sees them as Failed (exit 137/143) or Succeeded.
6. Flux reconciles HelmReleases, which rolls workloads forward against
   the new kubelet - a fresh ReplicaSet (different hash) spawns clean
   pods. The old pod entries stay in the API as Failed / Succeeded
   ghosts because their owner ReplicaSet no longer matches.

The control comparison: `just talos reboot-node` also uses `-m powercycle`
(`kubernetes/talos/mod.just:322-323`) and is reported clean. The only
delta is the Tuppr kubectl drain step. Conclusion: the drain step is the
trigger, not the reboot mode.

## Evidence base

- Tuppr 0.2.1 CRD (`config/crd/bases/tuppr.home-operations.com_talosupgrades.yaml`,
  upstream main): `spec.drain` has only two fields - `enabled` (required)
  and `disableEviction` (optional).
- Tuppr 0.2.1 release notes: PR #310 "disable talosctl drain on single-node
  upgrades". This is the talosctl-internal drain, not the Tuppr-controller
  drain.
- Tuppr README documents native `hooks.pre` / `hooks.post` on TalosUpgrade
  only (KubernetesUpgrade has no hooks field). HookSpec supports image,
  command, args, env, envFrom, volumeMounts, volumes, serviceAccountName,
  activeDeadlineSeconds (default 600), backoffLimit (default 0),
  imagePullPolicy.
- Worked example in upstream README: `ceph osd set noout` / `unset noout`
  around the upgrade window.
- Incident snapshot 2026-06-05 17:30 local: 65 Running, 33 Succeeded,
  13 Failed of 111 pods total after the Tuppr v1.13.3 Talos upgrade.
- Controller logs show no drain failures, just a clean
  "Upgrade completed successfully nodes=1" at 17:32:45. So the drain
  step happened but did not error out in a way the controller flagged -
  it ran, did the partial eviction, and moved on.

## Phase 1 - implemented (2026-06-05)

File `kubernetes/apps/system-upgrade/tuppr/upgrades/talosupgrade.yaml`:

```yaml
spec:
  talos:
    version: "v1.13.3"
  drain:
    enabled: false        # Phase 1 - the actual fix
  policy:
    rebootMode: powercycle  # matches just talos reboot-node behaviour
  healthChecks:
    - ...
```

Notes:

- `drain.enabled: false` skips Tuppr's own kubectl drain on the single
  node. talosctl's internal `--drain` is already off (0.2.1 PR #310).
- `rebootMode` is kept on `powercycle` for parity with the manual
  `just talos reboot-node` recipe (also `-m powercycle`).
- No other changes. `policy.placement` stays at the default (`soft`),
  `policy.timeout` stays at default (`30m`).
- The `healthChecks` block stays as-is (volsync ReplicationSource idle
  gate is sufficient for a single-node).
- No new RBAC, no new image, no new CronJob, no new ConfigMap.

## Phase 2 - deferred behind Phase 1 verification

Only proceed if the next Tuppr-driven Talos upgrade still produces
stranded pods.

### Option A - Tuppr hooks.post (TalosUpgrade only)

```yaml
spec:
  hooks:
    post:
      - name: cleanup-stranded-pods
        image: bitnami/kubectl:1.36
        serviceAccountName: tuppr-post-cleanup
        command: ["sh", "-c"]
        args:
          - |
            # filter and delete Failed/Succeeded pods whose owner has a
            # Ready replacement, skip Job-owned pods, dry-run-safe
            ...
```

- Requires a new ServiceAccount + ClusterRole in `tuppr/app/` with
  get/list on pods, delete on pods, get on deployments/statefulsets/
  daemonsets/replicasets cluster-wide.
- Only covers Tuppr-triggered upgrades.
- Lifecycle-coupled to the upgrade run; ghosts appear and disappear
  inside the same TalosUpgrade reconciliation.

### Option B - In-cluster CronJob

- 15-minute cadence, same RBAC shape as Option A.
- Covers manual `just talos reboot-node`, unexpected power loss, any
  reboot path.
- Higher steady-state cost (a CronJob in the namespace), longer
  worst-case latency.

### Decision matrix for Phase 2 (only if needed)

If Phase 1 leaves <5 ghost pods per upgrade -> Option A is enough.
If manual reboots also produce ghosts (re-test after Phase 1) ->
Option B (or both).

## Rejected options (from the original plan)

- **Systemd / Talos post-reboot hook**: still rejected - violates
  GitOps source-of-truth and adds host-cluster state divergence.
- **Manual runbook only**: re-introduces the toil the user complained
  about. Keep a `just k8s cleanup-pods` recipe only if Phase 2 lands
  and it is a thin wrapper around the same script.
- **Upstream Tuppr `postUpgradeActions` PR**: no longer needed - the
  feature already exists in 0.2.1 as `hooks.post`.

## Out of scope

- Garbage-collecting old ReplicaSets - handled by kube-controller-manager
  with `TerminatedPodGCThreshold` (default 12500); not the trigger here.
- Cleaning up Completed Job pods - intentional history.
- `restartOnReboot: true` pod-spec feature (K8s 1.30+ alpha) -
  irrelevant on single-node; the kubelet that would restart the pod is
  the one going away.

## Acceptance criteria

- After the next Tuppr-driven Talos upgrade, `kubectl get pods -A` shows
  zero Failed or Succeeded pods owned by a Deployment / StatefulSet /
  DaemonSet within 5 minutes of the upgrade reaching Completed.
- The post-upgrade controller logs show no "drain failed" or "drain
  timed out" entries (the drain step is skipped entirely).
- Workloads come back Ready within the normal post-reboot window
  (cilium endpoints reconciled, ESO refreshing, gateways routing).

## Verification plan

1. Commit Phase 1 change to `talosupgrade.yaml`.
2. Wait for the next Renovate-driven Talos version bump (or trigger one
   by patching the TalosUpgrade CR with the same version).
3. After Tuppr marks the run Completed:
   - `kubectl get pods -A --field-selector=status.phase=Failed`
   - `kubectl get pods -A --field-selector=status.phase=Succeeded`
   - Filter out Job-owned pods (`ownerReferences[*].kind=Job`)
   - Count remaining; expected 0.
4. If 0 -> mark this roadmap completed, file Phase 2 as a closed
   alternative.
5. If >0 -> proceed to Phase 2 with the recorded count.

## Related

- continues [[tuppr-upgrade-automation]] - same subsystem, post-impl hygiene
- relates_to [[AD-019-tuppr-system-upgrade]]
- relates_to [[k8s-workloads]] - cluster inventory invariant
- relates_to [[talos-cluster]] - reboot trigger
