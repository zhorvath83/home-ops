---
title: crowdsec-blocklist-import
type: progress-note
permalink: home-ops/docs/progress/crowdsec-blocklist-import
---

# crowdsec-blocklist-import — execution progress

## Metadata (observation-form)

- [topic] GitOps manifests for the crowdsec-blocklist-import CronJob (roadmap phases 1-3 only); DRY_RUN starts true
- [status] DONE — implemented, deployed, live-verified. PR #4119 (manifests) + PR #4120 (cap 75k + CrowdSecDecisionBudgetNearCap alert, merge a98bbf706) + PR #4129 (freshness alerting) all merged to main. Core roadmap delivered; Phase 4 observation window and Phase 5 Tier B promotion carried forward as follow-on (see Follow-ups), not blockers.
- [branch] feat/crowdsec-blocklist-import — merged to main via PR #4119; cap+alert round via PR #4120 (merge a98bbf706)
- [area] crowdsec, flux-gitops, external-secrets, networking (Cilium), observability
- [created] 2026-08-04
- [implements] [[crowdsec-blocklist-import]] roadmap (closed)
- [roadmap] merged into this note — docs/roadmap/crowdsec-blocklist-import deleted on closure; design rationale (security value, list-selection tiers, sizing, design spec, execution plan, risks) preserved in the "Roadmap design rationale" section below
- [closed] 2026-08-05

## What was done

Implemented the crowdsec-blocklist-import roadmap item as Flux-managed manifests under `kubernetes/apps/crowdsec/blocklist-import/`. Scope is strictly phases 1-3 (manifests + auth wiring + egress/alerting); DRY_RUN is committed as `"true"` so the first scheduled runs (04:00 daily) are observable before any decision is actually written to the LAPI.

### Phase 1 — app manifests

New app: `ks.yaml` (Flux Kustomization, dependsOn onepassword-connect + crowdsec), `app/kustomization.yaml`, `app/helmrelease.yaml` (bjw-s app-template v5.0.1, cronjob controller), `app/externalsecret.yaml`, `app/ciliumnetworkpolicy.yaml`, `app/prometheusrule.yaml`. Parent `kubernetes/apps/crowdsec/kustomization.yaml` wired to discover it.

- Image pinned by digest: `ghcr.io/wolffcatskyy/crowdsec-blocklist-import:3.7.1@sha256:78ec83464827a129128e2e1cba0bc23562988bec177745334a9f2896c817860c` with a `# renovate:` annotation.
- CronJob: schedule `0 4 * * *`, concurrencyPolicy Forbid, backoffLimit 3, history 1/3, restartPolicy OnFailure.
- Pod security: runAsNonRoot true, runAsUser/runAsGroup/fsGroup 999, readOnlyRootFilesystem true, capabilities drop ALL, seccomp RuntimeDefault, automountServiceAccountToken false. Resources: requests cpu 50m / memory 64Mi, limits memory 256Mi. Probes disabled (batch job).
- `/tmp` backed by an emptyDir (repo idiom for read-only-root pods).

### Phase 2 — auth (auto-registration only, no manual cscli)

The tool uses TWO LAPI credentials (verified in v3.7.1 `blocklist_import.py`): a bouncer API key (`CROWDSEC_LAPI_KEY`, X-Api-Key) for READ, and machine credentials (`CROWDSEC_MACHINE_ID` + `CROWDSEC_MACHINE_PASSWORD`, JWT via `/v1/watchers/login`) for WRITE. Both are wired via auto-registration:

- Bouncer: `BOUNCER_KEY_blocklist_import` added to the crowdsec ExternalSecret template.data; `docker_start.sh` auto-registers a bouncer per `BOUNCER_KEY_*` env var on LAPI start. The blocklist-import pod reads the same value as `CROWDSEC_LAPI_KEY`.
- Machine: the existing LAPI postStart hook was extended to also run `cscli machines add blocklist-import -p ${BLOCKLIST_IMPORT_MACHINE_PASSWORD} -f /dev/null --force` (idempotent, exit 0 always — never restart-loops the LAPI). The blocklist-import pod reads `CROWDSEC_MACHINE_PASSWORD` from its own ExternalSecret (`blocklist-import-secret`).
- Both new 1Password fields use loud-fail explicit `data:` remoteRefs (missing field fails the ExternalSecret rather than seeding empty creds).

The LAPI `reloader.stakater.com/auto` annotation means a `crowdsec-secret` change auto-restarts the LAPI, so adding the fields triggers the postStart re-registration.

### Phase 3 — egress + alerting

- CNP (`blocklist-import`): egress to the LAPI (toEndpoints `k8s-app: crowdsec, type: lapi`, port 8080) and to the Tier A feed FQDNs (443) only. The telemetry FQDN `bouncer-telemetry.ms2738.workers.dev` is deliberately ABSENT and `TELEMETRY_ENABLED=false` / `METRICS_ENABLED=false` in the release — defence in depth.
- LAPI-side ingress: the existing `crowdsec-lapi` CNP gained a `fromEndpoints: app.kubernetes.io/name: blocklist-import` rule on 8080.
- Alerting: `CrowdSecBanActive` now excludes the `blocklist-import` origin (`origin!~"CAPI|lists(:.*)?|blocklist-import"`) so the high-volume expected decisions don't page. A new `CrowdSecBlocklistImportFailed` rule fires on `kube_job_status_failed{namespace="crowdsec", job_name=~"blocklist-import-.*"} > 0`.

### Tier A feed set (v3.7.1 BLOCKLIST_SOURCES, ENABLE_* keys)

Enabled (Tier A): SPAMHAUS, ABUSE_CH, EMERGING_THREATS, BINARY_DEFENSE, DSHIELD, BRUTEFORCE_BLOCKER, CYBERCRIME_TRACKER, MONTY_SECURITY_C2, VXVAULT, BOTVRIJ. Disabled (Tier B/C, out of scope): FIREHOL (single master in v3.7.1, not per-level keys), IPSUM, BLOCKLIST_DE, CI_ARMY, GREENSNOW, ABUSE_IPDB, SENTINEL, TOR, SCANNERS, STOPFORUMSPAM.

FQDNs allowed in the CNP: www.spamhaus.org, feodotracker.abuse.ch, urlhaus.abuse.ch, rules.emergingthreats.net, www.binarydefense.com, www.dshield.org, feeds.dshield.org, danger.rulez.sk, raw.githubusercontent.com, www.botvrij.eu.

### UID open question — resolved

The roadmap asked for the `blocklist` user UID. Verified from the GHCR amd64 image `/etc/passwd`: UID/GID 999. Used as runAsUser/runAsGroup/fsGroup in the release.

## Validation (quality gates)

1. `pre-commit run --files <all 11 touched>` — clean (yamlfmt, yamllint, promtool-rule-tests, gitleaks all Passed).
2. `kustomize build kubernetes/apps/crowdsec/blocklist-import/app` — exit 0.
3. `flux-local build ks blocklist-import --path kubernetes/flux/cluster --namespace crowdsec` — exit 0. (The `dependsOn with invalid names` stderr warning is a known flux-local resolution quirk: the bouncer and web-ui siblings use the identical `name: crowdsec, namespace: crowdsec` pattern and reconcile fine in production.)
4. `helm template blocklist-import oci://ghcr.io/bjw-s-labs/helm/app-template --version 5.0.1 -f values.yaml` — exit 0; rendered CronJob + ServiceAccount with all securityContext, env, envFrom, resource, and /tmp-mount fields verified.

## Open items / human actions

- **1Password fields to create in the existing `crowdsec` item**: `BLOCKLIST_IMPORT_BOUNCER_KEY` (a random bouncer API key) and `BLOCKLIST_IMPORT_MACHINE_PASSWORD` (the machine password). Both ExternalSecrets fail loudly until these exist.
- After the fields exist and the PR merges: the reloader restarts the LAPI → postStart registers the machine. Observe the first 04:00 run (DRY_RUN=true, logs only), then flip `DRY_RUN` to `"false"` in the HR for the next cycle.
- **PR is DRAFT and must NOT be merged by the worker** — control-lane decision.

## Fix round (Maestro independent verification)

Independent verification of the round-1 manifests found one real blocker (B1), a pre-existing same-class item traced to a false positive (N7), and documentation/wording fixes. All applied on the same branch; PR stays DRAFT.

### B1 — BLOCKER, fixed

`crowdsec/app/externalsecret.yaml` fetched `BLOCKLIST_IMPORT_MACHINE_PASSWORD` in `spec.data` but never emitted it in `spec.target.template.data`. ESO `mergePolicy` defaults to `Replace`, so the rendered `crowdsec-secret` contained only the templated keys and the LAPI postStart hook ran `cscli machines add blocklist-import -p ""` (empty credential → the CronJob 401s at `/v1/watchers/login`, or the 30×2s retry blocks postStart ~60s on every LAPI restart). Fixed by emitting `BLOCKLIST_IMPORT_MACHINE_PASSWORD: "{{ .BLOCKLIST_IMPORT_MACHINE_PASSWORD }}"` in `template.data`. Final rendered `crowdsec-secret` key set (5 keys): `BOUNCER_KEY_envoy`, `AGENT_PASSWORD`, `ENROLL_KEY`, `BOUNCER_KEY_blocklist_import`, `BLOCKLIST_IMPORT_MACHINE_PASSWORD`.

### N7 — traced, FALSE POSITIVE, no fix

