---
title: arr-search
type: note
permalink: home-ops/docs/progress/arr-search
---

# arr-search

## Goal

Add a Kubernetes CronJob (`arr-search`, namespace `downloads`) that triggers a **Missing**
search and a **Cutoff Unmet** search in **both** Sonarr and Radarr via their v3 REST APIs
(4 `POST /api/v3/command` calls total), mirroring `recyclarr/fix-radarr-language.sh`'s
per-step OK/ERROR logging and `set -euo pipefail` discipline.

**Cadence**: MONTHLY — once on the **first Saturday of the month at 01:03**
(Europe/Budapest TZ injected by the k8tz mutating webhook).

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Monthly first-Saturday, not weekly | Maestro mid-flight requirement change; standard 5-field cron cannot express "Nth weekday of month" (no hash/L modifier; `1-7 * 6` uses OR semantics and would fire far too often), so the schedule is `3 1 * * 6` (every Saturday 01:03) and a bash guard at the top of the script keeps only the first Saturday (day-of-month 1-7) |
| D2 | Image = `alpine/k8s:1.36.2` (already in repo, reused from pod-garbage-collector) | Maestro directive "choose an image already in our repo"; alpine/k8s bundles bash+curl+jq — proven by pod-gc's jq usage in its script |
| D3 | CNP admission scope = (a) — add arr-search to BOTH sonarr AND radarr CNP fromEndpoints in THIS PR | arr-search pods are dropped by the AD-023 per-consumer ingress CNPs (named allowlist: bazarr/prowlarr/seerr/recyclarr); no source-side fix exists. Maestro authorized scope expansion to the 2 CNP files (originally touch-only-arr-search-tree guard) |
| D4 | Reuse existing 1Password items (sonarr/radarr), no new secrets | ESO `onepassword-connect` ClusterSecretStore; `ExternalSecret` pulls `sonarr_api_key` from item `sonarr` and `radarr_api_key` from item `radarr` |
| D5 | Sonarr command names are SINGULAR; Radarr are PLURAL | Verified against Sonarr frontend `commandNames.js` + source-class derivation (see Evidence) |

## Verified API command names + citations

The v3 command endpoint is `POST /api/v3/command` with body `{"name":"<CommandName>"}` and
header `X-Api-Key`. The command name string is the C# class name with the trailing `Command`
suffix stripped (`Name = GetType().Name.Replace("Command","")`, `Command.cs:41`).

| Call | Command name string | Servarr source class path | Frontend constant |
|---|---|---|---|
| Sonarr Missing | `MissingEpisodeSearch` | `src/NzbDrone.Core/IndexerSearch/MissingEpisodeSearchCommand.cs` | `commandNames.js` MISSING_EPISODE_SEARCH |
| Sonarr Cutoff Unmet | `CutoffUnmetEpisodeSearch` | `src/NzbDrone.Core/IndexerSearch/CutoffUnmetEpisodeSearchCommand.cs` | `commandNames.js` CUTOFF_UNMET_EPISODE_SEARCH |
| Radarr Missing | `MissingMoviesSearch` | `src/NzbDrone.Core/IndexerSearch/MissingMoviesSearchCommand.cs` | Radarr `commandNames.js` |
| Radarr Cutoff Unmet | `CutoffUnmetMoviesSearch` | `src/NzbDrone.Core/IndexerSearch/CutoffUnmetMoviesSearchCommand.cs` | Radarr `commandNames.js` |

**Singular-vs-plural note**: the Maestro initially required plural Sonarr names
(`MissingEpisodesSearch`/`CutoffUnmetEpisodesSearch`) claiming the singular form HTTP-400s.
This was **refused** with evidence (Sonarr frontend + source derivation show singular), and
the Maestro later self-corrected: "you were right, I was wrong" — singular is correct for
Sonarr, plural only for Radarr's `Movies` names. This was verify-don't-trust working as
intended: the worker refused a wrong directive rather than complying.

## Files created / modified

