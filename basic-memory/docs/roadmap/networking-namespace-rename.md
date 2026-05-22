---
title: networking-namespace-rename
type: note
permalink: home-ops/docs/roadmap/networking-namespace-rename
---

# Networking namespace rename — networking → network

## Metadata (observation-form, schema validation)
- [topic] Namespace rename — networking → network
- [status] proposed
- [priority] medium
- [scope] Rename the Kubernetes namespace and repo directory from `networking` to `network`, updating all cross-references across the repository.

## Rationale
The `networking` namespace is the only namespace in the cluster that uses a gerund form rather than a noun. The other system namespaces follow a noun pattern (`kube-system`, `volsync-system`, `cert-manager`, `external-secrets`). Renaming to `network` aligns naming conventions and shortens the most-referenced namespace in the repo (34+ cross-namespace parentRef lines).

## Scope

### 1. Namespace and directory rename
- Rename K8s namespace: `networking` → `network`
- Rename repo directory: `kubernetes/apps/networking/` → `kubernetes/apps/network/`
- Update top-level `kubernetes/apps/kustomization.yaml` entry: `- ./networking` → `- ./network`

### 2. Flux Kustomization resources (7 files in ks.yaml)
- `targetNamespace: networking` → `targetNamespace: network` in all ks.yaml files
- `path:` references from `./kubernetes/apps/networking/...` → `./kubernetes/apps/network/...`

### 3. In-namespace resources
- `kustomization.yaml` namespace field
- Gateway resources (`gateway-external.yaml`, `gateway-internal.yaml`) namespace field
- HTTPRoute parentRef namespace fields in `gateway-policies.yaml`
- CiliumNetworkPolicy namespace label selectors (3 files)
- PodMonitor/ServiceMonitor namespaceSelector.matchNames
- Cloudflare Tunnel HelmRelease: `envoy-external.networking.svc.cluster.local` FQDN → `envoy-external.network.svc.cluster.local`
- Echo HelmRelease parentRef namespace

### 4. Cross-namespace HTTPRoute parentRefs (bulk — 17 apps in default/)
- Every app under `kubernetes/apps/default/` that routes through envoy gateways has two parentRef lines: `namespace: networking` → `namespace: network`
- Affected apps: actual, backrest, bazarr, calibre-web-automated, home-gallery, homepage, maintainerr, mealie, paperless, paperless-gpt, prowlarr, qbittorrent, radarr, seerr, sonarr, subsyncarr, wallos

### 5. Other cross-namespace references
- `kubernetes/apps/observability/grafana/app/helmrelease.yaml` — HTTPRoute parentRef (2 lines)
- `kubernetes/apps/observability/speedtest-exporter/app/helmrelease.yaml` — HTTPRoute parentRef (2 lines)
- `kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml` — HTTPRoute parentRef (2 lines)
- `kubernetes/apps/flux-system/flux-instance/app/github/httproute.yaml` — HTTPRoute parentRef (1 line)
- `kubernetes/apps/default/paperless/app/ciliumnetworkpolicy.yaml` — CiliumNetworkPolicy endpoint namespace label

### 6. Bootstrap
- `kubernetes/bootstrap/helmfile.d/00-crds.yaml` — envoy-gateway CRD helmfile release namespace

### 7. Grafana dashboard naming (cosmetic, not K8s namespace)
- Dashboard provider name and folder path in `observability/grafana/app/helmrelease.yaml` — optional rename from "networking" to "network"

## Impact
- ~35 files with direct `namespace: networking` references
- Bulk is mechanical: same `parentRefs.namespace` pattern repeated across 17 default apps
- Service DNS FQDN change (`.networking.svc` → `.network.svc`) affects only in-cluster callers (cloudflare-tunnel HelmRelease)
- Directory rename requires `git mv` and all Flux path updates in a single commit

## Risks
- Flux reconciliation gap: the old namespace must be drained before the new one is active
- Cluster-mutating: requires a coordinated apply — create new namespace resources, migrate workloads, then remove old namespace
- Cross-namespace references must all be updated atomically to avoid broken routing

## Execution Steps
1. Create the new `network` namespace resource and update the top-level kustomization
2. `git mv kubernetes/apps/networking kubernetes/apps/network`
3. Bulk rename all `namespace: networking` → `namespace: network` and FQDN references
4. Update all Flux ks.yaml targetNamespace and path references
5. Update all cross-namespace HTTPRoute parentRef namespaces (17 default/ apps + observability + volsync-system + flux-system)
6. Update CiliumNetworkPolicy namespace selectors
7. Update monitoring selectors and dashboard naming
8. Update bootstrap helmfile namespace
9. Validate: `just k8s reconcile` or Flux reconciliation check
10. Remove old namespace after confirming all workloads healthy in new namespace

## Related
- relates_to [[networking]]
- relates_to [[namespace-split]]
- part_of [[home-ops-platform]]
