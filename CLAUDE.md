# CLAUDE.md - AI Assistant Guidance for home-ops

This file is the operational guide for working in this repository. Treat it as the authoritative source for agent behavior inside `home-ops`. Subdirectory guides live in `CLAUDE.md` files and are traversed manually per the rule below.

## Non-Negotiables

- Treat this repository as potentially public and durable. Do not introduce plaintext credentials or new sensitive external identifiers.
- Do not commit plaintext secrets, API keys, tokens, passwords, or certificate material anywhere in the repo.
- Do not hardcode public domains, public IP addresses, or email addresses in manifests, docs, operational wrappers, or examples when the value belongs in secret-backed configuration.
- Private RFC1918 addresses, cluster-local hostnames, and other internal topology values are acceptable when they reflect the live repo model.
- Sensitive cluster-wide substitutions belong in `kubernetes/flux/vars/cluster-secrets.sops.yaml`; non-secret cluster-wide values belong in `kubernetes/flux/vars/cluster-settings.yaml`.
- For app-managed secrets, prefer External Secrets backed by the shared `ClusterSecretStore` named `onepassword-connect` when the target area already follows that pattern.
- Keep GitOps as the source of truth for steady-state cluster configuration. Avoid manual out-of-band `kubectl apply` changes except for documented bootstrap, recovery, or existing Just-driven workflows in the repo.

## Scope And Priorities

Use these sources in this order:

1. The current files in the repository
2. This `CLAUDE.md`
3. More specific `CLAUDE.md` files in subdirectories
4. `.justfile` (root) and `mod.just` files under `kubernetes/`, `kubernetes/bootstrap/`, `kubernetes/talos/`, `kubernetes/volsync/`, `provision/openmediavault/`, `provision/cloudflare/`, `provision/ovh/`, `provision/sops/`, `provision/openwrt/`
5. `.renovaterc.json5` (repo root) and the imported fragments under `.renovate/*.json5`
6. repo-local skills under `.claude/skills/`
7. Root `README.md` and `docs/*.md` for human-facing context

## Guide Traversal Rule

When working on any file or subtree, always read this root `CLAUDE.md` first, then descend through any `CLAUDE.md` files on the path to the target directory.

Practical rule:

1. start at the root guide
2. descend through each parent directory on the path
3. apply the most specific guide last

Examples:

- `kubernetes/apps/networking/...` -> root `CLAUDE.md` -> `kubernetes/CLAUDE.md` -> `kubernetes/apps/networking/CLAUDE.md`
- `provision/cloudflare/...` -> root `CLAUDE.md` -> `provision/CLAUDE.md` -> `provision/cloudflare/CLAUDE.md`

## Current Repository Shape

This repository currently manages a single-node home infrastructure stack with these main areas:

- `kubernetes/`: GitOps-managed cluster state with Flux `Kustomization` objects, Helm releases, and reusable components
- `provision/cloudflare/`: Terraform for Cloudflare DNS, tunnel, workers, pages, redirects, and zone configuration
- `provision/ovh/`: Terraform for OVH Cloud Project Storage (S3 backup buckets and the S3 user consumed by the VolSync/Kopia and resticprofile backup planes)
- `.claude/skills/`: repo-local skill sources for reusable workflow knowledge
- `.justfile` + `**/mod.just`: operational entry points (Just-based, replaces the previous Task system)
- `.renovaterc.json5` + `.renovate/*.json5`: Renovate policy and package rule definitions (root config + per-topic fragments)
- `docs/`: human-facing runbooks and reference notes

## Working Rules

- Inspect the target area before editing; do not assume the memory docs are current.
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
- Introducing plaintext secrets outside SOPS-encrypted files or External Secrets.
- Making imperative cluster changes that bypass Flux for normal steady-state configuration.
- Treating local file edits as if they were already deployed by GitOps, or using `flux reconcile` as though it applied the local working tree.
- Changing shared secret names, store names, or dependency wiring without tracing the related Flux and Just recipe references first.
- Refactoring file layout or documentation structure when an established local pattern already exists.

## State To Assume Today

- There is no shared identity stack currently declared under `kubernetes/apps/`.
- The active ingress stack is Envoy Gateway with Gateway API.
- The ingress model is split between `envoy-external` for Cloudflare-published traffic and `envoy-internal` for LAN traffic.
- LAN split DNS is provided by `k8s-gateway`, which watches routes attached to `envoy-internal` and returns the internal Envoy VIP.
- Backup handling is intentionally split into two planes that both target OVH object storage:
  - cluster PVC backups use VolSync plus Kopia and are centralized through `kubernetes/components/volsync/`
  - user documents, media, and other file-level data under the shared backup tree use `resticprofile`, with Backrest as the snapshot browser
- Some critical workloads keep an extra app-level export in addition to PVC snapshots so the exported data is also covered by the file-level backup plane. Current example: Paperless exports documents to `/backups/paperless`.
- Secrets are split between SOPS-managed repo secrets and 1Password through External Secrets.
- Cloudflare resources are managed from `provision/cloudflare/`.
- OVH Cloud Project Storage buckets and the S3 user that backs both backup planes are managed from `provision/ovh/`.

## Validation And Routing

- After edits, run the smallest relevant validation available for the touched area.
- When validation cannot run, say which dependency is missing: tool, credential, cluster access, or other environment requirement.
- When mentioning Kubernetes impact, be explicit whether the change is local-only, committed, or live.
- Use repo-local skills for procedures and detailed checklists:
  - `.claude/skills/architecture-review/`
  - `.claude/skills/security-review/`
  - `.claude/skills/sre/`
  - `.claude/skills/versions-renovate/`
  - `.claude/skills/sops-secrets/`
  - `.claude/skills/flux-gitops/`
  - other domain skills under `.claude/skills/`

## Just And Renovate Model

- The root `.justfile` is the command index; prefer existing Just modules over ad-hoc shell flows.
- Current Just modules (groups) are: `cluster-bootstrap`, `k8s`, `talos`, `volsync`, `omv`, `cloudflare`, `ovh`, `sops`, `openwrt`.
- Each module lives next to the area it operates on: `kubernetes/bootstrap/mod.just`, `kubernetes/mod.just`, `kubernetes/talos/mod.just`, `kubernetes/volsync/mod.just`, `provision/openmediavault/mod.just`, `provision/cloudflare/mod.just`, `provision/ovh/mod.just`, `provision/sops/mod.just`, `provision/openwrt/mod.just`.
- Invoke recipes as `just <group> <recipe> [args]` (e.g. `just k8s sync-hr paperless default`, `just volsync list-snapshots actual`, `just sops re-encrypt`, `just talos apply-node k8s-cp0`).
- Recipe arguments are **positional only** — Just does not parse `key=value` named arguments the way the previous Task system did. Pass values in order, omitting trailing defaults.
- Pre-commit is invoked directly via the `pre-commit` CLI (no Just wrapper); the hook list is in `.pre-commit-config.yaml`.
- Renovate configuration starts in `.renovaterc.json5` at the repo root and imports the fragments under `.renovate/` (`allowedVersions`, `autoMerge`, `customManagers`, `disabledDatasources`, `groups`, `overrides`, `prBodyNotes`, `semanticCommits`, `talosFactory`).
- Preserve inline `# renovate:` annotations when touching versioned manifests.
- If Renovate behavior changes, inspect the root config together with the touched fragment or annotation.

## Commit Conventions

If the user asks for a commit, follow the repo's existing conventional commit style from the old project guidance:

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
