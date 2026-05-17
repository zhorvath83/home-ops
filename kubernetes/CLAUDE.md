# Kubernetes Agent Guide

This guide applies to everything under `kubernetes/`.

## What Lives Here

`kubernetes/` contains the declarative cluster state reconciled by Flux. The main structure is:

- `apps/`: application and platform workloads grouped by namespace or domain
- `bootstrap/`: Talos + Kubernetes platform bootstrap chain (helmfile + `resources.yaml.j2`), wrapped by `just cluster-bootstrap cluster`
- `components/`: reusable Kustomize components (notably `components/volsync/`)
- `flux/cluster/`: the single root `cluster-apps` Kustomization that FluxInstance reconciles (no `cluster-vars` / `flux/vars/` substitution layer — that pattern was retired in Phase 6.7 for bjw-s parity)
- `talos/`: Talos `machineconfig` template, schematic, and node values consumed by `just talos *` recipes
- `volsync/`: operational helpers (`mod.just` recipes) for the VolSync + Kopia backup plane

## Subtree Guides

Use more specific guides when working in these areas:

- default applications: [apps/default/CLAUDE.md](apps/default/CLAUDE.md)
- networking platform: [apps/networking/CLAUDE.md](apps/networking/CLAUDE.md)
- external secrets platform: [apps/external-secrets/CLAUDE.md](apps/external-secrets/CLAUDE.md)
- VolSync platform: [apps/volsync-system/CLAUDE.md](apps/volsync-system/CLAUDE.md)

Examples:

- `kubernetes/apps/default/...` -> root guide -> `kubernetes/CLAUDE.md` -> `kubernetes/apps/default/CLAUDE.md`
- `kubernetes/apps/networking/...` -> root guide -> `kubernetes/CLAUDE.md` -> `kubernetes/apps/networking/CLAUDE.md`

## GitOps Apply Boundary

Treat everything under `kubernetes/` as desired state for Flux, not as an imperative apply tree.

- Local edits in this repository do not change the cluster by themselves.
- `flux reconcile` only refreshes committed state that Flux can fetch.
- If changes are uncommitted or not pushed to the watched Git source, a reconcile will not deploy them.
- Be explicit whether you are describing local-only, committed, or live state.
- Use `just k8s flux-reconcile` or `flux reconcile ...` only for committed GitOps state, not as a substitute for commit or push.
- If the user wants to verify or apply uncommitted changes against the cluster, call out that this is intentionally outside the normal GitOps flow.

## Cross-Cutting Platform Facts

- Gateway API with Envoy Gateway is the active ingress model.
- Gateway exposure is split between `envoy-external` for Cloudflare Tunnel traffic and `envoy-internal` for LAN traffic.
- `k8s-gateway` provides split DNS for `horvathzoltan.me` on the LAN by resolving HTTPRoutes attached to `envoy-internal`.
- External Secrets with the `onepassword-connect` ClusterSecretStore is the standard for app-managed secrets.
- Persistent app PVC backups use the shared VolSync component under `components/volsync/` and store snapshots in OVH Object Storage through Kopia.
- File-level backups for shared user data, documents, and media use the `resticprofile` workload and also target OVH Object Storage; Backrest is the browsing surface for that repository.
- Critical apps may intentionally use both layers: PVC snapshots for the live app volume and a separate export into the shared `/backups/...` tree for secondary recovery coverage. Paperless is the canonical example.
- There is no shared auth platform currently declared under `kubernetes/apps/`.

## Default Patterns

