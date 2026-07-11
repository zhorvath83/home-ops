---
title: silence-operator
type: progress
permalink: home-ops/docs/progress/silence-operator
topic: Execution state for the silence-operator deploy (suppress KubeHpaMaxedOut false-positives
  from zeroscaler HPAs)
status: done
related_areas:
- observability
tags:
- progress
- silence-operator
- alertmanager
- silencing
- observability
- ad-023
---

# silence-operator — execution progress

## Metadata (observation-form)

- [topic] Execution state for the silence-operator deploy (suppress KubeHpaMaxedOut false-positives from zeroscaler HPAs)
- [status] done
- [priority] low
- [related_area] observability

## Scope

Deploy the giantswarm silence-operator to reconcile GitOps-managed `Silence` CRs into Alertmanager silences, and silence the 11 KubeHpaMaxedOut false-positives emitted by the zeroscaler HPAs (maxReplicas:1, permanently "maxed out" while the NFS probe is healthy). Direct consequence of the [[nfs-dependency-zeroscaler]] work.

## Session 1 — deploy + verify (2026-07-11)

### Done

- Created [file] kubernetes/apps/observability/silence-operator/{ks,app/kustomization,app/ocirepository,app/helmrelease,app/ciliumnetworkpolicy,silences/kustomization,silences/hpa_maxed_out}.yaml — 2 Flux Kustomizations (silence-operator app/ with healthCheck on HR + dependsOn kube-prometheus-stack; silence-operator-silences silences/ dependsOn silence-operator) + OCIRepository (oci://gsci.azurecr.io/charts/giantswarm/silence-operator 0.20.1, new registry) + minimal-spec HelmRelease (alertmanagerAddress http://alertmanager-operated.observability.svc.cluster.local:9093, networkPolicy.enabled:false) + AD-023 CNP (egress kube-apiserver:6443 + alertmanager:9093, ingress prometheus:8080) + Silence CR hpa-maxed-out (matchers alertname=KubeHpaMaxedOut).
- Modified [file] kubernetes/apps/observability/kustomization.yaml — added '- ./silence-operator/ks.yaml'.
- Modified [file] kubernetes/apps/observability/kube-prometheus-stack/app/ciliumnetworkpolicy.yaml — added silence-operator to the alertmanager CNP ingress allowlist (port 9093). Functional requirement: the alertmanager CNP is ingress default-deny, so without this the silence-operator API calls to Alertmanager would be blocked.
- Code commit f4b684b7f on main: '✨ feat(observability): silence KubeHpaMaxedOut via giantswarm silence-operator'. Pushed to origin/main. Pre-commit all Passed.

### Verify (live, post-deploy) — ALL PASS

- [observation] flux get ks silence-operator + silence-operator-silences → Ready, applied rev f4b684b7.
- [observation] OCIRepository stored artifact (gsoci.azurecr.io pull OK); HelmRelease InstallSucceeded chart silence-operator@0.20.1.
- [observation] Silence CRDs created: silences.observability.giantswarm.io (v1alpha2) + silences.monitoring.giantswarm.io (v1alpha1). kubectl get silence is ambiguous due to the two CRDs sharing the short name — use silences.observability.giantswarm.io explicitly.
- [observation] Silence CR hpa-maxed-out present in observability ns; operator pod Running 1/1; silence-operator CNP VALID.
- [observation] operator logs: "Successfully synced silence with Alertmanager" for hpa-maxed-out.
- [observation] Alertmanager /api/v2/silences: active silence id e521e846, matcher alertname=KubeHpaMaxedOut, createdBy silence-operator, perpetual (ends 2126-07-11).
- [observation] Alertmanager /api/v2/alerts filter alertname=KubeHpaMaxedOut: 11 alerts, all state=suppressed, silencedBy e521e846. Pushover notifications stopped.

### Decisions

- [decision] Adopted the giantswarm silence-operator (bjw-s pattern) over disabling/modifying the default KubeHpaMaxedOut rule: keeps the alert visible in Prometheus, GitOps-managed + reversible (delete the Silence CR), reusable for future silences. Cost: a new lightweight operator + two CRDs.
- [decision] AD-023 full hardening (silence-operator own restrictive CNP: egress only kube-apiserver + alertmanager, ingress prometheus metrics) beyond bjw-s minimal — matches the repo's per-component AD-023 posture. silence-operator added to the alertmanager CNP ingress allowlist because our alertmanager CNP is ingress default-deny (bjw-s minimal would leave the operator blocked from Alertmanager in this cluster).
- [decision] Global silence (matcher alertname=KubeHpaMaxedOut only, not per-HPA) — matches bjw-s. Acceptable today because no maxReplicas>1 HPA exists, so no real maxed-out signal is lost. Follow-up: if a real autoscaling HPA (max>1) is added, scope the silence to specific HPAs (add horizontalpodautoscaler/namespace matchers) so genuine maxed-out alerts are not suppressed.

## Relations

- continues [[nfs-dependency-zeroscaler]]
- relates_to [[observability]]
- relates_to [[prometheus-adapter]]
