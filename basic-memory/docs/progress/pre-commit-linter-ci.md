---
title: pre-commit-linter-ci
type: note
permalink: home-ops/docs/progress/pre-commit-linter-ci
---

# Pre-commit / Linter / CI Pipeline — Consensus Parity COMPLETE

## Metadata

- [topic] Pre-commit, linter, and CI/PR pipeline feature parity with reference repos
- [status] completed
- [created_at] 2025-05-24
- [completed_at] 2025-05-25
- [scope] pre-commit, CI, linters, PR checks, zizmor

---

## Completed Phases

### Phase 1 — Config konszolidacio ✅
- Merged .github/yamllint.config.yaml into root .yamllint.yaml
- Moved .github/linters/.markdownlint.yaml to root .markdownlint.yaml
- Created root .tflint.hcl (cloudflare + ovh plugins, required_providers rule)
- Deleted unused configs (.prettierrc.yaml, .prettierignore, .ansible-lint, empty .tflint.hcl)
- Deleted .github/linters/ directory entirely

### Phase 2 — yamlfmt bevezetes ✅
- Created .yamlfmt.yaml (bjw-s/onedr0p consensus: doublestar, include_document_start, force_array_style block, indent 2, retain_line_breaks_single, scan_folded_as_literal)
- Added yamlfmt pre-commit hook (language: system, mise-managed)
- One-time formatting pass across repo (21 files)
- Excluded Homepage settings.yaml (YAML complex syntax conflict with yamllint)

### Phase 3 — shellcheck + actionlint ✅
- Created .shellcheckrc (SC1091, SC2155 suppressions, matching onedr0p/buroa)
- Added shellcheck and actionlint pre-commit hooks (language: system, mise-managed)

### Phase 4 — flux-local CI workflow ✅ *(superseded 2026-06-03 — see [[flate-migration]])*
- Created .github/workflows/flux-local.yaml (4 jobs: filter, test, diff matrix, success gate)
- Uses GITHUB_TOKEN for PR comments (not 1Password service account)
- Sticky PR comments via github-script (matching bjw-s pattern)
- Concurrency group with cancel-in-progress
- metadata.namespace NOT added to ks.yaml files (bjw-s/onedr0p pattern — Flux uses spec.targetNamespace)
- **Reversed decision (2026-06-03)**: workflow was replaced by `.github/workflows/flate.yaml` and `.github/workflows/validate-images.yaml` — see [[flate-migration]]. Both reference repos (bjw-s-labs/home-ops, onedr0p/home-ops) have completed the same migration.

### Phase 5 — PR auto-labeler + label sync ✅
- Created .github/labeler.yaml (5 area labels: github, kubernetes, renovate, talos, terraform)
- Created .github/labels.yaml (area, type, hold labels with colors)
- Created .github/workflows/labeler.yaml (actions/labeler v6.1.0)
- Created .github/workflows/label-sync.yaml (EndBug/label-sync v2.3.3, daily + push trigger, delete-other-labels)

### Phase 6 — MegaLinter rovidites ✅
- Trimmed ENABLE_LINTERS from 11 to 5: GIT_GIT_DIFF, KUBERNETES_KUBECONFORM, MARKDOWN_MARKDOWNLINT, MARKDOWN_MARKDOWN_LINK_CHECK, TERRAFORM_TFLINT
- Removed DISABLE_LINTERS and YAML_YAMLLINT_CONFIG_FILE (dead config after linter consolidation)
- Remaining linters are CI-only (not covered by pre-commit)

### mise consolidation ✅
- Pinned yamlfmt (0.17.2) and actionlint (1.7.7) in mise (were "latest")
- Added shellcheck (0.10.0), gitleaks (8.30.1), yamllint (1.38.0) to mise
- Converted all linter/formatter hooks to language: system (no duplicate tool installations)
- Removed 5 external pre-commit repos (yamlfmt, yamllint, shellcheck-py, actionlint, gitleaks)
- Fixed gitleaks command: detect --staged -> protect --staged (v8.x API change)

### Feature parity hooks ✅
- just-fmt: formats .justfile + all mod.just files (matching onedr0p/buroa)
- mise-fmt: formats .mise.toml (matching onedr0p/buroa)
- mise-lock: updates mise.lock on .mise.toml changes (matching onedr0p/buroa)
- Generated mise.lock (7 platforms, 21+ tools)
- Fixed texthooks tag: v0.7.1 -> 0.7.1 (no v-prefix)

### zizmor ✅
- Added zizmor v1.25.2 to mise
- Added zizmor pre-commit hook (language: system, --offline, .github/workflows/ scope)
- Matches onedr0p/home-ops pattern (no config file, default rules, --offline)
- 7 findings identified — all remediated (see [[progress/zizmor-gh-actions-security-audit]])

### Bug fixes along the way ✅
- Excluded Homepage settings.yaml from yamlfmt (YAML complex syntax conflict)
- Fixed yamllint colons error in settings.yaml with disable-line comment
- Removed dead MegaLinter config (DISABLE_LINTERS, YAML_YAMLLINT_CONFIG_FILE)
- Fixed pre-commit hook findings (EOF newlines, yamlfmt indentation)
- Cleaned up .gitignore for .DS_Store

