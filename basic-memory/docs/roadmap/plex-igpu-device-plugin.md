---
title: plex-igpu-device-plugin
type: roadmap
permalink: home-ops/docs/roadmap/plex-igpu-device-plugin
topic: Replace Plex host-mounted iGPU with Intel GPU Resource Driver (DRA/CDI)
status: in-progress
scope: Deploy the Intel GPU Resource Driver (DRA/CDI) pattern instead of the legacy
  device plugin or host-mount approach. The resource driver exposes the iGPU via Kubernetes
  Dynamic Resource Allocation, and Plex requests GPU access via ResourceClaimTemplate
  + resourceClaims. This is the bjw-s/onedr0p community standard pattern.
priority: medium
rationale: Kubernetes-native DRA/CDI resource management is the modern approach for
  GPU allocation. It avoids hostPath mounts, supplementalGroups, and device plugin
  extended resources. The Talos i915 extension is already enabled. containerd CDI
  spec dirs configured.
related_areas:
- k8s-workloads
- talos-cluster
- flux-gitops
---

# Replace Plex host-mounted iGPU with Intel GPU Resource Driver (DRA/CDI)

## Metadata (observation-form, schema validation)
- [topic] Replace Plex host-mounted iGPU with Intel GPU Resource Driver (DRA/CDI)
- [status] in-progress
- [priority] medium

## Scope
Deploy the Intel GPU Resource Driver (DRA/CDI) pattern instead of the legacy device plugin or host-mount approach. The resource driver exposes the iGPU via Kubernetes Dynamic Resource Allocation, and Plex requests GPU access via ResourceClaimTemplate + resourceClaims.

## Rationale
Kubernetes-native DRA/CDI resource management is the modern approach for GPU allocation. It avoids hostPath mounts, supplementalGroups, and device plugin extended resources (gpu.intel.com/i915). The Talos i915 extension is already enabled. containerd CDI spec dirs configured in machineconfig.

## Implementation
- Deployed intel-gpu-resource-driver HelmRelease (OCI chart from ghcr.io/intel)
- Created shared components/gpu/ ResourceClaimTemplate component
- Updated Plex HelmRelease with resourceClaims + resources.claims
- Added containerd cdi_spec_dirs to Talos machineconfig
- No supplementalGroups needed — CDI handles device injection
- Rootless operation fully preserved

## Related
- relates_to [[k8s-workloads]]
- relates_to [[talos-cluster]]
- relates_to [[flux-gitops]]
