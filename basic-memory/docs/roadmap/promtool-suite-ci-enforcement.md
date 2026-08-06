---
title: promtool-suite-ci-enforcement
type: roadmap
permalink: home-ops/docs/roadmap/promtool-suite-ci-enforcement
topic: CI enforcement for the promtool PrometheusRule unit-test suite
status: proposed
priority: medium
related_areas:
- observability
---

# CI enforcement for the promtool PrometheusRule suite

## Metadata (observation-form, schema validation)

- [topic] Run the promtool PrometheusRule unit-test suite in CI on pull requests, so the suite is enforced by the platform rather than only by a bypassable local pre-commit hook.
- [status] proposed
- [priority] medium
- [created] 2026-08-06 — surfaced by the Maestro while verifying [[prometheusrule-unit-test-coverage]]

## Why

- [evidence] `.github/workflows/` holds flux-local, label-sync, labeler, scanning-deprecated-kube-resources, security-scan, update-ai-bots, update-cloudflare-networks. NONE runs `just k8s test-prom-rules`; `security-scan.yaml` is a gitleaks scan only. Verified by reading the workflow directory 2026-08-06.
- [observation] The suite is therefore enforced ONLY by the local `promtool-rule-tests` pre-commit hook, which any `git commit --no-verify` bypasses silently. A bypassed commit reaches `main` with no signal at all.
- [observation] It also leaves the review lane without independent evidence: a reviewer who does not run the suite locally has nothing but the author's word. During the prometheusrule-unit-test-coverage work this had to be settled by the human running the recipe by hand.
- [observation] Same failure class as the parent item: a control that exists but is never exercised proves nothing.

## Scope

- A GitHub Actions job running the promtool suite on pull requests that touch PrometheusRule manifests or `*_test.yaml` files.
- promtool and yq must come from the versions the repo already pins in `.mise.toml`, the way `security-scan.yaml` reads its gitleaks pin from `.mise.toml` so CI and local can never drift.
- Must pass `zizmor` (the repo lints its own workflows) and use least-privilege `permissions`.

## Open questions

- [question] Reuse the repo's mise setup in CI, or install promtool/yq from pinned releases with checksum verification (the `security-scan.yaml` pattern)?
- [question] Path-filtered trigger or always-run? The suite is fast, and a path filter can be defeated by a rename.
- [question] Should CI invoke `just k8s test-prom-rules`, or call promtool directly — and if directly, how is that logic kept from drifting from `kubernetes/mod.just`?

## Acceptance criteria

- A PR that breaks a promtool test case fails a required check.
- A PR committed with `--no-verify` carrying a broken rule template still fails CI.
- The promtool/yq versions used in CI come from the existing `.mise.toml` pins, not a second hardcoded copy.
- `zizmor` passes on the new workflow.

## Related

- relates_to [[observability]]
- continues [[prometheusrule-unit-test-coverage]]
