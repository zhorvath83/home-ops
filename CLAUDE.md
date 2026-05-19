# CLAUDE.md - AI Assistant Guidance for home-ops

This file is the operational guide for working in this repository. Treat it as the authoritative source for agent behavior inside `home-ops`. Subdirectory guides live in `CLAUDE.md` files and are traversed manually per the rule below; current-state detail per area lives in Basic Memory under `docs/areas/<name>` and is read via the `basic-memory` MCP.

## Non-Negotiables

- Treat this repository as potentially public and durable. Do not introduce plaintext credentials or new sensitive external identifiers.
- Do not commit plaintext secrets, API keys, tokens, passwords, or certificate material anywhere in the repo.
- The public domain, public IPs **may be hardcoded** in manifests, docs, and operational wrappers — they are not secret, they are published via DNS/TLS/Cloudflare.
- Private RFC1918 addresses, cluster-local hostnames, and other internal topology values may be hardcoded directly in manifests when they reflect the live repo model.
- App-level secrets (tokens, passwords, hashes, multi-line config files) are delivered via External Secrets backed by the shared `ClusterSecretStore` named `onepassword-connect`. Values live either inline in manifests (when non-sensitive) or in per-app `ExternalSecret` resources. Multi-line config-as-secret content (e.g. homepage dashboard config) is stored in 1Password as multi-line text fields and rendered via ESO `template.data`.
- Bootstrap-time secrets (1Password Connect creds, Talos machine config templating) are injected from 1Password via `op inject` during the `just cluster-bootstrap` chain.
- Keep GitOps as the source of truth for steady-state cluster configuration. Avoid manual out-of-band `kubectl apply` changes except for documented bootstrap, recovery, or existing Just-driven workflows in the repo.

## Scope And Priorities

Use these sources in this order:

1. The current files in the repository
2. This `CLAUDE.md`
3. More specific `CLAUDE.md` files in subdirectories
4. Basic Memory area-references under `docs/areas/<name>` (read via `basic-memory` MCP)
5. `.justfile` (root) and `mod.just` files under `kubernetes/`, `kubernetes/bootstrap/`, `kubernetes/talos/`, `kubernetes/volsync/`, `provision/openmediavault/`, `provision/cloudflare/`, `provision/ovh/`, `provision/openwrt/`
6. `.renovaterc.json5` (repo root) and the imported fragments under `.renovate/*.json5`
7. repo-local skills under `.claude/skills/`
8. Root `README.md` for human-facing context

## Guide Traversal Rule

When working on any file or subtree, always read this root `CLAUDE.md` first, then descend through any `CLAUDE.md` files on the path to the target directory. Once the durable guardrails are clear, consult the matching Basic Memory area-reference for current-state detail.

Practical rule:

1. start at the root guide
2. descend through each parent directory on the path
3. apply the most specific guide last
4. consult the matching `docs/areas/<area>` BM note via the `basic-memory` MCP for component-level facts

Examples:

- `kubernetes/apps/networking/...` -> root `CLAUDE.md` -> `kubernetes/CLAUDE.md` -> `kubernetes/apps/networking/CLAUDE.md` -> BM `docs/areas/networking`
- `provision/cloudflare/...` -> root `CLAUDE.md` -> `provision/CLAUDE.md` -> `provision/cloudflare/CLAUDE.md` -> BM `docs/areas/cloudflare`

## Current Repository Shape

This repository currently manages a single-node home infrastructure stack with these main areas:

- `kubernetes/` — GitOps-managed cluster state with Flux `Kustomization` objects, Helm releases, and reusable components
- `provision/cloudflare/` — Terraform for Cloudflare DNS, tunnel, workers, pages, redirects, and zone configuration
- `provision/ovh/` — Terraform for OVH Cloud Project Storage (S3 backup buckets and the S3 user consumed by the VolSync/Kopia and resticprofile backup planes)
- `.claude/skills/` — repo-local skill sources for reusable workflow knowledge
- `.justfile` + `**/mod.just` — operational entry points (Just-based)
- `.renovaterc.json5` + `.renovate/*.json5` — Renovate policy and package rule definitions (root config + per-topic fragments)
- `basic-memory/` — Basic Memory knowledge graph (project name `home-ops`); area-references, schemas, decisions, and roadmap notes authored via Basic Memory MCP and committed to git

## Working Rules

- Inspect the target area before editing; do not assume the BM area-reference is fully current — the `verified_at` field in each note is the staleness signal.
- Keep changes minimal and consistent with existing patterns.
- Prefer existing abstractions over inventing new ones.
- Preserve existing secret flows, shared resource names, and Just-driven workflows unless the task explicitly changes them.
- Do not create new documentation locations unless they clearly fit the current structure.
- Preserve `README.md` as human-facing overview unless the task explicitly requires changing it.
- Prefer repo-native operational entry points over raw commands when they already exist as Just recipes.
- Distinguish carefully between local repository state and live cluster state.
- Local file edits do not change the cluster until the watched Git source is updated and reconciled.
- Do not treat `flux reconcile` as if it applied the local working tree.
- Stage commits with explicit pathspecs (`git add <file>` per touched file), never `git add -A` or `git add .`. The working tree often contains user-driven in-progress work (config refactors, schema URL migrations, doc renames) that must not bleed into unrelated commits. The session-start `git status` snapshot can be stale — always run `git status` immediately before staging to see the live state.

