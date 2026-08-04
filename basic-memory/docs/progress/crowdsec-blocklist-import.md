---
title: crowdsec-blocklist-import
type: progress-note
permalink: home-ops/docs/progress/crowdsec-blocklist-import
---

# crowdsec-blocklist-import — execution progress

## Metadata (observation-form)

- [topic] GitOps manifests for the crowdsec-blocklist-import CronJob (roadmap phases 1-3 only); DRY_RUN starts true
- [status] phases 1-3 delivered and live-verified (PR #4119 merged, Flux main@0a5f86df); Phase 4 observation window open 2026-08-05 → review ~2026-08-26
- [branch] feat/crowdsec-blocklist-import
- [area] crowdsec, flux-gitops, external-secrets, networking (Cilium), observability
- [created] 2026-08-04
- [implements] [[crowdsec-blocklist-import]] roadmap

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

## Follow-ups (out of scope, logged — do NOT implement in this PR)

- Phase 4: the 3-week observation window (decision volume, feed health, alert noise) — separate change.
- Phase 5: Tier B/C feeds (evidence-gated) — separate change.
- Roadmap note FQDN-list inaccuracies to correct later: `sentinel.tdmdn.com` is a typo (real host is `view.sentinel.turris.cz`), redundant `github.com`/`api.github.com`/`gist`/`crowdsecurity.github.io` entries, and the abuseipdb feeds actually use `raw.githubusercontent.com` + `api.abuseipdb.com`. Not blocking; flagged for a roadmap-note cleanup.
- **N2 fail-open**: upstream `_run_once` returns 0 whenever at least ONE source succeeded, so 9 of 10 Tier A feeds being blocked still yields a successful Job and no alert. The delivered observability cannot detect a silently degraded import. Needs its own issue.
- **N5**: `raw.githubusercontent.com` also serves 4 disabled Tier B/C feeds, so at that host the Tier A restriction is enforced by env flags only, not by the network policy.
- **N6**: UID 999 is build-time-derived from `useradd -r`; safe while digest-pinned, but must be re-verified on any Renovate digest bump.

- **D4 — stale comment on main (pre-existing, own issue)**: `kubernetes/apps/crowdsec/crowdsec/app/externalsecret.yaml:17-18` claims the extra machine comes from `AGENT_USERNAME`/`AGENT_PASSWORD`, but the crowdsec chart 0.24.0 `docker-start-custom.sh` has zero `AGENT_USERNAME`/`AGENT_PASSWORD` references — the extra machine is registered by the LAPI postStart hook, not the entrypoint. Out of scope for this PR; own issue.

- **Final-round (a) — get_existing_ips unpaginated**: the upstream `get_existing_ips` issues a single unpaginated `GET /v1/decisions` and `response.json()`s the whole body; with ~33.8k decisions (~6.8 MB JSON today) this is the rationale for the 512Mi limit. Does not scale — a paginated fetch is its own issue.
- **Final-round (b) — feed-rot structurally undetectable**: the Monty C2 dead-feed discovery this round (upstream `data/all.txt` 404) proves N2's mechanism in practice — a fully-dead feed is invisible to the job's exit code because `_run_once` returns 0 as long as ≥1 source succeeded. Monty was found by a manual upstream check, not by any job signal.
- **Final-round (c) — job pod resource usage UNVERIFIED**: the CronJob pod is scaled to 0 between runs and `METRICS_ENABLED=false`, so the 512Mi limit is a reasoned estimate (single unpaginated decision fetch), not a measured high-water mark. Verify on the first non-dry-run run.
- **Final-round (d)**: the previously logged N2/N5/N6 and D4 items above remain open (no change this round).

- **Closing (C4) — bouncer-key path fails silently**: upstream `health_check()` returns `response.status_code in (200, 403)` (True for 403 — "200 = OK, 403 = unauthorized but reachable") and `get_existing_ips()` logs an error on 403 and returns `[]`. So an invalid or revoked BOUNCER key does not fail the run — it silently skips dedup, and `max_new` widens to the full `MAX_DECISIONS` (50000). The write-path gate we validated (manual Job `bli-live-1`) covers only the MACHINE credential, not the bouncer key. Same "fails without a signal" family as N2 — needs its own issue. (Verified against `blocklist_import.py` main.)
