# Project-Specific AI Instructions - home-ops
<!-- Keep all instructions in English for AI consumption -->

## Project Identity

**Project Name**: home-ops
**GitHub Repository**: https://github.com/zhorvath83/home-ops
**GitHub Project ID**: 381819341
**Basic Memory Project**: `home-ops`

## Project Context

**Project Type**: Personal home infrastructure / single-node Kubernetes cluster GitOps monorepo (Infrastructure as Code)

**Primary Language**: YAML (Kubernetes/GitOps manifests), HCL (Terraform), minijinja/Jinja2 templates, shell scripts — no single application runtime language; the repo is infrastructure/configuration-as-code

**Status**: Active production cluster on a single bare-metal Talos Linux control-plane node (HP ProDesk 600 G6), with NAS/OMV host as secondary machine. Flux-based GitOps is the steady-state reconciliation model.

## Technology Stack

- **Cluster OS & Runtime**: Talos Linux (immutable, API-driven) + Kubernetes
- **GitOps Engine**: Flux CD via Flux Operator pattern; root Kustomization at `kubernetes/flux/cluster/ks.yaml`
- **Package/Deployment**: Mainly Helm 4.x, Helmfile
- **CNI & Ingress**: Cilium; Envoy Gateway
- **Secrets Management**: External Secrets Operator + 1Password Connect
- **Storage**: democratic-csi (local-hostpath backend)
- **Backup Planes**: VolSync + Kopia → S3 (PVC snapshots)
- **Provisioning (cloud)**: Terraform for Cloudflare and OVH Cloud Project Storage (S3)
- **Task Runner**: Just
- **Version/Tool Management**: mise
- **Dependency Update Automation**: Renovate
- **Linting/Security**: pre-commit hooks, yamlfmt, yamllint, actionlint, shellcheck, gitleaks, tflint, zizmor, markdownlint-cli2
- **Knowledge Graph**: Basic Memory
- **Source Control**: GitHub, default branch `main`, conventional commits with emoji prefixes

## Source Control Platform

This project is on **GitHub** (not GitLab). The personal layer's `gitops-principles` and `gitlab-workflow` rules are GitLab-oriented; the following overrides apply to this project:

- Default branch: `main` — the personal rule's `master` terminology does NOT apply here
- Use **Pull Request (PR)** — not "Merge Request / MR"
- Branches may be created locally; the GitLab MCP and MR-first branch creation rule do not apply
- CI/CD is driven by **GitHub Actions** (`.github/workflows/`); there is no `.gitlab-ci.yml`
- Issues and PRs are managed on GitHub, not via GitLab MCP

## Architecture Quick View

```
home-ops
├── kubernetes/       # GitOps-managed cluster state (Flux)
│   ├── apps/         # workloads grouped by namespace
│   ├── bootstrap/    # Talos + K8s platform bootstrap
│   ├── components/   # reusable Kustomize components
│   ├── flux/cluster/ # root cluster-apps Kustomization
│   ├── talos/        # Talos machine config templates
│   └── volsync/      # backup plane helpers
├── provision/        # provider-facing infrastructure (Terraform)
│   ├── cloudflare/   # DNS, Tunnel, Access, WAF, R2, Workers
│   ├── ovh/          # S3 backup storage
│   ├── openmediavault/
│   └── openwrt/
├── .claude/skills/   # repo-local AI skills
└── basic-memory/     # project knowledge graph

```

## AI Workflow Model

```
Request → Identify Domain → Load Relevant Skills → Gather Specifics → Execute
```

This project uses **Claude Code** with a **skill composition model**:
- **Language skills** (code style, type system, architecture) + **Role skills** (debugging, testing, security) are composed per task
- Skills load **on-demand** via progressive disclosure (metadata → SKILL.md → references/)
- Use the **Task tool** only for truly parallel, independent work streams — not for role-based delegation
- **Rules** (personal + project) enforce constraints with high priority, always loaded

## What the Personal Layer Provides

The personal layer (`~/.claude/`) provides global rules and skills available in ALL projects:
- **Rules** (always loaded): security-principles, code-generation, working-principles, code-style, spec-driven-development, MCP access, BM access, tool assignment, document constraints, operating rules, testing principles, agent-mode, gitlab-workflow, gitops-principles — note: `gitlab-workflow`'s GitLab-specific behaviors (MR terminology, GitLab MCP, master branch) are overridden by the Source Control Platform section above
- **Skills** (on-demand): session management, project-memory (project↔wiki boundary routing), language development, role skills (investigation, security-audit, test-writing, refactoring, API design, DB design, macOS)
- **CLAUDE.md** (`~/.claude/CLAUDE.md`): global routing table pointing to all rules and skills
- **Read-only**: `~/.claude/` is a deployed artifact — NEVER modify directly. Changes go through the template's `personal/` layer and `/updatepersonal`.

