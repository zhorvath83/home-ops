# Layout

Use this reference to rebuild the Flux and GitOps control-plane layout before editing.

## Main Areas

- `kubernetes/bootstrap/`: Talos + Kubernetes platform bootstrap chain (`resources.yaml.j2`, `helmfile.d/00-crds.yaml`, `helmfile.d/01-apps.yaml`, `mod.just`). Installs Flux Operator + `FluxInstance` among the other bootstrap-time releases.
- `kubernetes/apps/flux-system/flux-operator/`: HelmRelease + OCIRepository for the operator
- `kubernetes/apps/flux-system/flux-instance/`: HelmRelease that creates the `FluxInstance` CR (Flux controllers, distribution, `sync.ref`, performance patches)
- `kubernetes/apps/flux-system/addons/`: Flux add-ons — currently `webhooks/` (GitHub receiver). Per-namespace Pushover Alerts come from the `kubernetes/components/flux-alerts/` Kustomize component.
- `kubernetes/apps/flux-system/flux-provider-pushover/`: shared Pushover Notification relay used by the per-namespace Alerts
- `kubernetes/components/flux-alerts/`: Kustomize component included by each `apps/<ns>/kustomization.yaml`, instantiates an Alert + Provider + ExternalSecret per workload namespace
- `kubernetes/flux/cluster/ks.yaml`: the single root `cluster-apps` Kustomization. The `FluxInstance` `sync.path` points here.

## Change Placement

- bootstrap or install-flow changes (helmfile, `resources.yaml.j2`, `mod.just` stages) usually land under `kubernetes/bootstrap/`
- FluxInstance config (`sync.ref`, controllers, patches) lives in `kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml`
- root Kustomization wiring (the `cluster-apps` Kustomization, its patches) lives in `kubernetes/flux/cluster/ks.yaml`
- notification, receiver, or provider changes belong in `kubernetes/apps/flux-system/addons/`, `kubernetes/apps/flux-system/flux-provider-pushover/`, or `kubernetes/components/flux-alerts/`
- app-local `ks.yaml` edits stay in the app subtree unless they alter shared dependency or naming conventions

If a task only changes one app's `ks.yaml` or manifests, use `k8s-workloads` instead.
