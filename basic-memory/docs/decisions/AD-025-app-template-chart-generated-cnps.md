---
title: AD-025-app-template-chart-generated-cnps
type: decision
permalink: home-ops/docs/decisions/ad-025-app-template-chart-generated-cnps
decision_id: AD-025
topic: Chart-generated per-app CiliumNetworkPolicies for app-template apps
status: active
decided_at: '2026-10-13'
decision: For bjw-s app-template workloads the per-app CNP is declared as HelmRelease
  values.networkpolicies.main (type cilium) and rendered by the chart, with the endpointSelector
  derived from the controller; AD-023 semantics, the label vocabulary and the clusterwide
  CCNPs are unchanged; non-app-template workloads keep hand-written CNPs. Migration
  is additive->retire per batch (rename to -legacy, add chart policy, delete legacy).
rationale: Removes the rename-desync trap (#4132) by deriving the selector from release+controller,
  co-locates vocabulary labels and app-unique rules in one file, moves validation
  to chart-schema render time (flux-local test), and deletes 19 manifest files with
  no new machinery.
tradeoffs: 'Two CNP carriers coexist along the chart boundary; app-template bumps
  become security-relevant (mitigated: no automerge + flux-local diff on PRs); chart
  schema allows one peer kind per rule; cross-release peers stay raw matchLabels;
  tree grep no longer finds every per-app CNP.'
related_areas:
- networking
- k8s-workloads
tags:
- cilium-networkpolicy
- app-template
- bjw-s
- ad-023
---

# AD-025 — Chart-generated per-app CiliumNetworkPolicies for app-template apps

## Metadata (observation-form, schema validation)

- [decision_id] AD-025
- [status] active
- [decided_at] 2026-10-13
- [topic] Carrier of per-app CNPs for bjw-s app-template workloads: chart-generated via HelmRelease `networkpolicies` values instead of standalone manifest files

## Context

- [observation] AD-023 decides WHAT the per-app CNPs contain (app-unique content only: narrow-world toFQDNs, named east-west consumers, LB fromCIDR, LAN exceptions) and keeps generic grants in the 7-label vocabulary + clusterwide CCNPs. It does not decide the CARRIER; today every per-app CNP is a hand-written `app/ciliumnetworkpolicy.yaml`.
- [observation] 19 app-template apps carry a hand-written CNP (actual, backrest, calibre-web-automated, cloudflare-tunnel, crowdsec-blocklist-import, homepage, jellyfin, llama-cpp, paperless, paperless-gpt, plex, plex-trakt-sync, pocket-id, prowlarr, qbittorrent, radarr, resticprofile, sonarr, sure); 17 non-app-template CNP files exist (ESO, envoy-gateway, crowdsec, grafana, kube-prometheus-stack, tuppr, …). No HelmRelease used chart-level `networkpolicies` before this decision. plex and plex-trakt-sync are slated for full removal (user decision 2026-10-13), so 17 apps migrate.
- [observation] The hand-written endpointSelector duplicates labels the chart derives from the release name and controller key; a HelmRelease or controller rename moves the pod label while the CNP stays behind and silently drops traffic — the #4132 trap recorded in `docs/areas/k8s-workloads`.
- [observation] common 5.3.0 (app-template 5.3.0, live since 2026-10-10 via #4507) renders CNPs from `networkpolicies.<id>` with `type: cilium` and derives the endpointSelector from the controller selector labels (`app.kubernetes.io/{name,instance,controller}`). Verified by `helm template` against the pulled 5.3.0 chart (digest sha256:0e13b145…ff63a), 2026-10-13: rule field contents are passed through verbatim (toFQDNs, toEntities kube-apiserver, fromCIDR/toCIDRSet, toServices, L7 `toPorts[].rules.dns` all render); a plex-trakt-sync render reproduced the live hand-written CNP spec rule-for-rule under the same name.

## Decision

- [decision] For bjw-s app-template workloads, the per-app CNP is declared in the HelmRelease as `values.networkpolicies.main` with `type: cilium` and rendered by the chart. The standalone `app/ciliumnetworkpolicy.yaml` is not used for these apps.
- [decision] AD-023 semantics are unchanged: the 7-label vocabulary stays in `defaultPodOptions.labels` (or controller pod labels) and the generic grants stay in the hand-written clusterwide CCNPs under `kubernetes/apps/kube-system/cilium/netpols/`. Only app-unique rules go into `networkpolicies.main`; a vocabulary grant is never duplicated into a chart policy.
- [decision] Selector: omit `controller` for single-controller apps (the chart auto-selects the only enabled controller); set `controller: <key>` or `controllers: [..]` explicitly when the release has more than one controller (paperless: `controller: paperless`; sure: `controllers: [server, worker]`). A raw `endpointSelector` is not used.
- [decision] Peers: same-release sibling controllers use `fromControllers` / `toControllers`; cross-release and cross-namespace peers stay raw `fromEndpoints` / `toEndpoints` matchLabels with `k8s:io.kubernetes.pod.namespace`.
- [decision] Naming: exactly one entry (`main`) per release, so the rendered name equals the release name — identical to today's CNP names. No `forceRename`.
- [decision] Scope: non-app-template workloads (upstream charts, operators, platform) keep hand-written CNP manifests. New app-template apps adopt the chart-generated form from the start.
- [decision] Comments: the AD-023 one-line intent comment moves from the CNP file header onto the `networkpolicies:` block; per-rule WHY comments stay terse, per the inline comment policy.

## Rationale

- [observation] The selector becomes a function of the release and controller: a rename can no longer desynchronise the policy from its pods (removes the #4132 class instead of guarding it by convention).
- [observation] Co-location: the pod's vocabulary labels and its app-unique rules live in one file, so the full network posture of an app is reviewable in one place.
- [observation] Validation moves earlier: the chart schema (rule items `additionalProperties: false`, policy `unevaluatedProperties: false`) fails `helm template`, which `flux-local test` runs in CI on every PR.
- [observation] Net reduction: 19 manifest files and 19 kustomization entries removed; no new machinery.

## Tradeoffs

- [observation] Two carriers coexist repo-wide (chart-generated for app-template, hand-written for the rest). Accepted: the split follows the chart boundary, which is mechanical and readable.
- [observation] A chart bump can change rendered security policy (common 5.3.0 itself reworked the CNP schema). Mitigation, both verified 2026-10-13: Renovate does not automerge app-template (`.renovate/autoMerge.json5` — every rule `automerge: false`), and the `flux-local diff` job posts the rendered HelmRelease diff on each PR, so a CNP change surfaces in review. Every app-template bump is therefore reviewed as a security-relevant change.
- [observation] Chart-imposed constraints: one peer kind per rule (`toEndpoints` + `toFQDNs` in one rule is rejected — split into two rules, which is equivalent Cilium semantics); `icmps` and `toPorts` cannot share a rule; rule fields outside the schema list are rejected. Schema errors surface as an opaque `'oneOf' failed … value must be 'native'` message.
- [observation] The hand-written name-only selectors (cloudflare-tunnel, crowdsec-blocklist-import, sure) become name+instance+controller selectors — equivalent for the pods they select today (verified live 2026-10-13: crowdsec-blocklist-import job pods carry all three labels); sure becomes a `controller In [server, worker]` matchExpression.
- [observation] `grep kind: CiliumNetworkPolicy` no longer finds every per-app policy in the tree; audits use the live cluster (`just k8s show-cnp-matrix` reads live CNPs) or `networkpolicies:` in HelmReleases.
- [observation] Cross-release peers gain nothing (still raw matchLabels) and remain exposed to the #4132 trap on the PEER side.

## Migration constraint (load-bearing)

- [observation] The chart-rendered CNP has the same name as the Flux-Kustomization-owned hand-written one. Replacing them in one commit races: kustomize-controller prunes the old object before helm-controller creates the new one (policy gap — fail-closed on egress, fail-OPEN on ingress for the 9 apps whose CNP carries ingress rules: cloudflare-tunnel, jellyfin, llama-cpp, paperless, plex, prowlarr, qbittorrent, radarr, sonarr), and if Helm runs first it refuses to take over an object it does not own.
- [decision] Therefore the migration runs per batch in 2 commits, retire → add: (1) delete the hand-written CNP files and their kustomization entries (Flux prunes them); (2) add `networkpolicies.main` to the HelmReleases (Helm creates the CNPs under the freed names). Retiring first avoids the Helm ownership conflict. A short CNP-less window between the two reconciles is ACCEPTED (user decision 2026-10-13): egress fails closed to the baseline/vocabulary grants, ingress falls back to the vocabulary CCNPs. Rollback = revert. After step 2: `just k8s show-cnp-matrix` + a Hubble DROPPED capture for the batch pods. Execution plan: [[app-template-chart-cnp-migration]].

## Related

- refines [[AD-023-cnp-threat-model-audit]]
- relates_to [[app-template-chart-cnp-migration]]
- relates_to [[app-template-common-5-3-0-migration]]
- relates_to [[k8s-workloads]]
- relates_to [[networking]]

## Update 2026-10-13 — execution findings

- [observation] Executed for all 17 apps on 2026-10-13 in 3 batches (progress: [[docs/progress/app-template-chart-cnp-migration]]); no hand-written CNP remains under an app-template app.
- [observation] Values shape: the rule arrays sit directly under `networkpolicies.main` (`ingress:` / `egress:`); a `rules:` key is rejected by the 5.3.0 schema (`unevaluatedProperties: false`) with the opaque `'oneOf' failed` error. `policyTypes` belongs to the native type only.
- [correction] The CNP-less window was fail-CLOSED on ingress too, not fail-open: the gateway vocabulary CCNPs already select the ingress-bearing pods for ingress, so peers listed only in the retired CNP were dropped (measured batch 2: radarr/sonarr->qbittorrent, bazarr/seerr->radarr/sonarr, paperless-gpt->paperless, until the chart CNPs appeared). The fail-OPEN wording in the Migration constraint above is superseded by this.
- [observation] Windows measured: batch 1 ~8 min, batch 2 ~3 min, batch 3 ~30 s (Flux prune -> Helm create); every HubblePolicyDeny drop stopped once the chart-rendered CNP existed.
