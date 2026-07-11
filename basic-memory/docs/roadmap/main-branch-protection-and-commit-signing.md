---
title: main-branch-protection-and-commit-signing
type: roadmap
permalink: home-ops/docs/roadmap/main-branch-protection-and-commit-signing
topic: Verifiable git→cluster trust — main branch protection, commit signing, Flux
  source verify
status: proposed
priority: high
scope: 'Make the main branch a tested, signed, non-bypassable gate for everything
  Flux applies: required status checks (flux-local), enforced admin rules, commit
  signing, and GitRepository.spec.verify.'
rationale: Flux reconciles main as the cluster source of truth, so a verified main
  becomes the single strongest guarantee that only reviewed, tested, cryptographically
  attributable config ever reaches the cluster — the GitOps source turns into a real
  trust anchor.
related_areas:
- flux-gitops
options:
- Single trusted signing key — simplest, one rotation point
- Multi-key keyring in spec.verify — supports multiple committers / key rotation overlap
---

# Verifiable git→cluster trust — main branch protection, commit signing, Flux source verify

## Metadata (observation-form, schema validation)

- [topic] Verifiable git→cluster trust — main branch protection, commit signing, Flux source verify
- [status] proposed
- [priority] high

## What we gain

- Every change reaching the cluster is tested (flux-local), reviewed, and attributable to a signed author.
- A stray or untrusted commit simply cannot reconcile — Flux rejects unverified revisions at the source.
- Admin actions meet the same bar as everyone else; no silent bypass path.
- Completes, on the git side, the same provenance story as signed images (see image-and-chart-signature-verification).

## What to do

1. Enable branch protection on main: mark the flux-local test/diff job a REQUIRED check; enable require_last_push_approval and dismiss_stale_reviews.
2. Set enforce_admins: true so maintainer pushes are held to the rules.
3. Adopt GPG or SSH commit signing for the maintainer key and enable required_signatures on GitHub.
4. Add GitRepository.spec.verify (mode: HEAD) in flux-instance with a keyring of the trusted public key(s).
5. Verify: an unsigned/failing PR is blocked from merge; Flux refuses an unverified revision.

## Options

1. Single trusted signing key — simplest, one rotation point
2. Multi-key keyring in spec.verify — supports multiple committers / key rotation overlap

## Related

- relates_to [[flux-gitops]]
- relates_to [[flux-components-common]]
- relates_to [[image-and-chart-signature-verification]]

## Execution plan (research-backed)

### Current state
- Flux syncs from a **floating branch**: `kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml:25-30` → `spec.sync` generates a GitRepository pointing at `url: https://github.com/zhorvath83/home-ops.git`, `ref: refs/heads/main`, `path: kubernetes/flux/cluster`, `interval: 1h`. The GitRepository is **operator-generated** (flux-operator FluxInstance), not a static manifest.
- kustomize-controller + helm-controller run with cluster-admin (verified in the audit), so whatever lands on `main` is applied cluster-wide.
- GitHub branch protection on `main` is weak: `enforce_admins=false`, `required_status_checks` not enabled, `required_signatures=false`, CODEOWNERS `* @zhorvath83` (self-approvable). PR #3987 merged with zero reviews.
- CI check that must become required: the **flux-local** job in `.github/workflows/flux-local.yaml`.

### Target state
- `main` cannot be updated except by a signed commit that passed the flux-local check; admin bypass off.
- (Optional, gated) Flux refuses to reconcile an unverified revision.

### Implementation steps
1. **Make flux-local a required status check + tighten protection.** Run (needs a token with repo admin; `gh auth status` first):
   ```bash
   # inspect current job/check name first
   gh api repos/zhorvath83/home-ops/commits/main/check-runs --jq '.check_runs[].name'
   # set protection (replace CHECK_NAME with the exact flux-local check name)
   gh api -X PUT repos/zhorvath83/home-ops/branches/main/protection \
     -H "Accept: application/vnd.github+json" \
     -f 'required_status_checks[strict]=true' \
     -f 'required_status_checks[contexts][]=CHECK_NAME' \
     -F 'enforce_admins=true' \
     -F 'required_pull_request_reviews[required_approving_review_count]=1' \
     -F 'required_pull_request_reviews[require_last_push_approval]=true' \
     -F 'required_pull_request_reviews[dismiss_stale_reviews]=true' \
     -f 'restrictions='  # null = no push restriction list
   ```
   (This is a GitHub API change, not a repo file. It is reversible and does not touch the cluster.)
2. **Enable commit signing** for the maintainer. SSH signing is simplest given an existing key:
   ```bash
   git config --global gpg.format ssh
   git config --global user.signingkey ~/.ssh/id_ed25519.pub
   git config --global commit.gpgsign true
   ```
   Add the same public key as a **Signing key** (not just Auth key) in GitHub → Settings → SSH and GPG keys. Then enable `required_signatures`:
   ```bash
   gh api -X POST repos/zhorvath83/home-ops/branches/main/protection/required_signatures -H "Accept: application/vnd.github+json"
   ```
   Note: the audit observed the SSH agent previously refused the ED25519 key sign (see progress/hubble-ui-auth) — resolve agent/key setup before flipping required_signatures, or pushes will be rejected.
3. **(Optional, verify CRD support first) Flux-side commit verification.** flux-operator's `FluxInstance.spec.sync` does **not** expose a `verify` field in current versions, so `spec.verify` cannot simply be added to `helmrelease.yaml`. Before planning this: `kubectl explain fluxinstance.spec.sync` and check flux-operator release notes. If unsupported, the options are (a) skip — branch protection + signing already gate the source, or (b) manage a standalone GitRepository with `spec.verify.mode: HEAD` + a `spec.verify.secretRef` keyring ConfigMap of allowed public keys, and point the sync at it. Treat (b) as a separate spike; do NOT hand-edit the generated GitRepository (Flux will revert it).

### Verification
- `gh api repos/zhorvath83/home-ops/branches/main/protection --jq '{admins:.enforce_admins.enabled, checks:.required_status_checks.contexts, sigs:.required_signatures.enabled}'` → admins true, flux-local in checks, sigs true.
- Open a throwaway PR with a failing/absent flux-local → merge button blocked.
- `git log --show-signature -1 origin/main` → shows a good signature after the next signed push.

### Rollback & safety
- All changes are GitHub settings or local git config — no cluster impact. Revert by re-running the API calls with the old values, or toggle in the GitHub UI.
- Risk: if signing isn't working, `required_signatures=true` blocks your own pushes. Enable step 2 and confirm a signed commit pushes to a test branch **before** step's required_signatures POST.

### Gotchas & dependencies
- Enables the "required check" that roadmap items `renovate-github-actions-merge-gate` and `ci-secret-and-iac-scanning` rely on.
- Resolve the SSH-agent signing issue first (known from prior sessions).

### Effort
S–M (~1–2h for protection+signing; +0.5d spike if pursuing Flux-side verify).