`helmrelease.yaml:31` `token: $\${REGISTRATION_TOKEN}` (double `$`) is NOT a 1Password field and is NOT missing from the ESO template. Trace: the root `ks.yaml` injects `postBuild.substituteFrom: cluster-settings` into every child Kustomization, so `\${LAN_SUBNET}` (single `$`, line 28) is a Flux postBuild substitution from the `cluster-settings` ConfigMap, while `$$` is the Flux postBuild ESCAPE — the literal `\${REGISTRATION_TOKEN}` reaches `config.yaml.local` and CrowdSec's own config loader expands it from the `REGISTRATION_TOKEN` env var. That env var is chart-generated: the repo sets no `secrets.externalSecret.name`, so the chart creates `crowdsec-lapi-secrets` itself (`templates/lapi-secrets.yaml`) with an auto-generated `registrationToken` (randAlphaNum 48, persisted via lookup) and injects `REGISTRATION_TOKEN` on the LAPI pod from it (`templates/lapi-deployment.yaml`). Verified by `helm template`: `crowdsec-lapi-secrets` has the `registrationToken` key and the LAPI pod env wires `REGISTRATION_TOKEN` → `secretKeyRef: crowdsec-lapi-secrets / registrationToken`. `auto_registration.token` is NOT empty. No 1Password field is needed; no manifest change. (The Maestro HARD RULE held: no field invented.)

### N3 — human-ratified DEVIATION from the roadmap Design

Deleted `blocklist-import/app/prometheusrule.yaml` and removed it from `app/kustomization.yaml`. The roadmap Design section named a per-app `PrometheusRule` (`CrowdSecBlocklistImportFailed` on `kube_job_status_failed > 0`); this is a deliberate, human-ratified deviation. Reason: the built-in `KubeJobFailed` alert (kube-prometheus-stack, `kubernetesApps: true`) already covers CronJob failure, and `kube_job_status_failed > 0` never self-resolves — `failedJobsHistory: 3` keeps the failed Job object queryable, so the alert keeps firing through subsequent successful runs. A second rule is pure duplication. KEPT: the `CrowdSecBanActive` regex change in `crowdsec/app/prometheusrule.yaml` (`origin!~"CAPI|lists(:.*)?|blocklist-import"`) — verified correct.

### N8 — diff-size correction

Round-1 report said "11 files, +260/-3". Accurate figures: the code commit (b5e19f361) is 11 files, +260/-3; the full branch diff vs main at current HEAD (feat/crowdsec-blocklist-import) is 12 files, +355/-4 (verified: `git diff --shortstat main..HEAD`). The +1 file vs the code commit is the BM progress note; the line count grew across the docs commits. The round-1 report understated by quoting the code-commit figure instead of the full branch figure.

### Gate note — promtool-rule-tests is a NO-OP here

`kubernetes/mod.just:349-351` only runs `promtool test rules` for modules that have a `tests/` directory; crowdsec has none. So "pre-commit Passed" is NOT evidence for the `CrowdSecBanActive` rule change. Run `promtool check rules` directly on `crowdsec/app/prometheusrule.yaml` instead (gate output in the session report).

## Final round (post-merge hardening — branch feat/crowdsec-blocklist-import-hardening)

PR #4114 merged; Flux reconciled main@8a51e2ee. LIVE Phase 1-3 outcome (verified on the merged cluster): both ExternalSecrets (`crowdsec`, `blocklist-import`) `SecretSynced`; bouncer `blocklist_import` (underline) and machine `blocklist-import` (hyphen) registered with the LAPI; the dry-run wrote no decisions; `hubble-live-capture` (89 MB) showed 0 dropped egress and 0 flow to the telemetry FQDN.

This round's manifest changes (single code commit, 2 files, +12/-5):

- **M1 — dead feed disabled**: `ENABLE_MONTY_SECURITY_C2: "false"` with a comment referencing the upstream `data/all.txt` removal (404, verified). `raw.githubusercontent.com` is KEPT in the CNP — Cybercrime Tracker and VXVault both fetch `raw.githubusercontent.com/firehol/blocklist-ipsets/master/...`, so the FQDN is still load-bearing.
- **M2 — AD-023 pod labels**: `defaultPodOptions.labels` adds `egress.home.arpa/custom-egress: "true"` (opts out of the blanket `allow-cluster-egress` CCNP, whose `endpointSelector` is `egress.home.arpa/custom-egress` `DoesNotExist`, so the per-app CNP becomes the sole egress source) and `ingress.home.arpa/none: "true"` (near-deny ingress via the `ingress-none` CCNP — no Service/route/probes, `METRICS_ENABLED=false`). Verified before editing: (a) the opt-out label removes the pod from the blanket CCNP; (b) `ingress-none` is the correct no-ingress label for a consumer-less workload (matches the `resticprofile` sibling); (c) the LAPI-side ingress rule in `crowdsec/app/ciliumnetworkpolicy.yaml` (`fromEndpoints: app.kubernetes.io/name: blocklist-import`) still matches — `matchLabels` only checks the listed key, and extra pod labels do not remove the match.
- **M3 — binarydefense apex**: added `- matchName: "binarydefense.com"` to the CNP `toFQDNs`; `https://www.binarydefense.com/banlist.txt` 301-redirects to `https://binarydefense.com/banlist.txt` (verified), and Cilium FQDN policy is per-DNS-name so the redirect target needs its own allow entry.
- **M4 — ratified config**: `DRY_RUN: "false"` (flipped after the Phase 2 dry-run was reviewed live), `LOG_LEVEL: "DEBUG"` (per-source `logger.debug`; ~12 extra lines/run, keeps VictoriaLogs), memory limit `256Mi` → `512Mi`.

Two intentional deviations from the roadmap spec (human-ratified):

1. **Memory 512Mi vs roadmap 256Mi**: the first non-dry-run run executes `get_existing_ips()` — a single unpaginated `GET /v1/decisions` + `response.json()`; the LAPI holds ~33.8k decisions (~6.8 MB JSON). 256Mi was the roadmap's pre-measurement estimate; 512Mi covers the unpaginated fetch. See follow-up (a).
2. **DRY_RUN flipped in the same PR**: the auth path is exercised for the FIRST time by this flip — `can_write()` (JWT `/v1/watchers/login`), `health_check()` and `get_existing_ips()` are all behind `if not config.dry_run`, so the green dry-run proved nothing about authentication. Flipping here ratifies the credential flow on the first real run.

Gates: pre-commit clean (yamlfmt, yamllint, gitleaks); `kustomize build kubernetes/apps/crowdsec/blocklist-import/app` exit 0 (renders CiliumNetworkPolicy, ExternalSecret, HelmRelease; CNP shows the new `binarydefense.com` apex); `helm template` (app-template 5.0.1, real values) renders the CronJob with `egress.home.arpa/custom-egress: "true"`, `ingress.home.arpa/none: "true"`, `DRY_RUN: "false"`, `ENABLE_MONTY_SECURITY_C2: "false"`, `LOG_LEVEL: DEBUG`, `memory: 512Mi`.

## Closing — live verification (post-merge, PR #4119)

PR #4119 merged; Flux reconciled main@0a5f86df. The third independent verification found ZERO blockers; the Maestro's P1 (DNS) and P2 (labels-override) suspicions were both disproven with evidence — the rendered pod-template labels block co-contains `app.kubernetes.io/name: blocklist-import` and the two AD-023 labels (so `defaultPodOptions.labels` merges, not replaces), and `allow-dns-egress` is a separate `endpointSelector: {}` CCNP that is the documented prerequisite for `toFQDNs`. The sibling `external-dns` has run the same label shape in production for 7 days.

Human-created 1Password fields (in the `crowdsec` item): `BLOCKLIST_IMPORT_BOUNCER_KEY` and `BLOCKLIST_IMPORT_MACHINE_PASSWORD`, 48 alphanumeric chars each. Field names match the ExternalSecret `remoteRef.property` values character-for-character — verified before merge.

LIVE evidence from the first real (non-dry-run) execution — Phase 2/3 acceptance proof:

