---
title: app-template-chart-cnp-migration
type: progress_note
permalink: home-ops/docs/progress/app-template-chart-cnp-migration
tags:
- cilium-networkpolicy
- app-template
- ad-025
- networking
---

# Progress — app-template-chart-cnp-migration (AD-025 execution)

Executes roadmap item [[app-template-chart-cnp-migration]] implementing
[[AD-025-app-template-chart-generated-cnps]]: move the per-app CNP of the 17 app-template apps
from `app/ciliumnetworkpolicy.yaml` into HelmRelease `values.networkpolicies.main` (type: cilium),
per batch = RETIRE commit (delete CNP + kustomization entry, Flux prunes) then ADD commit
(networkpolicies block, Helm creates the CNP under the freed name). Directly on main
(GitHub flow, pushes pre-authorized by the human 2026-10-13). Short CNP-less window accepted
per AD-025.

## Metadata (observation-form)

- [status] in progress — batch 1 executing 2026-10-13 (plan ratified by the Maestro)
- [area] k8s-workloads / networking
- [created] 2026-10-13
- [branch] main

## Execution log

- [observation] Pre-flight 2026-10-13: all 17 CNP files read against the 5.3.0 chart schema —
  zero rule splits needed (no rule mixes peer kinds; no icmps+toPorts pairing); controller
  matrix: 15 single-controller apps omit `controller`, paperless -> `controller: paperless`,
  sure -> `controllers: [server, worker]`; selector-shape render diffs expected only for
  crowdsec-blocklist-import, sure, cloudflare-tunnel.
- [observation] Batch 1 scope: actual, backrest, calibre-web-automated, crowdsec-blocklist-import,
  homepage, paperless-gpt, pocket-id, resticprofile (egress-only, single controller).
- [observation] Batch 1 pre-window checks 2026-10-13 ~22:00: Hubble baseline captured
  (120s cluster-wide, 25k flows, preserved per batch for re-slicing); resticprofile supercronic
  live schedule checked — backup 01:00 daily, forget 05:00 Tue — no cron collision with the
  window; paperless backup 00:30 and blocklist import 04:00 also clear.

## Batches

- [decision] Batch 1 — egress-only, single controller: actual, backrest, calibre-web-automated,
  crowdsec-blocklist-import, homepage, paperless-gpt, pocket-id, resticprofile.
- [decision] Batch 2 — ingress-bearing + multi-controller: jellyfin, llama-cpp, prowlarr,
  qbittorrent, radarr, sonarr, paperless, sure. NOT started (Maestro gate).
- [decision] Batch 3 — cloudflare-tunnel alone (edge path; window = public site offline ~minutes;
  human picks a quiet minute).

## Batch 1 result (2026-10-13, done)

- [observation] RETIRE commit 6b77debb5 (8 CNP files + 8 kustomization entries) pushed,
  cluster-apps reconciled, all 8 CNPs pruned (kubectl NotFound verified). Prune of the last
  4 objects lagged ~1 min behind the Kustomization apply — re-check after a short wait
  before declaring prune failures.
- [observation] Structural correction vs the plan: app-template 5.3.0 expects the rule arrays
  directly under `networkpolicies.main` (`egress:`/`ingress:`), NOT under a `rules:` key —
  the schema's `unevaluatedProperties: false` rejects `rules`. AD-025's "networkpolicies.<id>.rules"
  phrasing is stale on this point. `policyTypes` is a native-type-only requirement.
- [observation] ADD commit 5171ea352 (8 HelmReleases) pushed, reconciled. Render gate
  (helm template 5.3.0 + canonical JSON diff vs the deleted files): 7 apps byte-identical spec;
  crowdsec-blocklist-import differs only by endpointSelector gaining instance+controller labels
  (the ratified selector-shape diff). No enableDefaultDeny emitted, none set.
- [observation] Live verify: 8/8 HelmReleases Ready (upgrade succeeded, app-template@5.3.0);
  8/8 CNPs exist, Valid=True, managed-by=Helm; show-cnp-matrix shows exactly 1 CNP per app named
  after the release; Hubble 120s post-capture: zero DROPPED egress flows for all 8 apps
  (baseline capture identical); positive traffic present for 7 apps (resticprofile idle between
  01:00 backups, crowdsec-blocklist-import CronJob idle until 04:00 — real egress test at next runs).
- [observation] Environment notes: pre-commit fails on direct invocation (mise python3 shim
  recursion, machine-level brew python 3.15 issue) but runs clean inside the git commit hook;
  commit signing needs the 1Password agent socket (sandbox off); `diff <(...)` process
  substitution is blocked in the Bash sandbox — use temp files.

## Batch 2 result (2026-10-13, done)

- [observation] Ratified by the human via the Maestro ("mehet a 2. batch") plus direct
  confirmation in the worker terminal (the permission gate required the ratification in the
  worker transcript).
- [observation] RETIRE commit a5f55930b pushed 22:21, all 8 CNPs pruned on first check
  (~2 min after reconcile — the batch-1 prune lag did not recur). One HubblePolicyDeny alert
  class expected during the window (paperless -> dragonfly, sure -> postgres/dragonfly/llama-cpp
  fail closed); the Maestro independently verified only paperless-gpt -> paperless fired in
  batch 1's window and it self-resolves (increase[5m] expression).
- [observation] ADD commit fa0b52a57 pushed 22:23. Render gate: 7 apps byte-identical
  (paperless with controller: paperless renders exactly the hand-written selector); sure
  differs only by the ratified selector shape (instance label + controller In [server, worker]
  matchExpression). Live verify: 8/8 HRs Ready on app-template@5.3.0, 8/8 CNPs Valid + Helm-owned
  (CNPs appeared ~1 min after the HR upgrade — re-check after a wait, not immediately);
  show-cnp-matrix per-controller rows confirm paperless/backup stays CNP-less (baseline egress,
  name "-") and both sure controllers are covered by the single "sure" CNP.
- [observation] Hubble 120s post-capture: zero DROPPED egress AND ingress flows for all 8 apps
  (baseline identical); positive traffic present for all (98-471 flow-lines; sure-worker ->
  postgres:5432 FORWARDED under the new CNP). Captures preserved as baseline-hubble-batch2 /
  post-batch2.
- [observation] Values shape for app-template 5.3.0 (from batch 1): rule arrays directly under
  networkpolicies.main (no rules: key); batch-2 blocks authored in this shape from the start —
  first-try schema green on all 8.
