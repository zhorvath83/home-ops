---
title: plex-igpu-device-plugin
type: roadmap
permalink: home-ops/docs/roadmap/plex-igpu-device-plugin
topic: Replace Plex host-mounted iGPU with Intel device plugin
status: proposed
scope: 'Replace the current direct host-mount of the Intel iGPU device (`/dev/dri/*`)
  into the Plex pod with the Intel device plugin pattern (i915 device plugin, resource
  requests like `gpu.intel.com/i915: 1`). The host-mount approach works but is non-portable
  and bypasses Kubernetes resource accounting.'
priority: medium
rationale: Kubernetes-native GPU resource management improves resource scheduling
  correctness (the scheduler knows whether the iGPU is in use) and matches the pattern
  used by bjw-s and onedr0p. The host-mount approach is K3s-era residue. The Talos
  extension for i915 is already enabled.
related_areas:
- k8s-workloads
- talos-cluster
---

# Replace Plex host-mounted iGPU with Intel device plugin

## Metadata (observation-form, schema validation)
- [topic] Replace Plex host-mounted iGPU with Intel device plugin
- [status] proposed
- [priority] medium

## Scope
Replace the current direct host-mount of the Intel iGPU device (`/dev/dri/*`) into the Plex pod with the Intel device plugin pattern (i915 device plugin, resource requests like `gpu.intel.com/i915: 1`). The host-mount approach works but is non-portable and bypasses Kubernetes resource accounting.

## Rationale
Kubernetes-native GPU resource management improves resource scheduling correctness (the scheduler knows whether the iGPU is in use) and matches the pattern used by bjw-s and onedr0p. The host-mount approach is K3s-era residue. The Talos extension for i915 is already enabled.

## Related
- relates_to [[k8s-workloads]]
- relates_to [[talos-cluster]]
