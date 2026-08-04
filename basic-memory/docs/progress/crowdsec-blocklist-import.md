---
title: crowdsec-blocklist-import
type: progress-note
permalink: home-ops/docs/progress/crowdsec-blocklist-import
---

# crowdsec-blocklist-import — execution progress

## Metadata (observation-form)

- [topic] GitOps manifests for the crowdsec-blocklist-import CronJob (roadmap phases 1-3 only); DRY_RUN starts true
- [status] draft PR open, manifest-only — no live cluster change; awaiting human-created 1Password fields + merge
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

## Follow-ups (out of scope, logged — do NOT implement in this PR)

- Phase 4: the 3-week observation window (decision volume, feed health, alert noise) — separate change.
- Phase 5: Tier B/C feeds (evidence-gated) — separate change.
- Roadmap note FQDN-list inaccuracies to correct later: `sentinel.tdmdn.com` is a typo (real host is `view.sentinel.turris.cz`), redundant `github.com`/`api.github.com`/`gist`/`crowdsecurity.github.io` entries, and the abuseipdb feeds actually use `raw.githubusercontent.com` + `api.abuseipdb.com`. Not blocking; flagged for a roadmap-note cleanup.
- **N2 fail-open**: upstream `_run_once` returns 0 whenever at least ONE source succeeded, so 9 of 10 Tier A feeds being blocked still yields a successful Job and no alert. The delivered observability cannot detect a silently degraded import. Needs its own issue.
- **N5**: `raw.githubusercontent.com` also serves 4 disabled Tier B/C feeds, so at that host the Tier A restriction is enforced by env flags only, not by the network policy.
- **N6**: UID 999 is build-time-derived from `useradd -r`; safe while digest-pinned, but must be re-verified on any Renovate digest bump.

- **D4 — stale comment on main (pre-existing, own issue)**: `kubernetes/apps/crowdsec/crowdsec/app/externalsecret.yaml:17-18` claims the extra machine comes from `AGENT_USERNAME`/`AGENT_PASSWORD`, but the crowdsec chart 0.24.0 `docker-start-custom.sh` has zero `AGENT_USERNAME`/`AGENT_PASSWORD` references — the extra machine is registered by the LAPI postStart hook, not the entrypoint. Out of scope for this PR; own issue.
