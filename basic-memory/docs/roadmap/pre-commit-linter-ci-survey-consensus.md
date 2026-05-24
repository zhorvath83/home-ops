---
title: pre-commit-linter-ci-survey-consensus
type: note
permalink: home-ops/docs/roadmap/pre-commit-linter-ci-survey-consensus
tags:
- roadmap
- pre-commit
- linters
- ci
- flux-local
- consensus
- survey
---

# Pre-commit / Linter / CI Pipeline Survey & Consensus Roadmap

## Metadata (observation-form, schema validation)

- [topic] Pre-commit, linter, and CI/PR pipeline survey across home-ops community repos
- [status] proposed
- [created_at] 2025-05-24
- [scope] pre-commit, CI, linters, PR checks

---

## Survey Participants

| Repo | Maintainer | CI Platform | Task Runner | Pre-commit Manager |
|------|-----------|-------------|-------------|-------------------|
| bjw-s/home-ops | bjw-s | Forgejo Actions | Just | None (CI-only) |
| onedr0p/home-ops | onedr0p | GitHub Actions | Just | Lefthook |
| buroa/home-ops | buroa | GitHub Actions | Task | None |
| billimek/k8s-gitops | billimek | GitHub Actions | Task | None |
| zhorvath83/home-ops | zhorvath83 | GitHub Actions | Just | pre-commit (Python) |

---

## 1. Pre-commit Hooks Comparison

| Hook / Check | bjw-s | onedr0p | buroa | billimek | zhorvath83 |
|---|---|---|---|---|---|
| **Pre-commit framework** | No | No (Lefthook) | No | No | **Yes** |
| **yamllint** | CI only | No (uses yamlfmt) | No | No | Yes (pre-commit + CI) |
| **yamlfmt** | Yes (local/CI) | Yes (Lefthook) | No | No | **No** |
| **trailing-whitespace** | CI (helm-charts only) | — | — | — | Yes (pre-commit) |
| **end-of-file-fixer** | CI (helm-charts only) | — | — | — | Yes (pre-commit) |
| **fix-byte-order-marker** | CI (helm-charts only) | — | — | — | Yes (pre-commit) |
| **check-merge-conflict** | CI (helm-charts only) | — | — | — | Yes (pre-commit) |
| **check-added-large-files** | — | — | — | — | Yes (pre-commit) |
| **detect-private-key** | — | — | — | — | Yes (pre-commit) |
| **mixed-line-ending** | CI (helm-charts only) | — | — | — | Yes (pre-commit) |
| **remove-crlf** | CI (helm-charts only) | — | — | — | Yes (pre-commit) |
| **remove-tabs** | CI (helm-charts only) | — | — | — | Yes (pre-commit) |
| **fix-smartquotes** | — | — | — | — | Yes (pre-commit) |
| **gitleaks** | — | — | — | — | Yes (pre-commit) |
| **SOPS forbid-secrets** | — | — | — | — | Yes (pre-commit) |
| **shellcheck** | — | Yes (Lefthook) | Local only (.shellcheckrc) | — | CI only (MegaLinter) |
| **actionlint** | CI (Forgejo) | — | — | — | CI only (MegaLinter) |
| **gofmt** | — | Yes (Lefthook) | — | — | — |
| **just --fmt** | — | Yes (Lefthook) | — | — | — |
| **mise fmt** | — | Yes (Lefthook) | — | — | — |

---

## 2. CI/PR Pipeline Comparison

