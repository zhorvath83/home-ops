---
title: main-branch-protection-and-commit-signing
type: roadmap
permalink: home-ops/docs/roadmap/main-branch-protection-and-commit-signing
topic: Required commit signing on main — GitHub enforces signed commits to the cluster
  source branch
status: proposed
priority: high
scope: Require all commits pushed to main to be GPG/SSH-signed via GitHub required_signatures,
  after the maintainer enables commit signing. Signing only — no required status checks,
  no enforce_admins, no PR-review changes, no Flux-side spec.verify.
rationale: A signed main makes every commit cryptographically attributable to the
  maintainer's key; an unsigned or impersonated push (compromised token, forged author)
  is rejected at the GitHub layer before it can reconcile. Renovate already signs
  via the hosted GitHub App (verified=true observed on this repo), so enforcement
  does not break Renovate auto-merge. The maintainer's own commits are currently unsigned
  (verified=false) and must start signing first.
related_areas:
- flux-gitops
options: []
verified_at: '2026-07-27'
tags:
- roadmap
- security
- git
- signing
---

# Required commit signing on main

## Metadata (observation-form, schema validation)

- [topic] Required commit signing on main — GitHub enforces signed commits to the cluster source branch
- [area] flux-gitops
- [status] proposed
- [priority] high
- [verified_at] 2026-07-27

## What we gain

- Every commit on `main` is cryptographically attributable to the maintainer's signing key.
- An unsigned or impersonated push (compromised PAT, forged author) is rejected by GitHub before it can reach the cluster.
- Renovate is unaffected — its commits are already signed by the hosted GitHub App (`verified=true` observed on this repo), so `required_signatures` does not break Renovate auto-merge.
- Enforcement lives entirely at the GitHub layer; no Flux-side change.

## What to do

1. Enable commit signing for the maintainer (SSH signing given an existing ED25519 key, or GPG).
2. Add the public key as a **Signing key** in GitHub → Settings → SSH and GPG keys.
3. Enable `required_signatures` on `main`.
4. Verify a signed push succeeds and an unsigned push is rejected.

Out of scope (intentionally dropped from the earlier draft): required status checks, `enforce_admins`, PR-review requirements, and Flux `spec.verify`. Signing only.

## Current state (research-backed, 2026-07-27)

- `main` is `protected: true` but with **empty rules** — `required_status_checks.checks: []`, `enforce_admins: false`, `required_signatures.enabled: false`, no required PR review (read via admin scope: `gh api repos/zhorvath83/home-ops/branches/main/protection`).
- Maintainer commits (Horváth Zoltán, `zhorvath83`) are `verified=false reason=unsigned` (last 20 commits sampled) — the maintainer does **not** sign today.
- Renovate commits (`renovate[bot]`) are `verified=true reason=valid` — the hosted Renovate GitHub App signs via GitHub platform signing.
- Reference repos: `onedr0p/home-ops` signs everything (incl. its `bot-ross` App, `verified=true`); `bjw-s-labs/home-ops` does **not** sign Renovate commits (`verified=false`) and therefore cannot enable `required_signatures`. This repo's Renovate already signs, so enforcement is viable.

## Target state

- All commits pushed to `main` are GPG/SSH-signed; `required_signatures` enabled.
- No other branch-protection rules are added in this item.

## Implementation steps

1. **Configure local commit signing** (SSH, given an existing ED25519 key):
   ```bash
   git config --global gpg.format ssh
   git config --global user.signingkey ~/.ssh/id_ed25519.pub
   git config --global commit.gpgsign true
   ```
   Add the same public key as a **Signing key** (not just Auth key) in GitHub → Settings → SSH and GPG keys.
2. **Confirm a signed push works** on a throwaway branch **before** enabling enforcement:
   ```bash
   git checkout -b signing-test && git commit -S -m "test" --allow-empty && git push -u origin signing-test
   ```
   The commit must show "Verified" on GitHub. Resolve the SSH-agent signing issue first (the audit observed the ED25519 key previously refused to sign — see `progress/hubble-ui-auth`); if signing fails here, do not proceed to step 3 or your own pushes will be rejected.
3. **Enable required_signatures on main**:
   ```bash
   gh api -X POST repos/zhorvath83/home-ops/branches/main/protection/required_signatures -H "Accept: application/vnd.github+json"
   ```

## Verification

- `gh api repos/zhorvath83/home-ops/branches/main/protection/required_signatures --jq '.enabled'` → `true`.
- `git log --show-signature -1 origin/main` after the next signed push → good signature.
- An unsigned push to `main` (or an unsigned commit merged via PR) is rejected.

## Rollback & safety

- Disable: `gh api -X DELETE repos/zhorvath83/home-ops/branches/main/protection/required_signatures`.
- Local: `git config --global --unset commit.gpgsign` (optional).
- No cluster impact — GitHub-layer setting only.
- Risk: enabling `required_signatures` before confirming step 2 self-locks the maintainer out of pushing to `main`. Always verify a signed push first.

## Gotchas

- Renovate already signs (`verified=true`), so it is unaffected — no Renovate config change is needed.
- The maintainer's own commits are the only unsigned path today; signing must be set up first.
- SSH-agent must be able to sign with the ED25519 key (known prior-session issue); verify before flipping enforcement.

## Effort

S (~30 min: key config + GitHub signing key + one API call + verify a signed push).

## Related
- relates_to [[flux-gitops]]
