---
title: nfs-dependency-zeroscaler
type: roadmap
permalink: home-ops/docs/roadmap/nfs-dependency-zeroscaler
topic: Adopt zeroscaler component for NFS-dependency scale-to-zero gating
status: proposed
priority: low
scope: Mirror the bjw-s components/zeroscaler/ pattern into our repo. Single HorizontalPodAutoscaler
  (autoscaling/v2) manifest templated via postBuild substitute — no operator, no CRD.
  Default external metric probe_success with job=nfs_probe. Companion Probe CR on
  blackbox-exporter targeting 192.168.1.10:2049 (tcp_connect). Per-app wiring via
  components list in ks.yaml. Apply to NFS-dependent apps (paperless, media stack
  subset, backrest if NFS-mounted). Candidate list to be enumerated during implementation.
rationale: k8s-workloads drift explicitly notes the NFS SPOF — '192.168.1.10 is a
  single point of failure for /backups exports and media mounts across at least 11
  apps'. Today NAS-down → CrashLoopBackOff, alert noise, restart counter churn. With
  zeroscaler, affected apps cleanly scale to 0 until the probe recovers. Native HPA
  pattern (no operator added), identical between bjw-s and onedr0p, mature and low-maintenance.
options:
- NFS-only (bjw-s default) — single Probe + zeroscaler job, covers the actual SPOF
- Extended dependency gating — additional probes for other shared dependencies; no
  current driver
- Skip — accept CrashLoopBackOff during NAS-down as status quo
related_areas:
- k8s-workloads
- observability
blocked_by: prometheus-adapter
---

# Adopt zeroscaler component for NFS-dependency scale-to-zero gating

## Metadata (observation-form, schema validation)
- [topic] Adopt zeroscaler component for NFS-dependency scale-to-zero gating
- [status] proposed
- [priority] low

## Scope
Mirror the bjw-s reusable `components/zeroscaler/` pattern into our `kubernetes/components/zeroscaler/` and wire it into apps that depend on the OMV NAS (`192.168.1.10`) NFS exports.

The component itself is a **single `HorizontalPodAutoscaler` (autoscaling/v2) manifest** templated via postBuild substitution — no operator, no CRD, no separate install. The bjw-s manifest verbatim:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${APP}
spec:
  minReplicas: 0
  maxReplicas: 1
  scaleTargetRef:
    apiVersion: apps/v1
    kind: ${CONTROLLER:=Deployment}
    name: ${APP}
  metrics:
    - type: External
      external:
        metric:
          name: ${ZEROSCALER_METRIC_NAME:=probe_success}
          selector:
            matchLabels:
              job: ${ZEROSCALER_JOB_NAME:=nfs_probe}
        target:
          type: Value
          value: "1"
  behavior:
    scaleDown: { policies: [{type: Pods, value: 1, periodSeconds: 15}], selectPolicy: Max, stabilizationWindowSeconds: 0 }
    scaleUp:   { policies: [{type: Pods, value: 1, periodSeconds: 15}], selectPolicy: Max, stabilizationWindowSeconds: 0 }
```

Per-app wiring (`ks.yaml`):

```yaml
components:
  - ../../../../components/volsync
  - ../../../../components/zeroscaler
postBuild:
  substitute:
    APP: <app-name>
```

Companion Probe CR on blackbox-exporter (mirrors bjw-s shape):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata:
  name: nfs
spec:
  jobName: nfs_probe
  module: tcp_connect
  prober:
    url: blackbox-exporter.observability.svc.cluster.local:9115
  targets:
    staticConfig:
      static:
        - 192.168.1.10:2049
```

Candidate apps for adoption (NFS-dependent, single-replica appropriate): the ~11 apps the k8s-workloads drift note flags as NFS-mount consumers. Exact list to be enumerated during implementation — paperless (NFS export consumer), media stack (radarr/sonarr/plex/bazarr if NFS-mounted), backrest if reading `/backups` over NFS.

## Rationale
The k8s-workloads area-reference explicitly calls out the NFS SPOF: **"The NFS server 192.168.1.10 is a single point of failure for /backups exports and media mounts across at least 11 apps."** Today when the NAS is offline, those pods CrashLoopBackOff on mount or hang stateful operations — alert noise, restart counters incrementing, log churn. With the zeroscaler pattern, affected apps cleanly scale to 0 until the probe reports recovery; no fake-alarm noise, automatic restoration when NFS comes back.

The pattern is **native HPA** (no operator added to the cluster) and identical between bjw-s and onedr0p, so it is mature and low-maintenance.

## Options
1. **NFS-only (bjw-s default)** — single Probe + single zeroscaler metric job; covers the actual SPOF
2. **Extended dependency gating** — additional probes for other shared dependencies (e.g. external DB, OVH S3 reachability); no current driver, defer
3. **Skip entirely** — accept CrashLoopBackOff during NAS-down as today's status quo; viable if alert noise is tolerable

## Related
- relates_to [[k8s-workloads]]
- relates_to [[observability]]
- relates_to [[observability-probes-and-disk-health]]
- relates_to [[prometheus-adapter]]
