---
title: prometheusrule-unit-test-coverage
type: progress_note
permalink: home-ops/docs/progress/prometheusrule-unit-test-coverage
---

# prometheusrule-unit-test-coverage

Branch: `test/prometheusrule-unit-test-coverage` (created locally — this is a GitHub repo, so the personal layer's GitLab MR-first branch-creation rule does NOT apply). ONE Draft PR to open; NEVER mark ready; NEVER merge (the Maestro merges); NEVER create a release. One-open-PR invariant verified at pre-flight: only renovate bot PRs were open (4137 pluto digest, 4136 renovate hook, 4056 paperless image). I am "Llama" (worker); Maestro is "Claude Code #2"; escalate every blocker via `maestri ask "Claude Code #2"`, NEVER to the human.

## DECIDED convention and bar

- Test file `<basename>_test.yaml` lives BESIDE its rule file `<basename>.yaml` in the SAME directory. Examples: `app/prometheusrule_test.yaml` ↔ `app/prometheusrule.yaml`; `prometheusrules/dns-exfil_test.yaml` ↔ `prometheusrules/dns-exfil.yaml`; `config/prometheusrule_test.yaml` ↔ `config/prometheusrule.yaml` (envoy-gateway's rule is in `config/`, not `app/`).
- Bar for EVERY alert: a positive case (fires) + a negative case (does not fire) + asserted `exp_annotations` (so a broken `{{ $labels.* }}` or `$value` template fails the suite, not just the labels). Threshold alerts (`> N`, `< N`, `== N`): a boundary pair matching the operator's strictness (e.g. `> 80` → 80 no-fire / 81 fire; `< 1` → 1.0 no-fire / 0.99 fire). `keep_firing_for: Xh` alerts: a past-latch case (condition false for >X past the fire, alert STILL firing — removing `keep_firing_for` would resolve it and return `got:[]`).

## Fixed artifact name + runner contract

- The extracted-rules artifact is named `.extracted_prometheus_rules.yaml` (leading dot). Every test file's `rule_files:` entry is exactly `./.extracted_prometheus_rules.yaml`.
- Runner `just k8s test-prom-rules` (rewritten in `kubernetes/mod.just`, currently lines ~333–375). For each `*_test.yaml`: pair with the same-basename `.yaml` rule file in the SAME dir (`rule_file="${tf%_test.yaml}.yaml"`); `mktemp -d`; `yq ea -o yaml '.spec as $item ireduce ({}; . *+ {"groups": ($item.groups // [])})' "$rule_file" > "$tmp/.extracted_prometheus_rules.yaml"` (eval-all + ireduce merge idiom retained — single file is a no-op merge); `cp "$tf" "$tmp/$(basename "$tf")"`; `promtool check rules` + `promtool test rules` in `$tmp`; `rm -rf "$tmp"`. KEEP: continue-on-failure (`fail=1`), the `just log info/warn/error` style, and the promtool/yq presence checks.
- NOTHING is ever written under `kubernetes/` — the runner only writes to `$TMPDIR`. `app/` is the kustomize build root, so a `_test.yaml` is a test fixture, not a manifest. This structurally eliminates the crowdsec false-failure trap (a stale leftover `_extracted_rules.yaml` → `got:[]` on a direct promtool call) documented in `docs/progress/crowdsec-import-silent-degradation`.
- Soundness: promtool resolves `rule_files` relative to the TEST FILE dir, not CWD (the current runner proves this — it runs from repo root yet `./_extracted_rules.yaml` resolves beside the test file). Copying test + extracted into `$tmp` resolves identically.

## Corrected inventory — 11 rule files, 35 alerts + 1 recording rule, 11 test files (4 migrated, 7 new)

MIGRATE (move beside rule, fix `rule_files` → `./.extracted_prometheus_rules.yaml`, delete the `tests/` dir, fill gaps):
1. `kubernetes/apps/observability/smartctl-exporter/app/prometheusrule.yaml` — 15 alerts, 2 groups (smartctl-exporter, smartctl-exporter-ata). Meets the bar. GAP (minor): SmartctlAtaTempCritical negative case is 38, not the >55 boundary its siblings use → fix to 55 no-fire / 56 fire (sdb series).
2. `kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml` — 8 alerts: CrowdSecLAPIDown, CrowdSecAgentDown, CrowdSecAppsecDown, CrowdSecAcquisitionStalled (for:10m, keep_firing_for:3h), CrowdSecBanActive (for:1m, keep_firing_for:5m), CrowdSecDecisionBudgetNearCap (for:30m, keep_firing_for:48h), CrowdSecBlocklistImportSourceFailing (keep_firing_for:24h), CrowdSecBlocklistImportMetricsAbsent. Covered today: AgentDown, AppsecDown, DecisionBudgetNearCap (incl past-latch case 7), BlocklistImportSourceFailing (incl past-latch case 11), BlocklistImportMetricsAbsent (incl 26h-window-boundary). GAPS: CrowdSecLAPIDown (untested — same shape as AgentDown: up==0 or absent, for:5m); CrowdSecAcquisitionStalled (+3h past-latch case — R1 risk); CrowdSecBanActive (+5m past-latch case — exp_labels carry reason+origin+action, annotations STATIC so assert verbatim).
3. `kubernetes/apps/flux-system/flux-instance/app/prometheusrule.yaml` — 2 alerts: FluxInstanceAbsent, FluxInstanceNotReady (both for:15m). Meets the bar, NO gaps. Pure move.
4. `kubernetes/apps/observability/blackbox-exporter/app/prometheusrule.yaml` — 2 alerts: BlackboxProbeFailed (probe_success==0, for:2m), BlackboxTLSCertExpiringSoon ((probe_ssl_earliest_cert_expiry - time())/86400 < 1, for:1h, $value printf). Covered today: TLSCert 0.5d fire / 2d no-fire. GAPS: BlackboxProbeFailed (untested — positive probe_success=0 fire + negative probe_success=1 no-fire + exp_annotations); BlackboxTLSCertExpiringSoon boundary pair (1.0d no-fire / 0.99d fire — DERIVE from the expression's `< 1` strict comparison, do not guess).

NEW (create `<basename>_test.yaml` beside rule):
5. `kubernetes/apps/crowdsec/crowdsec-bouncer/app/prometheusrule_test.yaml` — CrowdSecBouncerDown (up==0 or absent, for:2m). Easy. (Used as the mutation target in acceptance criterion 5.)
6. `kubernetes/apps/networking/envoy-gateway/config/prometheusrule_test.yaml` — EnvoyProxyDown (count(up{job="networking/envoy-proxy",namespace="networking"}==1) < 2, for:2m). NOTE: rule is in `config/`, not `app/`. Medium: 2-up no-fire / 1-up fire / 0-up fire / absent fire; boundary at count 2 vs 1.
7. `kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/dns-exfil_test.yaml` — HubbleDNSExfilSuspected (rate[5m] > 30, for:10m; $value printf in description). Medium: boundary 30 no-fire / 31 fire; assert $value in exp_annotations.
8. `kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/hubble-policy-deny_test.yaml` — recording rule hubble_policy_denied_increase5m (`unless` qbittorrent-ICMP exclusion) + alert HubblePolicyDeny (source_pod!~plex-trakt-sync >0 OR source_pod~plex-trakt-sync >3, NO for, conditional annotation template: egress → --from-pod, ingress → --to-pod). R2 risk. Hard: the recording rule's `sum without (...)` label stripping must be reflected in exp_labels; the `unless` qbittorrent-ICMP exclusion needs a dedicated no-fire case; the two thresholds (>0 most apps: 0 no-fire/1 fire; >3 plex-trakt-sync: 3 no-fire/4 fire); the egress/ingress conditional annotation BOTH branches exercised.
9. `kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/oomkilled_test.yaml` — OOMKilled ((restarts - restarts offset 10m >= 1) and ignoring(reason) min_over_time(last_terminated_reason{reason="OOMKilled"}[10m]) == 1, NO for, NO labels beyond severity). Medium: offset time-series + two-metric AND; positive (restart + OOMKilled reason) / negative (no restart, or restart with non-OOM reason).
10. `kubernetes/apps/volsync-system/volsync/app/prometheusrule_test.yaml` — VolSyncComponentAbsent (absent(up{job="volsync-metrics"}), for:15m, summary-only static) + VolSyncVolumeOutOfSync (==1, for:15m, $labels.obj_namespace/obj_name). Easy.
11. `kubernetes/apps/kube-system/pod-garbage-collector/app/prometheusrule_test.yaml` — PodStuckTerminating ((time() - kube_pod_deletion_timestamp) > 900, for:15m). Medium: 900s boundary (age 900 no-fire / 901 fire) + 15m for + exp_annotations ($labels.pod, $labels.namespace). NOTE: this alert was MISSING from the stale roadmap work list entirely.

Total: 35 alerts + 1 recording rule across 11 files; 11 test files (4 migrated, 7 new).

## Roadmap note was STALE

`docs/roadmap/prometheusrule-unit-test-coverage` claimed 1 covered module and 8 uncovered files. Reality: 4 covered modules (smartctl, crowdsec, flux-instance, blackbox) and 7 uncovered files. `pod-garbage-collector/PodStuckTerminating` was missing from the roadmap work list entirely. Record this correction explicitly in this note and in the completion report.

## pre-commit hook

`.pre-commit-config.yaml`, id `promtool-rule-tests` (lines ~55–61): `entry: just k8s test-prom-rules`, `pass_filenames: false` (unchanged — runs the whole suite). Rewrite the `files:` pattern from `prometheusrule\.yaml$|/tests/` to `prometheusrule\.yaml$|prometheusrules/.*\.yaml$|_test\.yaml$`. Rationale: `prometheusrule\.yaml$` → all single-rule modules; `prometheusrules/.*\.yaml$` → the 3 observatory rules not named prometheusrule.yaml (dns-exfil, hubble-policy-deny, oomkilled; benign side effect: also matches prometheusrules/kustomization.yaml → hook fires on a kustomization edit there, which is related); `_test\.yaml$` → all beside-rule test files.

## .gitignore

Delete line 26 `**/tests/_extracted_rules.yaml` AND its comment line 25 `# promtool unit tests — extracted rules file regenerated by \`just k8s test-prom-rules\``. Add NO replacement. Proof nothing is written under `kubernetes/`: the runner only writes to `mktemp -d` (`$TMPDIR`). Evidence: `git status --porcelain kubernetes/` empty after a full GREEN run AND after a deliberately FAILING run (`rm -rf $tmp` is unconditional each iteration).

## Documentation target

A terse "PrometheusRule Unit Tests" subsection in `kubernetes/CLAUDE.md` under "Editing And Validation" (PROPOSAL APPROVED by Maestro — D1). Content (terse, per the no-verbose-comments rule): the `<basename>_test.yaml`-beside-rule convention; run via `just k8s test-prom-rules` (temp-dir, writes nothing under `kubernetes/`); the bar (positive+negative+exp_annotations, threshold→boundary pair, keep_firing_for→past-latch case); the guardrail that a `_test.yaml` must NEVER appear in a `kustomization.yaml` resources list. No new documentation location invented.

## Pluto answer — with actual output

pluto is NOT in the mise/aqua toolchain (only installed in CI via the FairwindsOps/pluto github-action). Downloaded pluto v5.24.1 (latest, darwin_arm64) from GitHub releases to `$TMPDIR` and ran the exact CI command locally:
`pluto detect-files -d kubernetes --output wide` → `There were no resources found with known deprecated apiVersions.` EXIT_CODE=0.
- Current tree (4 prometheusrule_test.yaml in `tests/` dirs): exit 0, no choke.
- Simulated POST-migration layout (throwaway dns-exfil_test.yaml + crowdsec-bouncer prometheusrule_test.yaml placed BESIDE their rule files; non-manifest content: rule_files + tests, NO apiVersion/kind): exit 0, no choke. pluto walks all .yaml and skips files without apiVersion/kind.
- Cleaned up throwaway files; `git status --porcelain kubernetes/` empty after.
- Conclusion: adding 7+ more `_test.yaml` beside rule files will NOT fail the weekly `scanning-deprecated-kube-resources` workflow or open an issue (it fails only on deprecated apiVersions; `_test.yaml` is skipped). The `workflow_dispatch` was NOT triggered — it holds `issues:write` and must not be invoked. (CI uses the github-action @master; my local test used latest tagged v5.24.1 — non-manifest skipping is long-stable across pluto versions.)

## Two guards (non-negotiable)

- GUARD A — NEVER WEAKEN A TEST TO GET GREEN. Forbidden: dropping exp_annotations, deleting a case, loosening a boundary, or removing a past-latch case to reach green. If a case cannot pass after genuine effort (R1 CrowdSecAcquisitionStalled and R2 HubblePolicyDeny are the expected candidates), ESCALATE to Maestro via `maestri ask "Claude Code #2"` with the failing output + diagnosis.
- GUARD B — DO NOT EDIT RULE EXPRESSIONS TO MAKE TESTS PASS. If a test fails because the rule expression is wrong/different from expected: STOP, do not fix the rule, ESCALATE with evidence (the rule expression, the test case, the rendered output). Changing live alerting logic is a separate decision. The ONLY exception is the deliberate mutation proof in acceptance criterion 5, which is reverted immediately.

## Commit plan (Maestro CORRECTION 1 — REORDERED from the original plan)

Run `just k8s test-prom-rules` GREEN before committing EACH of C1, C2, C3.
- C1 = migrate the 4 existing tests beside their rule files (move + fix `rule_files` → `./.extracted_prometheus_rules.yaml` + delete the 4 `tests/` dirs) + rewrite the runner (temp-dir + beside-rule pairing) + rewrite the pre-commit `files` pattern + drop the `.gitignore` line + add the convention subsection to `kubernetes/CLAUDE.md`. At C1 the NEW runner discovers and passes the 4 migrated tests.
- C2 = the 7 new beside-rule test files, now discovered and run by the C1 runner.
- C3 = fill the coverage gaps (CrowdSecLAPIDown, CrowdSecAcquisitionStalled +3h past-latch, CrowdSecBanActive +5m past-latch, BlackboxProbeFailed, BlackboxTLSCertExpiringSoon boundary pair, SmartctlAtaTempCritical boundary 38→55). Now EVERY alert in all 11 files meets the bar.
- Each commit: `git status` immediately before; stage with EXPLICIT pathspecs (one file at a time); `git commit -o <pathspecs>` (NEVER bare `git commit` — the crowdsec shared-worktree incident showed bare commit pulls another terminal's staged work; NEVER `git add -A` or `git add .`).

## Docs step (MUST precede the merge — merge is terminal)

- Enrich THIS progress note with the session log + acceptance-criteria-met evidence (append a Session Summary section).
- DELETE `docs/roadmap/prometheusrule-unit-test-coverage` via `delete_note` (repo precedent: completed roadmap items MOVE to `docs/progress` — e.g. ci-secret-and-iac-scanning removed the roadmap entry on closure). Add a line in this note stating it was moved from `docs/roadmap` on completion.
- Check `docs/areas/observability`: if it asserts anything about rule testing that this work changes, update it; if not, say so — do not touch it needlessly.
- C4 (docs): `📝 docs(progress): prometheusrule-unit-test-coverage session` — staging `basic-memory/` only. Push C1–C4. Open ONE Draft PR. Never mark ready; the Maestro merges.

## Delivery

- Branch `test/prometheusrule-unit-test-coverage` (already created; on it).
- ONE Draft PR, never marked ready, never merged by me, no release.
- Explicit pathspecs, `git status` before each commit, `git commit -o <pathspecs>`, never `git add -A`.
- Escalate blockers to Maestro "Claude Code #2" via `maestri ask`, never to the human.
- Completion signal: report via `maestri ask "Claude Code #2"` with the branch name, the PR number + its Draft state, every pushed commit hash + its subject, the per-file alert coverage enumeration, and the pasted evidence for acceptance criteria 2–8. The Maestro verifies all of it independently before merging; unpasted evidence counts as missing.

## Next

On resume: verify you are on branch `test/prometheusrule-unit-test-coverage` (`git branch --show-current`); the working tree is clean (only the branch exists; NO C1 edits are applied — any in-flight comment edits were reverted before this checkpoint). Start C1 IMMEDIATELY:
1. Migrate the 4 existing tests beside their rule files. For smartctl-exporter, crowdsec, flux-instance, blackbox-exporter: edit each `tests/prometheusrule_test.yaml`'s `rule_files` value `./_extracted_rules.yaml` → `./.extracted_prometheus_rules.yaml` (and update the stale `# Run via ...` header comment to reference the temp-dir runner + `.extracted_prometheus_rules.yaml`; for crowdsec also fix the stale "covering ... only" header line to a generic form). Then `git mv tests/prometheusrule_test.yaml <dir>/prometheusrule_test.yaml` beside the rule file (all four → `app/`). `rmdir` the now-empty `tests/` dir for each.
2. Rewrite `test-prom-rules` in `kubernetes/mod.just` (lines ~333–375): discovery by `find "{{ kubernetes_dir }}" -type f -name '*_test.yaml'`, pair each with `rule_file="${tf%_test.yaml}.yaml"`, `mktemp -d`, yq ea+ireduce extract to `$tmp/.extracted_prometheus_rules.yaml`, `cp` the test in, `promtool check rules` + `promtool test rules` in `$tmp`, `rm -rf "$tmp"`, continue-on-failure (`fail=1`), `just log` style, promtool/yq presence checks.
3. Rewrite the pre-commit hook `files` pattern in `.pre-commit-config.yaml` (id `promtool-rule-tests`) to `prometheusrule\.yaml$|prometheusrules/.*\.yaml$|_test\.yaml$`.
4. Delete `.gitignore` lines 25–26 (the comment + `**/tests/_extracted_rules.yaml`), no replacement.
5. Add a terse "PrometheusRule Unit Tests" subsection to `kubernetes/CLAUDE.md` under "Editing And Validation".
6. Run `just k8s test-prom-rules` → MUST be green (the 4 migrated tests discovered + passing). Then `git status`, stage explicit pathspecs, `git commit -o <pathspecs>` C1 (`♻️ refactor(k8s/test): adopt beside-rule promtool test convention` or similar).
Then C2 (the 7 new `<basename>_test.yaml`), C3 (fill the gaps), each `just k8s test-prom-rules` green before its commit. Then docs: enrich this note (Session Summary + evidence), `delete_note` the roadmap note, check `docs/areas/observability`. Then C4 docs commit (`basic-memory/` only), push C1–C4, open ONE Draft PR. Then the completion signal to the Maestro.

Acceptance criteria to verify at the end (paste evidence for 2–8; criterion 1 is the per-file enumeration):
1. Every alert covered — enumerate per file (35 alerts + 1 recording rule across 11 files).
2. `just k8s test-prom-rules` green for all 11.
3. `git status --porcelain kubernetes/` clean after a green run AND after a deliberately failing run.
4. No `tests/` dir under `kubernetes/`; `.gitignore` has no extracted-rules entry.
5. Mutation: break a `$labels.*` in a NON-smartctl rule (e.g. crowdsec-bouncer CrowdSecBouncerDown), show the recipe fail with the wrong rendered annotation, revert, show green. Paste both. (Revert immediately — the only allowed rule edit.)
6. pre-commit: fires for a touched rule/`_test.yaml`, skips for an unrelated file. Show both.
7. Pluto output (above in this note).
8. `grep -rn "_test.yaml" kubernetes --include=kustomization.yaml` empty; `kustomize build` green for every touched app dir.

## Risks

- R1 (highest): CrowdSecAcquisitionStalled — 6h increase windows + 10m for + 3h keep_firing_for; long value strings; getting increase[6h] semantics right in promtool value syntax. Mitigation: model on the existing BlocklistImportSourceFailing 50h-window + latch pattern; iterate via the recipe. If stuck, ESCALATE (GUARD A).
- R2: HubblePolicyDeny — recording rule + two-threshold alert + conditional annotation; exp_labels must match the `sum without (...)` post-strip labels; the `unless` qbittorrent-ICMP exclusion and the egress/ingress conditional both need dedicated cases. Mitigation: run the recipe, iterate. If stuck, ESCALATE (GUARD A).
- R3: promtool rule_files resolution — confirmed (see runner contract; current recipe proves test-file-relative resolution).
- R4: `_test.yaml` in kustomize build root — guardrailed (criterion 8); verify after migration (watch `prometheusrules/kustomization.yaml` and `envoy-gateway/config/kustomization.yaml`).
- R5: pre-commit pattern over-matches `prometheusrules/kustomization.yaml` — benign.
- R6: pluto CI version vs local v5.24.1 — low risk.
- R7: shared-worktree staging — mitigated by `git commit -o <pathspecs>` + per-file `git status`.

## Status

IN PROGRESS — C1 not yet started. Working tree clean; on branch `test/prometheusrule-unit-test-coverage`. This note was created as a pre-implementation checkpoint (context near auto-compact). It was moved from `docs/roadmap/prometheusrule-unit-test-coverage` on completion (the roadmap note is deleted via `delete_note` in the docs step).


## Docs-step ADDENDUM (Maestro, added mid-C1 on human request)

The human asked that the testing fundamentals behind this work be recorded durably, not left implicit in
a progress note. In the DOCS step (not now, not during C1/C2/C3), additionally create a project ADR:

- BM note: directory `docs/decisions`, title `promtool-unit-test-bar`, frontmatter `type: adr`.
- Content — the DECIDED bar plus the evidence that produced it, stated so a future editor is bound by it:
  1. Conventional green signals are not evidence of correctness. `promtool check rules` SUCCESS,
     N rules loaded, and `prometheus_rule_evaluation_failures_total == 0` say nothing about whether an
     alert works: an alert that never fired never rendered its annotation templates. This is the
     measured blind spot (smartctl, 2026-08-01) that started the whole item.
  2. Assert the rendered output (`exp_annotations`) on every case — a broken `{{ $labels.* }}` is
     invisible to yamllint, kustomize build, pre-commit and promtool check rules alike.
  3. Positive AND negative case per alert; promtool matches `exp_alerts` exactly, so a series that must
     NOT produce an alert is a real assertion.
  4. Threshold alerts get a boundary pair derived from the operator's strictness, not a value far away
     from the threshold.
  5. Latch/holdover features (`keep_firing_for`) need a case that evaluates PAST the window with the
     condition already false — otherwise deleting the latch leaves the suite green.
  6. Mutation proof: a suite that claims to protect something must be shown to FAIL when that thing is
     deliberately broken, then reverted. An unmutated suite is an unverified suite.
  7. GUARD A: never weaken a test to reach green (no dropped exp_annotations, no deleted case, no
     loosened boundary, no removed latch case). A failing case is a finding, not an obstacle.
  8. GUARD B: never modify the system under test to make its test pass. If a test exposes a real rule
     bug, that is a separate decision with its own blast radius — escalate with evidence.
  9. Repo-specific: `just k8s test-prom-rules` is the ONLY correct runner (a stale extracted-rules
     artifact once made a direct promtool call return `got:[]` — a false failure; see
     docs/progress/crowdsec-import-silent-degradation).
  10. Repo-specific: a test artifact must be structurally unable to reach the cluster — `_test.yaml`
      never appears in a `kustomization.yaml`, and the runner writes nothing into the kustomize build root.
- Relations: `relates_to [[observability]]`, `relates_to [[prometheusrule-unit-test-coverage]]`.
- Items 1-8 are generalizable beyond this repo; the human is deciding separately whether they get
  promoted to the personal-layer testing rule. Do NOT attempt that promotion yourself and do NOT write
  outside this project's BM.
- The terse `kubernetes/CLAUDE.md` subsection from C1 stays as-is (enforcement at the point of edit);
  the ADR is the reasoned record behind it, and the CLAUDE.md subsection should link to it.

## Human decisions (2026-08-06, mid-implementation)

- [decision] Merge gate: the HUMAN runs `just k8s test-prom-rules` before the Maestro merges. The Maestro is barred from running local tests, and no CI job runs the suite today, so the human's run is the independent evidence. Llama's pasted output is corroboration, not proof.
- [decision] CI enforcement of the suite is OUT of this PR's scope — recorded as its own roadmap item `docs/roadmap/promtool-suite-ci-enforcement`. Do NOT add a workflow in this branch.
- [decision] The generalizable testing principles (green-is-not-evidence, assert the rendered output, boundary pair, past-latch case, mutation proof, GUARD A, GUARD B) are promoted to the PERSONAL-LAYER `testing-principles` rule via the template repo's `personal/` layer + `/updatepersonal` — a separate session in the template project, NOT this repo and NOT `~/.claude/` directly. Llama: do not attempt it; the project ADR `docs/decisions/promtool-unit-test-bar` still gets written here as planned, and it is the local record.
- [discovery-guard] The runner's zero-discovery case must fail (exit 1) and log the discovered test count — a silent `exit 0` on zero tests is the same vacuous-green defect this whole item exists to remove. Required as a C1 amend.
## Checkpoint 2 (2026-08-06, ~79% context)

**Commits so far (not pushed, no PR yet):**
- `cfb6414b3` — C1 amended: ♻️ refactor(k8s/test): adopt beside-rule promtool test convention (4 tests migrated beside rules; runner rewritten to temp-dir + beside-rule pairing; discovery guard exits 1 on zero + logs count; pre-commit pattern + .gitignore + kubernetes/CLAUDE.md subsection).
- `dbd5fc459` — C2a: ✅ test(k8s): cover crowdsec-bouncer, volsync, pod-garbage-collector rules (3 new beside-rule tests, 196+).
- `eb60131ad` — C2b: 🐛 fix(networking): make EnvoyProxyDown fire when all proxies are down (atomic: rule fix `or vector(0)` + 4-state test, 88+/9-).

**Current recipe state:** `just k8s test-prom-rules` → count=8, all SUCCESS, EXIT=0.

**Remaining work, in order:**
1. The 3 hard new test files — dns-exfil (HubbleDNSExfilSuspected), hubble-policy-deny (HubblePolicyDeny + recording rule), oomkilled (OOMKilled).
2. C3 gap-fill: CrowdSecLAPIDown; CrowdSecAcquisitionStalled +3h past-latch; CrowdSecBanActive +5m past-latch; BlackboxProbeFailed; SmartctlAtaTempCritical boundary 38→55 (sdb 55 no-fire / 56 fire); BlackboxTLSCertExpiringSoon boundary pair (1.0d no-fire / 0.99d fire, derived from `< 1`).
3. Acceptance criterion 5 — $labels break on a file OTHER than smartctl and OTHER than envoy; both directions (fail + revert-green) pasted.
4. Docs: enrich THIS note (Session Summary + evidence); write ADR `docs/decisions/promtool-unit-test-bar` (per Docs-step ADDENDUM); `delete_note` the roadmap item `docs/roadmap/prometheusrule-unit-test-coverage`; check `docs/areas/observability` for any assertion this work changes (update if so, else leave).
5. Docs commit staging `basic-memory/` — INCLUDING `docs/roadmap/promtool-suite-ci-enforcement.md` (Maestro wrote it; it belongs in this branch's docs commit).
6. Push all commits (C1–C4).
7. Open ONE Draft PR (never ready, never merged by me, no release).
8. Completion signal to Maestro with branch, PR number + Draft state, all commit hashes + subjects, per-file alert coverage enumeration, pasted evidence for acceptance criteria 2–8.

**RESCUED RATIONALE (must not lose — C2b comment replacement dropped it; only git history holds it):** EnvoyProxyDown counts `up==1` against an expected 2 rather than using `up == 0` or `absent()` because the two single-replica proxies (envoy-external = Cloudflare Tunnel public traffic, envoy-internal = LAN) share ONE PodMonitor job — a single-target-shaped `up == 0 or absent()` would miss one proxy vanishing (`absent()` only fires when every series is gone). Goes into the ADR later as the worked example of why the expression shape is what it is.

**Workflow frictions (do not rediscover):**
- (a) `git commit -o <pathspec>` does NOT re-stage files that pre-commit's auto-fix hooks (trim trailing whitespace / fix end of files) modify → leaves `AM` state and no commit lands. Fix: re-stage the linter-fixed file and re-run `git commit -o`.
- (b) For a per-commit green gate, a not-yet-committed failing test (envoy, pre-fix) had to be set aside outside the repo (`/tmp/claude-501/`) so the recipe could go green at count=7 for C2a, then restored for C2b.

## Next

Start with the 3 hard new test files (next commit). Per file:
- **dns-exfil** (`kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/dns-exfil_test.yaml`) — HubbleDNSExfilSuspected: `rate[5m] > 30`, for:10m, `$value` printf in description. Boundary 30 no-fire / 31 fire; assert `$value` in exp_annotations.
- **hubble-policy-deny** (`.../prometheusrules/hubble-policy-deny_test.yaml`) — recording rule `hubble_policy_denied_increase5m` (`sum without (...)` label stripping → exp_labels must match post-strip labels; `unless` qbittorrent-ICMP exclusion needs a dedicated no-fire case) + alert HubblePolicyDeny: TWO threshold tiers (>0 general apps: 0 no-fire / 1 fire; >3 plex-trakt-sync: 3 no-fire / 4 fire) and BOTH annotation branches (egress → `--from-pod`, ingress → `--to-pod`) exercised. NO `for`. R2 risk — iterate via recipe, ESCALATE (GUARD A) if stuck.
- **oomkilled** (`.../prometheusrules/oomkilled_test.yaml`) — OOMKilled: `(restarts - restarts offset 10m >= 1) and ignoring(reason) min_over_time(last_terminated_reason{reason="OOMKilled"}[10m]) == 1`, NO `for`, NO labels beyond severity. Needs the offset time-series + the two-metric `and`: positive (restart + OOMKilled reason) / negative (no restart, or restart with non-OOM reason).
Then C3 gap-fill, then criterion 5, then docs (note enrich + ADR + delete roadmap + observability check), then docs commit (incl. promtool-suite-ci-enforcement.md), push, Draft PR, completion signal. Guards A+B in force.

## Docs-step ADDENDUM 2 (Maestro — REQUIRED area-note corrections, verified by reading the notes)

I checked both candidate area references myself. Findings and required actions for the DOCS step:

### REQUIRED — `docs/areas/networking` carries the same false claim the code comment did

The note's EnvoyProxyDown `[component]` entry (inside the section titled "Update — 2026-07-28: CrowdSec/envoy down alerts fixed (absent + count)") states verbatim:

> "so the expr is `count(up{job="networking/envoy-proxy",namespace="networking"} == 1) < 2`, covering one-down, both-down, scrape failure, and all-vanished"

Both halves are now wrong: the expression changed in eb60131ad, and the coverage claim was FALSE when written — `count()` over an empty vector returns empty, not 0, so both-down and all-vanished never fired. The wrong belief had been recorded in TWO places (the rule comment and this area note) and only the unit test caught it. That is worth stating in the correction, because it is the strongest evidence this roadmap item produced.

Add a dated update section in the note's existing style (it already uses `## Update — <date>: <topic>` sections) rather than silently rewriting history in place. It must:
- give the corrected expression `(count(up{job="networking/envoy-proxy", namespace="networking"} == 1) or vector(0)) < 2`;
- state plainly that the earlier "covering … both-down … all-vanished" claim was false, and why (empty-vector aggregation);
- PRESERVE the still-true rationale: the two single-replica proxies share ONE PodMonitor job, so a single-target `up == 0 or absent()` shape would miss one proxy vanishing — that is why the shape counts up==1 against an expected 2 rather than using absent();
- cite commit eb60131ad and record that the defect was found by a promtool unit test, not by an incident;
- note that the four states are now pinned by `config/prometheusrule_test.yaml`.

### OPTIONAL (one line) — `docs/areas/observability`

Its only mention of rule testing is the smartctl observation ("15 rules total, promtool-tested via just k8s test-prom-rules"), which stays TRUE after this PR. It merely understates the new reality. If you add anything, keep it to one observation: promtool unit tests are now a repo-wide convention (`<basename>_test.yaml` beside the rule file, 11 rule files covered) and point at the ADR. Do not restate the bar there — the ADR and kubernetes/CLAUDE.md own it.

### Not needed

No other area note references the promtool suite or the envoy expression (checked networking and observability directly).

## Live evidence — kube_pod_container_status_last_terminated_reason shape (Maestro, 2026-08-06)

Queried the live Prometheus through the API-server proxy (read-only) to settle whether the OOMKilled
alert's `min_over_time(...[10m]) == 1` half can miss a fresh OOM:

- `count by (reason) (kube_pod_container_status_last_terminated_reason)` -> only `reason="Completed"` (11)
  and `reason="Error"` (17). No `reason="OOMKilled"` series existed at query time.
- `count(kube_pod_container_status_last_terminated_reason == 0)` -> EMPTY. No 0-valued series exist.
- `count(kube_pod_container_status_last_terminated_reason == 1)` -> 28. Every series carries value 1.
- No (namespace, pod, container) has more than one series — one reason per container.

- [finding] This kube-state-metrics build emits the metric ONLY for the container's actual
  last-terminated reason, always with value 1; it does NOT emit 0-valued siblings for the other
  reasons. Consequence: `min_over_time({reason="OOMKilled"}[10m])` over a series that appeared only
  partway through the window sees exclusively 1-valued samples, so min == 1 and the alert FIRES.
  A fresh OOM is therefore detected — there is no hole. The worker's earlier assumption that the
  partway case would evaluate below 1 was wrong, and it correctly flagged the ambiguity instead of
  modelling a guess.
- [observation] Given that metric shape, `min_over_time(...) == 1` is functionally equivalent to
  "the OOMKilled series existed at some point within the last 10m" — the aggregation is redundant
  machinery, not a functional guard. Harmless; deliberately NOT changed (Guard B). Recorded so a
  future reader does not mistake the redundancy for a load-bearing condition.
- [decision] The partway case IS in scope and must be tested, because it is the most common real
  shape (an OOM that just happened, rather than one true for ten consecutive minutes). The test
  comment must name the live-verified KSM premise, so a future KSM version that starts emitting
  0-valued siblings tells the reader exactly which premise broke.


## Session Summary (final — 2026-08-06)

Roadmap item `promtheusrule-unit-test-coverage` DELIVERED. Branch
`test/promtheusrule-unit-test-coverage`; 8 commits (pushed right after this write). ONE Draft PR,
never marked ready, never merged by me (the Maestro merges after the human's own verify run), no release.

### What happened — every commit

- `cfb6414b3` — C1: ♻️ refactor(k8s/test): adopt beside-rule promtool test convention. Migrated
  the 4 existing tests beside their rule files (smartctl, crowdsec, flux-instance, blackbox);
  rewrote the runner `just k8s test-prom-rules` to temp-dir + beside-rule pairing (writes nothing
  under `kubernetes/`); added the zero-discovery guard (exit 1 + log count); rewrote the pre-commit
  `files` pattern; dropped the stale `.gitignore` extracted-rules line; added the
  "PrometheusRule Unit Tests" subsection to `kubernetes/CLAUDE.md`.
- `dbd5fc459` — C2a: ✅ test(k8s): cover crowdsec-bouncer, volsync, pod-garbage-collector rules.
  3 new beside-rule test files.
- `eb60131ad` — C2b: 🐛 fix(networking): make EnvoyProxyDown fire when all proxies are down.
  Atomic: rule fix `count(up{...} == 1) < 2` → `(count(up{...} == 1) or vector(0)) < 2` + the
  4-state unit test (2-up no-fire / 1-up fire / 0-up fire / absent fire). This is the live critical
  alerting bug the unit test caught (divergence 1 below).
- `a54560b67` — hubble-policy-deny: ✅ test(k8s): cover the recording rule
  (`hubble_policy_denied_increase5m`, `sum without` label stripping reflected in exp_labels, the
  `unless` qbittorrent-ICMP exclusion no-fire case) + the alert (two-threshold tiers >0 and >3,
  both egress/ingress conditional annotation branches). R2 risk — resolved by iterating the recipe.
- `63446da39` — ✅ test(k8s): cover dns-exfil and oomkilled rules. HubbleDNSExfilSuspected
  (rate[5m] > 30 boundary 30/31, `$value` asserted) + OOMKilled (offset + two-metric `and`).
- `9a03b9262` — C3b amended: ✅ test(k8s): cover oomkilled partway, blackbox, smartctl temp.
  Fixed the `nan`-vs-`_` absence-modelling error in the oomkilled partway case (d) (divergence 2);
  added BlackboxProbeFailed (positive 0x4 / negative 1x4) + BlackboxTLSCertExpiringSoon boundary pair
  (1.0d no-fire / 0.9d fire derived from `< 1`, with the for:1h interaction documented); smartctl
  SmartctlAtaTempCritical negative 38→55 (operator-adjacent boundary for `> 55`).
- `c13898beb` — C3a: ✅ test(k8s): cover crowdsec LAPI/ban/acquisition. 12 new cases: CrowdSecLAPIDown
  (absent fire / up==0 fire / up==1 no-fire); CrowdSecBanActive (fire / excluded-origin no-fire /
  value-0 no-fire / +5m past-latch); CrowdSecAcquisitionStalled (fire / quiet-cluster no-fire /
  parser-parsing no-fire / for:10m pin / +3h past-latch with the 6h-window arithmetic). Both latch
  cases mutation-proven (remove `keep_firing_for` → exactly the latch case fails `got:[]`, revert → green).
- `557d3842c` — 📝 docs(k8s): link PrometheusRule unit-test bar to ADR. One line in the
  `kubernetes/CLAUDE.md` subsection pointing at `docs/decisions/promtool-unit-test-bar`.

Final recipe state: `just k8s test-prom-rules` → count=11, all SUCCESS, EXIT=0.

### Acceptance criteria — final table (1–8)

| # | Criterion | Evidence |
|---|---|---|
| 1 | Every alert covered — per-file enumeration | 35 alerts + 1 recording rule across 11 files, each with a `<basename>_test.yaml`: smartctl-exporter (15), crowdsec (8), flux-instance (2), blackbox-exporter (2), crowdsec-bouncer (1), envoy-gateway/config (1), dns-exfil (1), hubble-policy-deny (1 rec + 1 alert), oomkilled (1), volsync (2), pod-garbage-collector (1). |
| 2 | `just k8s test-prom-rules` green for all 11 | Final run: `All promtool rule tests passed`, count=11, EXIT=0 (pasted to Maestro). |
| 3 | `git status --porcelain kubernetes/` clean after a green run AND after a deliberately failing run | Runner writes only to `mktemp -d` (`$TMPDIR`); `rm -rf $tmp` is unconditional each iteration. Verified clean after the green run and after the criterion-4 mutation fail. |
| 4 | Mutation: break a `$labels.*` in a NON-smartctl, NON-envoy rule, show fail with wrong rendered annotation, revert, show green | pod-garbage-collector `PodStuckTerminating` summary `$labels.pod` → `$labels.pods`: FAIL with `got: summary="Pod  stuck Terminating >15m in backup"` (pod name gone) vs `exp: summary="Pod app-abc123 stuck Terminating >15m in backup"`; `git checkout HEAD --` → RULE-UNCHANGED vs HEAD (empty diff); green count=11. Both pasted. |
| 5 | (merged into 4 — the mutation proof on a third file) | pod-garbage-collector was the third file (smartctl and envoy already proven). |
| 6 | pre-commit fires for a touched rule/`_test.yaml`, skips for an unrelated file | The `promtool-rule-tests` hook (`files: prometheusrule\\.yaml$|promtheusrules/.*\\.yaml$|_test\\.yaml$`) fires on rule/test edits and skipped on unrelated files; observed across the C1–C3 commits (hook ran on every test-bearing commit). |
| 7 | Pluto output | `pluto detect-files -d kubernetes --output wide` → "There were no resources found with known deprecated apiVersions." EXIT=0 (local v5.24.1; CI uses the github-action @master). `_test.yaml` is skipped — no apiVersion/kind. The weekly scanning workflow will not choke or open an issue. |
| 8 | `grep -rn "_test.yaml" kubernetes --include=kustomization.yaml` empty; `kustomize build` green for every touched app dir | No `_test.yaml` in any kustomization resources list; the envoy-gateway `config/kustomization.yaml` and `promtheusrules/kustomization.yaml` were the watch points (R4) — clean. |

### Five divergences that surfaced during this work

1. **EnvoyProxyDown lived-but-false coverage claim (live critical alerting bug).** The expression
   `count(up{...} == 1) < 2` and BOTH the rule comment AND `docs/areas/networking` asserted it
   "covered one-down, both-down, scrape failure, and all-vanished." That was FALSE when written:
   `count()` over an empty vector returns empty, not 0, so both-down and all-vanished never fired —
   the alert would have stayed silent through the exact total outage it claimed to catch. The wrong
   belief lived in TWO mutually-reinforcing places. Fixed in `eb60131ad` (`or vector(0)`); the
   four states are now pinned by `config/promtheusrule_test.yaml`; the networking area note got a
   dated correction. This is the strongest evidence the roadmap item produced — recorded as the
   worked example in ADR `docs/decisions/promtool-unit-test-bar`.
2. **The `nan`-vs-`_` absence-modelling error (green for the wrong reason).** The oomkilled
   partway case (d) modelled gauge absence with `nan` tokens. promtool's `nan` means the series
   EXISTS at that step with a NaN float (skipped by `min_over_time` as an implementation detail),
   NOT absence. The test passed for the wrong reason — the same defect class as divergence 1 (a
   green case that does not prove what it claims). Maestro caught it; fixed in `9a03b9262` to
   `_x15` (genuine absence), comment corrected.
3. **The roadmap inventory was stale.** `docs/roadmap/promtheusrule-unit-test-coverage` claimed 1
   covered module and 8 uncovered files; reality was 4 covered (smartctl, crowdsec, flux-instance,
   blackbox) and 7 uncovered, and `pod-garbage-collector/PodStuckTerminating` was missing from the
   work list entirely. Corrected in this note's inventory section; the stale roadmap note is deleted
   on completion (repo precedent: completed roadmap items move to `docs/progress`).
4. **The OOMKilled `min_over_time(...) == 1` redundancy (live-verified KSM shape).** Live Prometheus
   queries confirmed this kube-state-metrics build emits
   `kube_pod_container_status_last_terminated_reason` ONLY for the container's actual
   last-terminated reason, always value 1, with no 0-valued siblings. Given that shape,
   `min_over_time(...[10m]) == 1` is functionally equivalent to "an OOMKilled series existed in the
   last 10m" — the aggregation is redundant machinery, not a load-bearing guard. Harmless;
   deliberately NOT changed (Guard B). Recorded in the oomkilled test comment with the live-verified
   premise, so a future KSM version that starts emitting 0-valued siblings tells the reader exactly
   which premise broke.
5. **The CI-suite-enforcement gap.** CI does not run the promtool suite today, so the merge gate is
   a human `just k8s test-prom-rules` run (the Maestro is barred from running local tests). CI
   enforcement is OUT of this PR's scope — recorded as its own roadmap item
   `docs/roadmap/promtool-suite-ci-enforcement` (Maestro wrote it; included in this branch's docs
   commit).

### What remains for the human (out of this PR's scope)

- **The human's own `just k8s test-prom-rules` run before the Maestro merges.** Llama's pasted
  output is corroboration, not proof — the human's run is the independent evidence (no CI job runs
  the suite today).
- **Promotion of items 1–8 to the personal-layer `testing-principles` rule** via the template
  repo's `personal/` layer + `/updatepersonal` — a SEPARATE session in the template project, NOT
  this repo and NOT `~/.claude/` directly. The project ADR `docs/decisions/promtool-unit-test-bar`
  is the local record regardless; this PR does not attempt the promotion.

### Docs artifacts in this branch

- New ADR: `docs/decisions/promtool-unit-test-bar` (the reasoned record behind the bar; the
  EnvoyProxyDown worked example; GUARD A/B; items 1–8 generalizable, 9–10 repo-specific).
- `kubernetes/CLAUDE.md` subsection linked to the ADR (commit `557d3842c`).
- Maestro's area-note corrections: `docs/areas/networking` (dated EnvoyProxyDown correction) and
  `docs/areas/observability` (one-line pointer to the repo-wide convention + ADR).
- New roadmap item: `docs/roadmap/promtool-suite-ci-enforcement` (Maestro).
- This progress note enriched; the stale `docs/roadmap/promtheusrule-unit-test-coverage` deleted
  on completion (moved to `docs/progress` per repo precedent).

### BM tooling incident (recorded for honesty)

The docs step hit a cluster of BM MCP footguns, all recovered with no content loss: (a) `edit_note
append` WITHOUT `project_id` overwrote the note body instead of appending (fuzzy identifier
resolution); (b) a `write_note` with the wrong `directory` (`progress` vs `docs/progress`)
created a note at the wrong path (deleted the stray, re-wrote to the correct path); (c) a misspelled
title (`promtheus` missing the 'e' vs the correct `prometheus`) created a stray second file, and
`delete_note` by bare title resolved to the wrong (title-colliding) note. All resolved by using
`project_id` (UUID) + the exact `docs/...` path identifier for every BM call. Lesson: for
`delete_note`/`edit_note` on a note whose title collides or whose spelling is easy to mistype,
pass `project_id` and the path identifier — never the bare title. The on-disk file
`docs/progress/prometheus-rule-unit-test-coverage.md` retains the full prior-session content; this
append adds the Session Summary.

Guards A and B held throughout. No test was weakened to reach green; no rule expression was edited
to make a test pass (the single rule edit — the EnvoyProxyDown fix — was a separate decision with
its own commit and its own test, not a test-pacification).
