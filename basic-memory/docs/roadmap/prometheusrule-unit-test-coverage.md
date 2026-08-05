---
title: prometheusrule-unit-test-coverage
type: roadmap
permalink: home-ops/docs/roadmap/prometheusrule-unit-test-coverage
topic: promtool unit tests for every hand-written PrometheusRule, test file beside
  the rule
status: proposed
priority: medium
scope: 'Adopt "<name>_test.yaml beside the rule file" as the repo-wide convention
  for promtool unit tests, migrate the existing smartctl test out of its tests/ directory
  so exactly one convention exists, and cover the remaining 11 alerts across 8 PrometheusRule
  files to the same bar the smartctl suite set: positive AND negative case per alert
  plus asserted exp_annotations. Includes updating the just k8s test-prom-rules discovery,
  the pre-commit hook files pattern, and dropping the .gitignore entry by running
  promtool in a temp directory instead of writing an extracted-rules artifact into
  the tree.'
rationale: 'The smartctl case proved the blind spot is real, not theoretical: promtool
  check rules passed, and the live rule group evaluated with 0 failures — yet no alert
  had ever fired, so the annotation templates had never rendered even once. A deliberately
  broken $labels.device reference was caught ONLY by the unit test, which reported
  the rendered text as "Drive  on k8s-cp0". Eleven alerts across eight files currently
  carry exactly that blind spot: their templates and thresholds will first be exercised
  by a real incident.'
options:
- 'Naming: <name>_test.yaml beside the rule — DECIDED 2026-08-01'
- 'Placement: next to the rule file, not a module-level tests/ dir — DECIDED 2026-08-01'
- 'Bar: smartctl-grade (positive + negative + exp_annotations) for every alert — DECIDED
  2026-08-01'
related_areas:
- observability
---

# promtool unit tests for every hand-written PrometheusRule

## Metadata (observation-form, schema validation)

- [topic] promtool unit tests for every hand-written PrometheusRule, test file beside the rule
- [status] proposed
- [priority] medium
- [created] 2026-08-01 — generalizes the pattern proven by [[observability-probes-and-disk-health]]

## Why (the proven blind spot)

- [evidence] For the smartctl rules, `promtool check rules` returned `SUCCESS: 8 rules found` and
  the live `prometheus_rule_group_rules{rule_group=~".*smartctl.*"}` was 8 with
  `prometheus_rule_evaluation_failures_total` at 0 — every conventional signal was green.
- [evidence] Yet **no alert had ever fired**, so the `{{ $labels.* }}` annotation templates had
  never rendered. A deliberate break of `$labels.device` → `$labels.devices` was caught only by
  the unit test, which failed with `got: … description="Drive  on k8s-cp0 …"` (empty device).
  Neither `yamllint`, `kustomize build`, `pre-commit`, nor `promtool check rules` detects this.
- [observation] Nothing today proves a threshold boundary either: only the unit test distinguishes
  "fires at 81" from "fires at 80".

## Decisions (made with the human, 2026-08-01)

- [decision] **Naming**: `<source-basename>_test.yaml`, e.g. `prometheusrule_test.yaml`,
  `dns-exfil_test.yaml`, `oomkilled_test.yaml`. Matches the existing smartctl filename, so no
  rename, and matches the `_test` convention used elsewhere in the personal toolchain.
- [decision] **Placement**: directly beside the rule file, NOT in a module-level `tests/` dir.
  The deciding case is `kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/`,
  which holds three independent rule files — a single sibling `tests/` dir cannot express which
  test belongs to which rule, while `<name>_test.yaml` is unambiguous by construction.
- [decision] **Migrate the existing smartctl test** from
  `kubernetes/apps/observability/smartctl-exporter/tests/prometheusrule_test.yaml` to
  `.../app/prometheusrule_test.yaml`; the `tests/` directory disappears. One convention only.
- [decision] **Bar**: every alert gets a positive AND a negative case (negative expressed as a
  second series that must NOT appear in `exp_alerts`, which promtool matches exactly), plus
  `exp_annotations` asserting the fully rendered summary and description. Threshold alerts are
  tested on the boundary pair (e.g. 80 does not fire / 81 does). **Latch corollary** (added 2026-08-05, from the crowdsec-blocklist-import closing round): alerts that carry `keep_firing_for` — `CrowdSecBanActive` (5m), `CrowdSecAcquisitionStalled` (3h), and the newly-added `CrowdSecDecisionBudgetNearCap` (48h) — need an ADDITIONAL case that evaluates PAST the latch window with the condition already false, asserting the alert stays firing; otherwise removing `keep_firing_for` leaves the suite green and the latch is untested. The `CrowdSecDecisionBudgetNearCap` 7th case (`values: 63751x40 0x30`, eval 60m) is the template — verified by mutation that removing `keep_firing_for: 48h` fails exactly that case while the other 12 stay green. `CrowdSecBanActive` and `CrowdSecAcquisitionStalled` do not yet have such a case; add one each when those work-list rows are implemented.

