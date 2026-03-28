# AGENTS.md - AI Assistant Guidance for home-ops

This file is the operational guide for working in this repository. Treat it as the authoritative source for agent behavior inside `home-ops`.

## Non-Negotiables

- Treat this repository as potentially public and durable. Do not introduce plaintext credentials or new sensitive external identifiers.
- Do not commit plaintext secrets, API keys, tokens, passwords, or certificate material anywhere in the repo.
- Do not hardcode public domains, public IP addresses, or email addresses in manifests, docs, task wrappers, or examples when the value belongs in secret-backed configuration.
- Private RFC1918 addresses, cluster-local hostnames, and other internal topology values are acceptable when they reflect the live repo model.
- Sensitive cluster-wide substitutions belong in `kubernetes/flux/vars/cluster-secrets.sops.yaml`; non-secret cluster-wide values belong in `kubernetes/flux/vars/cluster-settings.yaml`.
- For app-managed secrets, prefer External Secrets backed by the shared `ClusterSecretStore` named `onepassword` when the target area already follows that pattern.
- Keep GitOps as the source of truth for steady-state cluster configuration. Avoid manual out-of-band `kubectl apply` changes except for documented bootstrap, recovery, or existing task-driven workflows in the repo.

## Scope And Priorities

Use these sources in this order:

1. The current files in the repository
2. This `AGENTS.md`
3. More specific `AGENTS.md` files in subdirectories
4. `Taskfile.yml` and `.taskfiles/*`
5. `.github/renovate.json5` and `.github/renovate/*`
6. repo-local skills under `.codex/skills/`
7. Root `README.md` and `docs/*.md` for human-facing context

## Guide Traversal Rule

When working on any file or subtree, always read `AGENTS.md` files from the repository root down to the target directory.

Practical rule:

1. start at the root guide
2. descend through each parent directory on the path
3. apply the most specific guide last

Examples:

- `kubernetes/apps/networking/...` -> root guide -> `kubernetes/AGENTS.md` -> `kubernetes/apps/networking/AGENTS.md`
- `provision/cloudflare/...` -> root guide -> `provision/AGENTS.md` -> `provision/cloudflare/AGENTS.md`

## Current Repository Shape

This repository currently manages a single-node home infrastructure stack with these main areas:

- `kubernetes/`: GitOps-managed cluster state with Flux `Kustomization` objects, Helm releases, and reusable components
- `provision/kubernetes/`: Ansible inventory and playbooks for host and cluster lifecycle operations
- `provision/cloudflare/`: Terraform for Cloudflare DNS, tunnel, workers, pages, redirects, and zone configuration
- `.codex/skills/`: repo-local Codex skill sources for reusable workflow knowledge
- `.taskfiles/`: operational entry points used from `Taskfile.yml`
- `.github/renovate*`: Renovate policy and package rule definitions
- `docs/`: human-facing runbooks and reference notes

## Working Rules

- Inspect the target area before editing; do not assume the memory docs are current.
- Keep changes minimal and consistent with existing patterns.
- Prefer existing abstractions over inventing new ones.
- Preserve existing secret flows, shared resource names, and task-driven workflows unless the task explicitly changes them.
- Do not create new documentation locations unless they clearly fit the current structure.
- Preserve `README.md` as human-facing overview unless the task explicitly requires changing it.
- Prefer repo-native operational entry points over raw commands when they already exist in Taskfiles.
- Distinguish carefully between local repository state and live cluster state.
- Local file edits do not change the cluster until the watched Git source is updated and reconciled.
- Do not treat `flux reconcile` as if it applied the local working tree.

## Repo-Wide Anti-Patterns

- Hardcoding public domains, public IPs, email addresses, credentials, or other sensitive external identifiers.
- Introducing plaintext secrets outside SOPS-encrypted files or External Secrets.
- Making imperative cluster changes that bypass Flux for normal steady-state configuration.
- Treating local file edits as if they were already deployed by GitOps, or using `flux reconcile` as though it applied the local working tree.
- Changing shared secret names, store names, or dependency wiring without tracing the related Flux and Taskfile references first.
- Refactoring file layout or documentation structure when an established local pattern already exists.

## State To Assume Today

- There is no shared identity stack currently declared under `kubernetes/apps/`.
- The active ingress stack is Envoy Gateway with Gateway API, not Traefik.
- VolSync backups are centralized through `kubernetes/components/volsync/`.
- Secrets are split between SOPS-managed repo secrets and 1Password through External Secrets.
- Cloudflare resources are managed from `provision/cloudflare/`.

## Validation And Routing

- After edits, run the smallest relevant validation available for the touched area.
- When validation cannot run, say which dependency is missing: tool, credential, cluster access, or other environment requirement.
- When mentioning Kubernetes impact, be explicit whether the change is local-only, committed, or live.
- Use repo-local skills for procedures and detailed checklists:
  - `.codex/skills/architecture-review/`
  - `.codex/skills/security-review/`
  - `.codex/skills/sre/`
  - `.codex/skills/taskfiles/`
  - `.codex/skills/versions-renovate/`
  - `.codex/skills/sops-secrets/`
  - `.codex/skills/flux-gitops/`
  - other domain skills under `.codex/skills/`

## Taskfile And Renovate Model

- `Taskfile.yml` is the command index; prefer existing task namespaces over ad-hoc shell flows.
- Current task domains are `an:`, `es:`, `fx:`, `hm:`, `ku:`, `pc:`, `so:`, `tf:`, and `vs:`.
- Task orchestration fans out through `.taskfiles/Ansible`, `.taskfiles/ExternalSecrets`, `.taskfiles/Flux`, `.taskfiles/Kubernetes`, `.taskfiles/PreCommit`, `.taskfiles/Sops`, `.taskfiles/Terraform`, and `.taskfiles/VolSync`.
- Renovate configuration starts in `.github/renovate.json5` and imports the fragments under `.github/renovate/`.
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

- `kubernetes/`: see [kubernetes/AGENTS.md](kubernetes/AGENTS.md)
- `provision/`: see [provision/AGENTS.md](provision/AGENTS.md)
- `.codex/skills/`: see [.codex/skills/AGENTS.md](.codex/skills/AGENTS.md)
