---
title: chore-drop-pod-security-admission
type: progress_note
permalink: home-ops/docs/progress/chore-drop-pod-security-admission
status: done
verified_at: '2026-08-03'
topic: Drop Pod Security Admission (PSA) from the cluster
related_areas:
- k8s-workloads
tags:
- chore
- security
- gitops
---

# chore-drop-pod-security-admission — drop Pod Security Admission

## Metadata (observation-form, schema validation)

- [topic] Drop Pod Security Admission (PSA) from the cluster — remove the one repo-managed PSA enforcement label and delete the PSA roadmap + decision notes.
- [status] done
- [verified_at] 2026-08-03
- [priority] low
- [area] k8s-workloads

## Scope

- Remove the `metadata.labels` block (`pod-security.kubernetes.io/enforce: privileged`) from `kubernetes/apps/crowdsec/namespace.yaml`. The `kustomize.toolkit.fluxcd.io/prune: disabled` annotation is kept. The `privileged` profile equals the implicit cluster default, so this is not a posture change — it drops a documented exception, not a guarantee.
- Rewrite the comment at `kubernetes/apps/crowdsec/crowdsec/app/helmrelease.yaml:59` to drop the "privileged PSA exception" reference; the seccomp + capability-dropping hardening rationale stays. Workload-level hardening (runAsNonRoot, drop:[ALL], seccomp RuntimeDefault, automountServiceAccountToken false) is unchanged and is the actual security control.
- Delete BM notes `docs/roadmap/pod-security-admission-enforcement` and `docs/decisions/AD-024-crowdsec-namespace-psa-exception`.
- De-dangle the wiki-link lines (and one backtick path) that pointed at those two deleted notes, across 3 progress notes — Option A (de-wikilink only; historical PSA prose stays verbatim).

## Explicit exclusions / decisions

- **flux-system is untouched.** Its `warn=restricted` PSA labels are owned by `flux-operator` (verified in managedFields) and are out of scope; they are not repo-managed and were not removed.
- **No replacement decision record and no rationale note were created** — by explicit user decision. PSA knowledge is dropped, not superseded. Any future admission-policy decision would be a new AD, not a continuation of this one.
- **envoy-crowdsec-bouncer was not edited.** It carries PSA *prose* across many updates but zero `[[...]]` links to either deleted note; under Option A it is out of scope. Its prose is a closed session record.

## Verification (acceptance criteria)

1. `grep -rn "pod-security" --include='*.yaml' --include='*.yml' kubernetes/` → 0 hits. PASS.
2. `grep -rniE "pod-security|pod security admission|\bPSA\b" .` excluding basic-memory/, .git/, .terraform/ → 0 hits. PASS. Surviving PSA hits live only in basic-memory/ as historical prose (expected, per Option A).
3. `read_note` on the two deleted notes → "Note Not Found" for both. PASS.
4. `[[...]]` link matches for `pod-security-admission-enforcement` and `AD-024-crowdsec-namespace-psa-exception` → 0 across all living BM notes (verified by per-note full-content count of the bracketed forms). PASS. Plain-text PSA mentions in progress notes are expected and retained by decision.
5. `kubectl kustomize kubernetes/apps/crowdsec` renders clean; the crowdsec Namespace comes out without any `pod-security.kubernetes.io/*` label. PASS.
6. `pre-commit run --files <touched>` → yamlfmt, yamllint, gitleaks and hooks all Passed. PASS.

## Commits / PR

- Code commit: `🔥 remove(crowdsec): drop Pod Security Admission enforce label` (signed), on branch `chore/drop-pod-security-admission`.
- Docs commit: `📝 docs(progress): drop pod-security-admission notes`.
- Draft PR opened; never merged by the worker — merge is the Maestro's terminal step.

## Relations

- relates_to [[crowdsec-psa-removal-and-official-chart-migration]]
- relates_to [[k8s-workloads]]