- Live CronJob confirmed `DRY_RUN=false`, `memory limit 512Mi`, and all 5 pod labels present (`app.kubernetes.io/{name,instance,controller}` + `egress.home.arpa/custom-egress` + `ingress.home.arpa/none`) — `defaultPodOptions.labels` merges, does not replace.
- Manual Job `bli-live-1` at 2026-08-04 23:58: `Complete=True`, pod `Completed exit=0` — no OOMKilled; 512Mi was adequate.
- `Obtained machine JWT token` — the machine write credential works. This was the single dry-run-blind risk (`can_write()`, `health_check()` and `get_existing_ips()` are all gated behind `if not config.dry_run`); resolved in production.
- `Sources: 11 successful, 0 unavailable` — the M1 dead-feed disable removed the nightly spurious WARNING.
- `Imported 4660 new IPs`; LAPI confirms via `cscli metrics show decisions`: `external/blocklist (all sources) | blocklist-import | ban | 4660` alongside CAPI's 33,827 (24773 http:scan + 7714 ssh:bruteforce + 1340 generic:scan). 4660 < the dry-run's 5198 because `get_existing_ips()` now dedups against decisions CAPI already holds — expected, not a loss.
- `LOG_LEVEL=DEBUG` delivers the per-source breakdown the Phase 4 gate needs (e.g. `Cybercrime Tracker: 373 total IPs, 325 unique new`, `VXVault: 68 total, 66 unique new`, `DShield Top Attackers: 14 total, 9 unique new, 14 parse errors`).
- 8746 parsing errors — benign and fully attributed (URLhaus is a URL feed: domain hosts, never IPs; DShield metadata columns).
- Hubble re-verified AFTER the label change (the dry-run ran without `custom-egress`, so this was genuinely new): 504 pod-associated flows, 0 DROPPED from the pod (the one DROPPED row is an unrelated ICMPv6 router-solicitation the recipe's label filter does not scope out), 0 telemetry flows across 89 MB.
- Bouncer consumes without a restart: `cscli bouncers list` shows `envoy@10.244.0.210` pulling seconds after the write.

### Phase 4 observation window (open)

Window OPENS 2026-08-05; review due ~2026-08-26 (3 weeks). The concrete measurements to take are specified in the roadmap note's Phase 4 section — reference them there, do not re-derive here. The `LOG_LEVEL=DEBUG` per-source log lines (e.g. `Cybercrime Tracker: N total IPs, M unique new`) are the data source for the feed-pruning / promotion decision — that is what DEBUG was enabled for. A future session picks the gate up from the roadmap Phase 4 criteria plus these per-source DEBUG logs.

## Cap + alert round (PR #4120 — merged a98bbf706)

A measurement round found a time-sensitive operational defect: `MAX_DECISIONS` is a TOTAL cap (CAPI included), not per-run — `max_new = max(0, MAX_DECISIONS - len(existing))` where `existing` is the full `GET /v1/decisions` result (verified against v3.7.1 `blocklist_import.py`). On budget exhaustion the importer logs `MAX_DECISIONS budget reached ... — skipping remaining sources` and still exits 0, so `KubeJobFailed` never fires and the tail sources (Cybercrime Tracker, VXVault) drop silently. CAPI grew 15,273 → 34,445 in 5 days (deltas +2,146/+2,100/+970/+1,341, ~1.5k/day); the live `cs_active_decisions` total is 39,393 (CAPI 34,445 + blocklist-import 4,948), so the current budget under the 50k cap is only 10,607 — ~7 days to truncation. This round raises the cap and adds a predictive alert.

### R1 — cap raised 50k → 75k (manifest: `helmrelease.yaml`)

`MAX_DECISIONS: "75000"` with a 1-line comment ("TOTAL cap across all origins (CAPI included), not per-run"). Onset is **`MAX_DECISIONS − F`** (F = feed-set size ≈ 4,948 today; the sawtooth's two phases cancel exactly to this — see Final fix round F3), i.e. CAPI > 70,052, total ≈ 74,712 (~290 below the cap); current CAPI 34,445 → ~23 days to onset at ~1.5k/day (numerically the same 35,607 as total-cap minus live-total today, but the `onset = MAX_DECISIONS − F` formulation generalizes — see F4). Memory justification (NOT in the manifest — recorded here): independently re-measured (2026-08-05T12:24Z) the live bouncer `envoy-proxy-bouncer` working set is 39.56 MiB instant at 39,393 cached decisions (37 MiB on the 6h-step range; limit 128Mi) — slope ~1.0 KiB/decision (29 MiB @ ~31k → 37 MiB @ ~39k). Linear extrapolation to 75k ≈ 74.3 MiB, ~58% of the 128Mi limit; no bouncer memory raise and no bouncer restart is needed (`MAX_DECISIONS` is an env var on the importer CronJob only, not the bouncer). The earlier 36Mi / 0.93 KiB figure understated by ~3 MiB; conclusion unchanged. Caveat: the 07-30 51 MiB peak (measured when CAPI was ~15k, ~3.4× the linear model) shows non-linear transient refresh spikes that exceed steady-state — there is NO reliable model of the refresh spike at 75k (a reason to prefer 75k over 100k, see F5c), not a reason to raise the bouncer.

### R2 — predictive truncation alert (manifest: `crowdsec/app/prometheusrule.yaml`)

Added `CrowdSecDecisionBudgetNearCap` to the EXISTING crowdsec `PrometheusRule` (same group, same `cs_active_decisions{job="crowdsec-service", namespace="crowdsec"}` metric as `CrowdSecBanActive`): `sum(cs_active_decisions{...}) > 63750` (85% of 75000), `for: 30m`, `keep_firing_for: 48h`, `severity: warning`. Threshold lead time: current 39,393 → 63,750 at ~1.5k/day is ~16 days to fire; fire → 75,000 cap is 11,250 decisions / ~1.5k = ~7.5 days of action window (raise the cap again or prune a feed). `for: 30m` rides out single-scrape noise. CORRECTED (the no-flap claim was wrong, fixed in F1): `for: 30m` delays FIRING but not RESOLUTION, so the daily sawtooth (blocklist-import's 24h-duration decisions decay between 04:00 runs, amplitude ~4,948) crossing 63,750 produced ~1-2 spurious resolve/refire cycles over ~2.9 days before latching — the alert fires at the peak crossing and latches only at the trough crossing ~3 days later. `keep_firing_for: 48h` (≥ the sawtooth period) is what actually prevents the flap; it self-resolves when the count drops below 63,750 and stays down past the 48h window.

**Not a reversal of the N3 deletion.** N3 deleted the per-app `CrowdSecBlocklistImportFailed` (`kube_job_status_failed > 0`) because the built-in `KubeJobFailed` already covers CronJob FAILURE. This new alert covers a DIFFERENT condition — a silent budget exhaustion that EXITS 0 — which has NO built-in coverage. A future reader must not read the pair as flip-flopping.

### R3 — pruning decision: PRUNE NOTHING (but record leave-one-out)

No feed is disabled. The naive per-run figures mislead because `_run_once` banks shared IPs to whichever source runs first.

- **Emerging Threats ≈ Bruteforce Blocker**: intersection 546 of 554/560. The run log's ET 484 / BFB 9 split is a processing-ORDER artifact (ET runs first, banks the shared 546). Leave-one-out: ET-only 8, BFB-only 14, JOINTLY 481 unique. At most ONE of them may ever be pruned.
- **Leave-one-out unique-lost** (the metric Phase 4 decides on): Spamhaus 1662, URLhaus 1263, Binary Defense 794, Cybercrime Tracker 325, VXVault 66, DShield 37, BFB 9, DShield Top 9, Feodo 5, ET 5, Botvrij 4.
- **Botvrij**: 182 days stale (Last-Modified 2026-02-03), 4 entries, own gate + own FQDN — the only clean prune candidate if we ever prune.
- **Feodo (5, dead) is NOT independently prunable**: shares `ENABLE_ABUSE_CH` with URLhaus's 1,263. **DShield Top** shares `ENABLE_DSHIELD` with DShield. Do not try to prune them alone.
- **Cybercrime Tracker is a FROZEN mirror**: `Source File Date: Tue Jul 7` against a documented 12-hour update frequency (28 days stale). Review trigger, not a prune: re-read that header in ~30 days; if it has not advanced, prune it then.

### R4 — Phase 4 hit-attribution gap RESOLVED (roadmap updated)

The bouncer does NOT expose a per-origin block counter. Verified against the live bouncer `/metrics` (pod proxy): 15 metric families; `bouncer_requests_total{action="allow"}` is labelled by `action` ONLY (no `origin`); `bouncer_decision_cache_size{origin=...}` exists (CAPI 34,445 / blocklist-import 4,948) but counts CACHE, not hits. Therefore the roadmap's VictoriaLogs fallback — correlating `cscli decisions list --origin blocklist-import -o json` against bouncer/Envoy-denied 403s — is MANDATORY, not optional. Roadmap Phase 4 + "Open questions / evidence gaps" updated to mark the gap RESOLVED.

### R6 — Phase 4 candidate decision table (documentation only, no config change)

Net-new measured against the live union (CAPI ∪ blocklist-import ≈ 39,393):

- **DEFER (ranked by risk-adjusted value)**: (1) `ENABLE_CI_ARMY` 13,369 net-new, 0 Tor overlap, 0 broad blocks, needs NEW FQDN `cinsscore.com`; weakness: no published removal process. (2) `ENABLE_SENTINEL` 7,935, 2 Tor, NEW FQDN `view.sentinel.turris.cz`; weakness: greylist semantics. (3) `ENABLE_BLOCKLIST_DE` 18,989, 53 Tor, NEW FQDN `lists.blocklist.de`; the ONLY candidate with a documented delist path.
- **DISQUALIFIED on measured false-positive risk (not size)**: `ENABLE_ABUSE_IPDB` mirror (498 Tor exits = 21.3% of all known exits, +3,014 cloud/CDN hits — bans privacy users at scale, unaudited user-submitted mirror); `ENABLE_IPSUM` (300 Tor, reputation-by-count, no verification); `ENABLE_GREENSNOW` (1.4% Tor density); `ENABLE_SCANNERS` (Censys/Shodan static /23+/24 presets block legitimate research; scanner IPs rotate); `ENABLE_STOPFORUMSPAM` (60 entries → 124,780 addresses of whole hosting ranges; irrelevant, no public forum); `ENABLE_TOR` (Tor by definition); `ENABLE_FIREHOL` (single master gate forces L1+L2+L3, 25,878 net-new incl. Tier C).
- **Cap arithmetic for the strongest candidate**: 4,660 + 13,369 = 18,029 + CAPI 33,827 = 51,856 — EXCEEDED the old 50,000 cap, i.e. CI Army could not have been added without this round's raise. Under 75,000 it fits.
- **CGNAT is a NON-ISSUE by construction**: the parser strips `100.64.0.0/10` itself.
- **Measured 30-day yield**: `bouncer_requests_total{action="ban"}` = 19 vs `action="allow"` = 52,630 (0.036%); all 19 ban events PREDATE blocklist-import.
- **Genuine coverage gap**: cloud-hosted scanners/C2 — Tier A holds almost nothing in major cloud ranges (URLhaus 5, Cybercrime 39, Binary Defense 71). This is exactly what Phase 4 should test and what CI Army would close.
- **Caveat (honest)**: the cloud/CDN prefix set used for these measurements was hand-picked coarse ranges, not authoritative provider lists — directionally valid, not exact. Per-candidate ASN composition is UNMEASURED.

### Gates

pre-commit clean (incl. `promtool-rule-tests` — see premise drift below); `kustomize build` both `blocklist-import/app` and `crowdsec/app` exit 0; `promtool check rules` on the extracted `spec.groups` → `SUCCESS: 6 rules found` (the 6th is `CrowdSecDecisionBudgetNearCap`); `helm template` renders `MAX_DECISIONS: "75000"` in the CronJob env.

### Premise drift found this round (flagged to control lane)

- **`tests/` dir now exists**: the brief said the `promtool-rule-tests` hook is a NO-OP for crowdsec (no `tests/` dir), but the HUMAN's `prom` commit 59c4aa89a on main (merged into this branch) added `kubernetes/apps/crowdsec/crowdsec/tests/prometheusrule_test.yaml` (originally covered `CrowdSecAgentDown` + `CrowdSecAppsecDown` only). Attribution corrected this round: the tests dir is the HUMAN's commit 59c4aa89a, NOT the Maestro's. The hook now PASSES (not a no-op); `just k8s test-prom-rules` reports the crowdsec module as `SUCCESS: 6 rules found` (12 test cases after this round's F2 added 6 boundary cases for `CrowdSecDecisionBudgetNearCap`).
- **R5 verified against the pinned v3.7.1, not `main`**: `main`-branch `blocklist_import.py` already has `ENABLE_FIREHOL_LEVEL1/2/3` per-level overrides, but the DEPLOYED image is `3.7.1@sha256:...`, whose source has only the single `ENABLE_FIREHOL` master gate (all three levels share `enabled_key="enable_firehol"`). The brief's R5 describes the deployed version correctly; the per-level override is a newer-main feature.
- **Bouncer memory decomposition**: recorded my own live numbers rather than the brief's "62-80Mi cache + 21Mi baseline" split, which does not fully reconcile against the single live sample. The conclusion (75k fits under 128Mi, no bouncer raise/restart) is unchanged and independently confirmed. Re-measured this round (F3): 39.56 MiB instant / ~1.0 KiB/decision → 74.3 MiB @ 75k ≈ 58% of 128Mi; the 36Mi figure understated by ~3 MiB, 07-30 transient corrected to 51 MiB.

### Final fix round (PR #4120 — pre-merge)

Fourth independent verification found ZERO blockers but CORRECTED the Maestro's own onset hypothesis: truncation onset is **NOT total ≈ 70,052; it is `onset = MAX_DECISIONS − F`** (F = the feed-set's full size, ≈ 4,948 today), i.e. CAPI > 70,052, total ≈ 74,712 (~290 below the cap). The sawtooth's two phases cancel EXACTLY to this:
- high phase (post-import): `existing` = CAPI + 288 (today's fresh), `need` ≈ 4,660 → sum > 70,052 when CAPI > 65,104;
- low phase (pre-import, 24h-decisions decayed): `existing` = CAPI + 4,660, `need` 288 → sum > 70,052 when CAPI > 70,052.
Both → `CAPI > 70,052` onset. The mechanic is "SKIPPED ENTIRELY": once the budget is exhausted an already-present IP is skipped — no new, no refreshed, zero budget, not overwritten — which is why `0 refreshed IPs` appears across all 11 sources. Code commit this round: `dcbb32431`.

- **F1 (flap fix — real defect)**: `for: 30m` delays FIRING but NOT RESOLUTION, so the daily sawtooth crossing 63,750 produced ~1-2 spurious resolve/refire cycles over ~2.9 days before latching. Added `keep_firing_for: 48h` (≥ the sawtooth period) to `CrowdSecDecisionBudgetNearCap` — same idiom the file already uses (`CrowdSecBanActive` 5m, `CrowdSecAcquisitionStalled` 3h).
- **F2 (boundary unit tests — human ratified into this PR)**: appended 6 cases to the EXISTING `kubernetes/apps/crowdsec/crowdsec/tests/prometheusrule_test.yaml` (now 12 cases total). `63750` is a hand-computed 85% of `MAX_DECISIONS` that lives in a DIFFERENT file (`blocklist-import/app/helmrelease.yaml`) — nothing ties them together, so a future cap bump would silently desync the alert. GOTCHA verified before writing: the expr is `sum(...)` with NO `by()`, so every label aggregates away — `exp_labels` is ONLY `alertname: CrowdSecDecisionBudgetNearCap` + `severity: warning` (NO `job`/`namespace`). Tests passed FIRST TRY (the gotcha did not bite). 6 cases: (1) boundary NO-fire CAPI 63750×40 eval 31m → []; (2) boundary FIRE CAPI 63751×40 eval 31m → fires; (3) `for` not yet met CAPI 63751×40 eval 29m → []; (4) cross-origin sum CAPI 60000×40 + blocklist-import 4948×40 = 64948 eval 31m → fires; (5) negative current region CAPI 58000×40 + blocklist-import 4948×40 = 62948 eval 31m → []; (6) selector pin wrong job `crowdsec-agent-service` 70000×40 eval 31m → [].
- **F3 (progress-note corrections)**: see P1/P2/P3/P4 inline edits above (onset formulation, no-flap correction via `keep_firing_for`, attribution to HUMAN 59c4aa89a, memory re-measurement 39.56 MiB / ~1.0 KiB → 74.3 MiB @ 75k ≈ 58%).
- **F4 (Phase 5 precondition — hard gate, human ratified, in BOTH notes)**: ANY feed-set expansion REQUIRES recomputing this alert's threshold. Concrete: CI Army (+13,369 → F ≈ 18,000) moves onset to `CAPI > 57,000`, which is BELOW the alert's own sustained trigger level (`CAPI > 59,090` = 63,750 − 4,660) — the alert would fire only AFTER truncation had already begun. Recorded as a GATE on Phase 5 (roadmap + here), not a passing note.
- **F5a (metric artifact)**: the `blocklist-import` origin series only begins at 2026-08-04 22:24Z (LAPI pod restart), so the +5,053 jump in the 14d total is the origin label APPEARING, not real growth — the growth rate is read from the CAPI series only.
- **F5c (why 75k not 100k)**: the cap is a safety VALVE against the ballooning feed, not a target — raising it weakens the protection (at 100k a runaway feed could write ~60k junk decisions before being stopped). The hard constraint is the fail-closed bouncer's 128Mi: 75k ≈ 58%, 100k ≈ 78%, and the 07-30 transient (51 MiB at ~15k, ~3.4× linear) means there is NO reliable refresh-spike model. 75k gives ~23 days to onset + ~7 days alert lead (actual 7.2d at 1,520/day CAPI); 100k would force raising the bouncer to 256Mi first = a restart = a fail-closed denial window with control off.

- **F6 (reduce Alerts-view noise — human ratified, code commit 13e677ffa)**: set `BATCH_SIZE` 500 → 5000 at `blocklist-import/app/helmrelease.yaml:80`, with a 1-line comment ("Alert-record granularity (decisions per POST /v1/alerts), not throughput."). CrowdSec models an Alert as a container carrying decisions; with `CONSOLIDATE_ALERTS: "true"` (L81) the importer's per-source flush is bypassed (defer) and the run's deferred IPs are chunked by `batch_size` at end-of-run — one POST `/v1/alerts` per chunk (`add_decisions` → `json=[alert]`, one alert per POST). At 500 a full-refresh run (~4,900 net-new) yielded ~10 alert records; at 5000 it produces ONE. Low-phase runs (~288 net-new) already produced 1 record at BATCH_SIZE=500 — the "~11 per run" figure was actually 10 (full-refresh) + 1 (low-phase) across TWO runs, not one run. Verified against upstream: (a) importer `blocklist_import.py` @ v3.7.1 — `batch_size=int(os.getenv("BATCH_SIZE","1000"))`, bare `int()` cast, NO clamp/validation, controls only the `/v1/alerts` chunk (both per-source and consolidated paths), not dual-purpose; (b) receiving LAPI `crowdsecurity/crowdsec` @ v1.7.8 — `POST /v1/alerts` (`CreateAlert`, `gctx.ShouldBindJSON`) is under `jwtAuth` with `AuthenticatedBodyLimit = 50 MiB` (`http.MaxBytesReader`, `pkg/apiserver/middlewares/v1/body_limit.go`; wired at `pkg/apiserver/controllers/controller.go:114-125`); the importer authenticates as a machine (JWT via `BLOCKLIST_IMPORT_MACHINE_PASSWORD`), so the 50 MiB limit applies. A 5000-decision POST is 387 + 5000×155.2 = 776,538 B = 0.74 MiB = 1.48% of the 50 MiB limit (67.5× headroom; the 413 crossover is at ~338,000 decisions). The 50 MiB `AuthenticatedBodyLimit` is HARDCODED (not configurable) and applies to the DECOMPRESSED body — NO 413 risk. No proxy hop (single `crowdsec-lapi` Go container, direct `crowdsec-service:8080` ClusterIP; no HTTPRoute/ingress to the LAPI — only `crowdsec-web-ui` has one). Measured evidence (per-creation-minute — TWO runs, not one): 10 records @ 2026-08-04T21:58Z (initial import, 4,660 net-new → 4660/500=10) + 1 record @ 2026-08-05T02:00Z (scheduled run, 288 net-new → 1) = 11 total in `cscli alerts list --limit 200`, all scenario `external/blocklist (all sources)`. CAPI creates no alert records, so those dominated the Alerts view and buried local scenario bans. This invalidates the naive acceptance test "next run produces 1 record instead of 11" — it passes trivially on a low-phase run (288 net-new already yielded 1 at the OLD BATCH_SIZE=500). The real gate: the run must import MORE than 500 IPs for the single-record result to prove anything. Retention framing: the LAPI's own alert flush config is max_items 5000 / max_age 7d, so at ~10 records/full-refresh run that was ~77 records/7 days ≈ 1.5% of the limit — storage was NEVER at risk, so F6 is purely UI signal-to-noise. **Tradeoff**: one alert record per run instead of 11, at the cost of a larger single POST — if that one call fails the whole run's batch is lost rather than 1/11 of it; `backoffLimit: 3` retries the Job, so the exposure is bounded. **This is a UI-ergonomics change, NOT a correctness fix — the 11-records behaviour was correct.** **Cap interaction**: at `MAX_DECISIONS 75000` the worst case is 75000/5000 = 15 batches, nothing degenerates. Gates: pre-commit clean, `kustomize build blocklist-import/app` exit 0, render proves `BATCH_SIZE: "5000"`. NOTE: commit `13e677ffa` was human-committed with the terse message `hr` (content is exactly the F6 edit; non-conventional message flagged to the control lane — left as-is, no amend/force-push without approval); a `.gitignore` commit `0703548e0` also landed on the branch as the human's own unrelated change.

## Follow-ups (out of scope, logged — do NOT implement in this PR)
- Phase 4: the 3-week observation window (decision volume, feed health, alert noise) — separate change.
- Phase 5: Tier B/C feeds (evidence-gated) — separate change.

**Silent-degradation theme** — the import plane can degrade to near-zero protection while every health signal stays green: feed-rot invisible to the job exit code (`_run_once` returns 0 if ≥1 source succeeds; the Monty C2 dead-feed proved it live), bouncer-key 403 swallowed by `health_check()`/`get_existing_ips()` (skips dedup, widens `max_new` to the full cap), the FQDN allowlist blind to accidental Tier B/C enablement of hosts already allowed for Tier A (`raw.githubusercontent.com`), frozen-mirror feed decay (Cybercrime Tracker), unverified job-pod resources (`METRICS_ENABLED=false`), and the unpaginated `get_existing_ips` fetch. Tracked in [[crowdsec-import-silent-degradation]] — the detail lives there, not here.

**keep_firing_for latch test gap** — removing `keep_firing_for` from `CrowdSecBanActive` (5m) or `CrowdSecAcquisitionStalled` (3h) would likely leave the suite green, since no case evaluates past the latch window. Tracked in [[prometheusrule-unit-test-coverage]] as a scoped refinement of those two alerts' work-list rows (the `CrowdSecDecisionBudgetNearCap` 7th-case mutation pattern is the template).

**Doc-cleanup items (note-level, kept here):**

- Roadmap note FQDN-list inaccuracies to correct later: `sentinel.tdmdn.com` is a typo (real host is `view.sentinel.turris.cz`), redundant `github.com`/`api.github.com`/`gist`/`crowdsecurity.github.io` entries, and the abuseipdb feeds actually use `raw.githubusercontent.com` + `api.abuseipdb.com`. Not blocking; flagged for a roadmap-note cleanup.
- **N6**: UID 999 is build-time-derived from `useradd -r`; safe while digest-pinned, but must be re-verified on any Renovate digest bump.
- **D4 — stale comment on main (pre-existing, own issue)**: `kubernetes/apps/crowdsec/crowdsec/app/externalsecret.yaml:17-18` claims the extra machine comes from `AGENT_USERNAME`/`AGENT_PASSWORD`, but the crowdsec chart 0.24.0 `docker-start-custom.sh` has zero `AGENT_USERNAME`/`AGENT_PASSWORD` references — the extra machine is registered by the LAPI postStart hook, not the entrypoint. Out of scope; own issue.
- **Final fix round — Tier table Firehol gate follow-up**: the roadmap's Tier table rows still name `ENABLE_FIREHOL_LEVEL1/2/3` as the gates for Firehol L1/L2/L3, which do not exist in pinned v3.7.1 (single `ENABLE_FIREHOL` master gate; see premise-drift R5 above). The prose nearby states the v3.7.1 reality correctly, so it is internally explained, but a reader could set a key that silently does nothing. Same bucket as the FQDN inaccuracies above; logged only.
## Roadmap closure (2026-08-05)

The crowdsec-blocklist-import roadmap item is CLOSED. Implementation, deploy and live-verification are complete; the roadmap note `docs/roadmap/crowdsec-blocklist-import` was merged into this progress note and deleted on closure (repo closure pattern, cf. commit 9875fc28d).

**Merged PRs (all on main):**
- PR #4119 — Phase 1-3 manifests (CronJob, ExternalSecret, CNP, alerting regex), squash-merged; live-verified (first real run imported 4660 IPs, 11/11 sources successful, 0 dropped egress, 0 telemetry flow).
- PR #4120 — cap raised 50k → 75k + `CrowdSecDecisionBudgetNearCap` predictive alert + `keep_firing_for: 48h` flap fix + 6 boundary unit tests; merge commit a98bbf706.
- PR #4129 — blocklist-import freshness alerting (the [[crowdsec-import-silent-degradation]] workstream); merge 2ea1daaa1.

**Carried forward (NOT blockers — logged in Follow-ups):**
- Phase 4 — 3-week observation window (opens 2026-08-05, review ~2026-08-26): decision volume by origin, feed health, alert noise, hit-attribution via VictoriaLogs (the bouncer exposes no per-origin block counter). Criteria are in the "Execution plan → Phase 4" section below.
- Phase 5 — conditional Tier B promotion, evidence-gated by Phase 4; HARD PRECONDITION on recomputing the `CrowdSecDecisionBudgetNearCap` threshold (see "Execution plan → Phase 5").

The design rationale below is the archived roadmap body (its internal status fields are historical). It is preserved here so the Phase 4 cross-references in this note ("reference them there, do not re-derive here") still resolve after the roadmap note's deletion.

## Roadmap design rationale (merged from docs/roadmap on closure, 2026-08-05)


## Context

The purpose of this roadmap item is defensive coverage: drop automated attack traffic from known-bad source IPs at `envoy-external`, before the request reaches an application or the SSO/OIDC gate. The cluster today enforces the CAPI community blocklist (~20k IPs) and local scenario-based bans via the Envoy CrowdSec bouncer; CAPI is a baseline, and the external feeds widen it with independently curated intelligence on C2 infrastructure, brute-force sources, hijacked netblocks and compromised hosts. The `crowdsec-blocklist-import` tool automates the ingestion of such feeds directly into the LAPI via a batch process, with built-in deduplication to avoid overloading the single-node SQLite backend.

**Scope boundary.** In scope: the blocklist import plane only — a CronJob that fetches curated
feeds and writes decisions into the existing LAPI, plus its secret delivery, egress policy and
observability. Out of scope, because they are already owned by the deployed CrowdSec/bouncer
implementation ([[envoy-crowdsec-bouncer]]): how the gateway resolves the client IP, the extAuth
wiring, CAPI configuration, and the local scenario/AppSec planes. This item consumes whatever
client IP the bouncer already evaluates; it neither changes nor depends on how that value is
derived.

**Exposure regime and marginal value.** The cluster sits behind Cloudflare Tunnel today, whose edge
filtering absorbs a lot, so extra feeds buy less than on a directly-exposed host. Cloudflare is a
current deployment detail, not a design premise: under direct exposure there is no edge filter, no
managed WAF and no bot/threat scoring in front of the cluster, and the blocklist plane becomes a
primary control rather than a supplement. The design must hold in both regimes without rework.
Consequently "the feed only buys a little because Cloudflare already filters" is not a valid reason
to disable a feed — only false-positive risk, genuine irrelevance to this cluster's services, or
redundancy with CAPI/another enabled feed is.

## Security value

**What it buys** — pre-authentication blocking at the cluster edge (`envoy-external`), with no
per-app work, against attack classes that are identifiable by source IP:

- known C2 and malware-hosting infrastructure — Abuse.ch (Feodo + URLhaus), Cybercrime Tracker,
  Monty Security C2, VX Vault, Botvrij, Binary Defense
- mass credential-stuffing and SSH/RDP brute-force sources — Bruteforce Blocker, DShield
- hijacked / permanently criminal-controlled netblocks — Spamhaus DROP
- hosts already compromised and used for automated attack traffic — Emerging Threats

These are the Tier A feeds (see list selection): every entry asserts *confirmed* malicious
infrastructure. Reputation aggregates (Blocklist.de, IPsum, CI Army, GreenSnow, AbuseIPDB, Firehol)
would add volume in the same attack classes but not verification, so they stay evidence-gated in
Tier B — the defensive claim above is deliberately limited to what Tier A actually supports.

The block happens *in front of* the SSO/OIDC gate, so it also shields surfaces the gate does not
cover (unauthenticated endpoints, health/callback paths, any route exposed without the OIDC
SecurityPolicy). It is defence-in-depth ahead of that gate, never a replacement for it.

**What it does NOT protect against** — stated plainly so the plane is not over-trusted:

- targeted attacks from clean or rapidly rotating IPs; residential-proxy and cloud-rented IPs
- application-layer vulnerabilities (that is AppSec/WAF territory, and patching)
- credential compromise, session/token theft, or abuse by an authenticated user
- insider or LAN-origin abuse — LAN is whitelisted by design (`crowdsecurity/whitelists`)
- anything arriving over a path that does not traverse `envoy-external` (internal gateway,
  NodePort/hostPort, direct pod access, non-HTTP protocols)

**Posture in both exposure regimes** — today: Cloudflare edge filtering + CAPI + local scenarios +
this plane. After a possible move to direct exposure: this plane + CAPI + local scenarios **only**,
with no edge filter, no managed WAF and no bot/threat scoring in front of the cluster. That is the
argument for adopting now rather than later: the control is in place, sized and measured *before*
the exposure change removes the edge, instead of being stood up under pressure afterwards.

**False positives are a security-adjacent availability failure** (self-lockout of legitimate users
is an outage, and an outage is a security event). That is why Tor exit nodes and scanner feeds stay
disabled, and why the 24h decision TTL, the `ALLOWLIST`, and the existing `crowdsecurity/whitelists`
parser are treated as required compensating controls, not optional extras.

## Assessment — integration shape

A Kubernetes `CronJob` is the correct integration shape for this tool in this cluster.

- **CronJob (Recommended)**: The tool is designed to run once and exit (`INTERVAL=0` default). A CronJob aligns perfectly with this execution model and the repo's GitOps workflow. It allows external scheduling, prevents resource consumption during idle periods, and integrates cleanly with Flux CD.
- **Long-running Deployment (Rejected)**: While the tool supports a daemon mode (`INTERVAL=3600`), keeping a Python process running constantly just to wake up hourly is wasteful on a single-node cluster. A CronJob achieves the same result with lower resource overhead.
- **CrowdSec-native mechanisms (Partly redundant)**: CAPI is already enabled and provides ~20k IPs. This tool supplements CAPI with specialized lists that are not natively included in the free CAPI tier.
- **Do nothing (Live option)**: No third-party threat-intel plane at all — the cluster relies on CAPI, local scenario detections and, for as long as it lasts, Cloudflare edge filtering. Security cost: after a move to direct exposure the cluster would face the internet with CAPI + local scenarios alone, and the coverage gap would have to be closed reactively. For a home cluster the baseline may still be judged sufficient; that is the human's call (decision 1).

## Assessment — list selection

Feeds are classified by **precision** — what a listing actually asserts about an IP — not by size.
Volume is not a defensive benefit: an IP that never sends a request to this cluster is a row in
SQLite, not a blocked attack. Every low-precision entry, by contrast, carries a real chance of
locking out a legitimate user of *these* services (CGNAT, mobile carriers, shared hosting, VPN
exits).

| List | Env flag | Approx size | Precision (what a listing asserts) | Tier | FP risk |
|------|----------|-------------|------------------------------------|------|---------|
| Spamhaus DROP | `ENABLE_SPAMHAUS` | 1.5k | netblock is hijacked / wholly criminal-controlled | **A** | Low |
| Abuse.ch (Feodo + URLhaus) | `ENABLE_ABUSE_CH` | ~1.3k IP | verified malware C2 / malware-hosting host — URLhaus is a URL feed, only ~8% IP-literal (1284/15985); the 8642 domain hosts are the run's benign "8747 parsing errors", not lost IPs | **A** | Low |
| Emerging Threats | `ENABLE_EMERGING_THREATS` | 0.5k | host observed compromised and used for attacks | **A** | Low |
| Binary Defense | `ENABLE_BINARY_DEFENSE` | 1.3k | malware / botnet infrastructure, vetted | **A** | Low |
| DShield (ISC top attackers) | `ENABLE_DSHIELD` | 40 + 14 | DShield (40) + DShield Top (14); top attack sources by volume across ISC sensors | **A** | Very low |
| Bruteforce Blocker | `ENABLE_BRUTEFORCE_BLOCKER` | 0.5k | host observed performing SSH/RDP brute force; 97.5% redundant with Emerging Threats specifically (546 of 554 shared; 14 net-new of 560; at most one of ET/BFB may be pruned) | **A** | Low |
| Cybercrime Tracker | `ENABLE_CYBERCRIME_TRACKER` | small | tracked C2 panel / fraud infrastructure | **A** | Low |
| Monty Security C2 | `ENABLE_MONTY_SECURITY_C2` | DEAD | upstream removed `data/all.txt` (404); feed disabled — `ENABLE_MONTY_SECURITY_C2="false"` | **A** | Low |
| VX Vault | `ENABLE_VXVAULT` | small | malware distribution host | **A** | Low |
| Botvrij | `ENABLE_BOTVRIJ` | 4 | verified botnet C2; 182 days stale (Last-Modified 2026-02-03) — only clean prune candidate | **A** | Very low |
| Firehol Level 1 | `ENABLE_FIREHOL_LEVEL1` | 4.5k | composite of high-confidence feeds (largely the same sources as Tier A) | **B** | Low |
| IPsum | `ENABLE_IPSUM` | 19k | appeared on ≥3 other blocklists — reputation, not verification | **B** | Moderate |
| Blocklist.de (+ SSH/Apache/mail sub-lists) | `ENABLE_BLOCKLIST_DE` | 27k (+31k) | someone reported abuse from this IP | **B** | Moderate–High |
| CI Army | `ENABLE_CI_ARMY` | 15k | "poor reputation" score, vague criterion | **B** | Moderate |
| GreenSnow | `ENABLE_GREENSNOW` | 4.3k | attack attempts seen by GreenSnow sensors, limited vetting | **B** | Moderate |
| AbuseIPDB (public mirror) | `ENABLE_ABUSE_IPDB` | unknown | user-submitted reports, mirror quality unverified | **B** | Moderate |
| Sentinel (Turris) | `ENABLE_SENTINEL` | 10,367 | Turris sensor greylist (observation, not confirmation); 2 Tor exits | **B** | Moderate |
| Firehol Level 2 | `ENABLE_FIREHOL_LEVEL2` | 19k | aggregate of aggregates | **C** | Moderate |
| Firehol Level 3 | `ENABLE_FIREHOL_LEVEL3` | >30k | most aggressive aggregation level | **C** | High |
| Firehol (meta flag) | `ENABLE_FIREHOL` | — | v3.7.1 single master gate; on → forces L1+L2+L3 (25,878 net-new incl. Tier C); leave off | **C** | — |
| Tor exit nodes | `ENABLE_TOR` | 1.3k + 2.4k | this IP is a Tor exit — not a malice signal | **C** | High (privacy-using legitimate visitors) |
| Scanners (Shodan/Censys) | `ENABLE_SCANNERS` | 47 | known internet-measurement infrastructure | **C** | Moderate (blocks legitimate research; rotating IPs make it futile) |
| StopForumSpam | `ENABLE_STOPFORUMSPAM` | 53 | forum-spam submitter | **C** | Low (irrelevant: no public forum) |

**Tier meanings.** **A** = confirmed malicious infrastructure, adopt now — ~5.2k decisions covering ~15M IPv4 addresses (1689/5200 entries are CIDR netblocks; Spamhaus DROP alone is 1664 netblocks, measured 14,971,063 addresses).
**B** = reputation aggregate; adopt only on evidence from the observation window (below).
**C** = never for this cluster, for the reason stated in the row.

**Primary recommendation — Tier A only.** Complete env-var block:

```yaml
ENABLE_SPAMHAUS: "true"
ENABLE_ABUSE_CH: "true"
ENABLE_EMERGING_THREATS: "true"
ENABLE_BINARY_DEFENSE: "true"
ENABLE_DSHIELD: "true"
ENABLE_BRUTEFORCE_BLOCKER: "true"
ENABLE_CYBERCRIME_TRACKER: "true"
ENABLE_MONTY_SECURITY_C2: "false"
ENABLE_VXVAULT: "true"
ENABLE_BOTVRIJ: "true"
# v3.7.1 exposes a single ENABLE_FIREHOL master, not per-level keys.
ENABLE_FIREHOL: "false"
ENABLE_IPSUM: "false"
ENABLE_BLOCKLIST_DE: "false"
ENABLE_CI_ARMY: "false"
ENABLE_GREENSNOW: "false"
ENABLE_ABUSE_IPDB: "false"
ENABLE_SENTINEL: "false"
ENABLE_TOR: "false"
ENABLE_SCANNERS: "false"
ENABLE_STOPFORUMSPAM: "false"
DECISION_DURATION: "24h"
DECISION_ORIGIN: "blocklist-import"
MAX_DECISIONS: "75000"
BATCH_SIZE: "5000"
CONSOLIDATE_ALERTS: "true"
ALLOWLIST: "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
TELEMETRY_ENABLED: "false"
METRICS_ENABLED: "false"
LOG_LEVEL: "DEBUG"
```

`MAX_DECISIONS: 75000` is a TOTAL cap across all origins (CAPI included), not per-run — `max_new = max(0, MAX_DECISIONS - len(existing))` where `existing` is the full `GET /v1/decisions` result. On budget exhaustion the importer logs "skipping remaining sources" and exits 0, so `KubeJobFailed` never fires and the tail feeds (Cybercrime Tracker, VXVault) drop silently; raised from 50000 to 75000 after CAPI grew to ~34.4k (measured ~1.5k/day). Tier A ~5.2k plus ample headroom remains against a ballooning feed. `METRICS_ENABLED: "false"` because the cluster runs no Prometheus
Pushgateway — LAPI-side metrics are the observability path. `ALLOWLIST` complements, and does not
replace, the existing `crowdsecurity/whitelists` parser.

**Promotion path to Tier B.** Tier B is enabled per feed, one at a time, only when the observation
window (Phase 4) shows Tier A + CAPI leaving a real gap — i.e. attack traffic reaching the services
from IPs that a specific Tier B feed lists. Enable one feed, keep the same window length, and check
both directions: did anything new get blocked, and did any legitimate user get locked out. Note that
v3.7.1 exposes a single `ENABLE_FIREHOL` master gate (no per-level keys), so Firehol L1 cannot be
enabled alone — the gate forces L1+L2+L3 (25,878 net-new incl. Tier C), making the L1-only promotion
path UNIMPLEMENTABLE as a Tier B feed in this version. L1 also largely re-derives the Tier A
sources, so it is the *least* likely Tier B feed to add coverage regardless.

Per the repo's priority order (Security > Clarity > Performance), resource headroom must never be
the reason a defensive feed is dropped — only false-positive risk or genuine irrelevance may
disable one. Equally, "we may raise memory" is permission, not an obligation to import volume.

## Sizing

The memory number is a **consequence** of the list decision, not an independent choice.

- Measured (2026-08-05): bouncer `envoy-proxy-bouncer` working set 36Mi at 39,393 cached decisions
  (CAPI 34,445 + blocklist-import 4,948; CAPI grew ~20k → ~34.4k at ~1.5k/day), request 64Mi,
  limit 128Mi (`kubernetes/apps/crowdsec/bouncer/app/helmrelease.yaml:62-67`).
- Steady state is ~0.93 KiB/decision; the 07-30 peak of 49.5Mi (CAPI ~15k) shows non-linear
  transient refresh spikes that exceed steady state, so the earlier ~1.6 KiB/decision single-point
  figure (from 32Mi @ ~20k CAPI) is an **extrapolation**, not a measurement of scaling — the
  2-point steady-state range is ~0.9-1.6 KiB/decision.
- Tier A (~5.2k decisions — covering ~15M IPv4 addresses; the bouncer cache and SQLite LAPI pay per **decision**, never per address) on top of CAPI (~34.4k, growing ~1.5k/day) ≈ ~40k decisions → ~36Mi measured; at the 75k cap
  linear extrapolation ≈ ~70Mi, ~1.8x headroom inside the **existing** 128Mi limit.

**Recommendation now: change nothing.** Keep `requests.memory: 64Mi` / `limits.memory: 128Mi`. A
raise is not free: the bouncer is fail-closed (`failOpen: false`), so restarting it to apply a new
limit denies traffic on `envoy-external` for the duration of the rollout. Speculative headroom buys
nothing and costs a remediation gap.

**Only if Tier B is later promoted** (worst case ~90k additional decisions → ~145Mi by the same
conservative estimate) raise to `requests.memory: 192Mi` / `limits.memory: 384Mi`, in the same
change that enables the feed, so the restart is paid once. If instead the node ever gets tight (it
is not today: 64GiB, 14% requested, 20% used), revisit the request rather than the limit.

Watch the LAPI side independently: `cs_active_decisions{job="crowdsec-service", namespace="crowdsec"}`
for total decision growth, plus LAPI CPU/memory (43Mi / 256Mi request / 768Mi limit today) and the
latency of the bouncer's decision stream. SQLite + WAL handles tens of thousands of rows without
trouble; a Postgres LAPI is a follow-up only if measurements demand it, and is out of scope here.

## Design

- **File paths**:
  - `kubernetes/apps/crowdsec/blocklist-import/ks.yaml`
  - `kubernetes/apps/crowdsec/blocklist-import/app/kustomization.yaml`
  - `kubernetes/apps/crowdsec/blocklist-import/app/helmrelease.yaml`
  - `kubernetes/apps/crowdsec/blocklist-import/app/externalsecret.yaml`
  - `kubernetes/apps/crowdsec/blocklist-import/app/ciliumnetworkpolicy.yaml`
- **CronJob spec**: Deployed via `bjw-s/app-template` (repo idiom). Schedule: `0 4 * * *` (daily). `concurrencyPolicy: Forbid`, `restartPolicy: OnFailure`, `backoffLimit: 3`. CronJob pod resources: requests `cpu: 50m`, `memory: 64Mi`; limits `memory: 256Mi` (the importer's own working set — unrelated to the bouncer's cache sizing).
- **Secret flow**: The tool requires a bouncer key (read) and machine credentials (write). These will be generated manually via `cscli` and stored in the existing 1Password `crowdsec` item. An `ExternalSecret` will sync them to a Kubernetes Secret named `blocklist-import-secret`. The HelmRelease will mount these via `envFrom`.
- **Egress network policy**: A CiliumNetworkPolicy must allow egress from the CronJob pod to:
  - `http://crowdsec-service.crowdsec.svc.cluster.local:8080` (LAPI)
  - External blocklist FQDNs for the BROAD selection:
    - `feodotracker.abuse.ch`
    - `urlhaus.abuse.ch`
    - `rules.emergingthreats.net`
    - `www.binarydefense.com`
    - `feeds.dshield.org`
    - `www.dshield.org`
    - `danger.rulez.sk`
    - `www.spamhaus.org`
    - `www.botvrij.eu`
    - `github.com`
    - `api.github.com`
    - `raw.githubusercontent.com`
    - `gist.githubusercontent.com`
    - `crowdsecurity.github.io`
    - `lists.abuseipdb.com`
    - `api.abuseipdb.com`
    - `sentinel.tdmdn.com`
  - `bouncer-telemetry.ms2738.workers.dev` must NOT be allowed (`TELEMETRY_ENABLED=false` in addition, defence in depth).
- **Observability**: CronJob failure is covered by the built-in `KubeJobFailed` alert (kube-prometheus-stack, `kubernetesApps: true`), so no per-app `PrometheusRule` ships — a deliberate, human-ratified deviation (a second `kube_job_status_failed > 0` rule would be pure duplication, and never self-resolves because `failedJobsHistory: 3` keeps the failed Job queryable). The only rule change is the `CrowdSecBanActive` origin-regex extension in `kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml` (exclude `blocklist-import`), so the high-volume expected decisions do not page.
- **Pod security**: Image provenance pinned to `ghcr.io/wolffcatskyy/crowdsec-blocklist-import:3.7.1@sha256:78ec83464827a129128e2e1cba0bc23562988bec177745334a9f2896c817860c` (OCI image index, multi-arch). The Dockerfile creates a non-root system user (`blocklist`) without a fixed UID. The pod security context will set `runAsNonRoot: true` and `readOnlyRootFilesystem: true`. `capabilities: {drop: ["ALL"]}`.
- **Renovate**: The image will be tracked via `renovate: datasource=docker depName=ghcr.io/wolffcatskyy/crowdsec-blocklist-import` annotation.
- **Allowlist**: The `ALLOWLIST` env var complements (does not replace) the existing `crowdsecurity/whitelists` parser which already whitelists LAN traffic.

## Execution plan (research-backed)

### Phase 1 — credentials and registration
- Generate a bouncer API key and machine credentials, store them in the existing 1Password
  `crowdsec` item as `BLOCKLIST_IMPORT_BOUNCER_KEY` and `BLOCKLIST_IMPORT_MACHINE_PASSWORD`.
- Wire `BOUNCER_KEY_blocklist_import` into the LAPI HelmRelease env (auto-registration) and the
  machine registration into the existing postStart hook; add the fields to the crowdsec
  `ExternalSecret`.
- **Acceptance**: `kubectl -n crowdsec get externalsecret` reports `SecretSynced`;
  `kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli bouncers list` and `cscli machines list`
  both show the registration, with a deliberate naming split: `cscli bouncers list` shows
  `blocklist_import` (UNDERSCORE — the LAPI `docker_start.sh` derives bouncer names via
  `cut -d_ -f3-` and bash `compgen -A variable` cannot see hyphenated env-var names), while
  `cscli machines list` shows `blocklist-import` (HYPHEN — registered by the postStart hook).
  Seeing `blocklist-import` in `cscli bouncers list` would be a failure.

### Phase 2 — CronJob with Tier A, dry run first
- Add `kubernetes/apps/crowdsec/blocklist-import/{ks.yaml,app/*}` (app-template, cronjob
  controller), image pinned by digest, Tier A env block, `DRY_RUN: "true"` on the first roll-out.
- **Acceptance**: `kubectl -n crowdsec create job --from=cronjob/blocklist-import bli-dryrun` →
  `kubectl -n crowdsec logs job/bli-dryrun` shows every Tier A feed fetched, a deduplicated count,
  and no write attempt; `cscli decisions list --origin blocklist-import` still empty.
- **Auth gate (does NOT depend on dry-run)**: the `DRY_RUN: "false"` run below is the
  credential gate — a 401 at `/v1/watchers/login` (machine JWT) or `/v1/decisions` (bouncer key)
  fails the Job loudly, catching an empty or templated-out machine password or bouncer key. Under
  `DRY_RUN=true` upstream skips the auth check, `can_write()`, the health check and the
  existing-decisions fetch, so a green dry-run is NOT sufficient evidence and its dedup count is
  vacuous against an empty existing-decisions set.
- Then flip `DRY_RUN: "false"`, re-run manually, and confirm
  `cscli decisions list --origin blocklist-import | wc -l` is in the expected ~10–20k range and
  `MAX_DECISIONS` was not hit.

### Phase 3 — network policy and observability
- `CiliumNetworkPolicy`: egress to the LAPI service on 8080 plus **only** the Tier A feed FQDNs;
  `bouncer-telemetry.ms2738.workers.dev` explicitly not allowed. Add the LAPI-side ingress entry
  for the new pod. Extend `CrowdSecBanActive` in
  `kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml:50` to exclude the
  `blocklist-import` origin.
- **Acceptance**: `just k8s hubble-live-capture 120` during a manual run, then
  `just k8s hubble-analyze k8s:app.kubernetes.io/name=blocklist-import DROPPED egress` shows no
  unexpected drops and no flow to the telemetry FQDN; `flux get ks -A` reconciled;
  the `CrowdSecBanActive` rule shows the extended `origin` regex (excluding `blocklist-import`) in Prometheus and is not firing; a failing blocklist-import Job surfaces via the built-in `KubeJobFailed` alert (no per-app rule ships).

### Phase 4 — observation window (3 weeks) and review gate
- Measure at the end of the window:
  - decision volume by origin: `sum by (origin) (cs_active_decisions{job="crowdsec-service", namespace="crowdsec"})`
    — verified to exist (`prometheusrule.yaml:50` already uses this metric).
  - bouncer cache size: `bouncer_decision_cache_size` by origin — verified in use
    (`docs/progress/envoy-crowdsec-bouncer`).
  - **hits** (requests actually blocked, by origin): RESOLVED (2026-08-05) — the bouncer does NOT
    expose a per-origin block counter. Verified against live `/metrics` (pod proxy): 15 metric
    families; `bouncer_requests_total{action="..."}` is labelled by `action` ONLY (no `origin`);
    `bouncer_decision_cache_size{origin=...}` exists (CAPI 34,445 / blocklist-import 4,948) but
    counts CACHE, not hits. The VictoriaLogs fallback is therefore MANDATORY: count
    bouncer-denied requests in VictoriaLogs (bouncer + Envoy access logs, 403s attributed to
    extAuth) and correlate the source IPs against `cscli decisions list --origin blocklist-import -o json`.
- Decision rule: prune any Tier A feed with zero correlated hits **and** no unique coverage; do not
  promote a Tier B feed unless the logs show attack traffic that Tier A + CAPI missed and that feed
  lists. Record the numbers in the progress note — a null result is a valid, publishable outcome.

### Phase 5 — conditional Tier B promotion (only if Phase 4 justifies it)
- **HARD PRECONDITION — recompute the truncation alert threshold (from the Cap+alert round, Draft PR #4120)**: ANY feed-set expansion REQUIRES recomputing `CrowdSecDecisionBudgetNearCap`'s `> 63750` threshold FIRST. Truncation onset is `MAX_DECISIONS − F` (F = the feed-set's full size), NOT the total cap, so adding a feed grows F and lowers the onset. Concrete: CI Army (+13,369 → F ≈ 18,000) moves onset to `CAPI > 57,000`, which is BELOW the alert's own sustained trigger level (`CAPI > 59,090` = 63,750 − 4,660) — the alert would fire only AFTER truncation had already begun. Before enabling any new feed: recompute `threshold = 0.85 × MAX_DECISIONS` and verify `threshold − F_low > sustained_trigger_margin` (the low-phase `need` ≈ fresh-per-run). This is a GATE on Phase 5, not a note.
- Enable one Tier B feed, together with the memory raise from the Sizing section and the matching
  `MAX_DECISIONS` bump and CNP FQDN additions, in a single change so the bouncer restarts once.
- **Acceptance**: after the restart, `kubectl -n crowdsec get pod -l app.kubernetes.io/name=crowdsec-bouncer -o jsonpath='{.items[*].status.containerStatuses[*].lastState.terminated.reason}'`
  shows no `OOMKilled`; `kubectl top pod -n crowdsec` stays below the new limit after a full import;
  a smoke request through `envoy-external` still succeeds; repeat the Phase 4 measurement for the
  newly enabled feed.

## Risks and blast radius

- **False positives**: Blocking a legitimate IP could lock out a user. The `ALLOWLIST` includes private IP ranges to prevent self-bans. The 24h TTL ensures any false positives expire within a day.
- **Database bloat**: Every imported IP is a row in the SQLite LAPI and an entry in the bouncer's in-memory cache. Tier A (~5.2k) on top of CAPI (~34.4k, growing ~1.5k/day) is within today's limits (see Sizing); `MAX_DECISIONS: 75000` is a TOTAL cap across all origins (CAPI included), not per-run, so on budget exhaustion the importer exits 0 (silent truncation, `KubeJobFailed` never fires) rather than failing the run.
- **Egress policy complexity**: The CronJob requires egress to external FQDNs. If any FQDN changes, the job will fail to fetch that list, though it will continue with others. The CiliumNetworkPolicy must be maintained.
- **Telemetry**: The tool sends anonymous telemetry by default. This will be disabled (`TELEMETRY_ENABLED=false`) and the telemetry FQDN will be blocked by the CNP.
- **Dependency, not scope — client-IP resolution**: the value the bouncer matches decisions against is produced by the existing gateway/bouncer implementation. This plane inherits it and is only as accurate as that resolution. If the cluster ever leaves Cloudflare, revisiting client-IP handling belongs to [[envoy-crowdsec-bouncer]], and should be handled there before the exposure change; no work in this roadmap item depends on it.
- **Blast radius on already-deployed files**:
  - `kubernetes/apps/crowdsec/bouncer/app/helmrelease.yaml:62-67`: 64Mi request / 128Mi limit, single replica, fail-closed. Tier A needs no change here (see Sizing); a raise is only part of a later Tier B promotion, and because the bouncer is fail-closed the restart it requires is itself a brief denial window on `envoy-external`.
  - `kubernetes/apps/crowdsec/bouncer/app/helmrelease.yaml:40`: LAPI in-cluster URL is `http://crowdsec-service.crowdsec.svc.cluster.local:8080`.
  - `kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml:50`: The `cs_active_decisions{job="crowdsec-service", namespace="crowdsec"}` metric is already in use, and the existing `CrowdSecBanActive` expression filters `origin!~"CAPI|lists(:.*)?"`. The required change is extending that regex to also exclude `blocklist-import`.

## Decisions needed from human

1. **Adopt at all?** (a) Adopt with Tier A — recommended: pre-authentication blocking of confirmed
   malicious infrastructure, no outage risk, and the control is in place before a possible move to
   direct exposure removes Cloudflare's edge filtering. (b) Do nothing — CAPI + local scenarios +
   (for now) Cloudflare edge; accepts closing the gap reactively later.
2. **Scope of enablement.** (a) Tier A only now, Tier B strictly evidence-gated — **recommended**.
   (b) Tier A + Tier B immediately (~150k decisions): more rows, no demonstrated extra blocking,
   higher false-positive exposure for legitimate CGNAT/mobile/VPN users.
3. **Memory now or later.** (a) Change nothing now — 64Mi/128Mi covers CAPI + Tier A with ~2.3x
   headroom — **recommended**. (b) Raise to 192Mi/384Mi pre-emptively: costs a bouncer restart
   (a denial window on a fail-closed control) for headroom nothing currently needs.
4. **Observation window length.** (a) 2 weeks. (b) **3 weeks — recommended** (enough traffic to
   judge, short enough to act on). (c) 4 weeks.

## Open questions / evidence gaps

- RESOLVED (2026-08-05): Phase 4 hit attribution — the bouncer exposes NO per-origin block counter. Verified against live `/metrics` (pod proxy): 15 metric families; `bouncer_requests_total{action="..."}` is labelled by `action` ONLY (no `origin`); `bouncer_decision_cache_size{origin=...}` exists (CAPI 34,445 / blocklist-import 4,948) but counts CACHE, not hits. The VictoriaLogs fallback is therefore MANDATORY: count bouncer-denied requests and correlate source IPs against `cscli decisions list --origin blocklist-import -o json`.

- EVIDENCE GAP: The exact UID of the `blocklist` user in the Docker image. The Dockerfile uses `useradd -r` without a fixed UID. The security context will rely on `runAsNonRoot: true` without an explicit `runAsUser` unless the UID is verified.

## Related

- relates_to [[envoy-crowdsec-bouncer]] — the completed bouncer work that this roadmap item supplements
- relates_to [[networking]] — egress network policies and LAPI connectivity
- relates_to [[observability]] — PrometheusRules for job failure alerts and LAPI decision metrics
- relates_to [[external-secrets]] — 1Password Connect integration for bouncer and machine credentials
