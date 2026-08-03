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
- [status] planned
- [priority] high
- [effort] M (replanned 2026-08-03; the earlier S estimate covered only the signing config)
- [verified_at] 2026-08-03

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


## REPLAN 2026-08-03 (supersedes the Implementation steps, Verification and Effort sections above)

The 2026-07-27 spec was directionally right but materially incomplete. Re-planned with the
maintainer after live measurement. Effort corrected from **S (~30 min) to M**.

### Decisions taken with the maintainer

- [decision] Signing key: **reuse the existing auth key** `zhorvath83_git`
  (SHA256:QgBZaD3hBhFVlovoShVy85Ygrs8PId5wShmDF8tbZBI), uploaded a SECOND time to GitHub with
  Key type = "Signing key". Rejected: a dedicated `_sign` key. Rationale: fewer moving parts,
  and it is the path 1Password's own docs describe. Accepted coupling: a `_git` compromise
  costs push access AND retroactive history trust at the same time.
- [decision] `zhorvath83_ops` (SHA256:3qJ19iP3...) must NOT sign. That key opens Talos nodes,
  NAS, router and pve; its role is not to be widened.
- [decision] The two peter-evans workflows are fixed IN THIS ITEM as a hard prerequisite.
- [decision] The bot-PR merge path is MEASURED before enforcement, never assumed. The
  maintainer merges from BOTH the web UI and the API today, so both axes are measured.

### Corrections to the earlier spec

- [correction] The spec listed ONE unsigned push path (the maintainer). There are **two** —
  see the automation finding below.
- [correction] The spec's verification section did not cover PR merges at all, which is
  exactly where the breakage sits.
- [correction] Key separation ALREADY exists and was unknown when the spec was written.

### Evidence (measured 2026-08-03, not inferred)

- [evidence] The 1P agent offers two keys (`agent.toml` = default `vault = "Private"`).
  `ssh -vvv git@github.com`: `_ops` offered first and REJECTED, `_git` -> "Server accepts key".
  So `_git` is the GitHub auth key and `_ops` is LAN/server-only. The item titles were renamed
  to `zhorvath83_git` / `zhorvath83_ops` on 2026-08-03; fingerprints unchanged.
- [evidence] git 2.50.1 (Apple Git-155) — above the 2.34 minimum, no Homebrew git needed.
- [evidence] `~/.ssh/allowed_signers` does not exist yet. git config has only user.name and
  user.email (git@horvathzoltan.me); gpg.format, user.signingkey, commit.gpgsign all unset.
- [evidence] Renovate branch commits ARE genuinely signed — not a squash artifact. PRs
  4105/4103/4102/4101/4100/4099 branch commits: all `verified=true reason=valid`,
  committer `GitHub` (platform commits). The spec's premise holds.
- [evidence] **Two workflows produce UNSIGNED commits**: `update-ai-bots.yaml` and
  `update-cloudflare-networks.yaml`, both `peter-evans/create-pull-request@v8.1.1`, whose
  `sign-commits` input defaults to `false`. Proof: PR 4093 branch commit =
  `verified=false reason=unsigned`, committer `github-actions[bot]`. It landed on main as
  `verified=true` only because the squash rewrote it server-side.
- [evidence] The repo has ZERO Actions secrets, so `secrets.PAT || secrets.GITHUB_TOKEN`
  resolves to `GITHUB_TOKEN` — a bot token, which is exactly what `sign-commits: true`
  requires. It does NOT work with a PAT (PAT + sign-commits = PR created, commits unsigned).
- [evidence] Merge strategy in use is SQUASH: landed commits have a rewritten SHA,
  `author=renovate[bot]`, `committer=GitHub`. GraphQL `viewerDefaultMergeMethod = SQUASH`.
- [evidence] Merger differs from author on the majority of bot PRs: 4101/4100/4099/4097/4096/
  4090 are `author=renovate[bot]`, `merged_by=zhorvath83`. Only 4103/4098 were merged by
  renovate[bot] itself.

### The blocking constraint the earlier spec missed

GitHub docs, verbatim (About protected branches): *"you cannot squash and merge a pull request
into the branch on GitHub unless you are the author of the pull request."*

The maintainer's daily habit is precisely the forbidden combination — squash-merging a
bot-authored PR from the web UI. **This is the single most likely workflow breakage.**

- [claim] Renovate's own automerge is expected to SURVIVE. Renovate does not read a repo
  "default merge method" (GitHub persists none); its GitHub platform module auto-detects
  `config.mergeMethod` from the allow_* flags with priority **squash > merge > rebase**, and
  all three are allowed here, so it picks squash. With `platformAutomerge` defaulting to true
  and `:automergePr` setting automerge, Renovate is both author and merge-initiator, and
  GitHub signs the squash commit. To be confirmed by measurement, not assumed.