## MCP Access via Code-Executor

**All MCP tools are accessed through code-executor**. Use `callMCPTool()` for all MCP operations:

```typescript
// Use the Basic Memory project name defined in Project Identity section above
const PROJECT_NAME = 'home-ops';

// Read project context
const project = await callMCPTool('mcp__basic-memory__read_note', {
  identifier: 'docs/project',
  project: PROJECT_NAME
});

// Search notes
const results = await callMCPTool('mcp__basic-memory__search_notes', {
  query: 'pattern-name',
  project: PROJECT_NAME
});

// Get library documentation (Context7 FIRST, web search last)
const docs = await callMCPTool('mcp__Context7__get-library-docs', {
  libraryPath: '/org/library',
  topic: 'feature'
});
```

For MCP call examples, see the `mcp-patterns` skill.

## Documentation Scope Rules

**Where to write what**:
- New feature planning → `docs/roadmap`
- Architecture/technology choice → `docs/decisions`
- Fully implemented roadmap items → `progress/[roadmap-item-name]`
- Session progress notes → `docs/progress/[branch-name]`

## DO NOT MODIFY

- Basic Memory structure (docs/*, progress/* — NO guidelines/ in BM)
- Security-first approach (enforced by personal rules)
- Tool assignment rules (enforced by personal rules)


## Non-Negotiables

- Treat this repository as potentially public and durable. Do not introduce plaintext credentials or new sensitive external identifiers.
- Do not commit plaintext secrets, API keys, tokens, passwords, or certificate material anywhere in the repo.
- App-level secrets (tokens, passwords, hashes, multi-line config files) are delivered via External Secrets backed by the shared `ClusterSecretStore` named `onepassword-connect`. Values live either inline in manifests (when non-sensitive) or in per-app `ExternalSecret` resources. Multi-line config-as-secret content (e.g. homepage dashboard config) is stored in 1Password as multi-line text fields and rendered via ESO `template.data`.
- Bootstrap-time secrets (1Password Connect creds, Talos machine config templating) are injected from 1Password via `op inject` during the `just cluster-bootstrap` chain.
- Keep GitOps as the source of truth for steady-state cluster configuration. Avoid manual out-of-band `kubectl apply` changes except for documented bootstrap, recovery, or existing Just-driven workflows in the repo.


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


## Working Rules

- Inspect the target area before editing; do not assume the BM area-reference is fully current — the `verified_at` field in each note is the staleness signal.
- Keep changes minimal and consistent with existing patterns.
- Prefer existing abstractions over inventing new ones.
- Preserve existing secret flows, shared resource names, and Just-driven workflows unless the task explicitly changes them.
- Do not create new documentation locations unless they clearly fit the current structure.
- Preserve `README.md` as human-facing overview unless the task explicitly requires changing it.
- Prefer repo-native operational entry points over raw commands when they already exist as Just recipes.
- Local file edits do not change the cluster until the watched Git source is updated and reconciled; the full GitOps apply boundary is elaborated in `kubernetes/CLAUDE.md`.
- Stage commits with explicit pathspecs (`git add <file>` per touched file), never `git add -A` or `git add .`. The working tree often contains user-driven in-progress work (config refactors, schema URL migrations, doc renames) that must not bleed into unrelated commits. The session-start `git status` snapshot can be stale — always run `git status` immediately before staging to see the live state.

## Repo-Wide Anti-Patterns

- Hardcoding public domains, public IPs, email addresses, credentials, or other sensitive external identifiers.
- Introducing plaintext secrets outside External Secrets.
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
- Current Just modules (groups): `cluster-bootstrap`, `k8s`, `talos`, `volsync`, `omv`, `cloudflare`, `ovh`. The `openwrt` group is a shim in the root `.justfile` that forwards to the private `my-scripts-and-configs` repo (`OpenWRT/provision/`).
- Each module lives next to the area it operates on: `kubernetes/bootstrap/mod.just`, `kubernetes/mod.just`, `kubernetes/talos/mod.just`, `kubernetes/volsync/mod.just`, `provision/openmediavault/mod.just`, `provision/cloudflare/mod.just`, `provision/ovh/mod.just`.
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
- `docs/areas/observability` — kube-prometheus-stack + grafana + speedtest-exporter + victoria-logs
- `docs/areas/iam` — Pocket-ID OIDC provider + TinyAuth forward-auth, Envoy header-stripping trust chain, per-app group ACLs (apps/security)

Provisioning areas:

- `docs/areas/cloudflare` — zone, tunnel, Access apps, Workers, R2, mail-stack DNS, WAF
- `docs/areas/ovh-storage` — S3 buckets, object-store user, S3 policy, 1Password sync

Application area:

- `docs/areas/k8s-workloads` — app inventory, canonical shape, cross-cutting patterns, exposure model
