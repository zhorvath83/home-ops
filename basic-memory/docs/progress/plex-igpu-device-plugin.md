---
title: plex-igpu-device-plugin
type: progress
permalink: home-ops/docs/progress/plex-igpu-device-plugin
topic: Replace Plex host-mounted iGPU with Intel GPU Resource Driver (DRA/CDI)
status: completed
scope: Deploy the Intel GPU Resource Driver (DRA/CDI) pattern instead of the legacy
  device plugin or host-mount approach. The resource driver exposes the iGPU via Kubernetes
  Dynamic Resource Allocation, and Plex requests GPU access via ResourceClaimTemplate
  + resourceClaims. This is the bjw-s/onedr0p community standard pattern.
priority: medium
rationale: Kubernetes-native DRA/CDI resource management is the modern approach for
  GPU allocation. It avoids hostPath mounts, supplementalGroups, and device plugin
  extended resources. The Talos i915 extension is already enabled. Talos v1.13+ includes
  CDI spec dirs by default — no machineconfig change needed.
related_areas:
- k8s-workloads
- talos-cluster
- flux-gitops
---

# Replace Plex host-mounted iGPU with Intel GPU Resource Driver (DRA/CDI)

## Metadata (observation-form, schema validation)

- [topic] Replace Plex host-mounted iGPU with Intel GPU Resource Driver (DRA/CDI)
- [status] completed
- [priority] medium

## Scope

Deploy the Intel GPU Resource Driver (DRA/CDI) pattern instead of the legacy device plugin or host-mount approach. The resource driver exposes the iGPU via Kubernetes Dynamic Resource Allocation, and Plex requests GPU access via ResourceClaimTemplate + resourceClaims.

## Rationale

Kubernetes-native DRA/CDI resource management is the modern approach for GPU allocation. It avoids hostPath mounts, supplementalGroups, and device plugin extended resources (gpu.intel.com/i915). The Talos i915 extension is already enabled. Talos v1.13+ includes CDI spec dirs by default.

## Implementation

- Deployed intel-gpu-resource-driver HelmRelease (OCI chart v0.10.1 from ghcr.io/intel)
- Created shared components/gpu/ ResourceClaimTemplate component (allocationMode: All, deviceClassName: gpu.intel.com)
- Updated Plex HelmRelease with resourceClaims + resources.claims
- No supplementalGroups needed — CDI handles device injection
- No adminAccess — onedr0p pattern: exclusive GPU allocation without namespace label
- No containerd cdi_spec_dirs in machineconfig — Talos v1.13+ includes /run/cdi by default
- Rootless operation fully preserved
- Plex UI: enable "Use hardware acceleration when available" → Intel Quick Sync (QSV) (manual step)

## Verification

- ResourceClaimTemplate plex-gpu created and valid in default namespace
- Intel GPU Resource Driver DaemonSet running in kube-system

## Related

- relates_to [[k8s-workloads]]
- relates_to [[talos-cluster]]
- relates_to [[flux-gitops]]
