---
title: volsync-kopiur-migration
type: roadmap
permalink: home-ops/docs/roadmap/volsync-kopiur-migration
topic: VolSync (perfectra1n fork) → kopiur migration — adopt the existing Kopia repository
  in place on a maintained Kopia-native operator
status: planned
priority: medium
scope: Replace the abandoned perfectra1n VolSync fork with kopiur (home-operations/kopiur)
  as the PVC backup operator. kopiur adopts the existing Kopia repository on OVH S3
  in place (all 22 identities and their snapshot history preserved), so the migration
  is an operator swap plus a per-app Kustomize component rewrite, not a data migration.
  Full step-by-step plan worked out 2026-08-22 against upstream docs, the live repo,
  and the live cluster; execution gates on decisions D1-D6 and on accepting kopiur's
  alpha (v1alpha1) CRD surface.
rationale: The perfectra1n fork is abandoned; its developer now maintains kopiur.
  Because home-ops uses the fork Kopia mover, kopiur adopts the same Kopia repository
  in place — preserving all snapshot history — so the migration cost is operator-swap,
  not data-migration. kopiur additionally closes three live defects of the current
  plane (2695 index blobs from a 24h epoch floor, no restore-provability, a jitter
  MutatingAdmissionPolicy standing in for missing native scheduling) and replaces
  four hand-rolled PrometheusRules with chart-native alerting.
options:
- Parallel-run pilot then waved rollout (recommended) — kopiur adopts the repo read-only
  alongside the fork, one pilot app cuts over, then three waves by blast radius
- Wait-and-migrate — track kopiur to beta/stable, then one coordinated migration
- 'Fork-replace now — migrate all 22 apps in one commit (rejected: alpha CRD surface
  on a data-loss-critical system)'
related_areas:
- volsync-backup
- observability
- external-secrets
- ovh-storage
- networking
---

# VolSync (perfectra1n fork) → kopiur migration

## Metadata (observation-form, schema validation)

- [topic] VolSync (perfectra1n fork) → kopiur migration
- [status] planned — **D0 resolved: migrate** (parallel-run pilot → waved rollout). **D7 resolved: S3 only, unchanged** (no NAS mirror, no Phase 8). D1-D6 carry recommendations and are the remaining gate. Plan researched against upstream docs, the kopiur source, two reference implementations (onedr0p, bjw-s), and live cluster evidence, 2026-08-22.
- [priority] medium
- [gating] kopiur is **alpha** (API group `kopiur.home-operations.com`, version **v1alpha1**; "the CRD surface may still change between releases"). The 0.5.x→0.6.0 CRD relocation is a documented example of a breaking crossing. Accepted under D0: this is a maturity risk concentrated at upgrade boundaries, not a data-continuity risk — see the Rollback section.
- [created] roadmap first drafted 2026-05; execution plan researched and corrected 2026-08-22

## Context

