---
title: arr-config-sync
type: roadmap
permalink: home-ops/docs/roadmap/arr-config-sync
tags:
- roadmap
- recyclarr
- profilarr
- sonarr
- radarr
- arr-stack
- config-sync
- proposed
---

# *arr quality-config sync — Recyclarr vs Profilarr

## Metadata (observation-form, schema validation)

- [topic] Automate Sonarr/Radarr quality-profile, custom-format, quality-definition and naming synchronization from a curated upstream guide — evaluating two mutually exclusive candidates: Recyclarr (CronJob, YAML-in-git) and Profilarr (long-running web app, PCD git database)
- [status] proposed
- [priority] medium
- [scope] Pick ONE config-sync owner for the two Arr instances in the `downloads` namespace, then deliver it: Recyclarr as a `type: cronjob` app-template workload driven by a ConfigMap-mounted `recyclarr.yml`, or Profilarr as a two-container UI app (app + parser) with a VolSync-backed `/config` PVC, an `envoy-internal` route behind the `gateway-oidc` gate, and a Pocket ID client. Either path additionally requires new 1Password properties for the Sonarr/Radarr API keys plus callee-side CiliumNetworkPolicy edits on sonarr and radarr.
- [confidence] high on the repo-side facts (re-verified against the live tree 2026-08-04) and on the Profilarr/Recyclarr capability surface (upstream source, OpenAPI spec, release + registry APIs); medium on Profilarr's operational maturity trajectory, low on whether its `/config` can run under an arbitrary (≠1000) UID
- [assessed] 2026-08-04 — Profilarr added as a second candidate; the original 2026-06-13 Recyclarr survey re-verified and corrected in six places (see Corrections)
- [note] This note supersedes `docs/roadmap/recyclarr` (renamed to `docs/roadmap/arr-config-sync` on 2026-08-04) because the item is no longer "adopt Recyclarr" but "choose a config-sync owner".

## Context

Sonarr and Radarr quality profiles and custom formats drift from curated recommendations
over time, and hand-maintaining them through two web UIs is error-prone. Both candidate
tools fix the same problem — reconcile profiles/custom formats/quality definitions from a
curated upstream into the live Arr instances — but they sit at opposite ends of the
GitOps spectrum:

- **Recyclarr** is a CLI/one-shot container: the desired state is a `recyclarr.yml` in git,
  the tool holds no state worth keeping, and it reads the TRaSH Guides repo directly.
- **Profilarr** is a stateful web application: the desired state lives in a Git-backed
  "PCD" dataset plus a local SQLite database, edited through a UI, with a built-in job
  scheduler that pushes to the Arr instances.

They are **mutually exclusive per instance** (see below), so this is a choice, not a
sequence.

## Corrections to the previous survey (2026-06-13 → re-verified 2026-08-04)

The original note's config survey was materially wrong in six places. Corrected facts:

- [correction] **Namespace.** Sonarr and Radarr are **not** in `media` — they live in
  `kubernetes/apps/downloads/{sonarr,radarr}/` with `targetNamespace: downloads`
  (`kubernetes/apps/downloads/sonarr/ks.yaml:33`, `.../radarr/ks.yaml:33`). The `media`
  namespace holds Plex and its satellites. A config-sync app therefore belongs in
  **`downloads`**, alongside its two consumers — which also keeps the CNP edits
  same-namespace.
- [correction] **Exposure.** Both HTTPRoutes attach to **`envoy-internal` only**
  (`parentRefs` → `envoy-internal` in ns `networking`, `sectionName: https`;
  `.../sonarr/app/helmrelease.yaml:69-85`). The old note claimed
  `envoy-external + envoy-internal`. The Arr UIs are already LAN-only.
- [correction] **Images.** Current pins are `ghcr.io/home-operations/sonarr:4.0.19.2995@sha256:…`
  (`.../sonarr/app/helmrelease.yaml:35-36`) and
  `ghcr.io/home-operations/radarr:6.4.0.10540@sha256:…` (`.../radarr/app/helmrelease.yaml:35-36`),
  not the 4.0.17/6.2.0 pair recorded in June.
