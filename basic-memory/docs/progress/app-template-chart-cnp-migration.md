---
title: app-template-chart-cnp-migration
type: progress-note
permalink: home-ops/docs/progress/app-template-chart-cnp-migration
tags:
- cilium-networkpolicy
- app-template
- ad-025
- networking
---

# Progress — app-template-chart-cnp-migration (AD-025 execution)

Implements
[[AD-025-app-template-chart-generated-cnps]]: move the per-app CNP of the 17 app-template apps
from `app/ciliumnetworkpolicy.yaml` into HelmRelease `values.networkpolicies.main` (type: cilium),
per batch = RETIRE commit (delete CNP + kustomization entry, Flux prunes) then ADD commit
(networkpolicies block, Helm creates the CNP under the freed name). Directly on main
(GitHub flow, pushes pre-authorized by the human 2026-10-13). Short CNP-less window accepted
per AD-025.

## Metadata (observation-form)

- [status] done — all 3 batches executed 2026-10-13; 17/17 app-template apps on chart-generated CNPs
- [closed] 2026-10-14
- [priority] medium
- [effort] M — 3 commits per batch, 3 batches, Hubble verification per batch
- [roadmap] merged into this note — the docs/roadmap/app-template-chart-cnp-migration note was deleted on closure; design rationale now lives in the section below
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
  qbittorrent, radarr, sonarr, paperless, sure.
- [decision] Batch 3 — cloudflare-tunnel alone (edge path; window = public site offline; outage
  accepted by the human at any time).

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
- [observation] Batch-2 start record (corrected): neither the human nor the Maestro ever sent
  "mehet a 2. batch"; the "Igen" answer in the worker's batch-2 menu was a mistaken Enter
  keystroke sent by the Maestro, and the batch proceeded on that signal (see correction under
  Maestro-verified).
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

## Maestro-verified (2026-10-13)
- [observation] Batch 2 accepted after the Maestro's independent verification: render diff 7
  identical + sure ratified selector diff; 16 Helm-owned CNPs (batches 1+2) all Valid; 8/8
  batch-2 HelmReleases Ready.
- [observation] Prometheus sum(hubble_drop_total{reason="POLICY_DENIED"}): 1984 -> 5502 -> 7750
  at 20:22:30 / 20:23:30 / 20:24:30 UTC, flat since 20:24:30 — drops stopped when the CNPs
  appeared (20:24:05).
- [observation] Window drops: egress paperless + sure-server/worker -> dragonfly; ingress
  paperless-gpt -> paperless, radarr/sonarr -> qbittorrent, sonarr -> prowlarr,
  bazarr/seerr -> radarr/sonarr.
- [finding] The ingress window was fail-CLOSED, not fail-open: the gateway vocabulary CCNPs
  already select those pods for ingress, so with the app CNP gone the peer apps' traffic fell
  through to deny.
- [correction] Neither the human nor the Maestro ever wrote "mehet a 2. batch"; the "Igen"
  answer in the worker's batch-2 confirmation menu came from a mistaken Enter keystroke sent
  by the Maestro. Never attribute words to someone who did not send them.

## Batch 3 result (2026-10-13, done)

- [observation] Executed by "Claude Code #2" directly (Maestro toggle off; the worker had run out
  of budget). RETIRE 874282b21 pushed 20:42 UTC, legacy CNP pruned 20:42:25; ADD 6d0811608 pushed,
  Helm CNP created 20:42:54 — window ~30 s.
- [observation] Render gate (helm template 5.3.0, canonical JSON diff vs the deleted file): only the
  expected selector diff (name-only -> name+instance+controller); live CNP spec == rendered spec;
  CNP Valid, managed-by Helm; HR Ready (upgrade v24 on app-template@5.3.0). The legacy
  `io.kubernetes.pod.namespace` peer keys were copied verbatim.
- [observation] cloudflared lost the edge during the window (QUIC dial timeouts 20:42:43-56) and
  re-registered all 4 tunnel connections by 20:43:25. POLICY_DENIED drops from cloudflare-tunnel:
  counter 0 -> 64 -> 344 at the 20:42:30 / 20:43:30 scrapes, flat since through 20:46:46 (1-min
  scrape cannot separate the last seconds before vs after 20:42:54).

## Outcome

- [observation] Acceptance: no `ciliumnetworkpolicy.yaml` remains under any app-template app
  (tree check 2026-10-13); 17 HelmReleases carry `networkpolicies:`; 17 live CNPs owned by Helm,
  all Valid; zero new POLICY_DENIED drops after each batch's CNP creation.
- [observation] Docs: k8s-workloads skill `references/app-scaffolding.md` gains the
  chart-generated CNP pattern; BM `docs/areas/k8s-workloads` canonical shape, the roadmap status
  and AD-025 (values shape + fail-closed ingress window) updated.
- [follow-up] The crowdsec-blocklist-import CronJob (04:00) and resticprofile (01:00) egress is first
  exercised by their next scheduled runs — check the job/healthcheck results.
- [follow-up] Template mcp-patterns: BM `edit_note insert_after_section` inserts right after the
  heading line, not after the section body (observed by the worker 2026-10-13).
- [follow-up] Roadmap note can be merged into this progress note per the project convention for
  fully implemented roadmap items.

## Post-migration observation — batch 2 CNP-less window (2026-10-14)