### Created (arr-search tree, 5 files)
- `kubernetes/apps/downloads/arr-search/ks.yaml` — Flux Kustomization entry, targetNamespace downloads, dependsOn onepassword-connect (external-secrets ns), path ./kubernetes/apps/downloads/arr-search/app, postBuild.substitute APP: arr-search, interval 1h, prune true, timeout 5m, wait false
- `kubernetes/apps/downloads/arr-search/app/kustomization.yaml` — resources: externalsecret.yaml + helmrelease.yaml; configMapGenerator arr-search-config (arr-search.sh) with disableNameSuffixHash + `kustomize.toolkit.fluxcd.io/substitute: disabled` annotation (preserve shell `${VAR}`)
- `kubernetes/apps/downloads/arr-search/app/externalsecret.yaml` — ExternalSecret arr-search -> arr-search-secret, onepassword-connect, refreshInterval 12h, SONARR_API_KEY/RADARR_API_KEY
- `kubernetes/apps/downloads/arr-search/app/helmrelease.yaml` — bjw-s app-template, cronjob schedule `3 1 * * 6`, backoffLimit 0, concurrencyPolicy Forbid, failed/successfulJobsHistory 1; alpine/k8s 1.36.2 (digest-pinned, # renovate annotation); env from secretKeyRef; resources 5m/16Mi req, 64Mi mem limit; hardened pod (runAsNonRoot, UID/GID/fsGroup 10001, seccomp RuntimeDefault, readOnlyRootFilesystem, drop ALL caps, no priv escalation, automountServiceAccountToken false, enableServiceLinks false)
- `kubernetes/apps/downloads/arr-search/app/config/scripts/arr-search.sh` — the 4-call script with monthly-first-Saturday guard

### Modified (3 files)
- `kubernetes/apps/downloads/kustomization.yaml` — added `- ./arr-search/ks.yaml` (alphabetical, between recyclarr and bazarr)
- `kubernetes/apps/downloads/sonarr/app/ciliumnetworkpolicy.yaml` — added arr-search to fromEndpoints allowlist (alphabetical, before bazarr) + header comment consumer list
- `kubernetes/apps/downloads/radarr/app/ciliumnetworkpolicy.yaml` — same two edits

## Monthly first-Saturday guard

```bash
dom="$(date +%d)"; dom="${dom#0}"
if [ "$(date +%u)" != 6 ] || [ "$dom" -gt 7 ]; then
  echo "not first Saturday of month, skipping"
  exit 0
fi
```

Logic: `date +%u` = 6 means Saturday; day-of-month in 1-7 means first Saturday of the month.
Both must hold; otherwise skip with exit 0. Sanity-tested across (dow, dom) pairs — 1st
Saturday (dom 1/7) runs; 2nd+ Saturday (dom 8/14/31) skips; non-Saturday (Fri/Sun) skips.

## Egress / networking findings

- arr-search reaches sonarr/radarr in-cluster only (`sonarr.downloads.svc.cluster.local:8989`, `radarr.downloads.svc.cluster.local:7878`) — no internet egress needed.
- In-cluster egress is allowed by the default `allow-cluster-egress` CCNP for pods with the `custom-egress` label (bjw-s app-template sets this via the shared common component). No `allow-world-egress` opt-in label required.
- **Blocker found + resolved**: the sonarr/radarr AD-023 per-consumer ingress CNPs use a named allowlist (bazarr/prowlarr/seerr/recyclarr) and would DROP arr-search's connections. No source-side fix exists. Resolved via D3 (admit arr-search to both CNPs).

## Flux wiring

- arr-search/ks.yaml added to `kubernetes/apps/downloads/kustomization.yaml` resources (between recyclarr and bazarr).
- ks.yaml dependsOn `onepassword-connect` (namespace external-secrets) so the ExternalSecret's backing store is ready before the CronJob's HelmRelease reconciles.

## Validation results (all PASS)

- `shellcheck --shell=bash arr-search.sh` — EXIT 0
- `yamllint -c .yamllint.yaml` (7 YAML files) — EXIT 0 (after adding trailing newlines to the 4 new YAML files; .yamlfmt.yaml eof_newline: true)
- `yamlfmt -lint -conf .yamlfmt.yaml` — EXIT 0
- `gitleaks detect --no-git` — no leaks found
- `kubectl kustomize kubernetes/apps/downloads/arr-search/app` — EXIT 0 (ConfigMap + script render correctly)
- `kubectl kustomize kubernetes/apps/downloads/sonarr/app` — EXIT 0 (validates sonarr CNP edit)
- `kubectl kustomize kubernetes/apps/downloads/radarr/app` — EXIT 0 (validates radarr CNP edit)
- `kubectl kustomize kubernetes/apps/downloads` — EXIT 0 (validates arr-search/ks.yaml include + common component)
- Monthly guard logic — unit-tested across 7 (dow, dom) pairs, all correct
- pre-commit (full suite) — all hooks Passed (yamlfmt, yamllint, shellcheck, gitleaks, end-of-file-fixer, etc.)

## Session

- Branch: `feat/arr-search` (created locally per GitHub project override — GitLab MCP / MR-first rule does not apply)
- Code commit: `814ce42af` — `✨ feat(arr-search): add monthly missing/cutoff-unmet search cronjob for sonarr and radarr` (8 files, 207 insertions, 2 deletions)
- Draft PR: opened via `gh pr create --draft` (GitHub)

## Follow-ups / blockers

- None outstanding. CNP admission (D3) implemented in this PR; no deferred work.
- Live verification (actual first-Saturday run producing command ids in Sonarr/Radarr) is deferred to the first real fire after merge — not testable without a running first Saturday.

## Relations

- part_of [[docs/areas/k8s-workloads]]
- extends [[recyclarr]] (mirrors fix-radarr-language.sh logging pattern)
- decided_in [[docs/decisions/AD-023]] (per-consumer ingress CNP pattern)

- [type] progress-note
- [created] 2026-08-20