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
---

# nfs-dependency-zeroscaler — execution progress

## Metadata (observation-form)

- [topic] Execution state for the nfs-dependency-zeroscaler roadmap
- [status] done
- [roadmap] [[nfs-dependency-zeroscaler]] (docs/roadmap)
- [priority] low

## Scope

Mirror the bjw-s `components/zeroscaler/` pattern (single HPA via postBuild substitute, no operator/CRD), wire it into the NFS-dependent apps, and add the companion blackbox Probe targeting nas.lan:2049.

## Session 1 — component + wiring + probe rename + verify (2026-07-11)

### Done

- Created [file] kubernetes/components/zeroscaler/{kustomization,horizontalpodautoscaler}.yaml — Kustomize Component referencing a single HPA (autoscaling/v2) templated via postBuild substitute: ${APP}, ${CONTROLLER:=Deployment}, ${ZEROSCALER_METRIC_NAME:=probe_success}, ${ZEROSCALER_JOB_NAME:=nfs_probe}. minReplicas 0, maxReplicas 1, External metric (Value "1"), behavior scaleDown/scaleUp Pods policies periodSeconds 15, stabilizationWindowSeconds 0. Verbatim match of the bjw-s manifest.
- Modified [file] 11 app ks.yaml — added '../../../../components/zeroscaler' to components. Apps: downloads (bazarr, qbittorrent, radarr, sonarr, subsyncarr), media (calibre-web-automated, plex), selfhosted (backrest, home-gallery, paperless, resticprofile). home-gallery + resticprofile also received the APP substitute (the other 9 already had it).
- Modified [file] kubernetes/apps/observability/blackbox-exporter/app/probes.yaml — renamed Probe 1 metadata.name nas-icmp → devices (jobName: devices_probe, module icmp, target nas.lan) and Probe 2 metadata.name nfs-tcp → nfs (jobName: nfs_probe, module tcp_connect, target nas.lan:2049). prober.url prometheus-blackbox-exporter.observability.svc.cluster.local:9115 (our fullnameOverride). Symmetric `<name>_probe` jobName naming.
- Code commit 1be5f08bf on main: '✨ feat(autoscaling): add zeroscaler component, wire NFS-dependent apps'. Pushed to origin/main. Pre-commit all Passed.

### Verify (live, post-deploy) — ALL PASS

- [observation] 11 HPAs created across downloads (bazarr, qbittorrent, radarr, sonarr, subsyncarr), media (calibre-web-automated, plex), selfhosted (backrest, home-gallery, paperless, resticprofile) — each minReplicas 0, maxReplicas 1, currentReplicas 1, scaleTargetRef.name matching the app Deployment name.
- [observation] kubectl describe hpa -n selfhosted paperless → ScalingActive=True, ValidMetricFound ("the HPA was able to successfully calculate a replica count from external metric probe_success{job: nfs_probe}"), Metrics probe_success 1/1. HPA controller successfully consumes the external metric served by prometheus-adapter.
- [observation] Probe resources: 'devices' (job=devices_probe, icmp) and 'nfs' (job=nfs_probe, tcp_connect) live; old 'nas-icmp'/'nfs-tcp' pruned by Flux.
- [observation] Prometheus probe_success: devices_probe nas.lan → 1, nfs_probe nas.lan:2049 → 1.
- [observation] Transient FailedGetExternalMetric warnings on the HPA during adapter startup (2m33s/93s ago) are historical Events; current Conditions = ValidMetricFound (converged).

### Behavior

NAS/NFS down → probe_success{job=nfs_probe} → 0 → HPA ceil(0/1)=0 → minReplicas 0 scales the NFS-dependent app to 0. NAS recovers → probe_success → 1 → scales back to 1. This is the planned SPOF-mitigation behavior; CrashLoopBackOff noise during NAS-down is eliminated.

## Relations

- implements [[nfs-dependency-zeroscaler]]
- depends_on [[prometheus-adapter]]
- relates_to [[k8s-workloads]]
- relates_to [[observability]]
- relates_to [[observability-probes-and-disk-health]]


## Follow-up — KubeHpaMaxedOut silencing (2026-07-11)

- [follow-up] The zeroscaler HPAs (maxReplicas:1, minReplicas:0) are permanently "maxed out" while the NFS probe is healthy (desired=1=max); the kubernetes-apps KubeHpaMaxedOut rule guard `max != min` does not exclude them → 11 constant firing warnings. Suppressed via the giantswarm silence-operator + a GitOps-managed Silence CR. See [[silence-operator]].