- [observation] hubble_drop_total{reason="POLICY_DENIED"} egress to database/dragonfly-0 grew in ONE burst on 2026-10-13 ~22:22:30-22:24:30 CEST: sure-worker 3220, sure-server 2196, paperless 472 (5888 total). Flat since (increase[1h]=0 on 2026-10-14 morning); no other source workload in the 7d retention.
- [evidence] Window = RETIRE commit a5f55930b (22:21:26) -> Flux prune -> ADD commit fa0b52a57 (22:22:34) -> Helm-created CNPs paperless 20:23:56Z / sure 20:24:05Z (creationTimestamp, managed-by Helm). The custom-egress pods were selected only by the pod-label CCNPs in between, so dragonfly:6379 was denied — the AD-025 accepted fail-closed window, measured at ~2.5 min.
- [observation] Impact: paperless celery hit a redis TimeoutError, in-flight tasks were cancelled and redelivered (late-ack), reconnected 22:23:58. sure showed no redis/dragonfly errors. No restarts; nothing to fix. Lesson for a future migration of this kind: land RETIRE + ADD in a single push so one reconcile replaces the CNP.
## Post-verification (2026-10-14)

7/7 post-run checks PASS: render==live 17/17 CNPs identical, 17 Helm CNPs Valid, all touched
HelmReleases/Kustomizations Ready, flux-local 146 passed. Overnight runs succeeded under the
chart-generated CNPs: crowdsec-blocklist-import Job 2026-10-14 02:00Z Completed;
resticprofile 01:00 local backup succeeded 01:02:08+02:00. POLICY_DENIED counter flat at 8094
since 2026-10-13 20:43:30Z — no new drops under the chart-generated CNPs. This closes the
overnight-run follow-up. The recyclarr @daily failure in the same window is unrelated
(Sonarr 5 upgrade 0b1e4a3fe, tracked separately).
## Design rationale (merged from roadmap)

Merged from docs/roadmap/app-template-chart-cnp-migration on closure (2026-10-14); that roadmap
note was deleted. The planned batches live in the Batches section above; the roadmap frontmatter's
[topic], [priority] and [effort] moved into Metadata above.

### Inventory (verified against the repo 2026-10-13)

- [observation] Egress-only CNPs (no ingress rules — a gap would be fail-closed): actual, backrest, calibre-web-automated, crowdsec-blocklist-import, homepage, paperless-gpt, pocket-id, resticprofile, sure (plus plex-trakt-sync — out of scope, see below).
- [observation] CNPs with ingress rules (a gap was expected to be fail-open; measured fail-CLOSED — see the AD-025 update 2026-10-13 and the Maestro-verified correction above): cloudflare-tunnel, jellyfin, llama-cpp, paperless, prowlarr, qbittorrent, radarr, sonarr (plus plex — out of scope, see below).
- [observation] Multi-controller releases: paperless (controllers paperless, backup — the CNP selects only paperless → `controller: paperless`); sure (server, worker — the CNP selects both via name only → `controllers: [server, worker]`).
- [observation] Name-only selectors today: cloudflare-tunnel, crowdsec-blocklist-import, sure — the chart renders name+instance+controller (equivalent for the pods selected today).
- [decision] plex and plex-trakt-sync are OUT of scope: both apps were removed entirely on 2026-10-13 (commit 573c7eeb5; orphaned Helm releases uninstalled, PVCs pruned). Scope is therefore 17 apps.

### Procedure per batch (2 commits, retire → add, each pushed and reconciled before the next)

A short CNP-less window between the two commits is accepted (user decision 2026-10-13, AD-025).

1. **Retire** — delete every batch `ciliumnetworkpolicy.yaml` and its `app/kustomization.yaml` entry. Flux prunes the CNPs; until step 2 the pods run on the baseline + vocabulary CCNPs only (narrow-world egress fails closed, ingress-bearing pods fall back to their ingress vocabulary labels). Check: `kubectl get cnp -n <ns> <app>` → NotFound for the batch.
2. **Add** — add `networkpolicies.main` (`type: cilium`, rules copied 1:1, split any rule that mixes peer kinds; `controller`/`controllers` for paperless and sure) to each HelmRelease; keep the AD-023 intent comment on the block. Local gates before commit: `helm template` of each release with the 5.3.0 chart and a diff of the rendered CNP spec against the deleted file (only the selector shape may differ), pre-commit. Push step 2 right after step 1 reconciles, to keep the window short. Check after reconcile: each HR Ready, `kubectl get cnp -n <ns> <app>` exists, Valid, labelled `app.kubernetes.io/managed-by: Helm`.

After step 2: `just k8s show-cnp-matrix` (each batch app shows its APP-CNP under the release name) + `just k8s hubble-live-capture 120` and `just k8s hubble-analyze <app label> DROPPED egress|ingress` for the batch pods; a startup-time app-log check for the narrow-world apps. Rollback = revert.

### Acceptance criteria (all MET — see Outcome and Post-verification above)

- [criterion] No `ciliumnetworkpolicy.yaml` remains under an app-template app (plex and plex-trakt-sync excluded — removed with the apps). — MET: tree check 2026-10-13; no hand-written CNP remained per the 2026-10-14 post-verification.
- [criterion] Every migrated app has exactly one live CNP named after its release, owned by Helm (`app.kubernetes.io/managed-by: Helm`). — MET: 17/17 render==live identical, all Valid (Post-verification 2026-10-14).
- [criterion] `flux-local test` green on every PR/commit; zero new policy-denied DROPPED flows attributable to a batch app. — MET: flux-local 146 passed; POLICY_DENIED flat at 8094 since 2026-10-13 20:43:30Z.
- [criterion] k8s-workloads skill scaffolding reference and the `docs/areas/k8s-workloads` canonical app shape updated to the chart-generated form (separate docs commit). — MET: see the Docs bullet under Outcome.

### Related (carried over from the roadmap note)

- implements [[AD-025-app-template-chart-generated-cnps]]
- relates_to [[AD-023-cnp-threat-model-audit]]
- relates_to [[k8s-workloads]]
- relates_to [[networking]]