---

## Deliberate Decisions (NOT gaps)

- **pre-commit over Lefthook** — utility hooks (trailing-whitespace, etc.) need custom shell scripts in Lefthook; pre-commit repos provide battle-tested implementations
- **flate over flux-local** (2026-06-03, supersedes the previous "flux-local over flate" line) — see [[flate-migration]] for the full rationale. Reference repos (bjw-s-labs/home-ops, onedr0p/home-ops) have both completed the migration; flate 0.2.7 has a maintained install action, and removes the Python 3.13+ runtime requirement that bit us in Phase 9/11.
- **No monthly tagging** — release automation, not linter/CI
- **No 1Password CI tokens** — using GITHUB_TOKEN instead (simpler, fork PR limitation accepted)

---

## Commits (chronological)

1. chore: consolidate linter configs and add pre-commit hooks
2. ci: add flux-local workflow, PR labeler, label sync, and trim MegaLinter
3. chore: format all YAML with yamlfmt
4. docs(roadmap): add pre-commit/linter/CI survey consensus note
5. chore: fix pre-commit hook findings (eof newlines, yamlfmt, yamllint)
6. fix(lint): exclude Homepage settings.yaml from yamlfmt
7. refactor(lint): consolidate all linter/formatter tools under mise
8. chore: add just-fmt, mise-fmt, mise-lock hooks and format justfiles
9. feat(lint): add zizmor GitHub Actions security auditor

relates_to [[docs/areas/flux-gitops]]
relates_to [[docs/areas/k8s-workloads]]


### Phase 7 — Pre-commit/CI parity: markdownlint + tflint ✅

- Added markdownlint-cli2 (0.22.1) and tflint (0.62.1) to mise and pre-commit hooks
- Closed the gap where markdownlint and tflint were CI-only (MegaLinter) but not local
- markdownlint pre-commit hook: language system, types: markdown, uses .markdownlint.yaml config
- tflint pre-commit hook: language system, types: terraform, runs tflint --init (idempotent) then --recursive
- Both tools pinned to match MegaLinter CI versions

### Phase 8 — MegaLinter removal ✅

- Deleted .github/workflows/linter.yaml (MegaLinter workflow)
- Rationale: markdownlint and tflint now in pre-commit, kubeconform redundant with flate test, markdown-link-check dropped
- MegaLinter VALIDATE_ALL_CODEBASE: true caused 857 markdown errors on every PR regardless of scope
- Pre-commit hooks validate full codebase locally; CI validates changed files via flux-local

### Phase 9 — flux-local CI Python 3.13 fix ✅ → Phase 11 — Docker image migration ✅ *(both superseded 2026-06-03 — see [[flate-migration]])*

- Phase 9: Added actions/setup-python with python-version "3.13" to flux-local workflow (test + diff jobs)
- Root cause: flux-local>=8.0.0 requires Python >=3.13, but ubuntu-latest ships Python 3.12
- Phase 11: Replaced setup-python + mise-action with Docker image `ghcr.io/allenporter/flux-local:v8.2.0`
- Docker approach eliminates Python dependency entirely — no Python setup, no pipx, no mise in CI
- Local dev still uses `pipx:flux-local` via mise (Python 3.14 on macOS)
- **Reversed decision (2026-06-03)**: both phases were superseded by the flate migration. The Docker image approach is no longer needed because flate is a Go binary installed by `home-operations/flate/action`. See [[flate-migration]] for the full migration context.

## Updated Deliberate Decisions

- **MegaLinter removed** — pre-commit covers markdownlint/tflint locally, flate covers K8s manifest validation in CI (since 2026-06-03, see [[flate-migration]]), kubeconform was redundant with flate test
- **markdown-link-check dropped** — low signal-to-noise ratio, not worth CI time
- **Pre-commit parity** — all linters that run anywhere now also run locally before commit


### Phase 10 — markdownlint scope tuning ✅

- Excluded `.claude/` and all `CLAUDE.md` files from markdownlint (pre-commit exclude pattern extended)
- Rationale: these files are consumed by AI (Claude Code), which does not benefit from line-length limits; wrapped lines actively hurt semantic parsing by breaking coherent sentences and paths across continuation lines
- Structural markdownlint rules (headings, blank lines, table style) are also excluded for these files — the AI can parse any valid markdown, and the maintenance burden of keeping AI-authored files lint-clean outweighs the value
- Raised `code_block_line_length` from 80 to 240 in `.markdownlint.yaml` — tree diagrams, file paths, and Kubernetes resource references routinely exceed 80 chars and cannot be meaningfully wrapped
- Full `pre-commit run --all-files` pass completed successfully for the first time
- Fixed missing trailing newlines in `.renovate/*.json5` files, MD013/MD060 in README.md and `kubernetes/bootstrap/readme.md`