- [correction] **Both apps already carry the two shared components.** `ks.yaml:12-13` on each
  pulls in `../../../../components/volsync` and `../../../../components/gateway-oidc`, so
  their only ExternalSecrets today are the generated `${APP}-volsync` and `${APP}-oidc`
  (`kubernetes/components/volsync/externalsecret.yaml:6`,
  `kubernetes/components/gateway-oidc/externalsecret.yaml:6`). Container securityContext is
  the repo standard: UID/GID/fsGroup 10001, `runAsNonRoot`, `RuntimeDefault` seccomp,
  `readOnlyRootFilesystem: true`, all caps dropped, `emptyDir` at `/tmp`
  (`.../sonarr/app/helmrelease.yaml:20-27` and `:52-56`).
- [correction] **The API-key gap is confirmed, not conditional.** An exhaustive
  `api[-_]?key` grep across `kubernetes/apps/` finds only Mistral/OpenAI keys
  (`selfhosted/paperless-gpt`, `selfhosted/mealie`) and the CrowdSec bouncer key — **no
  Sonarr/Radarr API key is delivered by ExternalSecret anywhere**, and neither Arr
  HelmRelease has an `env:` block at all. Homepage does not expose them either: its whole
  `services.yaml` is injected as one 1Password field
  (`selfhosted/homepage/app/externalsecret.yaml:20`, `dataFrom.extract.key: homepage`), so
  any keys it uses are buried inside that blob rather than available as discrete
  properties. **New 1Password properties are required for either candidate**; the old
  note's "Option B — reuse existing items" is not available.
- [correction] **CiliumNetworkPolicy work was missing entirely from the old note.** Sonarr's
  CNP admits only `bazarr`, `prowlarr` and `seerr` on port 8989
  (`.../sonarr/app/ciliumnetworkpolicy.yaml:14-28`); radarr's is the same shape. A new
  syncer **must be added to both callees' `fromEndpoints` lists**, or its traffic is
  dropped by the callee. This is the single easiest step to miss.
- [confirmed] Recyclarr's `latest` tag really is gone in favour of major tags; the current
  release is **v8.7.0 (2026-07-15)**, so `ghcr.io/recyclarr/recyclarr:8` remains the right
  pin shape.

## Candidate A — Recyclarr