| CI Check | bjw-s | onedr0p | buroa | billimek | zhorvath83 |
|---|---|---|---|---|---|
| **K8s manifest validation** | flux-local test | flate test | flux-local test | flux-local test | kubeconform (MegaLinter) |
| **K8s diff on PR** | flux-local diff (sticky comment) | flate diff (sticky comment) | flux-local diff (sticky comment) | flux-local diff (sticky comment) | **No** |
| **Image pull verification** | docker pull on self-hosted | talosctl image pull | talosctl image pull | — | **No** |
| **YAML lint (CI)** | yamllint (changed files) | — | — | — | MegaLinter (all files) |
| **Shell lint (CI)** | — | — | — | — | MegaLinter |
| **Dockerfile lint (CI)** | — | — | — | — | MegaLinter (hadolint) |
| **JSON lint (CI)** | — | — | — | — | MegaLinter (jsonlint) |
| **Markdown lint (CI)** | — | — | — | — | MegaLinter (markdownlint) |
| **Markdown link check** | — | — | — | — | MegaLinter |
| **Terraform lint (CI)** | — | — | — | — | MegaLinter (tflint) |
| **dotenv lint (CI)** | — | — | — | — | MegaLinter (dotenv-linter) |
| **Actionlint (CI)** | Yes (Forgejo) | — | — | — | MegaLinter |
| **Pluto (deprecated API)** | — | — | — | — | Yes (weekly cron) |
| **PR auto-labeler** | Yes | Yes | Yes | Yes | **No** |
| **Label sync** | — | Yes | Yes | Yes | **No** |
| **Monthly tagging** | — | Yes | Yes | Yes | **No** |
| **CRD schema publish** | — | — | Yes | — | **No** |
| **Renovate** | Yes (Forgejo) | Yes (GitHub App) | Yes (GitHub Action) | Yes (self-hosted dispatch) | Yes (GitHub Action) |
| **Cloudflare CIDR updater** | — | — | — | — | Yes (daily cron) |

---

## 3. Linter Config Files Comparison

| Config File | bjw-s | onedr0p | buroa | billimek | zhorvath83 |
|---|---|---|---|---|---|
| .yamllint.yaml | Yes | No | No | No | Yes |
| .yamlfmt.yaml | Yes | Yes | No | No | **No** |
| .editorconfig | Yes (2sp default) | Yes (2sp, 4sp .sh/.just/.md) | Yes (2sp, 4sp .sh/.md) | No | Yes (2sp default) |
| .shellcheckrc | — | Yes (SC1091, SC2155) | Yes (SC1091, SC2155) | No | No |
| .gitattributes | Yes (LF, linguist) | — | — | Yes (LF, linguist) | No |
| .markdownlint.yaml | — | — | — | — | **Missing** (referenced by MegaLinter) |
| .tflint.hcl | — | — | — | — | **Missing** (referenced by MegaLinter) |
| .sops.yaml | — | — | Yes | — | — |
| .minijinja.toml | Yes | Yes | Yes | Yes (in .taskfiles/) | — |

---

## 4. Tooling Summary

| Tool | bjw-s | onedr0p | buroa | billimek | zhorvath83 |
|---|---|---|---|---|---|
| **Task runner** | Just | Just | Task | Task | Just |
| **Tool manager** | mise | mise | mise | mise | mise |
| **Template engine** | minijinja | minijinja | minijinja | minijinja | — |
| **Secret manager** | 1Password | 1Password | 1Password | 1Password | 1Password |
| **K8s validation tool** | flux-local | flate | flux-local | flux-local | kubeconform (via MegaLinter) |
| **Pre-commit manager** | — | Lefthook | — | — | pre-commit (Python) |
| **CI linter suite** | targeted (yamllint + actionlint) | Lefthook local | — | — | MegaLinter (12 linters) |

---

## 5. Gap Analysis (zhorvath83 vs Consensus)

### What we have that others mostly don't

| Feature | Value | Consensus |
|---|---|---|
| pre-commit framework | Comprehensive local hooks | Most use CI-only or Lefthook |
| MegaLinter (12 linters) | Broad CI coverage | Others use targeted CI or local only |
| gitleaks | Secret leak detection | Only we have this locally |
| SOPS forbid-secrets | Prevents decrypted SOPS commits | Only we have this |
| Pluto (deprecated K8s APIs) | Weekly scan | Only we have this |
| Cloudflare CIDR updater | Daily automation | Only we have this |

### What we're missing that the consensus has