## Work list — 11 alerts across 8 files

| file | alerts |
|---|---|
| `kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml` | `CrowdSecLAPIDown`, `CrowdSecAcquisitionStalled`, `CrowdSecBanActive` |
| `kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml` | `VolSyncComponentAbsent`, `VolSyncVolumeOutOfSync` |
| `kubernetes/apps/crowdsec/crowdsec-bouncer/app/prometheusrule.yaml` | `CrowdSecBouncerDown` |
| `kubernetes/apps/networking/envoy-gateway/config/prometheusrule.yaml` | `EnvoyProxyDown` |
| `kubernetes/apps/observability/blackbox-exporter/app/prometheusrule.yaml` | `BlackboxProbeFailed` |
| `.../kube-prometheus-stack/app/prometheusrules/dns-exfil.yaml` | `HubbleDNSExfilSuspected` |
| `.../kube-prometheus-stack/app/prometheusrules/hubble-policy-deny.yaml` | `HubblePolicyDeny` |
| `.../kube-prometheus-stack/app/prometheusrules/oomkilled.yaml` | `OOMKilled` |

Already covered: the 8 `Smartctl*` alerts in
`kubernetes/apps/observability/smartctl-exporter/app/prometheusrule.yaml` (migrating, not rewriting).

- [observation] Only hand-written rules are in scope. The bulk of the cluster's alerts ship inside
  the kube-prometheus-stack chart and are not manifests in this repo, so they cannot be tested here.

## Runner changes required

- [change] **Discovery**: `just k8s test-prom-rules` currently finds modules via
  `find -type d -name 'tests'` containing `*_test.yaml` (`kubernetes/mod.just`). It must instead
  pair each `*_test.yaml` with its same-basename rule file in the same directory.
- [change] **No artifact in the tree.** Today the recipe writes `tests/_extracted_rules.yaml`
  (gitignored) because the test file's `rule_files` must resolve relative to itself. With the test
  file now inside `app/`, generating there would put a stray file in the kustomize build root even
  transiently. Instead: copy BOTH the test file and the `yq`-extracted rules into a temp dir and
  run `promtool` there — `rule_files: ./<name>_extracted.yaml` resolves, and nothing is ever
  written under `kubernetes/`. The `**/tests/_extracted_rules.yaml` `.gitignore` entry is then
  deleted.
- [change] **pre-commit scope**: the `promtool-rule-tests` hook's
  `files: 'prometheusrule\.yaml$|/tests/'` pattern must cover `_test.yaml` files and the
  `prometheusrules/` directory's rule files, and must no longer reference `/tests/`.

## Guardrail (the cost of this placement)

- [risk] `app/` is the kustomize build root. A `_test.yaml` there is NOT in `kustomization.yaml`
  `resources`, so Flux and kustomize ignore it — verified: kustomize only reads listed resources
  and no kustomization in this repo uses globs. But it is one careless `kustomization.yaml` edit
  away from being applied to the cluster, which the `tests/` placement made structurally
  impossible. The convention must therefore be documented where a future editor will see it, and
  `_test.yaml` must never appear in a `kustomization.yaml`.
- [question] Does `pluto detect-files -d kubernetes` (the weekly
  `scanning-deprecated-kube-resources` workflow) walk and choke on a non-manifest `_test.yaml`?
  It should skip files without `apiVersion`/`kind`, but this is **unverified**: the workflow runs
  on a Friday cron and its last run was 2026-07-31, before the first test file landed on
  2026-08-01. Verify before adding eight more such files — note the workflow holds
  `issues: write` and opens an issue on findings, so a manual `workflow_dispatch` is a
  deliberate act.

## Acceptance criteria

- Every alert in the 9 hand-written PrometheusRule files has a positive case, a negative case, and
  asserted `exp_annotations`.
- `just k8s test-prom-rules` discovers and passes all of them, and writes nothing under
  `kubernetes/`.
- The `tests/` directory no longer exists; `.gitignore` no longer carries the extracted-rules entry.
- A deliberate `$labels.*` break in ANY covered rule file makes the recipe fail (spot-check at
  least one file other than smartctl — the regression proof is the point of the exercise).
- The pre-commit hook fires for a touched rule or test file and is skipped for unrelated files.
- `pluto` question above answered.

## Related

- relates_to [[observability]]
- continues [[observability-probes-and-disk-health]]
- relates_to [[blackbox-http-endpoint-probing]]
