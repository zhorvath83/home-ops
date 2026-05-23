---
title: ks-healthchecks-rollout
type: progress
permalink: home-ops/docs/progress/ks-healthchecks-rollout
topic: Flux Kustomization healthChecks rollout - bjw-s parity
status: completed
priority: high
scope: Roll out explicit healthChecks on every dependsOn target Kustomization, adopting
  the bjw-s-labs/home-ops reference pattern.
related_areas:
- flux-gitops
- networking
- external-secrets
- k8s-workloads
tags:
- progress
- flux-gitops
- healthchecks
- dependsOn
---

# Flux Kustomization healthChecks rollout - bjw-s parity (completed)

## What was implemented

### Phase 1 - cert-manager + envoy-gateway chain

| ks.yaml | healthChecks | healthCheckExprs | wait |
|---|---|---|---|
| cert-manager | HR cert-manager | - | true (default) |
| cert-manager-issuers | ClusterIssuer letsencrypt-production | ClusterIssuer Ready CEL | true (default) |
| envoy-gateway-certificate | - (dependsOn only, matches bjw-s) | - | true (default) |
| envoy-gateway | HR envoy-gateway | - | true (default) |
| envoy-gateway-config | - (dependsOn only, matches bjw-s) | - | true (default) |

### Phase 2 - high-fanout platform ks

| ks.yaml | healthChecks | healthCheckExprs | wait |
|---|---|---|---|
| democratic-csi | HR democratic-csi | - | true (default) |
| snapshot-controller | HR snapshot-controller | - | true (default) |

### Wait pattern alignment (all files touched)

Removed wait:false from every health-gated Kustomization, matching the bjw-s pattern where health-gated ks use the default wait:true and non-health-gated leaf ks retain wait:false.

Files where wait:false was removed:

- cert-manager/cert-manager/ks.yaml (both documents)
- envoy-gateway/ks.yaml (all three documents)
- democratic-csi/ks.yaml
- snapshot-controller/ks.yaml
- external-secrets/external-secrets/ks.yaml
- volsync-system/volsync/ks.yaml (both documents)
- volsync-system/kopia/ks.yaml

### Pre-existing healthChecks (unchanged)

| ks.yaml | healthChecks | healthCheckExprs |
|---|---|---|
| external-secrets | HR external-secrets | - |
| onepassword-connect | HR + ClusterSecretStore | ClusterSecretStore Ready CEL |
| volsync | HR volsync | - |
| kopia | HR kopia | - |

### Key decision: Certificate and Gateway CEL NOT added

The original roadmap proposed adding healthCheckExprs for Certificate (envoy-gateway-certificate) and Gateway (envoy-gateway-config). After comparing with the bjw-s reference repo, these were NOT implemented because bjw-s also does not gate on these CRDs. The envoy-gateway-certificate and envoy-gateway-config Kustomizations use dependsOn-only sequencing, matching bjw-s exactly.

### Key decision: wait: true (default) on health-gated ks

The original roadmap proposed wait:false + explicit healthChecks (Model A). After comparing with bjw-s, the pattern was changed to default wait:true on health-gated ks (matching bjw-s exactly). Non-health-gated leaf ks retain wait:false.

## Phase 3 - Deferred (matches bjw-s)

| ks.yaml | healthChecks | wait | Notes |
|---|---|---|---|
| cilium | - | false | bjw-s also no healthChecks |
| flux-operator | - | false | bjw-s also no healthChecks |
| kube-prometheus-stack | - | false | bjw-s also no healthChecks |

These match bjw-s parity. No action needed unless an incident motivates them.

## Phase 4 - Documentation (pending)

The following documentation updates are still needed:

- Update BM docs/areas/flux-gitops with a healthChecks convention section
- Add a brief note to kubernetes/CLAUDE.md about the healthChecks convention

## Canonical patterns

### HR-only gate (simplest case)

```yaml
healthChecks:
  - apiVersion: helm.toolkit.fluxcd.io/v2
    kind: HelmRelease
    name: <release-name>
    namespace: <target-namespace>
```

### HR + CRD with controller-specific Ready (CEL needed)

```yaml
healthChecks:
  - apiVersion: helm.toolkit.fluxcd.io/v2
    kind: HelmRelease
    name: <release-name>
    namespace: <target-namespace>
  - apiVersion: <crd-api>
    kind: <CRD>
    name: <crd-name>
healthCheckExprs:
  - apiVersion: <crd-api>
    kind: <CRD>
    failed: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'False')
    current: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
```

## Commit

- 86bb49c62 - feat(flux): add healthChecks to dependsOn targets, adopt bjw-s wait pattern

## Related

- implements [[flux-gitops]]
- relates_to [[networking]]
- relates_to [[external-secrets]]
- relates_to [[k8s-workloads]]
