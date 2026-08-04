---
title: kubelet-gc-and-flux-deadman-alerts
type: progress-note
permalink: home-ops/docs/progress/kubelet-gc-and-flux-deadman-alerts
---

# kubelet-gc-and-flux-deadman-alerts — execution progress

## Metadata (observation-form)

- [topic] kubelet image-GC + crashloop backoff cap, Flux dead-man alerts, Talos ISO download resilience, and one BM note correction
- [status] done — code merged via PR #4111 (68b7c8f93); item B applied to k8s-cp0 on 2026-08-04; item C live in cluster
- [branch] chore/adopt-upstream-hardening
- [area] talos-cluster, flux-gitops, observability
- [created] 2026-08-04

## What was done

Four independent items, one branch, three code commits + one docs commit.

### Item B — kubelet image-GC + crashloop backoff

File: `kubernetes/talos/machineconfig.yaml.j2` (`machine.kubelet.extraConfig`).

Added two keys (alphabetical order preserved):
- `crashLoopBackOff.maxContainerRestartPeriod: 60s` — caps container-restart backoff at 60s instead of the built-in 300s, shortening convergence after a reboot when dependency-ordering crashloops fire all at once.
- `imageMaximumGCAge: 168h` — age-based image GC, the only working reclaim path on this node.

Evidence: node `k8s-cp0` imageFs is 7.5% used (76,381,360,128 of 1,021,764,960,256 bytes), so the 70% high threshold (~715 GB) never fires — today NO image is ever garbage-collected and every Renovate bump leaves its predecessor on disk. `imageMaximumGCAge` is GA + LockToDefault since k8s 1.35; `KubeletCrashLoopBackOffMax` is beta-default-true since 1.35; kubelet runs v1.36.3. Validation: `maxContainerRestartPeriod` in [1s, 300s] and `imageMaximumGCAge` > `imageMinimumGCAge` (default 2m) — both satisfied. Neither key is in Talos v1.13's ProtectedConfigurationFields.

Caveat: the unused-image age timer RESETS on every kubelet restart, so a 168h window only completes in quiet stretches (every `apply-node`, Talos upgrade, K8s upgrade restarts kubelet). It still strictly dominates today's "never GC" state.

**Applied to k8s-cp0 on 2026-08-04.** After PR #4111 merged, the machineconfig was applied under separate human approval: `just --yes talos apply-node k8s-cp0` reported "Applied configuration without a reboot"; node k8s-cp0 stayed Ready, 78d uptime preserved. Verified live from the node's own configz endpoint (`kubectl get --raw /api/v1/nodes/k8s-cp0/proxy/configz`): `imageMaximumGCAge: 168h0m0s` and `crashLoopBackOff: {maxContainerRestartPeriod: 1m0s}` are live, and the four pre-existing keys survived unchanged (`imageGCHighThresholdPercent: 70`, `imageGCLowThresholdPercent: 50`, `maxPods: 150`, `serializeImagePulls: false`). The machineconfig is outside Flux, so it took an explicit apply rather than reconciling automatically. Future check: `imageFs.usedBytes` was 76,381,360,128 bytes (7.5% of the disk) at adoption time, so the 168h age-GC effect should be visible as a drop from that figure in roughly 8 days (modulo the kubelet-restart reset caveat above).

### Item C — Flux control-plane dead-man alerts

Files:
- NEW `kubernetes/apps/flux-system/flux-instance/app/prometheusrule.yaml`
- EDIT `kubernetes/apps/flux-system/flux-instance/app/kustomization.yaml` (added `- ./prometheusrule.yaml` to resources)
- NEW `kubernetes/apps/flux-system/flux-instance/tests/prometheusrule_test.yaml`

Two Prometheus-evaluated rules, living outside the notification-controller -> Alertmanager failure domain (if the FluxInstance or notification-controller is gone/unready, the existing Flux alert path cannot emit anything):
- `FluxInstanceAbsent` — `absent(flux_instance_info{exported_namespace="flux-system", name="flux"})`
- `FluxInstanceNotReady` — `flux_instance_info{exported_namespace="flux-system", name="flux", ready!="True"}`