- Optimize for low resource usage on a single-node cluster, hardened execution, GitOps-safe declarations, and reuse of existing repo patterns.
- Flux `Kustomization` objects in `ks.yaml` are the entry points for deployable app units.
- App manifests usually live under an `app/` directory referenced by `ks.yaml`.
- Shared reusable logic belongs in `components/` only when it is already proven across multiple apps.
- Dependencies between apps must be declared in `spec.dependsOn`; do not rely on creation order.
- Prefer official Helm charts first, then bjw-s `app-template`, then custom manifests only when needed.
- HelmRelease minimal-spec policy (bjw-s parity): an app `helmrelease.yaml` `spec` block should contain only `chartRef`, `interval`, `values` (and, very rarely, `postRenderers` when an upstream chart leaves no other way to patch a manifest field — `nextcloud`-style). The cluster-root `Kustomization` (`kubernetes/flux/cluster/ks.yaml`) injects `install.crds`, `install.strategy.name`, `rollback.cleanupOnFail`, `timeout`, `upgrade.cleanupOnFail`, `upgrade.crds`, `upgrade.strategy.name`, `upgrade.remediation.remediateLastFailure`, `upgrade.remediation.retries` into every HelmRelease through a kustomize patch — never repeat or override those fields per-app. Per-HR `install.createNamespace`, `install.remediation.retries: -1`, `upgrade.remediation.strategy: rollback`, `upgrade.remediation.retries: <N>`, `uninstall.keepHistory` were historical noise (legacy from the K3s era); they have been dropped. If a future app genuinely needs a different remediation profile, change the root patch or accept the default rather than re-introducing per-HR drift.
- Resource policy baseline:
  - user-facing workloads should declare explicit `resources.requests.cpu`, `resources.requests.memory`, and `resources.limits.memory`
  - CPU limits are optional and should be added only when there is a clear workload-specific reason
  - observability and platform components may use different resource profiles than user-facing apps, but should still set explicit requests and memory limits where the chart allows it

## Editing And Validation

- Optimize for hardened, rootless, low-overhead workloads unless a live sibling pattern or upstream requirement justifies an exception.
- Start Kubernetes YAML files with `---`, use 2-space indentation, and keep formatting close to neighboring manifests.
- Conventional top-level field order is `apiVersion → kind → metadata → spec`; within `metadata`, the order is `name → annotations → labels`. App-level manifests under `kubernetes/apps/*/app/` **do not carry `metadata.namespace`** — the Flux Kustomization `spec.targetNamespace` in the owning `ks.yaml` is the single source of namespace placement (bjw-s parity, repo-wide cleanup applied 2026-05-17). The same applies to `app/kustomization.yaml`: no top-level `namespace:` field. Match the existing sibling order when it diverges; do not reorder sibling manifests as a side effect of an unrelated change.
- Include `yaml-language-server` schema comments when the live sibling files already do so or when a stable schema URL is known.
- YAML anchor policy follows the bjw-s-labs reference repo:
  - **Allowed**: anchors for **scalar values** reused several times in the same manifest — typical examples are port numbers (`&port 8080`, `&httpPort 3000`), hostnames (`&host dash.horvathzoltan.me`), env-derived paths (`&exportDir "/data/nas/export"`), timezone (`&tz "Europe/Budapest"`), shared resource blocks (`&resources`, `&probes`, `&image`). Naming follows **lowerCamelCase**.
  - **Forbidden**: anchors for **scalar app names** (`name: &app paperless`) or for `controllers`, `persistence`, `serviceAccount`, `bindings` map **keys** (`*app :`). These collapse to literals that future readers (and grep) can follow without indirection. bjw-s never uses this pattern, and earlier such uses in this repo were a maintenance trap.
  - Rule of thumb: an anchor must save at least 2 reuses **and** name a value the chart values themselves understand. Anchors that exist only to deduplicate the app name are removed.
- Keep YAML formatting close to neighboring files rather than reformatting entire manifests.
- Preserve existing inline `# renovate:` annotations when touching versioned manifests.
- Use repo-local skills for detailed procedures:
  - app workloads: `.claude/skills/k8s-workloads/`
  - shared Flux wiring: `.claude/skills/flux-gitops/`
  - networking platform: `.claude/skills/networking-platform/`
  - shared secret delivery: `.claude/skills/external-secrets/`
  - backup policy and restore flow: `.claude/skills/volsync/`
- After edits, read the touched `ks.yaml`, `kustomization.yaml`, and primary manifests together, check dependency and naming consistency against sibling trees, and run the smallest relevant validation the environment allows.

## Current Reality

- No shared auth stack is currently present under `apps/`.
- Observability is split into `kube-prometheus-stack`, standalone `grafana`, and supporting exporters.
