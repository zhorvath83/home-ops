# Layout

Use this reference to rebuild the Flux and GitOps control-plane layout before editing.

## Main Areas

- `kubernetes/bootstrap/`: Talos + Kubernetes platform bootstrap chain (`resources.yaml.j2`, `helmfile.d/00-crds.yaml`, `helmfile.d/01-apps.yaml`, `mod.just`). Installs Flux Operator + `FluxInstance` among the other bootstrap-time releases.
- `kubernetes/apps/flux-system/flux-operator/`: HelmRelease + OCIRepository for the operator
- `kubernetes/apps/flux-system/flux-instance/`: HelmRelease that creates the `FluxInstance` CR (Flux controllers, distribution, `sync.ref`, performance patches)
- `kubernetes/apps/flux-system/addons/`: Flux add-ons split into `alerts/` (Pushover Alert) and `webhooks/` (GitHub receiver)
- `kubernetes/apps/flux-system/flux-provider-pushover/`: shared Pushover Notification provider used by `addons/alerts/`
- `kubernetes/flux/cluster/ks.yaml`: the two root Kustomizations `cluster-vars` (applies `kubernetes/flux/vars/`) and `cluster-apps` (reconciles `kubernetes/apps/`). The `FluxInstance` `sync.path` points here.
- `kubernetes/flux/vars/`: cluster-wide non-secret (`cluster-settings.yaml`) and SOPS-encrypted (`cluster-secrets.sops.yaml`) substitutions

## Change Placement

- bootstrap or install-flow changes (helmfile, `resources.yaml.j2`, `mod.just` stages) usually land under `kubernetes/bootstrap/`
- FluxInstance config (`sync.ref`, controllers, patches) lives in `kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml`
- root Kustomization wiring (`cluster-vars` and `cluster-apps`, their `substituteFrom` / `decryption` blocks) lives in `kubernetes/flux/cluster/ks.yaml`
- shared substitution changes belong in `kubernetes/flux/vars/`
- notification, receiver, or provider changes belong in `kubernetes/apps/flux-system/addons/` or `kubernetes/apps/flux-system/flux-provider-pushover/`
- app-local `ks.yaml` edits stay in the app subtree unless they alter shared dependency or naming conventions

If a task only changes one app's `ks.yaml` or manifests, use `k8s-workloads` instead.