The current PVC backup plane runs **VolSync + Kopia** on the **perfectra1n fork** image (`ghcr.io/perfectra1n/volsync`, chart `0.18.5`, image `v0.17.11`). That fork is effectively abandoned: its developer now builds **kopiur** ([home-operations/kopiur](https://github.com/home-operations/kopiur)) — a Rust/kube-rs Kopia-native backup operator that models a Kopia repository as a first-class Kubernetes resource.

The decisive compatibility fact: the fork's mover writes a **real Kopia repository**, so kopiur **adopts it in place** — no re-upload, no lost history — provided the snapshot **identity** is matched. `kubectl kopiur migrate volsync` computes the fork's identity (a bug-for-bug port of its sanitizer) and pins it. Live evidence (2026-08-22) confirms the identity shape for every app: `<app>@<namespace>:/data`.

## What we gain

- **Maintained operator** replacing a dead fork — security updates, an active upstream, cosign-signed digest-pinned OCI artifacts with SBOMs.
- **Kopia-native CRD model** with recipe / invocation / schedule separated: `SnapshotPolicy` (what), `SnapshotSchedule` (when), `Snapshot` (one run, the universal trigger), `Restore`, `Maintenance`, `Repository`/`ClusterRepository`, `RepositoryReplication`, `SnapshotReplication` — **9 CRDs**.
- **Native scheduling**: Jenkins-style `H` cron (deterministic per-schedule minute) + `jitter` + `timezone` — retires the cluster-wide `volsync-mover-jitter` MutatingAdmissionPolicy entirely.
- **Chart-native observability**: `ServiceMonitor`, `PrometheusRule` (11 alerts), and a grafana-operator `GrafanaDashboard` rendered from the chart — replaces four hand-rolled VolSync/Kopia rules plus the imported grafana.com dashboard.
- **First-class restore provability**: `verification.quick` / `verification.deep` prove backups are restorable on a schedule. The current plane has no such proof (`docs/areas/volsync-backup` logs this as an open gap).
- **Repository health as a controlled surface**: `spec.parameters.epoch.minDuration` fixes the live "too many index blobs" condition declaratively instead of via out-of-band `kopia` CLI.
- **A clean deploy-or-restore bootstrap** (`Restore` + `target.populator: {}` + `onMissingSnapshot: Continue`) that retires the current `IfNotPresent`-SSA ReplicationDestination dance and its "delete BOTH the PVC and the bootstrap RD" trap.
- **A real day-2 CLI** (`kubectl kopiur` via krew/Homebrew): `snapshot now`, `restore`, `logs`, `snapshots list`, `ls`/`cat`/`download`/`browse`, `status`, `doctor`, `maintenance run`, `suspend`/`resume`.

## What to do (high level)

1. Fix the live index-blob condition and run the pre-flight checks (Phase 0).
2. Stand up `kopiur-system` alongside VolSync, adopting the existing repository **read-only in effect** (no `create` block, maintenance disabled) — Phase 1-2.
3. Cut one pilot app over, prove dedup + restore continuity — Phase 3.
4. Roll the remaining 21 apps in three waves by blast radius — Phase 4.
5. Hand maintenance ownership from the fork's `KopiaMaintenance` to kopiur — Phase 5.
6. Tear down VolSync — keeping the repository Secret — Phase 6.
7. Re-home the docs: guides, skills, Just recipes, area-reference — Phase 7.

## Options

1. **Parallel-run pilot then waved rollout (recommended)** — kopiur adopts the repository while the fork stays the only writer; one pilot app cuts over; then three waves. Front-loads the learning on a low-value app, keeps rollback trivial for the whole window.
2. **Wait-and-migrate** — track kopiur to beta/stable, then one coordinated migration. Lower operator-maturity risk, but the fork accrues unpatched CVEs and the three live defects above stay unfixed for months.
3. **Fork-replace now** — all 22 apps in one commit. Rejected: alpha CRD surface on a data-loss-critical system, and the `AD-017-big-bang-cutover` precedent does not apply here (that was a greenfield cluster, this is live data).

## Related

- relates_to [[volsync-backup]] — the area being replaced; its area-reference is the current-state source of truth
- relates_to [[observability]] — four hand-rolled rules + one imported dashboard map onto chart-native alerting
- relates_to [[external-secrets]] — the repository password and S3 credentials move from 22 per-app ExternalSecrets to 5 per-namespace ones
- relates_to [[ovh-storage]] — same bucket, same credentials, same OVH `DE` region endpoint
- relates_to [[AD-023-cnp-threat-model-audit]] — mover-pod world egress must be re-granted under a kopiur-shaped selector
- relates_to [[alerting-coverage-gaps]] — `KopiaMaintenanceStale` was added there and has **no** direct kopiur equivalent (see W6)

---

## Execution plan (research-backed, 2026-08-22)

### Research basis

- Upstream docs pulled verbatim from `home-operations/kopiur@main/docs/` (34 pages), notably `cli/migrate-volsync.md`, `scenarios/adopt-existing-repo.md`, `repositories.md`, `backups.md`, `restores.md`, `maintenance.md`, `gitops.md`, `install.md`, `backends/s3.md`, `field-reference.md`.
- Chart surface from `deploy/helm/kopiur/{values.yaml,README.md,templates/prometheusrule.tpl}`.
- Operator source read where the docs were silent: `crates/mover/src/jobs.rs` (mover Job/pod label construction), `crates/controller/src/io/mover.rs`.
- Reference implementations: `billimek/k8s-gitops` (ResourceSet-driven, adopted an existing NFS Kopia repo in place), `rafaribe/home-ops` (`.kiro/stories/volsync-kopiur-adopt-in-place.md` and `volsync-to-kopiur-migration.md` — the second story is the *new-repository* variant and is **not** our model).
- Live cluster evidence (read-only, 2026-08-22): kopia identities, kopia repository status, maintenance owner, epoch parameters, K8s version, 22 healthy `ReplicationSource`s.

### Corrections to the earlier draft of this note

The pre-2026-08-22 body of this roadmap carried four factual errors, now fixed above and below:

- [correction] The CRDs are **not** `BackupConfig` / `Backup` / `BackupSchedule`. ADR-0004 ("breaking CRD and field renames") renamed them to **`SnapshotPolicy` / `Snapshot` / `SnapshotSchedule`**. Any manifest written from the old names will be rejected.
- [correction] There are **9** CRDs, not 6-7: the two repository kinds, `SnapshotPolicy`, `SnapshotSchedule`, `Snapshot`, `Restore`, `Maintenance`, `RepositoryReplication`, `SnapshotReplication`.
- [correction] Kubernetes requirement: the **chart** README states **≥ 1.32**; `install.md` states ≥ 1.24 for the volume-populator path alone. Live cluster is **v1.36.4** — satisfied either way.
- [correction] Chart version moved on: latest release **0.10.3** (2026-08-18), not `0.9.2`.

### Live baseline (measured 2026-08-22, not assumed)

| Fact | Value | Why it matters |
|---|---|---|
| Apps on `components/volsync` | **22** (`downloads` 8, `media` 6, `selfhosted` 7, `security` 1) | The rollout unit count |
| Kopia identities in the repo | `<app>@<namespace>:/data` for all 22 | Exactly the fork shape kopiur's translator pins |
| Snapshot counts per identity | 24-34 (matches `retain` hourly=24 daily=7 weekly=2 monthly=1) | Confirms current retention is live and effective |
| Orphan identity | `suggestarr@media:/data`, 5 snapshots | A removed app. Will surface as a permanent `origin: discovered` row (see W7) |
| Repository | one shared S3 bucket, **no prefix**, one `KOPIA_PASSWORD` | ⇒ a single `ClusterRepository` is the natural model, not 22 `Repository` objects |
| Backend | OVH Object Storage, region `DE`, endpoint `s3.<region>.io.cloud.ovh.net`; no `region` set in the live kopia config | Adopt with `region` omitted for parity; add only if bootstrap fails |
| Maintenance owner (kopia-side) | `maintenance@volsync` | A fork-authored owner string kopiur must take over (Phase 5) |
| **Index blobs** | **2695** — kopia prints *"Found too many index blobs, this may result in degraded performance"* | A live, pre-existing defect. Root cause below |
| Epoch parameters | advance on 20 blobs / 10.5 MB, **minimum 24h**; refresh 20m; range-compaction every 7 epochs | 22 hourly sources ≈ 500+ index blobs/day but the epoch cannot close more than once a day ⇒ unbounded accumulation |
| Kubernetes | v1.36.4 | ≥ 1.32 ✓; `AnyVolumeDataSource` ✓ |
| CSI snapshot stack | `snapshot-controller` + `democratic-csi-local-hostpath` VolumeSnapshotClass | `copyMethod: Snapshot` works unchanged |

Per-app parameter matrix (the substitution surface the new component must reproduce):

| ns | app | uid | gid | capacity |
|---|---|---|---|---|
| downloads | bazarr, maintainerr, prowlarr, qbittorrent, radarr, recyclarr, sonarr | 10001 | 10001 | 1Gi |
| downloads | seerr | 1000 | 1000 | 1Gi |
| media | crosswatch, jellyfin, plex | 10001 | 10001 | 5Gi |
| media | isponsorblocktv, plex-trakt-sync | 10001 | 10001 | 1Gi |
| media | calibre-web-automated | 1000 | **100** | 1Gi |
| security | pocket-id | 65532 | 65532 | 1Gi |
| selfhosted | actual, pingvin-share-x | 10001 | 10001 | 5Gi |
| selfhosted | mealie, paperless-gpt | 10001 | 10001 | 1Gi |
| selfhosted | wallos | 1000 | 1000 | 1Gi |
| selfhosted | paperless | 1000 | 1000 | 20Gi (retain daily=7 weekly=4 monthly=12) |
| selfhosted | **backrest** | **0** | **0** | 1Gi |

`backrest` running the mover as **UID 0** is the single sharpest gotcha in the whole migration — see W1.

### Decisions to take before Phase 1
Seven decisions gate this migration. Each is stated as the underlying tension first, the
alternatives second, and the recommendation last — because in every case the field-level answer is
easy once the tension is named, and misleading before it is.

#### D0 — Which risk do we choose to carry?

This is the only decision that is not technical, and it is the one the other six hang off.

The framing "is kopiur mature enough yet?" is the wrong question, because it implies that *not*
migrating is the null option. It is not. Staying on the perfectra1n fork is an active choice to
carry a different risk, and that risk **grows monotonically**: an abandoned fork accrues unpatched
CVEs in the operator and in six mover images, its chart stops tracking upstream VolSync, and the
three live defects this plane has today (a 24h epoch floor that cannot compact 22 hourly sources,
no proof that any backup is restorable, an admission webhook standing in for scheduling the
operator never grew) stay unfixed indefinitely. There is nobody upstream to fix them.

Kopiur's risk is different in shape: it is **alpha**, so the risk is concentrated at *upgrade
boundaries*, not in steady-state operation. The 0.5.x→0.6.0 CRD relocation is the documented
example — a version crossing that cascade-deleted CRs for anyone who applied it blind. That risk
is bounded, scheduled (it only fires when we bump a version), and mitigable by pinning tags and
reading `docs/upgrade.md` before merging a Renovate PR. The abandoned-fork risk is unbounded,
unscheduled, and unmitigable.

Crucially, the risk that would matter most — **losing backup history** — is near-zero on both
sides, and that is the finding that makes this decision tractable. Because the fork writes a real
Kopia repository and kopiur adopts it in place under a pinned identity, the two operators are
interchangeable writers to one repository. There is no data migration, no dual-write window, no
cut-over moment where history is in flight.

- **Option 1 — parallel-run pilot then waved rollout (recommended).** Accept the alpha risk now,
  bound it with pinned versions and a paced rollout, get the three defect fixes.
- **Option 2 — wait for beta.** Defers the alpha risk, keeps the fork risk growing. Reasonable
  only if there is a concrete expected date; "wait for stable" with no date is just Option 3 with
  extra steps.
- **Option 3 — big-bang.** Rejected on principle: `AD-017-big-bang-cutover` was a greenfield
  cluster with nothing to lose; this is live data.

#### D1 — Where does the boundary of the backup domain sit?

Today there is **one** physical Kopia repository, but it is *modelled* as if each app owned its
own: 22 ExternalSecrets, each rendering the same bucket, the same password, the same credentials,
under 22 different names. VolSync makes that invisible because it has no repository object at all
— the Secret *is* the repository. Kopiur promotes the repository to a first-class object, which
forces the modelling choice into the open.

Taking the path of least resistance is a trap here: `kubectl kopiur migrate volsync
--resolve-secrets` naturally emits one namespaced `Repository` per `ReplicationSource`, so the
tool's default output is the shape we should *not* adopt. Twenty-two `Repository` objects
describing one backend means 22 places for the backend to drift, and — more seriously — 22
operator-managed `Maintenance` CRs contending for a lease that Kopia only ever grants to **one**
owner. The default `takeoverPolicy: Never` makes that safe rather than destructive, but the steady
state is 21 objects yielding forever, each spawning a mover Job every cron slot to do nothing.

A single `ClusterRepository` matches what the storage actually is, and buys three things beyond
tidiness. Backend truth, epoch parameters, timezone, and mover defaults live in one place. The
maintenance lease has exactly one claimant. And `allowedNamespaces` becomes an explicit,
auditable statement of which namespaces may write to the backup repository — a tenancy property
this cluster does not have today, where anything holding the right Secret can write anything.

- **Recommendation: one `ClusterRepository` named `ovh-kopia`**, gated with an explicit
  `allowedNamespaces.list`, not `all: true`. The list is cheap to maintain (four entries) and it
  is the only place the backup plane states who is allowed in.

#### D2 — Who is trusted to move a credential across a namespace boundary?

The mover loads repository credentials with `envFrom`, which Kubernetes deliberately confines to
the pod's own namespace. Both available answers are ways of crossing that boundary; they differ
entirely in *who holds the capability to cross it*, which makes this a trust-boundary decision
rather than a convenience one.

Kopiur's `credentialProjection` asks for cluster-wide `secrets` `create`/`patch`/`delete`. The
important property is that RBAC `create` **cannot be scoped to a resource name** — the grant is
not "the operator may write `kopiur-repo-secret`", it is "the operator may write any Secret in any
namespace it manages". That turns the backup operator into a high-value target: compromising it
would allow planting or shadowing credentials fleet-wide, in namespaces that have nothing to do
with backups. In exchange it removes four manifests and keeps the copies ephemeral and always
fresh.

External Secrets is the alternative, and it is not a workaround — upstream names it as an intended
path. It changes nothing about the cluster's trust model: ESO already holds exactly this
capability, is already the sanctioned channel for every app secret in this repo, and already reads
the same 1Password items. The blast radius does not grow by one byte. The cost is four
near-identical manifests plus one in `kopiur-system`, and a rotation that fans out to five
refreshes — though all five pull the same 1Password item, so rotation remains a single action at
the source.

The scale is what settles it. At four workload namespaces, widening an operator's RBAC to save
four files is a bad trade; at forty it would be a good one.

- **Recommendation: ExternalSecret per namespace, `features.credentialProjection.enabled: false`.**
- **Revisit trigger:** if backing-up namespaces grow past roughly ten, or if per-app credential
  separation is ever introduced, re-open this.

#### D3 — Which principle yields: declarative config, or identifiers stay out of git?

Two things that are individually correct collide here.

Kopiur models the backend as **configuration** — `bucket` and `endpoint` are required spec strings
with no Secret indirection. That is deliberate and defensible design: a Secret-sourced bucket name
means you cannot see what your backups target without decrypting something, which is a bad
property for a disaster-recovery system whose whole job is to be readable on the worst day.

This repository takes the opposite position: the bucket name and the OVH endpoint are treated as
sensitive external identifiers and kept out of git entirely — not in `terraform.tfvars`, not in
`cluster-settings`, only in 1Password, resolved at apply time. That is a deliberate stance for a
repo that is explicitly "potentially public and durable".

So one of them has to bend, and the question is which cost is cheaper to carry.

Relaxing the repo rule is defensible on the merits — a bucket name is not a credential, and it is
useless without the access key. The cost is not technical, it is **precedential**: this would be
the first sensitive external identifier committed, and "it's not really a credential" is exactly
the reasoning by which such a rule erodes. Rules like this one survive on not having exceptions.

Keeping both principles is possible because Flux can substitute from a Secret, not just a
ConfigMap: ESO renders the values into a Secret, Flux interpolates them at build time, git holds
`${KOPIA_S3_BUCKET}`, and the object in the cluster holds the real value. The mechanism already
exists, and the repo already anticipated needing a per-Kustomization opt-out from the root's
injected substitution list (`substitution.flux.home.arpa/disabled`) — this would be its first use,
which is a sign the hook was built for exactly this and never needed until now.

The cost of that path is **comprehension**, plus one sharp failure mode worth naming up front: if
the Secret is missing at build time, the Kustomization renders a literal `${KOPIA_S3_BUCKET}` into
the CR rather than failing cleanly, so the symptom is a nonsense manifest rather than a clear
error. That is a documentation problem, and documentation problems are repayable. Precedents are
not.

- **Recommendation: keep both principles** — ESO Secret + `postBuild.substituteFrom` +
  the `substitution.flux.home.arpa/disabled` label, with the failure mode documented in the
  platform guide.

#### D4 — What is the bootstrap path actually for?

This is the only place the migration touches a genuinely immutable Kubernetes surface, and it
forces an honest answer about what the PVC's `dataSourceRef` is doing in the manifest at all.

That field does exactly one thing, once, at provisioning. For 22 already-bound PVCs it is dead
metadata. But Flux re-applies manifests continuously, so dead metadata that *changes* stops being
harmless: the API server rejects the patch on an immutable field and the app's Kustomization goes
red.

The three postures differ in what they are willing to spend:

Recreating all 22 PVCs so the new reference genuinely takes is the intellectually honest option
and an operationally absurd one — 22 outages and 22 full restores over the internet from OVH, to
change a field nothing will ever read again.

Freezing the PVC with `IfNotPresent` server-side apply spends *continuous reconciliation* instead.
Flux applies the PVC once and never re-templates it; existing PVCs keep their now-inert stale
reference, and any future provisioning — a new app, a rebuilt namespace, a bare-metal disaster
recovery — goes through the kopiur populator. The price is that capacity changes leave GitOps and
become a `kubectl patch`. That price is small in practice: Kubernetes only ever grows a PVC, never
shrinks it, so expansion is already a semi-manual, deliberate operation rather than something that
flows naturally from a git edit.

Dropping the PVC from the component and pushing it into each app is rejected — it dissolves the
"the component owns the whole backup contract" model that makes the per-app wiring a three-line
change.

What makes the recommendation comfortable is that **this repo already made this exact trade once**,
for the same reason, on the object next door: the bootstrap `ReplicationDestination` carries the
same `IfNotPresent` label so Flux applies it once and never overwrites. This is not new machinery,
it is the established local pattern applied one object over.

It is also worth being clear that the thing being replaced is *worse*. Today a fresh restore
requires deleting **both** the PVC and the frozen bootstrap RD — a trap documented in the platform
guide precisely because, without that knowledge, the bootstrap path simply looks broken. Kopiur's
populator `Restore` is a living source rather than a one-shot: delete the PVC alone and it
repopulates. The migration therefore removes a documented footgun while inheriting a milder
version of its cause.

- **Recommendation: `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` on the component's PVC**,
  with the capacity-change caveat written into the platform guide.

#### D5 — Scope discipline: what does *not* get fixed during this migration?

Kopiur can host the Kopia web UI itself (`ClusterRepository.spec.server`), and architecturally that
is tidier: one operator owning the repository and its browse surface. But it asks for the same
cluster-wide Secret-write grant that D2 just declined — this time for a convenience feature rather
than for the backup path itself. Accepting it here would make D2's reasoning incoherent, and a
security posture that bends for convenience is not a posture.

The existing standalone browser needs nothing from kopiur. It reads the repository through its own
config file and an ESO-delivered password, and is genuinely indifferent to which operator writes
that repository. So the cheap and correct move is to not touch it at all — just re-home it when
`volsync-system` is dismantled.

The real decision hiding here is a **scope-discipline** one, and it is more interesting than the
UI question. The area-reference records a standing security gap: this UI runs `--without-password`
and is reachable from the LAN across the entire backup repository, with `enableActions: false` and
LAN-only exposure as the only mitigations. We will be editing that file anyway during the move,
and the `components/gateway-oidc` gate already exists and is already used by other internal apps.
The temptation to fix it in passing is strong and should be resisted: bundling an authentication
change into a backup-operator migration means that if either breaks, attribution is ambiguous —
and worse, it entangles the migration's rollback story with an auth change that has nothing to do
with it.

A third option deserves naming rather than assuming: **drop the UI entirely** and rely on
`kubectl kopiur ls/cat/download/browse`. That is a genuine simplification — one fewer workload,
one fewer exposed surface, and it would close the security gap by deletion rather than by adding
an auth layer. The UI's actual purpose (occasionally looking inside a backup without restoring it)
is served by both. The reason not to decide it now is that nobody has used the CLI in anger yet;
this is the right question to ask again after Phase 6.

- **Recommendation: keep the standalone UI unchanged, move it in Phase 6, and file the OIDC gate
  as its own change** — before or after the migration, not during. Revisit "delete it entirely"
  once the CLI has replaced it in practice.

#### D6 — How many variables move at once?

Kopiur brings materially better scheduling primitives, and rewriting the per-app component is
exactly the moment when re-tuning cadence and retention feels natural. It should not be done,
for a reason that has nothing to do with the merits of the new values: if backup duration,
repository growth, or index-blob behaviour shifts after the migration, the change must be
attributable to the operator swap and nothing else. One variable at a time is what makes the
verification matrix meaningful rather than decorative.

Two changes are **forced** regardless, and are worth expecting rather than diagnosing later:

The jitter mechanism changes shape. Today every source fires at `0 * * * *` and a cluster-wide
MutatingAdmissionPolicy injects a fresh random 0-300s sleep per run, so the spread is different
every hour. Kopiur's Jenkins-style `H` derives a *stable* minute per schedule — each app fires at
the same minute every hour — with `jitter` adding a bounded window on top. That is a strictly
better property (predictable, debuggable, and with no admission webhook in the backup path), but
it is not identical behaviour: the first day's timing chart will look different. That is the
change working, not a regression.

Retention semantics change mechanism while keeping outcome. VolSync passes `retain` down to kopia;
kopiur pins kopia's own retention to effectively-infinite and enforces GFS itself by pruning
`Snapshot` CRs. Same numbers, same result, different machinery — and this is precisely why the
live CR count now equals the retained snapshot count by design (W4). Changing the retention
numbers would move that count too, which is another reason to hold them still.

- **Recommendation: keep cadence and retention byte-identical through Phase 4.**
- **Deferred to after Phase 5:** enable `verification.quick` (there is no reason to leave restore
  provability off once maintenance is stable, and it closes a documented gap), and consider
  trimming low-churn apps to a four-hourly cadence to reduce `Snapshot` CR volume and index-blob
  churn — the change billimek made for the same reason.

### Target architecture

```
kubernetes/
├── apps/kopiur-system/
│   ├── kustomization.yaml            # components: ../../components/common
│   ├── namespace.yaml
│   └── kopiur/
│       ├── ks.yaml                   # 3 Kustomizations: kopiur, kopiur-repository, (later) kopiur-ui
│       ├── app/                      # operator
│       │   ├── ocirepository.yaml    # oci://ghcr.io/home-operations/charts/kopiur, ref.tag pinned
│       │   ├── helmrelease.yaml
│       │   └── kustomization.yaml
│       └── repository/               # the adopted repository
│           ├── clusterrepository.yaml
│           ├── externalsecret.yaml   # kopiur-repo-secret (creds) + kopiur-repo-vars (bucket/endpoint)
│           └── kustomization.yaml
├── components/
│   ├── kopiur/                       # replaces components/volsync/
│   │   ├── kustomization.yaml
│   │   ├── snapshotpolicy.yaml
│   │   ├── snapshotschedule.yaml
│   │   ├── restore.yaml              # bootstrap populator
│   │   └── pvc.yaml                  # IfNotPresent SSA (D4)
│   └── kopiur-creds/                 # ExternalSecret, added to each workload namespace kustomization
│       ├── kustomization.yaml
│       └── externalsecret.yaml
└── apps/kube-system/cilium/netpols/allow-world-egress.yaml   # + kopiur mover selector (W2)
```

Deleted at the end of Phase 6: `kubernetes/apps/volsync-system/` (operator, maintenance, MutatingAdmissionPolicy, PrometheusRule + its `_test.yaml`, GrafanaDashboard/Folder), `kubernetes/components/volsync/`, `kubernetes/volsync/mod.just`, and the 22 per-app `${APP}-volsync` ExternalSecrets.

### Manifest shapes (drafts — validate against the published CRD schema before applying)

`ClusterRepository` — adoption, not creation. **No `create` block**: that is what makes a mis-parsed backend fail loudly instead of silently initializing an empty repository.

```yaml
apiVersion: kopiur.home-operations.com/v1alpha1
kind: ClusterRepository
metadata:
  name: ovh-kopia
spec:
  allowedNamespaces:
    list: [downloads, media, security, selfhosted]
  backend:
    s3:
      bucket: "${KOPIA_S3_BUCKET}"
      endpoint: "${OVH_S3_ENDPOINT}"
      auth:
        secretRef:
          name: kopiur-repo-secret
          namespace: kopiur-system
  encryption:
    passwordSecretRef:
      name: kopiur-repo-secret
      namespace: kopiur-system
  # Fixes the live 2695-index-blob condition: 22 hourly sources cannot compact
  # under kopia's 24h epoch floor.
  parameters:
    epoch:
      minDuration: 6h
  scheduleDefaults:
    timezone: Europe/Budapest
  catalog:
    periodicRefresh: true       # see the fork's new snapshots during the parallel window
    refreshInterval: 1h
  maintenance:
    enabled: false              # Phase 1-4; flipped to true in Phase 5
```

`SnapshotPolicy` (component) — the identity is the load-bearing part. kopiur's default `username` is the policy name (`${APP}`) and its default `hostname` is the namespace, so both **already match** the fork; only the source path differs (`/pvc/<name>` vs `/data`).

```yaml
apiVersion: kopiur.home-operations.com/v1alpha1
kind: SnapshotPolicy
metadata:
  name: "${APP}"
spec:
  repository:
    kind: ClusterRepository
    name: ovh-kopia
  copyMethod: Snapshot
  volumeSnapshotClassName: "${VOLSYNC_SNAPSHOTCLASS:=democratic-csi-local-hostpath}"
  sources:
    - pvc:
        name: "${VOLSYNC_CLAIM:=${APP}}"
      # The fork recorded /data; without this the identity forks the lineage.
      sourcePathOverride: /data
  compression:
    algorithm: "${VOLSYNC_COMPRESSION:=zstd-fastest}"
  upload:
    maxParallelFileReads: ${VOLSYNC_PARALLELISM:=2}
  retention:
    keepHourly: ${VOLSYNC_RETAIN_HOURLY:=24}
    keepDaily: ${VOLSYNC_RETAIN_DAILY:=7}
    keepWeekly: ${VOLSYNC_RETAIN_WEEKLY:=2}
    keepMonthly: ${VOLSYNC_RETAIN_MONTHLY:=1}
  mover:
    securityContext:
      runAsUser: ${APP_UID:=10001}
      runAsGroup: ${APP_GID:=10001}
    podSecurityContext:
      fsGroup: ${APP_GID:=10001}
      fsGroupChangePolicy: OnRootMismatch
```

`SnapshotSchedule`:

```yaml
apiVersion: kopiur.home-operations.com/v1alpha1
kind: SnapshotSchedule
metadata:
  name: "${APP}"
spec:
  policyRef:
    name: "${APP}"
  schedule:
    cron: "H * * * *"   # deterministic per-schedule minute — replaces the jitter MutatingAdmissionPolicy
    jitter: 5m
```

Bootstrap `Restore` — a standing populator, inert until an unbound PVC claims it. `inheritSecurityContextFrom: { snapshot: {} }` is the one inherit mode allowed with a populator target, and it is what makes a bare-cluster rebuild work with no live workload to copy a UID from.

```yaml
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: "${APP}-bootstrap"
spec:
  repository:
    kind: ClusterRepository
    name: ovh-kopia
  source:
    fromPolicy:
      name: "${APP}"
  target:
    populator: {}
  policy:
    onMissingSnapshot: Continue   # fresh PVC when there is no history yet
  mover:
    inheritSecurityContextFrom:
      snapshot: {}
```

`PVC` — `IfNotPresent` SSA per D4:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: "${VOLSYNC_CLAIM:=${APP}}"
  labels:
    kustomize.toolkit.fluxcd.io/ssa: IfNotPresent
spec:
  accessModes: ["${VOLSYNC_ACCESSMODES:=ReadWriteOnce}"]
  dataSourceRef:
    apiGroup: kopiur.home-operations.com
    kind: Restore
    name: "${APP}-bootstrap"
  resources:
    requests:
      storage: "${VOLSYNC_CAPACITY:=1Gi}"
  storageClassName: "${VOLSYNC_STORAGECLASS:=democratic-csi-local-hostpath}"
```

HelmRelease values (operator):

```yaml
values:
  installScope: cluster              # ClusterRepository is a cluster-scoped kind (D1)
  features:
    credentialProjection:
      enabled: false                 # D2 — do NOT widen secrets RBAC
    kopiaUi:
      enabled: false                 # D5
  monitoring:
    serviceMonitor: { enabled: true }
    prometheusRule: { enabled: true }
    dashboards:
      enabled: true
      grafanaOperator:
        enabled: true
        matchLabels: { dashboards: grafana }   # matches the cluster Grafana instanceSelector
```

Keep the repo's HelmRelease minimal-spec policy: no `install`/`upgrade`/`timeout` blocks — the root Kustomization injects them.

---

### Phase 0 — pre-flight (no kopiur yet)

- [ ] **P0.1 Fix the index-blob condition first.** 2695 blobs is a pre-existing defect and would land on kopiur's doorstep as `IndexBlobHealth: TooManyIndexBlobs`. Either lower the epoch floor now via the kopia CLI (`kopia repository set-parameters --epoch-min-duration 6h` from the `kopia` Deployment) and run `just volsync kopia-maintenance` until the count falls, **or** accept it and let the `ClusterRepository.spec.parameters.epoch.minDuration: 6h` re-stamp it on first bootstrap. *Recommendation: fix it now* — a clean baseline means the first kopiur health warning is signal, not inherited noise.
- [ ] **P0.2 Record the identity baseline.** `kubectl -n volsync-system exec deploy/kopia -- kopia snapshot list --all --json` → keep the identity list + per-identity counts. This is the continuity proof in Phase 3.
- [ ] **P0.3 Install the CLI.** `kubectl krew index add kopiur https://github.com/home-operations/kopiur.git && kubectl krew install kopiur/kopiur` (or `brew install home-operations/tap/kopiur`). Keep plugin and operator on the same release.
- [ ] **P0.4 Dry-run the translator, offline.** `kubectl kopiur migrate volsync -f kubernetes/components/volsync/replicationsource.yaml --repository ovh-kopia --out-dir /tmp/kopiur-migrated` will not resolve `${...}` substitutions; instead run it against the **live** objects for one namespace and read the accounting: `kubectl kopiur migrate volsync -n selfhosted --resolve-secrets`. **Do not `--apply`.** The single line to verify is the pinned `(fork snapshot identity)` — it must read `<app>@<namespace>:/data`. Every field it read is reported as `mapped` / `UNMAPPABLE` / `ignored`; nothing is silently dropped. Use its output to sanity-check the hand-written component above, not as the component itself (its output is per-app YAML, not a parameterized Kustomize component).
- [ ] **P0.5 Confirm the schema server publishes kopiur CRDs** at `https://k8s-schemas.home-operations.com/kopiur.home-operations.com/<kind>_v1alpha1.json` so the repo's `# yaml-language-server: $schema=` convention and any `kubeconform` gate resolve. If not, note it and skip the schema comment rather than pointing at a 404.
- [ ] **P0.6 Verify the mover pod label** the CNP will select (W2): after the first kopiur mover Job runs, `kubectl get pod -n <ns> -l job-name=<job> -o jsonpath='{.metadata.labels}'`. Source reading says `app.kubernetes.io/managed-by: kopiur` is stamped on **both** the Job and its pod template for every mover kind (`crates/mover/src/jobs.rs`, `managed_labels()` applied to `metadata` and `spec.template.metadata`), plus `kopiur.home-operations.com/config=<policy>` on snapshot movers. Confirm live before relying on it.

### Phase 1 — install the operator (no repository yet)

- [ ] **P1.1** `kubernetes/apps/kopiur-system/{kustomization.yaml,namespace.yaml}` + `kopiur/{ks.yaml,app/}`. `dependsOn`: `snapshot-controller` (kube-system). Pin `OCIRepository.ref.tag` to a specific release (0.10.3 at time of writing) — alpha means never floating.
- [ ] **P1.2** Add `kopiur-system` to `kubernetes/apps/kustomization.yaml`.
- [ ] **P1.3** CRD lifecycle: the 9 CRDs ship in the chart's `crds/` directory, which **Helm never updates on upgrade**. The root Kustomization already injects `install.crds: CreateReplace` and `upgrade.crds: CreateReplace` into every HelmRelease — verify that this is what actually lands for the kopiur release, because a missed CRD schema change on an alpha operator is a silent breakage. Flux applies server-side, which the two >256 KB repository CRDs require.
- [ ] **P1.4** Verify: `flux -n kopiur-system get hr kopiur`, `kubectl -n kopiur-system rollout status deploy/kopiur-controller deploy/kopiur-webhook`, `kubectl get crd | grep kopiur.home-operations.com | wc -l` = 9, `kubectl kopiur doctor`.
- [ ] **P1.5** The webhook cert is **self-managed by default** (`webhook.tls.mode: self`) — no cert-manager wiring needed. The webhook pod stays `ContainerCreating` until the controller mints its serving Secret; that is expected, not a fault.

### Phase 2 — adopt the repository (read-only in effect)

- [ ] **P2.1** ExternalSecrets: `kopiur-repo-secret` (`KOPIA_PASSWORD`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` from 1Password `volsync-template` + `ovh`) in `kopiur-system`, and `kopiur-repo-vars` (`KOPIA_S3_BUCKET`, `OVH_S3_ENDPOINT`) for the D3 substitution. **Same 1Password items, same values** — the fork's Secret is untouched.
- [ ] **P2.2** `ClusterRepository/ovh-kopia` as drafted, with `maintenance.enabled: false` and **no `create` block**. Its Kustomization carries `substitution.flux.home.arpa/disabled: "true"` and its own `substituteFrom` list (D3), and `dependsOn` `onepassword-connect` + `kopiur`.
- [ ] **P2.3** Wait for `Ready`: `kubectl wait --for=condition=Ready clusterrepository/ovh-kopia --timeout=300s`. `Connected` and `MaintenanceOwned` are the kind-specific conditions to read on failure.
- [ ] **P2.4** Prove adoption — the initial catalog scan materializes the fork's history:
  `kubectl get snapshots -A -l kopiur.home-operations.com/origin=discovered` → expect rows in `downloads`/`media`/`security`/`selfhosted` matching the P0.2 baseline. `kubectl kopiur snapshots list --origin discovered -A` gives the richer view.
- [ ] **P2.5** Prove a restore from adopted data **before** touching any app: pick one discovered `Snapshot` and restore it into a throwaway PVC (`Restore` with `source.snapshotRef` + `target.pvc`), then delete it. A `Completed` phase here is the single most valuable signal in the whole migration — it proves password, endpoint, credentials, identity, and mover security context all line up.
- [ ] **P2.6** At this point kopiur has written nothing to the repository. VolSync is still the only writer. Rollback = delete the `ClusterRepository`.

### Phase 3 — pilot cutover (one app)

Pilot candidate: **`isponsorblocktv`** (media, 1Gi, uid/gid 10001, no external consumers, trivial to rebuild). `recyclarr` is the alternative.

- [ ] **P3.1** Write `kubernetes/components/kopiur/` (4 files) and `kubernetes/components/kopiur-creds/`.
- [ ] **P3.2** Add `components/kopiur-creds` to `kubernetes/apps/media/kustomization.yaml` (the same slot `components/common` occupies).
- [ ] **P3.3** In the pilot's `ks.yaml`: swap `../../../../components/volsync` → `../../../../components/kopiur`, add `dependsOn` on `kopiur-repository` (kopiur-system). **Keep every `postBuild.substitute` value byte-identical** — the component contract is deliberately unchanged.
- [ ] **P3.4** Suspend the fork for this app only, so two operators never snapshot the same PVC concurrently: `kubectl -n media patch replicationsource isponsorblocktv --type merge -p '{"spec":{"paused":true}}'` (or delete the RS — the component swap removes it anyway once Flux prunes).
- [ ] **P3.5** Reconcile, then read the resolved identity **before** the first run: `kubectl -n media get snapshotpolicy isponsorblocktv -o jsonpath='{.status.resolved.identity}'` → must be `isponsorblocktv@media:/data`.
- [ ] **P3.6** Force one run: `kubectl kopiur snapshot now --policy isponsorblocktv -n media --wait`.
- [ ] **P3.7** **The dedup proof.** `kubectl -n media get snapshot <name> -o jsonpath='{.status.stats}'` → `bytesNew` must be **small** (delta only). If `bytesNew` ≈ full PVC size, the identity did not match and a new lineage was started — stop, fix `sourcePathOverride`/identity, and delete the stray snapshot.
- [ ] **P3.8** Adoption proof: the app's previously-`discovered` rows should flip to `origin: adopted` in its own namespace, carrying the policy's config label, and become GFS-governed. Watch for the `SnapshotsAdopted` Normal Event on the `SnapshotPolicy`.
- [ ] **P3.9** Restore drill: scale the app to zero, delete its PVC, let the populator re-provision it from the adopted history, bring the app back, verify data. This is the replacement for `just volsync restore` and must be proven once before the fleet moves.
- [ ] **P3.10** Let it run **at least 24h** (one full retention rotation through the hourly bucket) before Phase 4.

### Phase 4 — fleet rollout (three waves)

One PR per wave; one wave per day minimum, so a wave's first GFS prune is observed before the next starts.

- **Wave A — low blast radius (8):** `recyclarr`, `plex-trakt-sync`, `maintainerr`, `bazarr`, `prowlarr`, `seerr`, `calibre-web-automated`, `paperless-gpt`.
  `calibre-web-automated` is the gid=100 case — check its mover reads the source (a wrong GID surfaces as permission errors in the mover log, not as a silent empty backup).
- **Wave B — media and downloads state (6):** `sonarr`, `radarr`, `qbittorrent`, `jellyfin`, `plex`, `crosswatch`.
  `plex` and `jellyfin` are the 5Gi/high-churn cases — watch the first run's duration and `bytesNew`.
- **Wave C — critical / special (7):** `actual`, `mealie`, `wallos`, `pingvin-share-x`, `pocket-id`, `paperless`, **`backrest`**.
  `pocket-id` gates cluster SSO — a broken restore path here is a bad day. `paperless` is the largest (20Gi) and the only one with a non-default retention. `backrest` is the privileged-mover case (W1) and should go **last**, alone.

Per-app checklist (identical for all 21):
1. `ks.yaml`: component swap + `dependsOn: kopiur-repository`; substitutions unchanged.
2. Namespace `kustomization.yaml`: `components/kopiur-creds` present (once per namespace).
3. Pause/remove the fork `ReplicationSource`.
4. Verify `status.resolved.identity` **before** the first run.
5. `kubectl kopiur snapshot now --policy <app> -n <ns> --wait`, then check `bytesNew`.
6. Confirm `origin: adopted` rows appeared and the discovered rows for that identity are gone.

### Phase 5 — maintenance takeover

Only after **every** app is on kopiur.

- [ ] **P5.1** Delete the fork's maintenance: `kubernetes/apps/volsync-system/volsync/maintenance/` (the `KopiaMaintenance` CR, its ExternalSecret, the tokenless ServiceAccount) — and its `KopiaMaintenanceStale` PrometheusRule alert, which references `job_name=~"kopia-maint-kopia-daily-maintenance-.*"` and will alert forever once the CronJob is gone.
- [ ] **P5.2** Flip `ClusterRepository.spec.maintenance.enabled: true`. kopiur's default schedule is quick every 6h + full daily 03:00 — close to the current `30 */6 * * *`, and strictly better (the current CR runs one pass type only, and its name `kopia-daily-maintenance` has been lying about its 4×/day cadence for months).
- [ ] **P5.3** The kopia-side owner is currently `maintenance@volsync`. With no `identityDefaults.cluster` set, kopiur re-stamps a stale owner **unconditionally** on bootstrap, so this should just work. If `kubectl get maintenance -n kopiur-system` shows `OWNED=false`, set `maintenance.takeoverPolicy: Force` **once**, confirm the claim, then revert it to `Never` — leaving `Force` standing is what makes two owners ping-pong a lease.
- [ ] **P5.4** Verify: `kubectl get maintenance -A` → `OWNED=true`; index-blob count trending **down** over 24-48h (`kubectl get clusterrepository ovh-kopia` has an `IndexBlobs` print column).
- [ ] **P5.5** Add the `verification.quick` tier (`schedule.cron: "H 3 * * *"`) to the component now that maintenance is stable. This closes the "no restore-provability" gap in `docs/areas/volsync-backup`.

### Phase 6 — retire VolSync

- [ ] **P6.1** Delete `kubernetes/apps/volsync-system/volsync/` (operator HelmRelease, OCIRepository, `MutatingAdmissionPolicy` + binding, `PrometheusRule` + `prometheusrule_test.yaml`, GrafanaDashboard + GrafanaFolder).
- [ ] **P6.2** Delete `kubernetes/components/volsync/` and `kubernetes/volsync/mod.just`; drop `mod volsync` from `.justfile`.
- [ ] **P6.3** Move the `kopia` browser UI to `kubernetes/apps/kopiur-system/kopia/` (D5) — HelmRelease, ExternalSecret, HTTPRoute, homepage annotations unchanged. Delete `kubernetes/apps/volsync-system/` and its namespace last.
- [ ] **P6.4** **Never delete the repository Secret / 1Password items.** kopiur reads the same `KOPIA_PASSWORD`. Losing it loses every backup irrecoverably.
- [ ] **P6.5** VolSync CRDs: the chart sets `manageCRDs: true`, so uninstalling the release removes `replicationsources`/`replicationdestinations`/`kopiamaintenances`. **Check first** whether the 22 bound PVCs' stale `dataSourceRef` → `ReplicationDestination` survives CRD removal cleanly (it should — `dataSourceRef` is consulted only at provisioning and PVCs are not re-validated — but a bound PVC referencing a vanished kind is worth confirming on one app before the CRDs go).
- [ ] **P6.6** Add a Just module `kubernetes/kopiur/mod.just` (or fold into `kubernetes/mod.just`) covering the flows the old recipes provided, most of which are now one CLI call:

| old `just volsync` | kopiur replacement |
|---|---|
| `snapshot <rs> <ns>` | `kubectl kopiur snapshot now --policy <app> -n <ns>` |
| `snapshot-all` | a loop, or a `SnapshotSchedule` with `policySelector` |
| `restore <rs> [previous] [ns]` | `kubectl kopiur restore` (source × target matrix) — the wipe Job is no longer needed; `options` covers file deletion |
| `list-snapshots <rs> <ns>` | `kubectl kopiur snapshots list -n <ns>` (richer: origin, kopia id, size) |
| `kopia-maintenance` | `kubectl kopiur maintenance run` |
| `last-snapshots [date]` | keep as a repo-local script over `Snapshot` CRs — no direct CLI equivalent |
| `state suspend\|resume` | `kubectl kopiur suspend\|resume` (declarative `suspend:` on every kind) |

### Phase 7 — documentation and memory

- [ ] `kubernetes/apps/volsync-system/CLAUDE.md` → `kubernetes/apps/kopiur-system/CLAUDE.md`, rewritten.
- [ ] `.claude/skills/volsync/` → `.claude/skills/kopiur/` (SKILL.md + app-integration/operations/platform-policy/validation references). **Also fix the standing defect** recorded in the area-reference: `app-integration.md:20` documents a `VOLSYNC_SCHEDULE` variable that has never existed.
- [ ] Root `CLAUDE.md`: skill list, area-reference table (`docs/areas/volsync-backup` → `docs/areas/kopiur-backup`), the "App PVC backups use the shared `components/volsync/`" line in `kubernetes/CLAUDE.md`.
- [ ] `.claude/skills/just/references/catalog.md`, `k8s-workloads/references/app-scaffolding.md`, `k8s-workloads/SKILL.md`, `sre/references/investigation.md`, `references/role-bundles.md`, `.claude/CLAUDE.md`, `README.md` — all reference volsync.
- [ ] BM: retire `docs/areas/volsync-backup`, author `docs/areas/kopiur-backup`; close this roadmap into `docs/progress/volsync-kopiur-migration`.
- [ ] Renovate: confirm the `kopiur` OCIRepository tag is picked up by the existing custom managers (the repo tracks OCIRepository `ref.tag` today for volsync) and consider an `.renovate/groups.json5` entry so chart and CRDs move together.

---

### Verification matrix

| # | Gate | Command / signal | Pass |
|---|---|---|---|
| V1 | Operator healthy | `kubectl kopiur doctor` | exit 0, `ok repositories ready` |
| V2 | Repository adopted, not created | `kubectl get clusterrepository ovh-kopia` | `Ready`; `status.uniqueId` matches the pre-migration repo |
| V3 | History visible | `kubectl kopiur snapshots list --origin discovered -A` | counts match the P0.2 baseline |
| V4 | Restore from adopted data | throwaway `Restore` | `Completed` |
| V5 | **Identity continuity** | `SnapshotPolicy.status.resolved.identity` | `<app>@<namespace>:/data` |
| V6 | **Dedup working** | `Snapshot.status.stats.bytesNew` | ≪ PVC size |
| V7 | Adoption | `origin: adopted` rows, `SnapshotsAdopted` Event | discovered rows for that identity gone |
| V8 | Bootstrap path | delete PVC → populator re-provisions | app starts with its data |
| V9 | Maintenance owned | `kubectl get maintenance -A` | `OWNED=true` |
| V10 | Index health recovering | `ClusterRepository` `IndexBlobs` column | trending down, well under the warning threshold |
| V11 | Alerting | chart `PrometheusRule` loaded; a deliberately failed snapshot | `KopiurLastBackupFailed` fires |
| V12 | Dashboard | grafana-operator `GrafanaDashboard` in the cluster Grafana | renders |
| V13 | Egress | mover pods reach OVH S3 | no `DROPPED` egress in `just k8s hubble-analyze` |

### Rollback

The migration is reversible at every point up to Phase 6, and the reason is structural: **kopiur and VolSync write the same repository under the same identities**, and kopiur (with no `create` block, `maintenance.enabled: false`, and `Retain`-forced discovered rows) writes nothing until a `SnapshotPolicy` exists.

- **Phases 1-2**: delete the `ClusterRepository` and the HelmRelease. Nothing was written.
- **Phase 3-4, per app**: revert the app's `ks.yaml` to `components/volsync` and unpause its `ReplicationSource`. Kopiur's snapshots are already in the same lineage, so the fork continues from them.
- **Phase 5**: re-apply the fork's `KopiaMaintenance`; set `ClusterRepository.spec.maintenance.enabled: false`.
- **Phase 6 is the point of no return** — do not enter it until every app has completed at least one full backup **and** one restore drill on kopiur.
- **Never** delete the repository password. Both operators read it, and there is no recovery from losing it.

### Gotchas and work items (W)

- [W1] **`backrest` runs the mover as UID 0.** kopiur refuses a privileged mover unless the namespace opts in: `kubectl annotate namespace selfhosted kopiur.home-operations.com/privileged-movers=true` — better, declare the annotation on `kubernetes/apps/selfhosted/namespace.yaml`. Without it the `Snapshot` sits `Pending` with `MoverPermitted=False`. Note this is *more* restrictive than the current plane (the fork's component deliberately omits `runAsNonRoot` precisely because of backrest) — a genuine hardening improvement, but it must be wired before Wave C or backrest silently stops backing up. Consider whether backrest actually needs UID 0, or whether this is the moment to fix that.
- [W2] **AD-023 egress must be re-granted.** Mover pods talk to OVH S3, and `allow-world-egress.yaml` currently grants that via `egress.home.arpa/allow-world: "true"` set through VolSync's `moverPodLabels`. **kopiur has no equivalent field** — no `podLabels` exists anywhere in its CRD surface (verified against `field-reference.md`). The fix is a new `endpointSelector` spec in `allow-world-egress.yaml` matching `app.kubernetes.io/managed-by: kopiur`, which the operator stamps on every mover pod template (`crates/mover/src/jobs.rs`). Narrow it further with `app.kubernetes.io/component` if the label set allows. Confirm live per P0.6 **before** the pilot, or the pilot's first snapshot fails with an opaque S3 timeout. The kopiur **controller** and **webhook** need no world egress — only movers.
- [W3] **`substituteFrom` list replacement.** The root Kustomization patch injects a one-element `postBuild.substituteFrom`. Kustomize replaces the list rather than merging it, so the repository Kustomization **must** carry `substitution.flux.home.arpa/disabled: "true"` or the `kopiur-repo-vars` Secret entry disappears and the `ClusterRepository` renders with literal `${KOPIA_S3_BUCKET}`. First use of that label in this repo — call it out in the platform guide.
- [W4] **Snapshot CR volume.** kopiur keeps one `Snapshot` CR per retained snapshot per source. 21 apps × 34 + paperless × 47 ≈ **760 CRs**, plus discovered rows during the parallel window. Upstream sizes 1-2k CRs as comfortable; on a single-node control plane it is worth watching etcd size once after Wave C. The webhook warns on sub-hourly crons for exactly this reason — do not shorten the cadence.
- [W5] **`H` cron, not `H/N`.** The admission webhook rejects Jenkins step syntax in the hashed field. `H * * * *` and `H */4 * * *` are fine; `H/15 * * * *` is not.
- [W6] **`KopiaMaintenanceStale` has no kopiur equivalent.** The chart's 11 alerts cover backup/restore/repository/controller health but not maintenance staleness. Either re-author it against `kopiur_resource_phase{kind="Maintenance"}` (check the live metric first) or accept `KopiurRepositoryNotReady` + the `IndexBlobs` health surface as the replacement. If re-authored in-repo, the promtool unit-test bar in `docs/decisions/promtool-unit-test-bar` applies (positive + negative + boundary + asserted annotations). Chart-shipped rules are out of scope for that bar.
- [W7] **The `suggestarr@media` orphan.** 5 snapshots from a removed app. It will materialize as a `discovered` row that no policy ever adopts, forever. Either delete it kopia-side before migration (`kopia snapshot delete --all-snapshots-for-source suggestarr@media:/data --delete`) or bound it with `catalog.retain.maxAgeDays`. Leaving it is harmless but noisy.
- [W8] **`catalog.periodicRefresh: true` costs a bootstrap Job per scan.** Useful during the parallel window (it surfaces the fork's fresh snapshots hourly); turn it **off** after Phase 6, or raise `refreshInterval`, so the repository is not re-bootstrapped on a timer forever.
- [W9] **Unmappable fork fields.** None of our 22 apps use `actions.beforeSnapshot`/`afterSnapshot`, `policyConfig`, or `shallow` restore windows — verified against `components/volsync/`. If one is added before the migration completes, note that kopiur `hooks` run in the **workload** pod, not the mover pod, so a fork action does not port verbatim.
- [W10] **CRD upgrade discipline.** `helm upgrade` never touches `crds/`. Flux's `CreateReplace` handles it, but on an alpha operator every version bump deserves a read of `docs/upgrade.md` before merging the Renovate PR — the 0.5.x→0.6.0 crossing cascade-deleted CRs for people who skipped it.
- [W11] **`democratic-csi-local-hostpath` on a single node.** `sourceColocation` defaults to `Auto` and pins the mover to the node holding an RWO PVC — a no-op here, but leave it at the default rather than `Disabled`.
- [W12] **AGPL-3.0.** Irrelevant for in-cluster use; noted for completeness.

### Open questions

- [needs-decision] D1-D6 above — each has a recommendation; none is settled.
- [needs-research] Does the home-operations schema server publish kopiur CRD JSON schemas (P0.5)? Affects the `# yaml-language-server:` convention and any CI validation.
- [needs-research] Does `kopiur_resource_phase{kind="Maintenance"}` exist as a live metric, so W6 can be re-authored rather than dropped?
- [needs-research] Exact `Snapshot`-CR etcd footprint after Wave C on this single-node control plane (W4).
- [needs-decision] Does the kopia browser UI move behind `components/gateway-oidc` during Phase 6 (closing the `docs/areas/volsync-backup` security gap), or does that stay a separate change? Recommendation: separate — one migration at a time.

### Effort

**L — roughly 3-4 focused sessions**, spread over ~2 weeks of calendar time because the waves are deliberately paced:

| Phase | Effort |
|---|---|
| 0 (pre-flight, index fix, CLI, dry-run) | 0.5 session |
| 1-2 (operator + repository adoption + restore proof) | 1 session |
| 3 (component authoring + pilot + restore drill) | 1 session |
| 4 (3 waves × 6-8 apps, mechanical) | 0.5 session + calendar soak |
| 5-6 (maintenance takeover + teardown + Just module) | 0.5 session |
| 7 (docs, skills, BM) | 0.5 session |

Effort is dominated by Phase 3 (getting the component right once) and Phase 7 (the documentation surface is wide — 11 files outside `kubernetes/` mention volsync). Phase 4 is mechanical once Phase 3 is proven.

## Update 2026-08-22 (later) — D0 resolved, reference cross-check, and the repository-topology question

### D0 — RESOLVED: migrate

Decision taken: **we migrate**, on Option 1 (parallel-run pilot → waved rollout). The remaining
decisions D1-D6 stand as written; D7 below is new.

### Reference cross-check — `onedr0p/home-ops`

`onedr0p/home-ops` now runs kopiur in production (`kubernetes/apps/kopiur-system/kopiur/` +
`kubernetes/components/kopiur/`). Read in full on 2026-08-22. It independently confirms most of
the plan's structure, corrects two field names, and — importantly — does **not** answer three of
our decisions, because his install is greenfield while ours is an adoption.

**Confirmed (his layout is effectively the one this plan proposes):**

- `kopiur-system` namespace; `kopiur/ks.yaml` declaring **two** Kustomizations, `kopiur` (the
  operator, `path: .../kopiur/app`) and `kopiur-repository` (`path: .../kopiur/repository`,
  `dependsOn: kopiur`). Identical to the Target-architecture tree above.
- Chart `oci://ghcr.io/home-operations/charts/kopiur`, OCIRepository `ref.tag: 0.10.3`, with the
  same `layerSelector` stanza this repo uses for every chart mirror.
- **`ClusterRepository`, not per-app `Repository`** — D1 confirmed by an independent operator at
  larger app count.
- **ExternalSecret per namespace, delivered as a Kustomize Component** (`components/kopiur/secret`,
  added to each namespace's `kustomization.yaml`) — **not** `credentialProjection`. This is exactly
  the D2 recommendation, including the mechanism (a Component in the namespace kustomization, the
  slot `components/common` occupies here). The operator namespace gets the same Component.
- `components/kopiur/backup` as a Component rendering exactly `snapshotpolicy` + `snapshotschedule`
  + `pvc` + `restore`; per-app wiring is a component reference plus `APP` and a capacity variable
  in `postBuild.substitute` — the same three-line-change contract this repo has today.
- PVC `dataSourceRef` → `kind: Restore`, `apiGroup: kopiur.home-operations.com`; the `Restore`
  uses `target.populator: {}` + `policy.onMissingSnapshot: Continue` + `source.fromPolicy`.
- `SnapshotSchedule.spec.schedule.cron: H * * * *` — D6's cadence, confirmed.
- Monitoring values verbatim as drafted, including
  `monitoring.dashboards.grafanaOperator.matchLabels: {dashboards: grafana}` — the same label this
  cluster's Grafana `instanceSelector` uses, so the dashboard binds with no extra wiring.

**Diverges from this plan, deliberately:**

- `allowedNamespaces: {all: true}`. We keep an explicit four-entry list (D1) — his app count makes
  a list impractical; ours makes it free, and it is the only place the backup plane states who may
  write to it.
- `mover.cache: {mode: Persistent, capacity: <PVC size>, storageClassName: <slow class>}` — a warm
  per-app cache PVC. On this single node with `democratic-csi-local-hostpath` that would put a
  second copy of every cache on the same disk the PVCs live on, for a **3.7 GB** repository
  (measured, below). Keep kopiur's default ephemeral `emptyDir` cache; revisit only if a mover's
  metadata re-download ever shows up as a real cost.
- Controller `podSecurityContext` overridden to UID/GID 1000 + `resources`. The chart's own default
  (`runAsUser: 65534`, `runAsNonRoot`, `readOnlyRootFilesystem`) is already stricter, so keep the
  chart default and set only `resources` — this repo's resource-policy baseline requires explicit
  requests and a memory limit.

**Does NOT answer (his install is greenfield, ours is an adoption):**

- **D3** — he writes `bucket: kopiur` and `endpoint: expanse.internal:9000` in plaintext, but those
  are an internal MinIO hostname and a local bucket name, not an external provider's identifiers.
  He simply does not have this repo's constraint. D3 stays ours to decide.
- **D4** — his PVCs carry no `IfNotPresent` SSA label because he never had a PVC bound to a
  *different* `dataSourceRef`. This confirms the constraint is migration-specific, not a kopiur
  property: greenfield installs never meet it.
- **Identity pinning** — his `SnapshotPolicy` has no `identity` block and no `sourcePathOverride`,
  because a fresh repository has no lineage to continue. **Ours must set
  `sourcePathOverride: /data`** or it silently forks the history. This is the single most important
  difference between his component and ours, and copying his file verbatim would be the classic way
  to lose a year of snapshot history without any error message.

**Corrections to the manifest drafts above:**

- [correction] The compression field is **`spec.compression.compressor`** (a kopia compressor name
  string), **not** `algorithm`. Verified against `field-reference.md` and his manifest.
- [correction] `encryption.passwordSecretRef` takes an optional **`key`** — set it explicitly
  (`key: KOPIA_PASSWORD`) rather than relying on a default.
- [correction] **P0.5 is answered: yes.** The home-operations schema server publishes the kopiur
  CRD schemas — his manifests carry
  `https://k8s-schemas.home-operations.com/kopiur.home-operations.com/<kind>_v1alpha1.json` and they
  resolve. The repo's `# yaml-language-server:` convention applies unchanged.
- [note] He sets `region` even for MinIO (`us-east-1`). The live fork config here has **no** region
  and works against OVH, so adopt without one and add `region: de` only if the bootstrap Job
  complains — a region mismatch on an *adopted* repository is a connect failure, not a data risk.
- [note] His namespace carries `kustomize.toolkit.fluxcd.io/prune: disabled`; worth copying so a
  Kustomization error can never garbage-collect the namespace holding the backup platform.
- [note] He names both the `Restore` and the PVC `${APP}`. This plan keeps `${APP}-bootstrap` for
  the `Restore`, because `dataSourceRef: {kind: Restore, name: <app>}` on a PVC also named `<app>`
  reads ambiguously. Cosmetic; either works.

### D7 — Repository topology: does the NAS belong in the backup path?

New decision, raised 2026-08-22. Kopiur makes this askable for the first time: it supports a
`filesystem` backend with an **inline NFS export** (`backend.filesystem.volume.nfs.{server,path}`,
no PVC required — the shape this repo already uses for every NAS mount), and a
`RepositoryReplication` CR that mirrors a repository's blobs to a second backend on a cron
(`kopia repository sync-to` as a Kubernetes resource). So "back up to the NAS and sync that to S3"
is a first-class option rather than a scripting exercise.

**The measurement that reframes the question.** The entire PVC-backup repository is
**3.7 GB packed** (9.4 GB logical, 55 448 contents, 60.2% compression — `kopia content stats`,
2026-08-22). Not 3.7 GB per app: 3.7 GB for all 22 identities and their full retention window. A
NAS copy therefore costs nothing in space, and — the other direction — the "LAN restores are much
faster" argument is far weaker than it sounds: a single app's restore pulls tens to hundreds of
megabytes from OVH DE, which is minutes, not hours. Restore *latency* is not the problem this
cluster has.

**The existing topology, stated plainly.** Two independent planes, both one-copy-offsite:

| Plane | Source | Destination | Cadence |
|---|---|---|---|
| PVC-level | node-local hostpath PVCs | OVH S3 (kopia) | hourly |
| File-level | NAS `/backups` over NFS | OVH S3 (restic) | daily 01:00 |

The NAS is today a **source** for one plane and absent from the other. It is not a backup
destination for anything.

**Option A — keep S3 as the only repository (status quo, adopted).** Zero extra work; it is what
the in-place adoption gives for free, with history preserved. Remains one copy.

**Option B — NAS primary, S3 mirror** (`filesystem`/NFS repository + `RepositoryReplication` → S3).
This is the shape `rafaribe` and `billimek` run, and it is wrong for *this* cluster for three
independent reasons:

1. **It abandons the adopted repository.** The S3 repository *is* the history. Making the NAS
   primary means either seeding the NAS from S3 (possible — `spec.seed` in migrate mode) or
   starting a fresh lineage. Either way the migration stops being an operator swap and becomes a
   data migration, which is precisely the risk this plan is built to avoid.
2. **Per-app mover UIDs collide with filesystem ownership.** With S3 the mover's write is
   authorized by an access key and is UID-independent. With a filesystem backend the mover writes
   the repository **as its own UID** — and this cluster runs mover UIDs 0, 1000, 10001, and 65532
   because each must be able to read its app's source. A single NFS export writable by all four
   means `all_squash` or world-writable permissions on the NAS: a real hardening regression, traded
   for a latency problem the repository is too small to have. (Both reference repos avoid this by
   normalizing on one UID; this cluster deliberately does not.)
3. **Correlated failure.** The NAS is already the source of the file-level plane. Making it also
   the primary store of PVC backups means one NAS failure simultaneously destroys the primary copy
   of the PVC backups *and* the source data of the other plane. Concentrating both planes on one
   box is the opposite of what a second copy is for.

Additionally it puts the NAS in the **hourly write path**: NAS down at :00 means backups fail,
where today they do not care whether the NAS is up.

**Option C — S3 primary (unchanged), NAS as a mirror** (`RepositoryReplication`, S3 → NFS).
This inverts B and keeps every one of its benefits that actually applies here:

- The write path is untouched — no new SPOF, no per-app UID problem (only the *replication* mover
  writes to the NAS, and it inherits the repository's single `moverDefaults` UID).
- The adoption plan is untouched: the primary stays the repository we already have.
- It delivers the genuine 3-2-1 property — two media, one off-site — and the mirror is
  restore-ready (point a second `Repository` at it) *and* seed-ready (`spec.seed` rebuilds a fresh
  primary from it after a total loss of the OVH side).
- It costs ~4 GB on the NAS and one nightly cron.
- Residual risks: a silently-stale mirror needs its own alert (`status.lastReplicated` staleness),
  and it is one more moving part in an alpha operator.

**What a NAS mirror actually protects against, and the cheaper alternative for part of it.** OVH
object storage does not lose data to disk failure; the realistic threat model is (a) account or
billing loss, (b) credential compromise followed by malicious deletion, and (c) accidental
deletion. A local mirror mitigates all three. But (b) and (c) also have a more targeted answer
that adds no machine: **`ClusterRepository.spec.parameters.blobRetention`** — S3 object lock, which
kopiur exposes declaratively. Worth checking whether OVH Object Storage supports object lock on
this bucket before choosing; note that `COMPLIANCE` mode is an unshortenable storage-cost
commitment (nobody, including the account root, can release it early), so `GOVERNANCE` mode is the
sane starting point if it is available at all. Kopiur's own `deletionProtection` mass-deletion
circuit breaker separately guards against the operator itself doing something catastrophic, and is
on by default.

- **Recommendation: Option A during the migration, Option C afterwards as an explicit follow-up.**
  Adding a second backend while swapping the operator would break the "one variable at a time" rule
  D6 rests on, and would make any post-migration anomaly un-attributable. Sequence it as a
  **Phase 8**, after Phase 6 has proven kopiur alone: add a `RepositoryReplication` mirroring the
  adopted repository to an inline-NFS filesystem backend on the NAS, nightly after the hourly
  backups settle, plus a staleness alert on `status.lastReplicated`. Evaluate `blobRetention`
  independently — it addresses a different failure mode and does not compete with the mirror.
- **Explicitly rejected: Option B.** Not because NAS-primary is a bad pattern in general — it is
  the right pattern in the reference repos — but because this cluster's multi-UID mover fleet, its
  adopted-repository starting point, and the NAS's existing role as the other plane's source all
  point the other way.

## Update 2026-08-22 (third pass) — `bjw-s-labs/home-ops` cross-check

Read in full on 2026-08-22: `kubernetes/apps/system/kopiur/` and `kubernetes/components/kopiur/`,
both at `main` and at the pinned commit `e183e64`. **The two revisions are byte-identical for every
kopiur file**, which is itself a useful signal: this configuration is settled, not still moving.

### Third independent structural confirmation

Everything the onedr0p cross-check confirmed, bjw-s confirms again: the `kopiur/{app,repository}`
split with two Kustomizations (`kopiur-repository` `dependsOn: kopiur`), chart
`oci://ghcr.io/home-operations/charts/kopiur` at `0.10.3` with the same `layerSelector` stanza, a
`ClusterRepository` rather than per-app `Repository` objects, `components/kopiur/{backup,secret}`
with the **secret Component wired into the namespace `kustomization.yaml`** (`downloads` shows it
next to `flux-alerts` and `namespace`), `cron: H * * * *`, PVC `dataSourceRef` → `Restore`, and
`target.populator: {}` + `policy.onMissingSnapshot: Continue`. His HelmRelease `interval: 30m`
matches this repo's convention (onedr0p uses `1h`).

Two independent operators arriving at the same per-namespace-ExternalSecret mechanism settles **D2**
beyond the reasoning already given.

### Adopt from bjw-s — four improvements over the drafts above

- **`identityDefaults` pinned explicitly on the `ClusterRepository`:**

  ```yaml
  identityDefaults:
    hostnameExpr: namespace
    usernameExpr: policyName
  ```

  These CEL expressions resolve to exactly what kopiur would default to anyway — but writing them
  down means a future change to kopiur's implicit defaults cannot silently re-identify the whole
  fleet. For us they evaluate to `<app>@<namespace>`, i.e. precisely the fork's identity, so this is
  free *and* it makes the load-bearing part of the adoption explicit in the manifest instead of
  implicit in the operator. Set it **at creation**: editing `identityDefaults` once consumers have
  history is webhook-rejected (deliberately — it would re-identify every consumer fleet-wide).

- **Verification crons, concrete:** `verification.quick.schedule.cron: H 3 * * *` and
  `verification.deep.schedule.cron: H 5 1 * *` (monthly). This confirms P5.5 and supplies values.
  **Caveat for this cluster:** a `deep` verification is a scratch restore-test, so it provisions a
  throwaway volume sized to the source — for `paperless` that is 20Gi on
  `democratic-csi-local-hostpath`, i.e. real node disk, monthly. Either set
  `moverDefaults.scratch.capacity` deliberately, or enable `deep` only for the small apps and prove
  `paperless` by hand.

- **Rename the substitution surface `VOLSYNC_*` → `KOPIUR_*`.** Both references use `KOPIUR_*`
  (`KOPIUR_CLAIM`, `KOPIUR_CAPACITY`, `KOPIUR_STORAGECLASS`, `KOPIUR_SNAPSHOTCLASS`,
  `KOPIUR_ACCESSMODES`, `KOPIUR_MOVER_UID`/`KOPIUR_MOVER_GID`). This **revises** the earlier
  instruction to "keep every `postBuild.substitute` value byte-identical": keep the **values**
  identical (that is what D6 protects), but rename the **keys**. Every app's `ks.yaml` is being
  edited in Phase 3/4 anyway for the component swap and `dependsOn`, so the marginal cost is zero
  and the names stop lying. Verified safe: `APP_UID`/`APP_GID` are consumed by **nothing** in this
  repo except `components/volsync/replication{source,destination}.yaml`, so the rename touches no
  other component or chart. It also surfaces two dead substitutions to clean up as a follow-up —
  `resticprofile/ks.yaml` and `subsyncarr/ks.yaml` both set `APP_UID`/`APP_GID` with no consumer.

- **`dependsOn` target:** bjw-s points each app at `kopiur` (the operator). This plan points at
  `kopiur-repository`, which transitively depends on `kopiur` and is strictly more correct — a
  `SnapshotPolicy` cannot usefully reconcile until its repository is `Ready`. Keep ours.

### [correction] The bootstrap `Restore` must NOT inherit from the snapshot

The draft above used `Restore.mover.inheritSecurityContextFrom: { snapshot: {} }` for the bootstrap
populator, on the reasoning that a bare-cluster rebuild has no live pod to copy a UID from. **That
is wrong for an adoption**, and bjw-s's explicit form is the correct pattern for us.

`snapshot: {}` replays the identity recorded *on the backup*, decoded from the `kopiur-meta` kopia
tag — a tag **kopiur writes**. Every pre-migration snapshot in our repository was written by
VolSync and carries no such tag, so `status.recorded` is empty for all of them. A `Restore`
resolving one of those would hold indefinitely with `SecurityContextInherited=False` /
`MissingRecordedIdentity` — exactly the disaster-recovery path we most need to work, silently
broken by a field intended to make it more robust.

The fix is bjw-s's: set the UID/GID explicitly from the substitution variables, which are already
per-app values in git and therefore available on a rebuilt cluster:

```yaml
spec:
  mover:
    securityContext:
      runAsUser: ${KOPIUR_MOVER_UID:=10001}
      runAsGroup: ${KOPIUR_MOVER_GID:=10001}
    podSecurityContext:
      fsGroup: ${KOPIUR_MOVER_GID:=10001}
      fsGroupChangePolicy: OnRootMismatch
```

Keep `podSecurityContext.fsGroup` (bjw-s omits it): a freshly-provisioned restore volume is
root-owned `0755`, and the current VolSync `ReplicationDestination` sets `fsGroup` for exactly this
reason. `snapshot: {}` becomes usable later, for snapshots kopiur itself produced — but it must not
be the bootstrap path during and after an adoption.

### Do NOT copy — six items

- **`kopiur.home-operations.com/allow-identity-change: "true"` standing on every `SnapshotPolicy`.**
  bjw-s carries this annotation permanently in his component. It disables the admission guard that
  rejects an identity change on a policy that already has history — which is *the* guard protecting
  an adoption migration from silently forking a lineage and re-uploading every PVC. Whatever made
  it necessary in his repo, for us it must stay **absent**. If a genuine identity change is ever
  needed, add it for that one commit and remove it again.
- **`allowedNamespaces: {all: true}`** — both references use it. We keep the explicit four-entry
  list (D1). Recorded as a deliberate deviation, not a correction of them: their app counts make a
  list impractical, ours makes it free.
- **`mover.cache` with a sized volume + `storageClassName`** — bjw-s uses `mode: Ephemeral` with a
  sized PVC, onedr0p `mode: Persistent`. Either way it means CSI provision/deprovision churn per
  run (22×/hour here) against a **3.7 GB** repository on a single node. Keep kopiur's default
  `emptyDir`.
- **Controller `podSecurityContext` override to UID/GID 1000.** He needs it because his controller
  pod **mounts the NFS repository read-write** (below). With an S3 backend there is no such mount,
  so keep the chart's stricter default (`runAsUser: 65534`, `runAsNonRoot`,
  `readOnlyRootFilesystem`) and set only `resources`.
- **`credentialProjection: {allowed: true}` on the repository** — inert on its own (projection also
  needs the chart's `features.credentialProjection.enabled` *and* a consumer `enabled: true`, and we
  are setting neither). Omit it rather than leave an open gate with no user.
- **Namespace `system`.** bjw-s consolidates platform workloads into one namespace; this repo uses
  per-platform namespaces (`volsync-system`, `external-secrets`, `networking`, …), so
  `kopiur-system` is the consistent choice here.

### D7 — bjw-s runs the rejected topology, and his manifests strengthen the rejection

This is the most valuable thing in the reference, because bjw-s runs exactly **Option B**: a
`ClusterRepository` with `backend.filesystem` on an inline NFS export
(`volume.nfs.{server,path}` → `path: /repo`) on his NAS. Three details of how he makes it work
argue *against* doing the same here rather than for it:

1. **A filesystem backend pulls the NAS into the operator's own dependency path.** His HelmRelease
   mounts the same NFS export into the **controller pod** (`extraVolumes` + `extraVolumeMounts` →
   `/repo`), because for a filesystem backend kopiur can connect in-process instead of only through
   a mover Job. So it is not merely the movers that depend on the NAS being up — the controller
   does. That is a strictly larger blast radius than D7 assumed.
2. **He normalizes UIDs; we deliberately do not.** His controller runs at 1000/1000 with
   `fsGroup: 1000`, his movers default to 2000/2000. One controller UID and one mover UID against
   one export. This cluster runs mover UIDs **0, 1000, 10001 and 65532** because each mover must be
   able to read its own app's source — so a single NFS export would need to be writable by all four.
   His manifests are the concrete demonstration of D7's reason #2, not a counterexample to it.
3. **He has no `RepositoryReplication` and no S3 backend at all** — the NAS repository is his only
   copy. So his choice reads as "the NAS is where my storage is", not "NAS-primary is a better
   durability posture". It is not evidence for moving our off-site copy on-prem.

**D7 recommendation unchanged:** Option A (S3 only) during the migration, Option C (S3 primary +
`RepositoryReplication` mirror to an inline-NFS filesystem backend on the NAS) as an explicit
Phase 8. What the reference *does* add is confidence in the mechanism: the inline-NFS filesystem
backend is proven in production by a reference repo, so the Phase 8 destination is not speculative
— only its direction differs from his.

## Update 2026-08-22 (fourth pass) — D7 resolved

### D7 — RESOLVED: S3 only, unchanged

Decision taken: **Option A**, permanently — the adopted OVH S3 repository stays the single
repository, exactly as it is today. **Option C (a NAS mirror via `RepositoryReplication`) is NOT
scheduled as a Phase 8**; the migration ends at Phase 7.

What this locks in:

- The topology is unchanged by the migration: node-local hostpath PVCs → kopia mover → the same
  OVH S3 bucket, hourly. One repository, one copy, off-site. Kopiur replaces the operator and
  nothing else about where backups live.
- No `filesystem`/NFS backend, no `RepositoryReplication`, no second `ClusterRepository`. The NAS
  keeps its current role — source of the file-level `resticprofile` plane — and stays entirely out
  of the PVC-backup path, including out of the operator's dependency path (the bjw-s cross-check
  showed a filesystem backend also mounts into the controller pod).
- Consequently W2 (mover-pod world egress under a kopiur-shaped `CiliumClusterwideNetworkPolicy`
  selector) stays a **hard prerequisite** of the pilot rather than a detail: S3 is the only backend,
  so a mover with no world egress has nowhere to write.

The residual risk is accepted deliberately and stated here so it is not rediscovered as a surprise:
a single copy at one provider, with no on-prem replica. OVH object storage does not lose data to
disk failure; the accepted exposures are account/billing loss, credential compromise followed by
malicious deletion, and accidental deletion. Two mitigations for the latter two exist **inside** the
S3-only topology and need no new machine or destination, so they remain available without reopening
D7:

- `ClusterRepository.spec.parameters.blobRetention` — S3 object lock, exposed declaratively by
  kopiur. Not adopted now (the decision is "as it is today"); requires checking OVH Object Storage
  object-lock support first, and `GOVERNANCE` mode rather than the unshortenable `COMPLIANCE`.
- Kopiur's `deletionProtection` mass-deletion circuit breaker, which is **on by default** and
  guards against the operator itself pruning a wave of snapshots.

The full Option B / Option C analysis above is retained deliberately: it records why NAS-primary was
rejected on this cluster's specifics (adopted-repository starting point, four distinct mover UIDs,
the NAS's existing role as the other plane's source) and what Option C would look like if the
durability requirement ever changes. It is documentation of a closed decision, not a pending
follow-up.
