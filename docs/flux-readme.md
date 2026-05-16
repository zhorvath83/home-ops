# GitOps with Flux

The cluster runs Flux through the [Flux Operator](https://fluxcd.control-plane.io/) pattern: a single `FluxInstance` CR declares the controllers, GitRepository, and root Kustomization. There is no classic `flux bootstrap` step.

The full bootstrap procedure is described in [`docs/migration/05-flux-operator.md`](./migration/05-flux-operator.md) and triggered by `just k8s-bootstrap cluster`. This document is an operational cheatsheet for the running cluster.

## Topology

- `kubernetes/apps/flux-system/flux-operator/` — operator HelmRelease + OCIRepository
- `kubernetes/apps/flux-system/flux-instance/` — FluxInstance HelmRelease + OCIRepository; `sync.ref` points at the active branch (currently `talos`, becomes `main` at cutover)
- `kubernetes/flux/cluster/ks.yaml` — root `cluster-vars` + `cluster-apps` Kustomizations that the FluxInstance reconciles
- `kubernetes/flux/vars/` — `cluster-settings.yaml` (non-secret) + `cluster-secrets.sops.yaml` (SOPS-encrypted) cluster-wide substitutions

## Cheatsheet

Force a full reconcile (refresh GitRepository, then reconcile both root Kustomizations):

```sh
just k8s flux-reconcile
```

Verify Flux prerequisites (`flux check --pre`):

```sh
just k8s flux-check
```

Sync a single resource without waiting for the next interval:

```sh
just k8s sync-hr <namespace> <name>           # HelmRelease
just k8s sync-ks <namespace> <name>           # Kustomization
just k8s sync-es <namespace> <name>           # ExternalSecret

# polymorphic shortcut (resource = hr|ks|gitrepo|ocirepo|es)
just k8s sync <resource>
```

Inspect Flux state directly with the upstream CLI:

```sh
flux get sources git -A
flux get ks -A
flux get hr -A
flux get sources oci -A
flux events --watch
flux logs --all-namespaces --follow --level=error
```

## Failed HelmReleases

List or restart failed HRs:

```sh
just k8s list-failed-hrs
just k8s restart-failed-hrs
```

When a single HR is stuck with `MissingRollbackTarget` or a similar uninstall artefact, a Flux reconcile is **not** enough. Use `helm uninstall <release> -n <ns>` followed by `flux reconcile hr <name> -n <ns> --force`. The pattern is documented in `docs/migration/STATUS.md` (Phase 6 zárás).

## Local Kustomization Apply

Apply or delete a Flux Kustomization defined in the working tree without going through Git:

```sh
just k8s apply-ks <ns> <ks-name>
just k8s delete-ks <ns> <ks-name>
```

Use this only when intentionally working outside the normal GitOps flow — by default everything goes through commit → push → reconcile.

## Debug Helpers

```sh
just k8s browse-pvc <namespace> <claim>
just k8s mount-pvc <claim> [<ns>]
just k8s node-shell <node>
just k8s prune-pods
just k8s view-secret <namespace> <secret>     # requires kubectl-view-secret krew plugin
```
