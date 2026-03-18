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
6. Root `README.md` and `docs/*.md` for human-facing context

## Guide Traversal Rule

When working on any file or subtree, always read `AGENTS.md` files from the repository root down to the target directory.

Practical rule:

1. start at the root `AGENTS.md`
2. descend through each parent directory on the path to the target
3. apply the most specific guide last

Example:

- for work in `kubernetes/apps/networking/...`, read root `AGENTS.md` -> `kubernetes/AGENTS.md` -> `kubernetes/apps/networking/AGENTS.md`
- for work in `provision/cloudflare/...`, read root `AGENTS.md` -> `provision/AGENTS.md`

## Current Repository Shape

This repository currently manages a single-node home infrastructure stack with these main areas:

- `kubernetes/`: GitOps-managed cluster state with Flux `Kustomization` objects, Helm releases, and reusable components
- `provision/kubernetes/`: Ansible inventory and playbooks for host and cluster lifecycle operations
- `provision/cloudflare/`: Terraform for Cloudflare DNS, tunnel, workers, pages, redirects, and zone configuration
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
- Distinguish carefully between local repository state and live cluster state. Editing files in the working tree does not change the cluster until those changes are committed, pushed to the Git source watched by Flux, and reconciled or picked up by the next sync.
- Do not run `flux reconcile` just because local files changed. A reconcile only refreshes the committed source and reapplies the live GitOps state; it does not read uncommitted or unpushed local edits.

## Repo-Wide Anti-Patterns

- Hardcoding public domains, public IPs, email addresses, credentials, or other sensitive external identifiers.
- Introducing plaintext secrets outside SOPS-encrypted files or External Secrets.
- Making imperative cluster changes that bypass Flux for normal steady-state configuration.
- Treating local file edits as if they were already deployed by GitOps, or using `flux reconcile` as though it applied the local working tree.
- Changing shared secret names, store names, or dependency wiring without tracing the related Flux and Taskfile references first.
- Refactoring file layout or documentation structure when an established local pattern already exists.

## State To Assume Today

- The active identity stack is `pocket-id` plus `tinyauth`, not `rauthy`.
- The active ingress stack is Envoy Gateway with Gateway API, not Traefik.
- VolSync backups are centralized through `kubernetes/components/volsync/`.
- Secrets are split between SOPS-managed repo secrets and 1Password through External Secrets.
- Cloudflare resources are managed from `provision/cloudflare/`.

## Validation Expectations

- For Kubernetes changes, inspect the affected `ks.yaml`, `kustomization.yaml`, and app manifests together.
- For Taskfile-related changes, check the relevant `.taskfiles/*/Tasks.yaml`.
- For Renovate changes, inspect `.github/renovate.json5` together with the imported JSON fragments in `.github/renovate/`.
- For Terraform changes, inspect the relevant files in `provision/cloudflare/` and keep commands aligned with `task tf:*`.
- For Ansible changes, inspect inventory, playbooks, and task wrappers together.
- After edits, run the most relevant lightweight validation command available for the touched area.
- When mentioning cluster impact, be explicit whether a change is only local, committed but not yet reconciled, or already live in the cluster.
- If validation cannot be run, say so explicitly and name the missing tool, credential, cluster access, or environment dependency.

## Repository Knowledge Sources

- Task orchestration starts in `Taskfile.yml` and fans out through `.taskfiles/Ansible`, `.taskfiles/Flux`, `.taskfiles/Kubernetes`, `.taskfiles/Terraform`, `.taskfiles/VolSync`, `.taskfiles/ExternalSecrets`, `.taskfiles/PreCommit`, and `.taskfiles/Sops`.
- Renovate configuration starts in `.github/renovate.json5` and imports the rule fragments from `.github/renovate/`.
- Inline `# renovate:` annotations inside Kubernetes and provisioning manifests are part of the live dependency-management model and must be preserved when editing those files.

## Taskfile Operating Model

Use `Taskfile.yml` as the command index for the repository.

Current task domains:

- `list:` List available tasks grouped by domain
- `an:` Ansible host and cluster lifecycle tasks
- `hm:` Host maintenance tasks for Proxmox, OpenMediaVault, OpenWrt, and the k3s host
- `fx:` Flux bootstrap, reconcile, and cluster inspection tasks
- `ku:` Kubernetes utility tasks such as kubeconfig fetch and temporary PVC mounts
- `tf:` Cloudflare Terraform operations
- `vs:` VolSync snapshot, list, unlock, forget, and restore flows
- `es:` ExternalSecret sync helpers
- `pc:` pre-commit setup and execution
- `so:` SOPS encryption and re-encryption helpers

Practical rule:

- if a task already exists for an operation, prefer that workflow over inventing a bespoke shell command sequence
- if no task exists, inspect the nearest task domain first before adding a new one

## Renovate Operating Model

Renovate is a first-class part of the repo, not incidental automation.

Current live behavior from `.github/renovate.json5` and imported fragments:

- dependency dashboard is enabled
- semantic commits are enabled
- patch updates auto-merge
- docker digest updates auto-merge
- major docker and helm updates are labeled for review
- Kubernetes YAML under `kubernetes/` is scanned by Flux, Helm values, Kubernetes, and custom regex managers
- custom regex managers rely on inline `# renovate:` annotations in manifests
- pre-commit dependency updates are enabled
- some packages are grouped or version-constrained in `.github/renovate/*.json`

Editing rules:

- preserve existing `# renovate:` comments when touching versioned manifests
- if adding a dependency Renovate cannot discover automatically, add the minimal inline annotation pattern already used elsewhere
- inspect `.github/renovate/packageRules.json`, `.github/renovate/groupPackages.json`, and `.github/renovate/allowedVersions.json` before changing update behavior

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