## Repo-Wide Anti-Patterns

- Hardcoding public domains, public IPs, email addresses, credentials, or other sensitive external identifiers.
- Introducing plaintext secrets outside External Secrets.
- Making imperative cluster changes that bypass Flux for normal steady-state configuration.
- Treating local file edits as if they were already deployed by GitOps, or using `flux reconcile` as though it applied the local working tree.
- Changing shared secret names, store names, or dependency wiring without tracing the related Flux and Just recipe references first.
- Refactoring file layout or documentation structure when an established local pattern already exists.

## Validation And Routing

- After edits, run the smallest relevant validation available for the touched area.
- When validation cannot run, say which dependency is missing: tool, credential, cluster access, or other environment requirement.
- When mentioning Kubernetes impact, be explicit whether the change is local-only, committed, or live.
- Use repo-local skills for procedures and detailed checklists:
  - `.claude/skills/architecture-review/`
  - `.claude/skills/security-review/`
  - `.claude/skills/sre/`
  - `.claude/skills/versions-renovate/`
  - `.claude/skills/flux-gitops/`
  - other domain skills under `.claude/skills/`

## Just And Renovate Model

- The root `.justfile` is the command index; prefer existing Just modules over ad-hoc shell flows.
- Current Just modules (groups): `cluster-bootstrap`, `k8s`, `talos`, `volsync`, `omv`, `cloudflare`, `ovh`, `openwrt`.
- Each module lives next to the area it operates on: `kubernetes/bootstrap/mod.just`, `kubernetes/mod.just`, `kubernetes/talos/mod.just`, `kubernetes/volsync/mod.just`, `provision/openmediavault/mod.just`, `provision/cloudflare/mod.just`, `provision/ovh/mod.just`, `provision/openwrt/mod.just`.
- Invoke recipes as `just <group> <recipe> [args]` (e.g. `just k8s sync-hr paperless default`, `just volsync list-snapshots actual`, `just talos apply-node k8s-cp0`).
- Recipe arguments are **positional only** — Just does not parse `key=value` named arguments the way the previous Task system did. Pass values in order, omitting trailing defaults.
- Pre-commit is invoked directly via the `pre-commit` CLI (no Just wrapper); the hook list is in `.pre-commit-config.yaml`.
- Renovate configuration starts in `.renovaterc.json5` at the repo root and imports the fragments under `.renovate/` (`allowedVersions`, `autoMerge`, `customManagers`, `disabledDatasources`, `groups`, `overrides`, `prBodyNotes`, `semanticCommits`, `talosFactory`).
- Preserve inline `# renovate:` annotations when touching versioned manifests.
- If Renovate behavior changes, inspect the root config together with the touched fragment or annotation.

## Commit Conventions

If the user asks for a commit, follow the repo's existing conventional commit style:

- format: `<emoji> <type>(<scope>): <subject>`
- keep the subject short and imperative
- use focused commits instead of bundling unrelated changes

Common types:

- `✨ feat`
- `🐛 fix`
- `📝 docs`
- `♻️ refactor`
- `🔧 build`
- `👷 ci`
- `🧹 chore`
- `🔥 remove`

## Directory Guides

- `kubernetes/`: see [kubernetes/CLAUDE.md](kubernetes/CLAUDE.md)
- `provision/`: see [provision/CLAUDE.md](provision/CLAUDE.md)
- `.claude/skills/`: see [.claude/skills/CLAUDE.md](.claude/skills/CLAUDE.md)

## Basic Memory Area-References

Each area-reference is evidence-backed (file+line citations) and schema-validated. Read via the `basic-memory` MCP — do not Read/Edit `basic-memory/` files directly.

Platform areas:

- `docs/areas/flux-gitops` — Flux Operator + FluxInstance, cluster-apps root Kustomization, shared HelmRelease defaults, Pushover alerting
- `docs/areas/networking` — Envoy Gateway split (external/internal), Cloudflare Tunnel, ExternalDNS, k8s-gateway, Cilium L2 IPAM
- `docs/areas/external-secrets` — ESO + 1Password Connect + ClusterSecretStore, bootstrap secret flow
- `docs/areas/talos-cluster` — single control-plane Talos node, machine config templating, op-inject flow
- `docs/areas/volsync-backup` — VolSync + Kopia for PVC backups, jitter policy, KopiaMaintenance, per-app component
- `docs/areas/resticprofile-backup` — file-level NAS `/backups` plane + Backrest browse UI
- `docs/areas/observability` — kube-prometheus-stack + grafana + speedtest-exporter (draft)

Provisioning areas:

- `docs/areas/cloudflare` — zone, tunnel, Access apps, Workers, R2, mail-stack DNS, WAF
- `docs/areas/ovh-storage` — S3 buckets, object-store user, S3 policy, 1Password sync

Application area:

- `docs/areas/k8s-workloads` — app inventory, canonical shape, cross-cutting patterns, exposure model
