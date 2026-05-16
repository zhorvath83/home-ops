# Bootstrap

This directory holds the Talos + Kubernetes platform bootstrap chain — everything needed to bring an empty Talos node up to a Flux-reconciled cluster.

The full design rationale for each stage is in [`docs/migration/04-bootstrap-helmfile.md`](../../docs/migration/04-bootstrap-helmfile.md) and [`docs/migration/05-flux-operator.md`](../../docs/migration/05-flux-operator.md). This readme is the operational entry-point.

## Prerequisites

All tooling versions are pinned in `.mise.toml` at the repo root. Activate them with `mise install` (one-time per machine):

- `talosctl`, `kubectl`, `helm`, `helmfile`, `flux2`, `just`
- `sops`, `age`, `1password-cli` for secret decryption / `op inject`
- `minijinja` (via `aqua:mitsuhiko/minijinja`) for templated bootstrap resources
- `yq`, `jq`, `gum` for the recipe scripts

Additionally needed before running:

- a working `talosconfig` (generate with `just talos gen-talosconfig` after `just talos gen-secrets`)
- `op` signed in for `op inject` (1Password CLI)
- `SOPS_AGE_KEY_FILE` resolvable to the cluster Age key (the recipe template handles 1Password lookup)

## Bootstrap the cluster

A single recipe runs the entire chain idempotently:

```sh
just k8s-bootstrap cluster
```

The composed stages (each can be inspected via `just --list k8s-bootstrap`):

1. **`talos`** — apply Talos machine config to every node listed under `kubernetes/talos/nodes/`. Skips nodes that already accept a non-insecure connection.
2. **`kubernetes`** — `talosctl bootstrap` against the first controller to initialize etcd.
3. **`kubeconfig`** (lb=`node`) — fetch the kubeconfig from the controller, pinning the server to the node IP so the next stages can talk to the API before Cilium is up.
4. **`wait`** — wait for the node to register with the API server (`Ready=False` is fine — the CNI is still missing).
5. **`namespaces`** — create one namespace per directory under `kubernetes/apps/`.
6. **`resources`** — render `resources.yaml.j2` through `minijinja-cli | op inject` and apply the bootstrap-time Secrets (`sops-age` in `flux-system`, `onepassword-secret` in `external-secrets`).
7. **`crds`** — helmfile-render `helmfile.d/00-crds.yaml` and apply only `CustomResourceDefinition` objects (other kinds are filtered out by the `yq` pipeline; the Gateway API `ValidatingAdmissionPolicy` is intentionally excluded — see STATUS.md `safe-upgrades VAP` reminder).
8. **`apps`** — `helmfile sync` the main chain in `helmfile.d/01-apps.yaml`: Cilium → CoreDNS → cert-manager → External Secrets → 1Password Connect → Flux Operator → FluxInstance.
9. **`kubeconfig`** (lb=`cilium`, default) — re-fetch the kubeconfig so the server endpoint switches to the Cilium-L2-announced address.

After `apps` completes, Flux Operator reconciles `FluxInstance`, which creates the GitRepository pointing at `kubernetes/flux/cluster/` and the rest of the cluster comes up under GitOps.

## Force a reconcile

Once Flux is up, prefer regular reconcile commands instead of re-running the bootstrap:

```sh
just k8s flux-reconcile      # full refresh: GitRepository + cluster-vars + cluster-apps
just k8s flux-check          # flux check --pre
```

## Recovery

If a single helmfile stage fails (e.g. a hung HelmRelease, `MissingRollbackTarget`), the `cluster` recipe is safe to re-run — every stage is idempotent. For HR-level recovery patterns (`helm uninstall` + `flux reconcile hr --force`, `kubectl delete vap/vapb safe-upgrades.gateway.networking.k8s.io`), see `docs/migration/STATUS.md` Phase 6 zárás notes.