| Feature | Value | Who has it | Priority |
|---|---|---|---|
| **flux-local test in CI** | Validates entire Flux cluster build | bjw-s, buroa, billimek | **HIGH** |
| **flux-local/flate diff on PR** | Visual diff of K8s changes as PR comment | bjw-s, onedr0p, buroa, billimek | **HIGH** |
| **yamlfmt** | Consistent YAML formatting | bjw-s, onedr0p | **MEDIUM** |
| **PR auto-labeler** | Automatic PR labeling by area | All 4 others | **MEDIUM** |
| **Label sync** | Synchronized GitHub labels | onedr0p, buroa, billimek | **LOW** |
| **Image pull verification** | Pre-cache new images before merge | bjw-s, onedr0p, buroa | **LOW** |
| **Monthly tagging** | Calendar versioning tags | onedr0p, buroa, billimek | **LOW** |
| **Lefthook migration** | Faster, parallel pre-commit | onedr0p | **OPTIONAL** |

### Config gaps (referenced but missing)

| File | Issue |
|---|---|
| .markdownlint.yaml | Referenced by MegaLinter but not present — falls back to defaults |
| .tflint.hcl | Referenced by MegaLinter but not present — falls back to defaults |

---

## 6. Consensus Direction (Proposed)

### Phase 1 — Adopt flux-local (HIGH priority)

1. Add flux-local to mise tools (`.mise.toml`)
2. Create `.github/workflows/flux-local.yaml`:
   - filter-changes job (detect kubernetes/ changes)
   - test job (flux-local test)
   - diff job (matrix: helmrelease, kustomization) with sticky PR comment
   - success gate job
3. Add `.github/labeler.yaml` for automatic PR labeling
4. Add `.github/labels.yaml` + label-sync workflow

### Phase 2 — Adopt yamlfmt (MEDIUM priority)

1. Add yamlfmt to mise tools (`.mise.toml`)
2. Create `.yamlfmt.yaml` (align with bjw-s/onedr0p consensus config)
3. Add yamlfmt pre-commit hook or Lefthook hook
4. Run one-time format across the repo

### Phase 3 — Config hardening (MEDIUM priority)

1. Create `.markdownlint.yaml` (explicit config for MegaLinter)
2. Create `.tflint.hcl` (explicit config for MegaLinter)
3. Add `.gitattributes` for EOL enforcement (align with bjw-s/billimek)
4. Consider `.shellcheckrc` (SC1091, SC2155 suppressions)

### Phase 4 — Optional enhancements

1. Image pull verification workflow (requires self-hosted runner)
2. Monthly tagging workflow
3. CRD schema publishing (if desired)
4. Evaluate Lefthook migration (faster, parallel, Go-based vs Python pre-commit)
5. Consolidate MegaLinter → targeted CI (yamllint + actionlint only, like bjw-s)
---

## 7. Key Architectural Observations

1. **The community is converging on flux-local/flate for K8s validation** — all 4 other repos run flux-local test + diff in CI. We use kubeconform inside MegaLinter, which only validates schemas, not the full Flux build.

2. **YAML formatting over YAML linting** — onedr0p dropped yamllint in favor of yamlfmt (formatter). bjw-s uses both yamllint (CI) and yamlfmt (local). The trend is toward formatting-first.

3. **Lefthook is the emerging standard** — onedr0p uses it; it's faster than Python pre-commit (Go binary, parallel execution, remote config sharing). The home-operations/.github org provides a shared Lefthook config.

4. **MegaLinter is powerful but heavy** — our 12-linter MegaLinter CI covers more than anyone else's CI, but at the cost of runtime and maintenance. bjw-s's targeted approach (yamllint + actionlint on changed files only) is faster and more focused.

5. **PR diff comments are the killer feature** — all 4 other repos post flux-local/flate diff as sticky PR comments. This gives reviewers an immediate visual of what K8s resources change, which is arguably the most valuable CI check for a Flux-based GitOps repo.

---

relates_to [[docs/areas/flux-gitops]]
relates_to [[docs/areas/k8s-workloads]]
implements [[AD-008-mise-tool-manager]]