Both `severity: critical`, `for: 15m`. Evidence: `flux_instance_info` returns 1 series with `exported_namespace="flux-system"`, `name="flux"`, `ready="True"` (from flux-operator's `serviceMonitor.create: true`); `severity: critical` routes to Pushover. NOTE the label is `exported_namespace`, NOT `namespace`.

Q4 placement: co-located under `flux-instance/app/` because per-app co-location IS the dominant repo pattern (~9 existing `prometheusrule.yaml` files live under `apps/*/app/`). What sits in `kube-prometheus-stack/app/prometheusrules/` is the genuinely cross-cutting set (oomkilled, hubble-policy-deny, dns-exfil) belonging to no single app — a FluxInstance alert belongs with the flux-instance app.

Q5 semantic note: `ready!="True"` in PromQL ALSO matches a series with no `ready` label at all — that is the CORRECT dead-man semantic and is intentionally kept; do not "fix" it into `ready="False"`.

NOT adopted: `HelmReleaseReconciliationFailure` / `KustomizationReconciliationFailure` — the existing Flux Alert (`components/common/alerts/alertmanager/alert.yaml`) already fans these to the same Alertmanager->Pushover receiver with a tuned 5-entry exclusionList, so adding them would double-notify AND bypass the exclusionList.

Implementation note (deviation from the work order's test spec): the work order stated `absent()` yields an empty-label vector and the `FluxInstanceAbsent` test should expect only `{alertname, severity}`. promtool proved this wrong — `absent(matcher)` carries the matcher's labels (`exported_namespace`, `name`) into the result vector. The test was corrected to expect those labels; the rule itself is unaffected.

**Verified live (2026-08-04):** `PrometheusRule flux-instance` exists in `flux-system` with exactly `FluxInstanceAbsent` and `FluxInstanceNotReady`, both `for: 15m`, `severity: critical`; the rules are also present in the operator-rendered `prometheus-kube-prometheus-stack-rulefiles-0` ConfigMap in `observability` — which is what proves Prometheus actually loads them, not just that the CR exists.

### Item D — harden Talos installer-ISO download

File: `kubernetes/talos/mod.just` (`download-image` recipe curl).

Added flags to the existing curl: `--remove-on-error --retry 5 --retry-delay 5 --retry-all-errors`. `burn-image` auto-selects the newest `talos-*.iso` by mtime with NO checksum step, so a truncated/aborted download leaves a partial ISO that then becomes the burn candidate → unbootable USB, discovered at the bare-metal box. `--remove-on-error` makes that state unreachable; retry flags cover transient `factory.talos.dev` failures. One node — nothing to fall back to while re-burning. Host-side only.

### Item A — correct BM note `docs/progress/talos-config-refactor`

Three defects fixed in place (BM MCP only — see Method note):

1. etcd auto-compaction framing was factually wrong. Correction: kube-apiserver compacts the keyspace every 5m by default (`--etcd-compaction-interval`, default 5m0s; flag absent from both the live apiserver command line and `machineconfig.yaml.j2`, so the default applies — confirmed empirically by etcd logging "finished scheduled compaction" on an exact 5-minute grid across 12 consecutive intervals). Our etcd-side 1h compactor (`machineconfig.yaml.j2:145-146`, commit `a08f84c91`) is a no-op: it targeted revision 46,322,920 while the apiserver had already compacted to 46,355,468 — ~32,548 revisions (~40 min) behind; its calls complete in 392us-9ms with no DB-size change; the apiserver's real compactions take ~69 ms. The setting IS present and live but functionally redundant; kept (zero cost) as the sole fallback if the apiserver compactor were ever disabled. Measured state: `etcd_mvcc_db_total_size_in_bytes` 169 MB, in_use 64 MB → ~105 MB free pages (62%), 7.9% of the 2 GiB quota, no alarms; the ~105 MB of free pages is a DEFRAG matter (compaction returns pages to bbolt's freelist but never shrinks the file), not a compaction concern. Fixed in BOTH the Consensus Matrix `### etcd` verdict and the `### 1. etcd auto-compaction (HIGH value)` section. Documentation correction only — machineconfig NOT changed for this. `docs/areas/talos-cluster` was left untouched (it correctly cites :145-146).
2. Sources table `bjw-s` row: `3 CP` → `1 CP` (single controlplane node `delta`, single-member bond0, SATA-only Samsung 870 install disk). Added a one-line note that only the bjw-s row was re-verified 2026-08-04 and the other rows are unverified as of the note's original date.
3. Status inconsistency: frontmatter `status: implemented` vs observation `- [status] proposed` → fixed the observation line to `- [status] implemented`.

Method note: this BM build does NOT expose `edit_note` (only `read_note`/`write_note`/`search_notes`/etc.), so item A was applied via `write_note(overwrite=true)` with the full corrected body and the original frontmatter fields passed through `metadata`. Each defect was verified fixed by a post-write `read_note` read-back (10/10 marker checks passed) — a `write_note` success response alone is not proof.

## Validation results

- pre-commit on all seven touched files (5 code + 2 basic-memory/): PASSED (yamlfmt, yamllint, just-fmt, gitleaks, promtool-rule-tests, secrets checks).
- Item B: `just talos render-config k8s-cp0` (op inject, real secrets) piped to `talosctl validate -m metal` → `is valid for metal mode`, exit 0. Rendered content was NEVER printed (Q6 condition 1); the trap-cleaned mktemp + the validate tempfile were confirmed gone afterward (Q6 condition 2); `op inject` succeeded, no placeholder substitution needed (Q6 condition 3).
- Item C: `just k8s test-prom-rules` → all promtool rule tests passed (4 cases: FluxInstanceAbsent fire/no-fire, FluxInstanceNotReady fire/no-fire). `kubectl kustomize kubernetes/apps/flux-system/flux-instance/app` → builds clean.
- Item D: just-fmt + shellcheck via pre-commit → PASSED.

## Follow-ups (record ONLY — do NOT implement; each needs its own issue)

1. `machineconfig.yaml.j2:52-53` sets `discard_unpacked_layers = false` — kept because upstream runs spegel (P2P image mirror); we run no spegel anywhere, so we may be paying that storage cost for nothing. Plausibly part of the gap between 76 GB imageFs and ~14 GB of reported images — the other half of the same disk problem item B addresses.
2. BM `docs/areas/talos-cluster` claims in three places that the cluster runs "without CoreDNS (Cilium DNS)". Only the Talos-managed CoreDNS is disabled; CoreDNS is Flux-deployed and live (`kube-system/coredns`, chart 1.47.0). Needs a correction pass. Report only — do NOT edit in this branch.
3. `flux-instance/app/helmrelease.yaml` carries a duplicate `--concurrent` flag (a shared `=10` plus a controller-specific override) — effective value depends on pflag last-wins rather than being stated once. Readability wart only; measured throttling is 2.57% peak and `CPUThrottlingHigh` is not firing, so nothing to fix functionally.
4. notification-controller still has `limits.cpu: 1` because it falls outside the resources patch's target regex, while the patch is named as if it covered everything. It has never throttled (0 in every window) — naming/intent inconsistency, not a problem.
5. **Repo-wide BM `type:` inconsistency** (audit 2026-08-04): progress notes use a mix of `progress` (18), `note` (10), `roadmap` (5), `progress_note` (4), and `progress-note` (2). The reserved `progress/[branch]` anchor type per the global memory model is `progress-note` (hyphen); this note was corrected to it. A repo-wide normalization is its own task and is NOT authorized here — recorded as an observation only.

## Report-only flag

`docs/areas/observability`'s "Three PrometheusRules and three ScrapeConfigs ARE centralized here now" wording is imprecise — per-app co-location is the dominant repo pattern (see Q4 placement above). Not edited in this branch.

## Relations

- continues [[talos-config-refactor]]
- relates_to [[talos-cluster]]
- relates_to [[flux-gitops]]
- relates_to [[observability]]
