---
title: app-template-chart-cnp-migration
type: roadmap
permalink: home-ops/docs/roadmap/app-template-chart-cnp-migration
topic: Migrate the 19 app-template per-app CNPs from hand-written manifests to chart-generated
  networkpolicies values (AD-025), additive->retire per batch
status: accepted
priority: medium
scope: 19 app-template apps in 3 batches; plex and plex-trakt-sync deferred until
  their HelmReleases are resumed; non-app-template CNPs out of scope.
rationale: AD-025 decided the carrier change; this item executes it without a policy
  gap.
related_areas:
- k8s-workloads
- networking
created: '2026-10-13'
tags:
- cilium-networkpolicy
- app-template
- ad-025
---

# app-template chart-generated CNP migration (AD-025 execution)

Execute AD-025: move the per-app CiliumNetworkPolicy of the app-template apps from hand-written
`app/ciliumnetworkpolicy.yaml` files into HelmRelease `values.networkpolicies.main`, without a
policy gap, in batches of additive → retire commits.

## Metadata (observation-form)

- [topic] Migrate 19 app-template per-app CNPs to chart-generated networkpolicies (AD-025)
- [status] accepted
- [priority] medium
- [area] k8s-workloads / networking
- [created] 2026-10-13
- [effort] M — 3 commits per batch, 3 batches, Hubble verification per batch

## Inventory (verified against the repo 2026-10-13)

- [observation] Egress-only CNPs (no ingress rules — a gap would be fail-closed): actual, backrest, calibre-web-automated, crowdsec-blocklist-import, homepage, paperless-gpt, pocket-id, resticprofile, sure (plus plex-trakt-sync — out of scope, see below).
- [observation] CNPs with ingress rules (a gap would be fail-OPEN): cloudflare-tunnel, jellyfin, llama-cpp, paperless, prowlarr, qbittorrent, radarr, sonarr (plus plex — out of scope, see below).
- [observation] Multi-controller releases: paperless (controllers paperless, backup — the CNP selects only paperless → `controller: paperless`); sure (server, worker — the CNP selects both via name only → `controllers: [server, worker]`).
- [observation] Name-only selectors today: cloudflare-tunnel, crowdsec-blocklist-import, sure — the chart renders name+instance+controller (equivalent for the pods selected today).
- [decision] plex and plex-trakt-sync are OUT of scope: both HelmReleases (suspended, chart 5.1.0) are no longer needed and are to be removed entirely — HR, ks.yaml, CNP, ExternalSecret, PVC/VolSync wiring and namespace registration (user decision 2026-10-13). The removal is a separate task; their CNP files go with the apps, not through this migration. Scope is therefore 17 apps.

## Batches

- [decision] Batch 1 — egress-only, single controller: actual, backrest, calibre-web-automated, crowdsec-blocklist-import, homepage, paperless-gpt, pocket-id, resticprofile. Lowest risk; proves the procedure.
- [decision] Batch 2 — ingress-bearing + multi-controller: jellyfin, llama-cpp, prowlarr, qbittorrent, radarr, sonarr, paperless, sure.
- [decision] Batch 3 — cloudflare-tunnel alone (edge path; CIDR + endpoint rules).

## Procedure per batch (3 commits, each pushed and reconciled before the next)

1. **Rename** — in every batch CNP file set `metadata.name: <app>-legacy`. Kustomize applies the new object before pruning the old one, so the union is continuous. Check: `kubectl get cnp -A | grep legacy` lists the batch, the old names are gone.
2. **Add** — add `networkpolicies.main` (`type: cilium`, rules copied 1:1, split any rule that mixes peer kinds) to each HelmRelease; keep the AD-023 intent comment on the block. Local gates: `helm template` of each release with the 5.3.0 chart, a diff of the rendered CNP spec against the legacy file (only the selector shape may differ), pre-commit. Check after reconcile: each HR Ready, `kubectl get cnp -n <ns> <app>` exists and is Valid, legacy still present.
3. **Retire** — delete the `ciliumnetworkpolicy.yaml` files and their `app/kustomization.yaml` entries. Check: legacy objects pruned.

After steps 2 and 3: `just k8s show-cnp-matrix` (each batch app shows its APP-CNP under the release name) + `just k8s hubble-live-capture 120` and `just k8s hubble-analyze <app label> DROPPED egress|ingress` for the batch pods; a startup-time app-log check for the narrow-world apps. Rollback at any step = a single revert.

## Acceptance criteria

- [criterion] No `ciliumnetworkpolicy.yaml` remains under an app-template app (plex and plex-trakt-sync excluded — removed with the apps).
- [criterion] Every migrated app has exactly one live CNP named after its release, owned by Helm (`app.kubernetes.io/managed-by: Helm`).
- [criterion] `flux-local test` green on every PR/commit; zero new policy-denied DROPPED flows attributable to a batch app.
- [criterion] k8s-workloads skill scaffolding reference and the `docs/areas/k8s-workloads` canonical app shape updated to the chart-generated form (separate docs commit).

## Related

- implements [[AD-025-app-template-chart-generated-cnps]]
- relates_to [[AD-023-cnp-threat-model-audit]]
- relates_to [[k8s-workloads]]
- relates_to [[networking]]
