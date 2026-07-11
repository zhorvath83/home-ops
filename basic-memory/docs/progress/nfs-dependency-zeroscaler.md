---
title: nfs-dependency-zeroscaler
type: progress
permalink: home-ops/docs/progress/nfs-dependency-zeroscaler
topic: Execution state for the nfs-dependency-zeroscaler roadmap (component + 11-app
  wiring + Probe rename + verify)
status: done
roadmap: '[[nfs-dependency-zeroscaler]]'
related_areas:
- k8s-workloads
- observability
tags:
- progress
- zeroscaler
- hpa
- nfs
- blackbox
- scale-to-zero
priority: low
---

# nfs-dependency-zeroscaler

## Metadata

- [topic] Adopt zeroscaler component for NFS-dependency scale-to-zero gating (deployed + verified)
- [status] done
- [priority] low

## Scope

Mirror the bjw-s reusable `components/zeroscaler/` pattern into `kubernetes/components/zeroscaler/` and wire it into apps that depend on the OMV NAS (`192.168.1.10`) NFS exports.

The component is a **single `HorizontalPodAutoscaler` (autoscaling/v2) manifest** templated via postBuild substitution — no operator, no CRD, no separate install. The bjw-s manifest verbatim:

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

Companion `Probe` CR on blackbox-exporter (mirrors bjw-s shape):

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

Candidate apps for adoption (NFS-dependent, single-replica appropriate): the apps the k8s-workloads area-reference flags as NFS-mount consumers.

## Rationale

The k8s-workloads area-reference calls out the NFS SPOF: the NAS at `192.168.1.10` is a single point of failure for NFS exports across at least 11 apps. Today when the NAS is offline, those pods CrashLoopBackOff on mount or hang stateful operations — alert noise, restart counters incrementing, log churn. With the zeroscaler pattern, affected apps cleanly scale to 0 until the probe reports recovery; no fake-alarm noise, automatic restoration when NFS comes back.

The pattern is **native HPA** (no operator added to the cluster) and identical between bjw-s and onedr0p, so it is mature and low-maintenance.

## Options

1. **NFS-only (bjw-s default)** — single Probe + single zeroscaler metric job; covers the actual SPOF *(chosen)*
2. **Extended dependency gating** — additional probes for other shared dependencies (e.g. external DB, OVH S3 reachability); no current driver, defer
3. **Skip entirely** — accept CrashLoopBackOff during NAS-down as today's status quo; viable if alert noise is tolerable

## Session 1 — component + wiring + probe rename + verify (2026-07-11)

### Done

- Created [file] kubernetes/components/zeroscaler/{kustomization,horizontalpodautoscaler}.yaml — Kustomize Component referencing a single HPA (autoscaling/v2) templated via postBuild substitute: `${APP}`, `${CONTROLLER:=Deployment}`, `${ZEROSCALER_METRIC_NAME:=probe_success}`, `${ZEROSCALER_JOB_NAME:=nfs_probe}`. minReplicas 0, maxReplicas 1, External metric (Value "1"), behavior scaleDown/scaleUp Pods policies periodSeconds 15, stabilizationWindowSeconds 0. Verbatim match of the bjw-s manifest.
- Modified [file] 11 app ks.yaml — added `../../../../components/zeroscaler` to components. Apps: downloads (bazarr, qbittorrent, radarr, sonarr, subsyncarr), media (calibre-web-automated, plex), selfhosted (backrest, home-gallery, paperless, resticprofile). home-gallery + resticprofile also received the APP substitute (the other 9 already had it).
- Modified [file] kubernetes/apps/observability/blackbox-exporter/app/probes.yaml — renamed Probe 1 metadata.name nas-icmp → devices (jobName: devices_probe, module icmp, target nas.lan) and Probe 2 metadata.name nfs-tcp → nfs (jobName: nfs_probe, module tcp_connect, target nas.lan:2049). prober.url prometheus-blackbox-exporter.observability.svc.cluster.local:9115 (our fullnameOverride). Symmetric `<name>_probe` jobName naming.
- Code commit 1be5f08bf on main: `✨ feat(autoscaling): add zeroscaler component, wire NFS-dependent apps`. Pushed to origin/main. Pre-commit all Passed.

### Verify (live, post-deploy) — ALL PASS

- [observation] 11 HPAs created across downloads (bazarr, qbittorrent, radarr, sonarr, subsyncarr), media (calibre-web-automated, plex), selfhosted (backrest, home-gallery, paperless, resticprofile) — each minReplicas 0, maxReplicas 1, currentReplicas 1, scaleTargetRef.name matching the app Deployment name.
- [observation] kubectl describe hpa -n selfhosted paperless → ScalingActive=True, ValidMetricFound ("the HPA was able to successfully calculate a replica count from external metric probe_success{job: nfs_probe}"), Metrics probe_success 1/1. HPA controller successfully consumes the external metric served by prometheus-adapter.
- [observation] Probe resources: 'devices' (job=devices_probe, icmp) and 'nfs' (job=nfs_probe, tcp_connect) live; old 'nas-icmp'/'nfs-tcp' pruned by Flux.
- [observation] Prometheus probe_success: devices_probe nas.lan → 1, nfs_probe nas.lan:2049 → 1.
- [observation] Transient FailedGetExternalMetric warnings on the HPA during adapter startup are historical Events; current Conditions = ValidMetricFound (converged).

### Behavior

NAS/NFS down → probe_success{job=nfs_probe} → 0 → HPA ceil(0/1)=0 → minReplicas 0 scales the NFS-dependent app to 0. NAS recovers → probe_success → 1 → scales back to 1. This is the planned SPOF-mitigation behavior; CrashLoopBackOff noise during NAS-down is eliminated.

## Follow-up — KubeHpaMaxedOut silencing (2026-07-11)

- [follow-up] The zeroscaler HPAs (maxReplicas:1, minReplicas:0) are permanently "maxed out" while the NFS probe is healthy (desired=1=max); the kubernetes-apps KubeHpaMaxedOut rule guard `max != min` does not exclude them → 11 constant firing warnings. Suppressed via the giantswarm silence-operator + a GitOps-managed Silence CR. See [[silence-operator]].

## Relations

- depends_on [[prometheus-adapter]]
- relates_to [[k8s-workloads]]
- relates_to [[observability]]
- relates_to [[observability-probes-and-disk-health]]
- relates_to [[silence-operator]]
