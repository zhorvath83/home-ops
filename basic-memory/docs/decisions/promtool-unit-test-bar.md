---
title: promtool-unit-test-bar
type: adr
permalink: home-ops/docs/decisions/promtool-unit-test-bar
topic: testing
status: accepted
---

# ADR: promtool unit-test bar for PrometheusRule alerts

Date: 2026-08-06
Status: accepted
Supersedes: none

## Context

The repo's PrometheusRule alerts were nominally covered: `promtool check rules` returned SUCCESS,
N rules loaded, and `prometheus_rule_evaluation_failures_total == 0`. None of those signals say
whether an alert actually works. An alert that never fired never rendered its annotation templates,
so a broken `{{ $labels.* }}` reference or a wrong threshold semantics could sit in a rule file
indefinitely while every conventional green light stayed on. The blind spot was measured on
smartctl (2026-08-01) — an alert whose annotation template had never been exercised — and that
measurement is what started this roadmap item. The fix is not "more alerts" or "more dashboards";
it is a binding bar for what a unit test must assert, and a runner that makes the bar cheap to hold.

This ADR records the DECIDED bar plus the evidence that produced it, so a future editor is bound
by it rather than free to relax it. The terse enforcement-at-the-point-of-edit lives in
`kubernetes/CLAUDE.md` ("PrometheusRule Unit Tests"); this note is the reasoned record behind it.

## Decision — the bar

Every alert in a PrometheusRule file gets a sibling `<basename>_test.yaml` unit test
(`app/prometheusrule_test.yaml` beside `app/prometheusrule.yaml`; the same pairing under
`prometheusrules/` and `config/`). The test MUST hold the following. Items 1–8 are
generalizable principles (they hold for any Prometheus + promtool setup); items 9–10 are
repo-specific to home-ops.

### 1–8 — generalizable principles

1. **Conventional green is not evidence of correctness.** `promtool check rules` SUCCESS,
   "N rules loaded", and `prometheus_rule_evaluation_failures_total == 0` say nothing about
   whether an alert works: an alert that never fired never rendered its annotation templates.
   This is the measured blind spot (smartctl, 2026-08-01) that started the whole item.

2. **Assert the rendered output (`exp_annotations`) on every case.** A broken `{{ $labels.* }}`
   is invisible to yamllint, kustomize build, pre-commit, and `promtool check rules` alike. The
   only thing that catches it is a test that asserts what the template renders to.

3. **Positive AND negative case per alert.** promtool matches `exp_alerts` exactly, so a series
   that must NOT produce an alert is a real assertion, not padding. A negative case is the only
   proof the rule is not over-firing.

4. **Threshold alerts get a boundary pair derived from the operator's strictness**, not a value
   far away from the threshold. `> 80` → 80 no-fire / 81 fire; `< 1` → 1.0 no-fire / 0.99 fire;
   `== N` → N-1 no-fire / N fire (and N+1 where the operator is inclusive). A value far from the
   boundary only proves the boundary is somewhere, not where.

5. **Latch/holdover features (`keep_firing_for`) need a past-latch case** — evaluate PAST the
   latch window with the condition already false, and assert the alert is STILL firing. Otherwise
   deleting the latch leaves the suite green, which is exactly the vacuous-green defect this bar
   exists to remove.

6. **Mutation proof.** A suite that claims to protect something must be shown to FAIL when that
   thing is deliberately broken, then reverted. An unmutated suite is an unverified suite. For an
   expression-based claim, break the expression; for an annotation-rendering claim, break a
   `$labels.*` reference in the rule and watch the rendered text go visibly wrong. Both
   directions (fail, revert, green) must be pasted as evidence.

7. **GUARD A — never weaken a test to reach green.** Forbidden: dropping `exp_annotations`,
   deleting a case, loosening a boundary, or removing a past-latch case. A failing case is a
   finding, not an obstacle; it is escalated with evidence, never silenced.