- [reference] Upstream: [recyclarr/recyclarr](https://github.com/recyclarr/recyclarr) —
  MIT, 2059 stars, 12 open issues, v8.7.0 (2026-07-15), pushed 2026-08-03.
- **Model**: CLI (`recyclarr sync`) in a one-shot container. Desired state = `recyclarr.yml`
  in git; instance URL **and** API key are declared in that YAML, with `!env_var` /
  `!file` interpolation for the secret bits (`!file` since v7.5.0).
- **Source of truth**: the **TRaSH Guides repo directly** — no conversion layer.
- **Syncs**: quality definitions, quality profiles (guide templates by `trash_id` or
  custom), custom formats + scores, **custom-format groups** (v8, auto-syncs whole
  categories against guide-backed profiles), media naming, media management
  (propers/repacks). Ships ~13 Sonarr and ~16 Radarr guide templates
  (`recyclarr config create --template <name>`).
- **Does not do**: Prowlarr (out of scope by design — indexers are orthogonal), regex
  authoring/testing, release simulation, renaming, upgrade searches, drift reporting.
- **Scheduling**: one global schedule (`@daily` default). In Kubernetes this becomes the
  CronJob schedule instead.
- **Rootless**: by design; PUID/PGID explicitly unsupported (use `--user`), which suits
  this repo's fixed UID 10001 posture.
- **State**: a config dir holding the cloned guide repo plus logs — nothing a human authored.

## Candidate B — Profilarr

- [reference] Upstream: [Dictionarry-Hub/profilarr](https://github.com/Dictionarry-Hub/profilarr) —
  AGPL-3.0, 2509 stars, 33 open issues + 5 PRs, default branch `develop`.
- **Images**: `ghcr.io/dictionarry-hub/profilarr` plus an optional
  `ghcr.io/dictionarry-hub/profilarr-parser` (C#/.NET) that mirrors Radarr/Sonarr release
  parsing. `linux/amd64` + `linux/arm64`.
- [observation] **The documented major tag does not exist.** The README advertises `latest`
  / `develop` / exact / major tags, but the GHCR tag list contains only `2.0.0`…`2.0.9`,
  `develop`, `latest` and buildcache entries — **no `2`, no `2.0`**. Pinning must therefore
  use full semver + digest (which is the repo's house style anyway).
- **Runtime**: long-running Deno 2 / SvelteKit service on **6868**; parser on **5000**.
  Health endpoints `/api/v1/health` and `/health`.
- **State** in `/config` (`APP_BASE_PATH`): SQLite `data/profilarr.db` (WAL), `logs/`,
  `backups/`, and **cloned git repos** under `data/databases/{uuid}`. Write access is
  mandatory (mkdir at start, WAL writes, `git clone/pull`, backup tarballs).
- **UID**: the entrypoint runs a root path (PUID/PGID/UMASK + `chown -R /config`, then
  `su-exec`) **and** a non-root fast path that skips all privilege operations. The baked-in
  user is **1000**; the Dockerfile explicitly documents `runAsUser: 1000` for Kubernetes and
  states that volume ownership must be handled externally (fsGroup / init container /
  pre-provisioned perms). Support for an **arbitrary UID such as this repo's 10001 is
  undocumented** — the non-root path only `mkdir`s and assumes `/config` is already
  writable, so `fsGroup: 10001` would have to carry it.
- **`readOnlyRootFilesystem`**: not vendor-documented, but **community-proven** — public
  home-ops repos run it `true` with `runAsNonRoot`, UID/GID/fsGroup 1000 and an `emptyDir`
  at `/tmp` for both containers.
- **Auth**: `AUTH=on` (bcrypt + 7-day sliding sessions), `AUTH=oidc`
  (`OIDC_CLIENT_ID`/`OIDC_CLIENT_SECRET`/`OIDC_DISCOVERY_URL`, `ORIGIN` mandatory,
  callback `{ORIGIN}/auth/oidc/callback`), or `AUTH=off`. Plus a DB-backed local-network
  bypass toggle and an `X-Api-Key` header scoped to `/api/` paths only.
- **Source of truth**: **PCD** ("Profilarr Compliant Database") — a git repo of append-only
  SQL ops plus a `pcd.json` manifest, replayed into an in-memory SQLite cache on every
  compile. Layers: schema → base ops → tweaks → **user ops**. The primary dataset is
  [Dictionarry-Hub/database](https://github.com/Dictionarry-Hub/database) (332 stars).
- [observation] **TRaSH consumption is second-hand.** Profilarr cannot read the TRaSH Guides
  repo; it consumes [Dictionarry-Hub/trash-pcd](https://github.com/Dictionarry-Hub/trash-pcd),
  a conversion repo (MIT, 37 stars, single owner, branches `main`/`french`/`german`, last
  pushed 2026-07-20). That is a freshness/abandonment dependency Recyclarr does not have.
- **Local modifications survive upstream pulls** (they are user ops, never exported).
  Conflicts resolve per `conflict_strategy`: `override` (default — user wins, conflicted op
  regenerated against clean state, audited via `superseded_by_op_id`), `align` (upstream
  wins), or `ask` (manual per-op review).
- **Scheduling**: SQLite-backed serial job queue. Cron expressions per instance/section for
  `arr.sync.*`, `arr.upgrade`, `arr.rename`, `arr.cleanup`, `arr.drift`; fixed minute
  intervals for `arr.library.refresh` and `pcd.sync`; named schedules for backups and log
  cleanup. Sync triggers: `manual`, `schedule`, `on_pull`.
- **Sync semantics**: name-based matching, idempotent on retry, 3 instances in parallel,
  sections sequential (custom formats before profiles). **No diff tracking and no rollback.**
- **Extra capabilities Recyclarr has no equivalent for**: regex library with embedded
  Regex101 test cases; custom-format testing against real release titles via the parser;
  quality-profile **simulation/scoring** against real titles (TMDB metadata); automated
  **upgrade searches**; **bulk rename** with dry-run preview; **delay profiles**; drift
  detection against live Arr config; scheduled backups with retention (secrets stripped);
  notifications to Discord/Telegram/Slack/ntfy/Pushover/Gotify/Apprise/webhook; a REST API
  with an OpenAPI 3.1 spec.

### The decisive Profilarr constraint for this repo

- [observation] **Arr instances cannot be declared as code.** API v1 exposes `GET /arr` only
  (and never returns the key) — there is **no POST/PATCH/DELETE for Arr instances**. URL +
  API key must be typed into the UI and are then stored in `arr_instances.api_key` as
  **plaintext in SQLite**, deliberately ("encrypting secrets at rest would be theatre …
  the filesystem is the trust boundary"). Linked *databases* are fully API-manageable
  (`POST /databases`, `POST /databases/{id}/sync`), profiles are not.
- This collides with the repo non-negotiable that app-level secrets arrive via External
  Secrets: the Arr API keys would live in a PVC instead, and that PVC is VolSync/Kopia
  backed to OVH S3 (encrypted in transit/at rest by Kopia, so the backup leg is
  acceptable — the in-cluster plaintext is the part that is new). The same DB also holds
  GitHub PATs and TMDB/AI keys if those features are used. Only Profilarr's *own* OIDC
  client secret could come from ESO.

## Head-to-head

| Axis | Recyclarr | Profilarr |
|---|---|---|
| GitOps fit | **Full** — desired state is YAML in this repo | **Partial** — dataset is a git repo, but instances/credentials are UI-only |
| Cluster footprint | 1 CronJob, runs seconds/day | 2 always-on containers + PVC + VolSync + HTTPRoute + OIDC gate + Pocket ID client |
| Secret delivery | ESO → env var (`!env_var`) or mounted file (`!file`) | Typed into the UI, plaintext in SQLite; ESO only for its own OIDC secret |
| Upstream source | TRaSH Guides **directly** | Dictionarry DB; TRaSH only via the `trash-pcd` conversion repo |
| Authoring/testing | none | regex tests, CF testing vs releases, profile simulation |
| Beyond profiles | none | upgrade searches, bulk rename, drift reports, delay profiles, notifications |
| Scheduling | one global schedule (CronJob) | per-instance/per-section cron + intervals |
| Rollback | revert the YAML commit, re-run | none (no diff tracking) |
| Maturity | v8.7.0, steady cadence, MIT | v2.0.9 (2026-06-24), **no stable release since**, `develop` commits daily, AGPL-3.0 |
| UID fit (10001) | native (rootless by design) | documented for 1000; arbitrary UID unverified |
| Renovate | no group entry needed (bjw-s `repository`/`tag` picked up by the `helm-values` manager) | needs a `.renovate/groups.json5` entry — app + parser release in lockstep |
| Attack surface | no listening port, no UI, no route | HTTP UI + REST API on the internal gateway, plaintext credential store |

## The mutual-exclusion constraint

- [observation] Both tools reconcile **the same objects by name** into the same instances.
  Running them together means two competing writers: Recyclarr re-applies its YAML, and
  Profilarr's `arr.drift` + `arr.sync.*` jobs detect that as drift and re-apply the PCD
  state. Whichever ran last wins, forever. There is therefore **one config-sync owner per
  Arr instance** — the only safe coexistence is Profilarr with all `arr.sync.*` schedules
  disabled, used purely as an offline authoring/testing lab.

## Options

1. **Recyclarr only (recommended)** — smallest change that solves the stated problem, fully
   declarative, no new listening surface, no new plaintext credential store, mature
   upstream, native fit with the repo's UID/rootless/read-only posture. Loses the
   authoring, testing and simulation features, which are conveniences rather than
   drift-prevention.
2. **Profilarr only** — richest feature set and the better *authoring* experience, but it
   trades away declarative config for a UI-owned SQLite state, introduces a plaintext
   credential store and an internal HTTP surface, depends on a single-owner conversion repo
   for TRaSH content, and its v2 line is ~10 weeks old with no stable release in the last
   ~6 weeks. Defensible if the regex/simulation workflow is the actual goal.
3. **Recyclarr as owner + Profilarr as a non-syncing lab** — Recyclarr keeps the instances
   in line; Profilarr runs with every `arr.sync.*` schedule off, used only to author and
   test regexes/profiles, whose output is then hand-carried into `recyclarr.yml`. Highest
   total footprint and a manual hand-off step; only worth it if the testing tooling proves
   itself.
4. **Defer both** — accept manual profile maintenance. The status quo; costs nothing and
   loses nothing already working.

Recommendation: **Option 1 now**, with a **re-evaluation gate on Profilarr**: revisit when
it (a) publishes the documented major tag, (b) resumes a stable release cadence, and
(c) offers a declarative bootstrap path for Arr instances (write endpoints under `/arr`).

## Open decisions

- [needs-decision] Which candidate — Options 1–4 above.
- [needs-decision] **Quality profiles to adopt.** Sonarr: WEB-1080p, WEB-2160p, or the
  Combined variant? Radarr: HD Bluray + WEB, UHD Bluray + WEB, or both? Depends on display
  and storage budget, so it is a human call, not a research question.
- [needs-decision] **Custom-format scope**: guide-backed profiles + auto-synced CF groups
  (least config), guide-backed profiles + explicit CF list (explicit control), or fully
  custom profiles (most maintenance).
- [needs-decision] **Which sections to sync**: media naming yes/no, media management
  (propers/repacks) yes/no, quality definitions yes/no.
- [needs-decision] **1Password layout for the Arr API keys**: two new items
  (`sonarr-api-key`, `radarr-api-key`) with a single field each, versus two new properties
  on one shared item consumed by explicit `data[].remoteRef.{key,property}` — the shape
  already used by `kubernetes/components/gateway-oidc/externalsecret.yaml:20-23`
  (item `pocket-id-clients`, property `${APP}_client_secret`). The latter matches the
  established convention more closely.
- [needs-decision] Schedule (daily is almost certainly enough) and whether a sync failure
  should notify at all — Alertmanager/Pushover already exists, so a failed CronJob could
  ride the existing `KubeJobFailed`-class rules instead of adding tool-native notifications.
- [needs-research] Does Recyclarr need a persistent config dir at all here? Its state is the
  cloned guide repo plus logs, both re-derivable, so an `emptyDir` may be enough — which
  would drop the PVC, the VolSync component and the backup surface entirely (the original
  note assumed a PVC + VolSync by analogy with the reference repos). Measure the clone cost
  of one run before deciding.
- [needs-research] If Profilarr is chosen: does `/config` work under UID 10001 with
  `fsGroup: 10001`, or must the app get a UID-1000 exception? Also decide `AUTH=off` behind
  the `gateway-oidc` component (repo-canonical, mirrors
  `kubernetes/apps/media/suggestarr/app/helmrelease.yaml:41-42`) versus native `AUTH=oidc`
  with its own Pocket ID client — and note that the gate would also sit in front of
  `/api/`, so `X-Api-Key` access needs a route exception or must be given up.

## Implementation sketch — Recyclarr path

1. Decide the 1Password layout, create the properties, and read the two API keys out of the
   live Sonarr/Radarr `config.xml` to seed them.
2. Create `kubernetes/apps/downloads/recyclarr/` (**not** `media`): `ks.yaml`,
   `app/kustomization.yaml`, `app/ocirepository.yaml`, `app/externalsecret.yaml`,
   `app/helmrelease.yaml`, `app/ciliumnetworkpolicy.yaml`, `app/config/recyclarr.yml`.
3. `app/kustomization.yaml`: `configMapGenerator` for `recyclarr.yml` with
   `disableNameSuffixHash`, and the **Flux substitution-disable annotation** on the
   ConfigMap — `!env_var` is Recyclarr's own interpolation syntax and would otherwise
   collide with Flux `postBuild` substitution. (Precedent for the generator pattern:
   `kubernetes/apps/media/plex-trakt-sync/app/kustomization.yaml:10-18`.)
4. `app/helmrelease.yaml`: app-template via `chartRef` → OCIRepository, a single
   `type: cronjob` controller (`concurrencyPolicy: Forbid`, `successfulJobsHistory: 1`,
   `failedJobsHistory: 3`, all three probes disabled), image `ghcr.io/recyclarr/recyclarr:8`
   digest-pinned, `command: ["recyclarr","sync"]`, `envFrom` the ExternalSecret, repo-standard
   securityContext (UID/GID 10001, `readOnlyRootFilesystem`, caps dropped, `emptyDir` at
   `/tmp`). Shape reference: the only CronJob precedent in the repo is paperless' sibling
   `backup` controller, `kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml:178-213`
   — a standalone CronJob-only app would be first-of-kind at app level.
5. Labels: `egress.home.arpa/allow-world: "true"` for the GitHub clone of the guides (as
   sonarr already does) and `ingress.home.arpa/none: "true"` — nothing consumes it. DNS is
   covered cluster-wide by `kubernetes/apps/kube-system/cilium/netpols/allow-dns-egress.yaml:23`;
   in-cluster egress to the two Arr services is covered by the baseline as long as the pod
   does **not** take the `egress.home.arpa/custom-egress` opt-out.
6. **Edit both callees' CNPs** — add a `fromEndpoints` entry for recyclarr in
   `kubernetes/apps/downloads/sonarr/app/ciliumnetworkpolicy.yaml` and radarr's equivalent.
7. `ks.yaml`: `dependsOn` external-secrets/onepassword-connect (plus democratic-csi only if
   a PVC survives the `[needs-research]` item above), `postBuild.substitute: APP: recyclarr`,
   `targetNamespace: downloads`. No `gateway-oidc` component and no HTTPRoute — there is no UI.
8. Register the app in `kubernetes/apps/downloads/kustomization.yaml`.
9. Validate with `flux build ks recyclarr --dry-run` (plus `kubeconform`/pre-commit), commit,
   push, and verify the first Job's logs report the expected profile/CF changes.

## Implementation sketch — Profilarr path (only if Option 2/3 is chosen)

1. Resolve the two `[needs-research]` items first (UID 10001 viability; gate vs native OIDC)
   — both change the manifest shape.
2. `kubernetes/apps/downloads/profilarr/`: OCIRepository + HelmRelease with **two
   controllers/containers** (`profilarr` on 6868, `parser` on 5000), image and parser pinned
   to full semver + digest (no major tag exists), `PARSER_HOST`/`PARSER_PORT`, `TZ`,
   `ORIGIN: https://<sub>.${PUBLIC_DOMAIN}`, `emptyDir` at `/tmp`, probes on
   `/api/v1/health` and `/health`.
3. `/config` PVC via the shared VolSync component (`VOLSYNC_CLAIM` defaults to `${APP}`),
   `APP_UID`/`APP_GID` set to whatever the UID decision lands on.
4. Route on `envoy-internal` (inline `route:` in the HelmRelease — the repo has no
   standalone `httproute.yaml` for app-template apps) plus the `gateway-oidc` component,
   `APP_SUBDOMAIN` substitution, and a Pocket ID client registration in
   `provision/pocket-id/clients.yaml` with `gate: envoy` and the appropriate group.
   `mergeType: StrategicMerge` in the SecurityPolicy is mandatory — omitting it silently
   drops the Gateway-level RFC1918 allowlist and the CrowdSec gate for that route
   (`kubernetes/apps/networking/CLAUDE.md:35`).
5. Labels: `ingress.home.arpa/allow-gateway-internal: "true"`, plus world egress (or narrow
   `toFQDNs` under `custom-egress`) for the PCD git pulls and TMDB.
6. **Edit both callees' CNPs** (same requirement as the Recyclarr path).
7. Add a `.renovate/groups.json5` entry grouping the app and parser images (lockstep
   releases), following the shape at `.renovate/groups.json5:98-105`.
8. Bootstrap by hand in the UI: link `trash-pcd` and/or the Dictionarry database, add the two
   Arr instances with their API keys, set `conflict_strategy`, then enable the sync schedules.
   Record in this note that this step is deliberately non-declarative.

## Risks & unknowns

- [risk] **Both candidates start writing to live Arr instances.** First run should be against
  a known-good state with a fresh VolSync snapshot of the sonarr/radarr PVCs in hand;
  profile/CF changes are not trivially reversible from the Arr side.
- [risk] Profilarr has **no diff tracking and no rollback**, and its v2 line broke hard from
  v1 ("existing databases and configurations cannot be migrated"). A future v3 could do the
  same to a hand-curated dataset.
- [risk] Profilarr's TRaSH content flows through a single-owner conversion repo; if
  `trash-pcd` goes stale, the TRaSH-equivalent profiles go stale silently.
- [risk] The Arr API keys currently exist **only** inside each app's `/config/config.xml`.
  Copying them into 1Password creates a second source that must be re-synced if a key is
  ever regenerated in the UI.
- [unknown] Whether Profilarr tolerates an arbitrary UID (≠1000) on `/config`.
- [unknown] Whether a 2.1.0 stable is imminent — `develop` is active daily, but the bulletin
  channel points at a bare commit sha rather than a version.
- [unknown] Profilarr's official docs site could not be verified: `dictionarry.dev` redirects
  to a client-rendered SPA and `/wiki/profilarr-setup` 404s at the v2 host. Every Profilarr
  fact above comes from the repository source, the OpenAPI spec, the releases/registry APIs,
  and public home-ops manifests — **not** from vendor documentation pages.
- [risk] Recyclarr's `!env_var` interpolation vs Flux `postBuild` substitution is a real
  collision, not a theoretical one; the substitution-disable annotation on the ConfigMap is
  load-bearing.

## Effort

- **Recyclarr**: **M** — roughly half a day. One new app directory, one ConfigMap, one
  ExternalSecret, two callee CNP edits, plus the profile-selection decisions (which are
  taste, not engineering). Dominated by choosing profiles and by the first supervised run.
- **Profilarr**: **L** — 1–2 days. Two-container HelmRelease, PVC + VolSync, route + OIDC
  gate + Pocket ID client + Terraform apply, Renovate group, UID investigation, then a
  manual UI bootstrap that cannot be captured in git.

## Related

- relates_to [[k8s-workloads]] — the app shape, canonical patterns and the `downloads`/`media` split
- relates_to [[external-secrets]] — new 1Password properties for the Arr API keys; the
  `pocket-id-clients`-style `data[].remoteRef` shape
- relates_to [[volsync-backup]] — needed by the Profilarr path; possibly droppable on the
  Recyclarr path (see `[needs-research]`)
- relates_to [[networking]] — the callee-side CiliumNetworkPolicy edits and the
  `envoy-internal` route + `StrategicMerge` requirement
- relates_to [[iam]] — only if Profilarr is chosen: `gateway-oidc` component versus native
  `AUTH=oidc`, plus the Pocket ID client and group ACL