- [claim] **rebase-and-merge is ALWAYS blocked** on any path, because GitHub creates modified
  commit objects it cannot sign ("GitHub doesn't have access to the committer's private
  signing keys"). The repo currently allows all three strategies.
- [risk] The documented escape — that an API squash ignores the author restriction — rests on
  a GitHub-support quote reported by a third party and is **NOT in GitHub's own docs**. It must
  be measured.

### Plan

**Phase 0 — de-risk the agent (blocker check, FIRST).** The 2026-07-27 audit observed this
ED25519 key refusing to sign. Prove it can sign before anything else; every later phase
depends on it. Expect a Touch ID prompt.

**Phase 1 — local signing config (reuse `_git`).**
```
git config --global gpg.format ssh
git config --global user.signingkey 'ssh-ed25519 <_git PUBKEY>'
git config --global gpg.ssh.program '/Applications/1Password.app/Contents/MacOS/op-ssh-sign'
git config --global commit.gpgsign true
git config --global tag.gpgsign true
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
```
`user.signingkey` is the PUBLIC KEY STRING, not a path (1Password-agent model — do not mix it
with the plain-keyfile model). 1Password generates this snippet: SSH key item -> ellipsis ->
Configure Commit Signing. It does NOT create allowed_signers; that is manual, one line
`git@horvathzoltan.me ssh-ed25519 <_git PUBKEY>`, and the email must match `user.email`.

**Phase 2 — GitHub: register the same key a second time** with Key type = "Signing key".
GitHub keeps auth and signing as separate entries and permits identical key material across
the two types. `gh ssh-key add --type signing` needs the `admin:ssh_signing_key` scope which
the current token lacks (`gh auth refresh -h github.com -s admin:ssh_signing_key`), or use
the web UI.

**Phase 3 — fix the two workflows (prerequisite).** Add `sign-commits: true` to the
create-pull-request step in both. Handle the latent trap: introducing a `PAT` secret later
would SILENTLY stop signing. Either drop the PAT preference in these two workflows or record
the coupling — noting the tradeoff that GITHUB_TOKEN-created PRs do not trigger downstream
workflows. Verify via the action's `pull-request-commits-verified` output and by re-reading
the branch commit's verification status after a `workflow_dispatch` run.

**Phase 4 — measure, on a SHADOW branch, never on main.** Split the measurement by axis:
- *Signature axis, no protection change needed*: `GET /repos/.../commits/{ref}` returns the
  same `verification` object the rule enforces, so the rule's effect on any given commit is
  predictable without enabling anything.
- *Strategy axis, needs a live rule*: cut a throwaway branch from current main HEAD, protect
  it via the REST endpoint (`PUT .../branches/{branch}/protection` takes a LITERAL branch
  name, no wildcards, so there is zero spillover to main), then
  `POST .../required_signatures`. Run the matrix: {signed, unsigned} x {UI, API} x {squash,
  merge-commit, rebase} x {author=self, author=bot}. The bot-authored case comes from
  `workflow_dispatch` on update-ai-bots retargeted with `gh pr edit --base` (a metadata-only
  base change that preserves author, commits and signature status). Decisive cell: **API
  squash of a bot-authored PR**. Clean up in reverse: DELETE required_signatures, DELETE
  protection, delete branch.
- There is NO dry-run/preview API for the rule; the shadow branch is the authoritative way to
  settle the strategy axis.

**Phase 5 — enable enforcement on main**, only after 0-4 pass:
`gh api -X POST repos/zhorvath83/home-ops/branches/main/protection/required_signatures`.
Legacy branch protection is sufficient; migrating to rulesets is NOT required — the rule is
equivalent for pushes and PR merges and differs only on branch creation.

**Phase 6 — settle the merge habit** to whatever Phase 4 proved, and consider disabling
rebase-merge at the repo level so a permanently-blocked strategy cannot be chosen by accident.

### Verification criteria

- [ ] the 1P agent actually signs (Phase 0)
- [ ] a signed commit on a test branch shows "Verified" on GitHub
- [ ] `git log --show-signature -1` shows a good signature
- [ ] both workflows produce `verified=true` branch commits after the fix
- [ ] the Phase 4 matrix is recorded and the chosen merge path is proven
- [ ] `required_signatures --jq '.enabled'` -> true
- [ ] a Renovate PR auto-merges successfully AFTER enforcement is live

### Rollback

`gh api -X DELETE repos/zhorvath83/home-ops/branches/main/protection/required_signatures`;
`git config --global --unset commit.gpgsign`. No cluster impact — GitHub-layer and local
config only; Flux is unaffected.


## Phase 0 result — PASSED (measured 2026-08-03)

The feared blocker does NOT exist. The 2026-07-27 audit's observation that this ED25519 key
"previously refused to sign" does not reproduce.

Probe used the REAL code path — `op-ssh-sign` invoked exactly as git invokes
`gpg.ssh.program` (`-Y sign -n git -f <pubkey>`, payload on stdin), not a `ssh-keygen` stand-in.

- [evidence] `op-ssh-sign -Y sign -n git` -> `exit=0`, empty stderr, a real
  `-----BEGIN SSH SIGNATURE-----` SSHSIG blob produced. Touch ID prompt appeared as expected.
- [evidence] Public half of `zhorvath83_git` read from 1Password and fingerprint-confirmed as
  SHA256:QgBZaD3hBhFVlovoShVy85Ygrs8PId5wShmDF8tbZBI — the same key GitHub accepts for auth.
- [evidence] `ssh-keygen -Y verify -n git` -> `Good "git" signature for git@horvathzoltan.me`.
- [evidence] Negative control, wrong namespace: `-n file` -> "namespace does not match",
  exit 255. This empirically confirms the SSHSIG namespace binding that the key-separation
  decision rested on — it was previously only cited from OpenSSH PROTOCOL.sshsig, now measured.
- [evidence] Negative control, tampered payload -> "incorrect signature", exit 255.

=> Phases 1-6 are unblocked on the agent axis.

## Phase 1 CORRECTION — `--global` would be wrong on this machine

- [correction] The Phase 1 command block above (inherited from the 2026-07-27 spec) uses
  `git config --global`. That is WRONG on this workstation and must not be executed as written.
- [evidence] `~/.gitconfig` splits identity by directory with conditional `includeIf gitdir:`
  entries: one scoped to the personal project tree (`~/.gitconfig.personal`,
  git@horvathzoltan.me) and a second scoped to a separate non-personal tree with its own
  identity and its own remote host. Confirmed via `git config --show-origin user.email` inside
  home-ops, which resolves to `~/.gitconfig.personal`.
- [risk] Writing `user.signingkey` + `commit.gpgsign true` into `--global` would make the
  PERSONAL `zhorvath83_git` key sign commits in the other tree too — a cross-context identity
  leak straight through the boundary the maintainer deliberately built with `includeIf`.
  Signing would still succeed locally because signature verification is server-side, so the
  leak would be SILENT.
- [decision] Phase 1 writes the signing config into `~/.gitconfig.personal`, not `--global`,
  scoping commit signing to the personal project tree only. Signing in any other context is a
  separate decision needing its own key and its own server-side registration, and is out of
  scope for this item.
- [decision] Non-personal contexts are deliberately NOT named in this note: it is committed to
  a repo treated as potentially public and durable, so identifiers belonging to them stay out.


## Phase 1 result — PASSED (executed 2026-08-03)

Applied per the Phase 1 CORRECTION: all six settings written to `~/.gitconfig.personal` via
`git config --file` (no hand-editing), NOT to `--global`. A backup of the original file was
taken before the write.

Settings applied: `gpg.format=ssh`, `user.signingkey=<_git pubkey literal>`,
`gpg.ssh.program=/Applications/1Password.app/Contents/MacOS/op-ssh-sign`,
`commit.gpgsign=true`, `tag.gpgsign=true`,
`gpg.ssh.allowedSignersFile=~/.ssh/allowed_signers`.
`~/.ssh/allowed_signers` created, mode 600, one line: `git@horvathzoltan.me ssh-ed25519 <pub>`.

- [evidence] All six keys resolve from `file:~/.gitconfig.personal` when read from inside
  home-ops (`git config --show-origin --get`).
- [evidence] Scoping holds: `commit.gpgsign` and `user.signingkey` are ABSENT from the
  top-level `~/.gitconfig`, so no other project tree inherits signing. The cross-context leak
  the correction warned about is structurally prevented, not merely avoided by convention.
- [evidence] Full git signing path proven with `git commit-tree -S` (deliberately chosen over a
  real commit: it writes an unreferenced object and moves NO ref, so repo state is untouched;
  the dangling object is gc-collected later). Result: signed commit object
  `690a23b6b4b26975f54289f4c476a43c62ad26cb`, exactly one `gpgsig` header,
  author `Horváth Zoltán <git@horvathzoltan.me>`.
- [evidence] `git verify-commit` -> `Good "git" signature for git@horvathzoltan.me with ED25519
  key SHA256:QgBZaD3h...`, exit 0. So `allowedSignersFile` is wired correctly too and local
  verification works, not just signing.

=> Local signing is COMPLETE and verified. Next gate: Phase 2 (register the same public key on
GitHub a second time with Key type = "Signing key"), which is what turns these local signatures
into "Verified" on the platform. Until Phase 2 lands, commits are signed locally but GitHub will
still report them as unverified.
