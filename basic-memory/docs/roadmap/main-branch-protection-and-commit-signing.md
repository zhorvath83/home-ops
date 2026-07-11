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