8. **GUARD B — never modify the system under test to make its test pass.** If a test exposes a
   real rule bug, that is a separate decision with its own blast radius — escalate with the
   rule expression, the test case, and the rendered output. The ONE exception is the mutation
   proof in (6), which is reverted immediately.

### 9–10 — repo-specific to home-ops

9. **`just k8s test-prom-rules` is the ONLY correct runner.** It extracts each rule file's
   `.spec.groups` into a temp-dir `.extracted_prometheus_rules.yaml`, copies the test in, and
   runs `promtool` there — writing nothing under `kubernetes/`. A stale extracted-rules artifact
   once made a direct `promtool` call return `got:[]` (a false failure masking a real one); see
   `docs/progress/crowdsec-import-silent-degradation`. The runner also fails (exit 1) and logs the
   discovered test count on zero discovery — a silent `exit 0` on zero tests is the same
   vacuous-green defect this bar exists to remove.

10. **A test artifact must be structurally unable to reach the cluster.** A `_test.yaml` never
    appears in any `kustomization.yaml` resources list (Flux would try to apply it), and the
    runner writes nothing into the kustomize build root. The convention is enforced at the point
    of edit by the `kubernetes/CLAUDE.md` subsection and by criterion 8 of the roadmap item.

## Worked example — EnvoyProxyDown (why the expression shape is what it is, and why the bar caught it)

EnvoyProxyDown's expression is:

```
(count(up{job="networking/envoy-proxy", namespace="networking"} == 1) or vector(0)) < 2
```

It counts `up == 1` against an expected 2 rather than using `up == 0` or `absent()` because the
two single-replica proxies (envoy-external = Cloudflare Tunnel public traffic, envoy-internal =
LAN) share ONE PodMonitor job — a single-target-shaped `up == 0 or absent()` would miss one proxy
vanishing (`absent()` only fires when every series is gone). Counting `up == 1` against 2 fires
for one-down, both-down, scrape failure, and all-vanished.

**The bar caught a real, live defect here.** Before this work the expression was
`count(up{...} == 1) < 2` (no `or vector(0)`), and BOTH the rule comment AND the
`docs/areas/networking` area note asserted it "covered one-down, both-down, scrape failure, and
all-vanished." That claim was FALSE when written: `count()` over an empty vector returns empty,
not 0, so both-down and all-vanished never fired — the alert would have stayed silent through the
exact total outage it claimed to catch. The wrong belief lived in TWO mutually-reinforcing places
(the rule comment and the area note), and only a promtool unit test — exercising the both-down and
all-vanished states with asserted `exp_alerts` — surfaced it. Fix: `or vector(0)` so the count
falls to 0 when no proxy is up, and the four states are now pinned by
`config/prometheusrule_test.yaml` (commit eb60131ad). The defect was found by a unit test, not
by an incident.

This is the strongest evidence the roadmap item produced: the bar (item 2 — assert the rendered
output; item 3 — negative and positive; item 6 — mutation proof) caught a critical alerting bug
that two human-readable assertions had both certified as correct.

## Consequences

- Every new or modified alert MUST land with a test holding this bar; pre-commit
  (`promtool-rule-tests`) runs the whole suite on any touched rule or `_test.yaml`.
- The bar is enforced at the point of edit by `kubernetes/CLAUDE.md`; this ADR is the durable
  record a future editor is bound by.
- CI does not yet run the suite — that is its own roadmap item,
  `docs/roadmap/promtool-suite-ci-enforcement`. Until then, the merge gate is a human
  `just k8s test-prom-rules` run (the Maestro is barred from running local tests), and pasted
  output is corroboration, not proof.

## Relations

relates_to [[observability]]
relates_to [[prometheusrule-unit-test-coverage]]

## Note on promotion

Items 1–8 are generalizable beyond this repo. The human is deciding separately whether they get
promoted to the personal-layer `testing-principles` rule via the template repo's `personal/`
layer + `/updatepersonal` (a separate session in the template project, NOT this repo and NOT
`~/.claude/` directly). This ADR is the local record regardless.
