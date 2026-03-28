# Kubernetes Agent Guide

This guide applies to everything under `kubernetes/`.

## What Lives Here

`kubernetes/` contains the declarative cluster state reconciled by Flux. The main structure is:

- `apps/`: application and platform workloads grouped by namespace or domain
- `bootstrap/`: initial Flux bootstrap resources
- `components/`: reusable Kustomize components
- `flux/`: Flux configuration, repositories, and cluster variables

## Subtree Guides

Use more specific guides when working in these areas:

- default applications: [apps/default/AGENTS.md](apps/default/AGENTS.md)
- networking platform: [apps/networking/AGENTS.md](apps/networking/AGENTS.md)
- external secrets platform: [apps/external-secrets/AGENTS.md](apps/external-secrets/AGENTS.md)
- VolSync platform: [apps/volsync-system/AGENTS.md](apps/volsync-system/AGENTS.md)

Examples:

- `kubernetes/apps/default/...` -> root guide -> `kubernetes/AGENTS.md` -> `kubernetes/apps/default/AGENTS.md`
- `kubernetes/apps/networking/...` -> root guide -> `kubernetes/AGENTS.md` -> `kubernetes/apps/networking/AGENTS.md`

## GitOps Apply Boundary

Treat everything under `kubernetes/` as desired state for Flux, not as an imperative apply tree.

- Local edits in this repository do not change the cluster by themselves.
- `flux reconcile` only refreshes committed state that Flux can fetch.
- If changes are uncommitted or not pushed to the watched Git source, a reconcile will not deploy them.
- Be explicit whether you are describing local-only, committed, or live state.
- Use `task fx:reconcile` or `flux reconcile ...` only for committed GitOps state, not as a substitute for commit or push.
- If the user wants to verify or apply uncommitted changes against the cluster, call out that this is intentionally outside the normal GitOps flow.

## Cross-Cutting Platform Facts

- Gateway API with Envoy Gateway is the active ingress model.
- Gateway exposure is split between `envoy-external` for Cloudflare Tunnel traffic and `envoy-internal` for LAN traffic.
- `k8s-gateway` provides split DNS for `${PUBLIC_DOMAIN}` on the LAN by resolving HTTPRoutes attached to `envoy-internal`.
- External Secrets with the `onepassword` ClusterSecretStore is the standard for app-managed secrets.
- Persistent app PVC backups use the shared VolSync component under `components/volsync/` and store snapshots in B2 through Kopia.
- File-level backups for shared user data, documents, and media use the `resticprofile` workload and also target B2; Backrest is the browsing surface for that repository.
- Critical apps may intentionally use both layers: PVC snapshots for the live app volume and a separate export into the shared `/backups/...` tree for secondary recovery coverage. Paperless is the canonical example.
- There is no shared auth platform currently declared under `kubernetes/apps/`.

## Default Patterns

- Optimize for low resource usage on a single-node cluster, hardened execution, GitOps-safe declarations, and reuse of existing repo patterns.
- Flux `Kustomization` objects in `ks.yaml` are the entry points for deployable app units.
- App manifests usually live under an `app/` directory referenced by `ks.yaml`.
- Shared reusable logic belongs in `components/` only when it is already proven across multiple apps.
- Dependencies between apps must be declared in `spec.dependsOn`; do not rely on creation order.
- Prefer official Helm charts first, then bjw-s `app-template`, then custom manifests only when needed.
- Resource policy baseline:
  - user-facing workloads should declare explicit `resources.requests.cpu`, `resources.requests.memory`, and `resources.limits.memory`
  - CPU limits are optional and should be added only when there is a clear workload-specific reason
  - observability and platform components may use different resource profiles than user-facing apps, but should still set explicit requests and memory limits where the chart allows it

## Editing And Validation

- Optimize for hardened, rootless, low-overhead workloads unless a live sibling pattern or upstream requirement justifies an exception.
- Start Kubernetes YAML files with `---`, use 2-space indentation, keep top-level key order conventional, and keep formatting close to neighboring manifests.
- Include `yaml-language-server` schema comments when the live sibling files already do so or when a stable schema URL is known.
- Prefer short, stable anchors only when the same value is reused several times in one manifest. Do not use YAML anchors for scalar app names, resource names, or `controllers` keys.
- Keep YAML formatting close to neighboring files rather than reformatting entire manifests.
- Preserve existing inline `# renovate:` annotations when touching versioned manifests.
- Use repo-local skills for detailed procedures:
  - app workloads: `.codex/skills/k8s-workloads/`
  - shared Flux wiring: `.codex/skills/flux-gitops/`
  - networking platform: `.codex/skills/networking-platform/`
  - shared secret delivery: `.codex/skills/external-secrets/`
  - repo-encrypted secrets: `.codex/skills/sops-secrets/`
  - backup policy and restore flow: `.codex/skills/volsync/`
- After edits, read the touched `ks.yaml`, `kustomization.yaml`, and primary manifests together, check dependency and naming consistency against sibling trees, and run the smallest relevant validation the environment allows.

## Current Reality To Prefer Over Old Notes

- No shared auth stack is currently present under `apps/`.
- Observability is split into `kube-prometheus-stack`, standalone `grafana`, and supporting exporters.
- CrowdSec does not currently exist in the live `apps/` tree, even though it appears in memory notes.
