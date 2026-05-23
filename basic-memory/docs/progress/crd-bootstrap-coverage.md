---
title: crd-bootstrap-coverage
type: progress
permalink: home-ops/docs/progress/crd-bootstrap-coverage
topic: CRD bootstrap coverage audit — verified upstream feature parity, closed one
  gap
status: done
priority: medium
tags:
- progress
- crd
- bootstrap
- flux
- helmfile
---

# CRD bootstrap coverage (completed)

## Summary

Audited all CR kinds in kubernetes/apps/ against the four upstream reference implementations (onedr0p, bjw-s, billimek, szinn). Found that the home-ops bootstrap already followed the consensus pattern for almost everything. One gap was identified and closed.

## What was already in place

- **Cilium postsync hook** — CRD wait + network config apply via kustomize. Matches onedr0p/bjw-s/szinn.
- **Onepassword-connect postsync hook** — ClusterSecretStore apply after 1PW Connect deployment.
- **3-chart 00-crds.yaml** — envoy-gateway, kube-prometheus-stack, grafana-operator. Matches 3/4 consensus.
- **Bootstrap sequence** — namespaces → resources → crds → apps. resources.yaml.j2 only contains 1PW Connect Secrets, no CRD-dependent objects.
- **needs chain** — cilium → coredns → cert-manager → external-secrets → onepassword-connect → flux-operator → flux-instance.

## Change made

**kubernetes/bootstrap/helmfile.d/01-apps.yaml** — Added ESO CRD wait before ClusterSecretStore apply in the onepassword-connect postsync hook:

```yaml
hooks:
  - # Wait for the ESO CRD to become available before applying ClusterSecretStore
    command: kubectl
    args:
      - wait
      - --for=create
      - crd/clustersecretstores.external-secrets.io
      - --timeout=2m
    events:
      - postsync
    showlogs: true
  - # Apply ClusterSecretStore once the Connect deployment is up
    command: kubectl
    args: ...
    events:
      - postsync
```

Pattern: onedr0p explicit CRD wait (belt-and-suspenders with the needs chain).

## No changes needed

- 00-crds.yaml — stays at 3 charts
- resources.yaml.j2 — ClusterSecretStore not present, only 1PW Connect secrets
- Bootstrap sequence — correct as-is
- cert-manager, tuppr, volsync, snapshot-controller — handled by needs chain + Flux dependsOn
- CiliumNetworkPolicy/PrometheusRule consumers without explicit dependsOn — consensus pattern (no reference repo requires it either)

## Key findings from reference audit

| Repo | 00-crds.yaml charts | Postsync hooks |
|------|-----|------|
| onedr0p | 3 | cilium CRD wait + config; 1PW CRD wait + ClusterSecretStore |
| bjw-s | 3 | cilium CRD wait + config; 1PW ClusterSecretStore (no CRD wait) |
| billimek | 12 | None (comprehensive CRD pre-install) |
| szinn | 3 | cilium CRD wait + config |
| home-ops | 3 | cilium CRD wait + config; 1PW CRD wait + ClusterSecretStore |

## Relates

- continues [[crd-bootstrap-coverage]] (roadmap)
- relates_to [[flux-gitops]]
- relates_to [[external-secrets]]
- relates_to [[k8s-workloads]]
