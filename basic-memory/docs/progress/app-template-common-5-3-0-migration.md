---
title: app-template-common-5-3-0-migration
type: progress
permalink: home-ops/docs/progress/app-template-common-5-3-0-migration
topic: Upgrade the shared bjw-s app-template chart pin from 5.2.1 to 5.3.0 (which
  bundles common library v5.3.0), gated by a rendered-output diff of pod labels/selectors,
  and decide the follow-on questions the release raises (chart-generated CNP adoption,
  Renovate coverage of the chart pin)
status: done
priority: low
scope: 'One-line pin bump in kubernetes/components/common/repos/app-template/ocirepository.yaml
  affecting all 37 app-template HelmReleases, gated by a helm-render before/after
  diff on representative apps (pod labels, pod selectors, service clusterIP); plus
  two explicitly open follow-on decisions: whether to adopt chart-generated per-app
  CiliumNetworkPolicies via the new controllers option, and whether to bring the chart
  pin under Renovate coverage with a renovate annotation.'
rationale: 'common 5.3.0 changes label/selector rendering semantics: selector labels
  now take precedence over user-configured pod labels, and controller selectors are
  built by a new shared helper that also carries extraSelectorLabels. The repo has
  36 hand-written CiliumNetworkPolicy endpointSelectors that depend on exactly these
  labels, so the bump needs a render-diff gate before it is safe. The release also
  adds CNP controller referencing (directly relevant to the per-app CNP pattern) and
  COMMAND probes, and the chart pin is currently invisible to Renovate, so every future
  bump is manual. No repo value is known to break today, and no 5.3.0 feature has
  a current consumer, hence low priority and proposed (not accepted).'
related_areas:
- k8s-workloads
- networking
options:
- Plain pin bump 5.2.1 -> 5.3.0 with a pre-upgrade render-diff gate (default candidate)
- Pin bump plus a separate follow-on item to adopt chart-generated per-app CNPs (controllers
  option) where the AD-023 label vocabulary is preserved
- Hold at 5.2.1 until a concrete consumer of a 5.3.0 feature appears
created: '2026-10-12'
tags:
- app-template
- bjw-s
- helm
- cilium-networkpolicy
- renovate
---

# Progress — app-template 5.2.1 → 5.3.0 (common 5.3.0) migration

Roadmap item completed 2026-10-13 and moved from `docs/roadmap/app-template-common-5-3-0-migration`.
The pin bump itself was delivered by Renovate PR #4507 (merged 2026-10-10, commit c4519273e) before
this item was executed; this session verified the live result and closed the follow-on questions.

## Metadata (observation-form)

- [status] done — 5.3.0 live on all reconciling app-template releases, no regression found
- [priority] low
- [area] k8s-workloads / networking / versions-renovate
- [created] 2026-10-12
- [completed] 2026-10-13
- [branch] main
- [moved_from] docs/roadmap/app-template-common-5-3-0-migration

## Correction to the roadmap note

- [observation] The roadmap note claimed the chart pin is invisible to Renovate. Wrong: Renovate's built-in `flux` manager (enabled for `kubernetes/**.yaml` in `.renovaterc.json5`) extracts OCIRepository `spec.url` + `ref.tag`. Every app-template bump arrived as a Renovate PR: #4188 (5.0.1→5.1.0), #4376 (5.1.0→5.2.1), #4507 (5.2.1→5.3.0). No `# renovate:` annotation is needed; the Renovate-coverage question is closed with no change.
- [observation] app-template is not automerged (`.renovate/autoMerge.json5`: every rule `automerge: false`); #4507 was merged by hand.

## The release — verified facts (research 2026-10-12)

- [observation] app-template-5.3.0 (2026-10-10, tagged Latest): single changelog entry "Upgraded the common library to v5.3.0". The linked upgrade documentation covers 4-to-5 only; no dedicated 5.2-to-5.3 migration document exists.
- [observation] common-5.3.0 (library chart, 2026-10-10) changelog. Added: controller `extraSelectorLabels` plus a shared controller selector labels helper; direct support for `COMMAND` container probes; templateable annotation/label keys; cilium(Cluster)NetworkPolicy controller referencing (`controllers` option, `fromControllers`/`toControllers` peers, multi-controller targeting by identifier or regex); configurable recursive string template evaluation with path exclusions. Changed: controller selector labels are now used consistently for pod labels and generated pod selectors; improved ciliumNetworkPolicy schema validation. Fixed: ClusterIP is now rendered in LoadBalancer and NodePort Services; resource label merge order; resource annotation merge order. Source: https://github.com/bjw-s-labs/helm-charts/releases/tag/common-5.3.0
- [observation] Selector-label precedence change (the repo-relevant semantic): in common-5.3.0 `templates/lib/pod/metadata/_labels.tpl` merges global labels + user-configured pod labels first, then `mergeOverwrite $labels $selectorLabels` — selector labels take precedence over user pod labels (in-template comment: "Render metadata before merging so templated keys cannot override selector labels"). In common-5.2.1 the same helper merged user-configured pod labels last, so user labels took precedence over selector labels.
- [observation] New helper `bjw-s.common.lib.controller.metadata.selectorLabels` (`templates/lib/controller/metadata/_selectorLabels.tpl`): merges the shared selector labels (`app.kubernetes.io/name`, `app.kubernetes.io/instance`), `app.kubernetes.io/controller`, and controller `extraSelectorLabels` via mergeOverwrite (extras win). This file does not exist at the common-5.2.1 tag. Deployment `spec.selector.matchLabels` is now rendered from this helper; in 5.2.1 the class template assembled `app.kubernetes.io/controller` + selectorLabels inline.
- [observation] CNP controller referencing (`classes/_ciliumNetworkPolicy.tpl` + reworked `schemas/ciliumNetworkPolicy.json`): a policy can set `controllers` (list of identifiers, or regex, resolved via `bjw-s.common.lib.controller.resolveReferences`), a single `controller` shorthand, or nothing — in which case, when no nodeSelector/endpointSelector is set and exactly one controller is enabled, that controller is used by default. Endpoint selection delegates to `bjw-s.common.lib.networkpolicy.controllerSelector` (also accepts `extraSelectorLabels`). Schema rework: rules split into ingress/egress allow/deny definitions, `fromControllers`/`toControllers` peer fields, peer-selector exclusivity constraints, `noIcmpsWithToPorts`.
- [observation] COMMAND probes (`schemas/containers.json`): probe `type` enum is now TCP, HTTP, HTTPS, GRPC, COMMAND, AUTO; `command` is a string array (minItems 1); the description states type defaults to COMMAND when a command is configured, otherwise TCP.
- [observation] Recursive template evaluation (`templates/loader/_generate.tpl`): `global.templateEvaluation.passes` (default 1) and `global.templateEvaluation.excludePaths` (default empty list) drive multi-pass evaluation of the values tree on a deep copy. The common-5.2.1 loader evaluates templates single-pass and has no such options.
- [observation] clusterIP fix (`classes/_service.tpl`): 5.2.1 rendered `clusterIP` only inside the `eq $svcType "ClusterIP"` branch; 5.3.0 renders it for any non-ExternalName type when the option is set.
- [observation] Templateable keys: annotation and label keys support Helm templating (`schemas/definitions.json`).
- [observation] Resource label/annotation merge-order fixes: controller-level and network-policy-level metadata now use `mergeOverwrite` so per-object labels take precedence over chart-level labels (`classes/_deployment.tpl`, `classes/_ciliumNetworkPolicy.tpl`).

## Live verification (2026-10-13)

- [observation] All 15 namespaced `app-template` OCIRepositories store `5.3.0@sha256:0e13b145…`.
- [observation] 35 of 37 app-template HelmReleases report chart 5.3.0; `flux get hr -A --status-selector ready=false` is empty. The 2 others are plex and plex-trakt-sync — suspended, still at chart 5.1.0; both are no longer needed and are to be removed entirely (user decision 2026-10-13, tracked in [[app-template-chart-cnp-migration]]).
- [observation] Render-diff gate, run for the two releases that have not upgraded yet: `helm template` with live HR values, 5.1.0 vs 5.3.0 — the only differences are the `helm.sh/chart` label and the key order inside `spec.selector.matchLabels`. Resuming them is safe with respect to the chart bump (no immutable-selector change).
- [observation] For the upgraded releases the gate is implicit: an upgrade that changed a Deployment `spec.selector` would have failed on the immutable field, and none failed.
- [observation] CNP selector check: every one of the 42 live CNPs' endpointSelectors evaluated against running pods. The 4 without a running match are explained: plex + plex-trakt-sync scaled to 0 (suspended), crowdsec-blocklist-import is a CronJob (its Completed job pod carries all three app.kubernetes.io labels), llama-cpp was mid-rollout (new pod labels match).
- [observation] Hubble policy-denied drops over the 3 days are not attributable to the bump: downloads destination drops started 2026-10-10 19h UTC, before the merge; the ai burst is 2026-10-11 14h (local-ai-stack rollout); selfhosted drops are sporadic. Firing `KubeHpaMaxedOut` alerts date from 2026-10-07.

## Follow-on questions — resolved

- [decision] Render-diff scope: done as above (live-value analysis + plex render-diff); no rendered pod label/selector change for repo values.
- [decision] CNP model: chart-generated per-app CNPs for app-template apps — decided as [[AD-025-app-template-chart-generated-cnps]], executed by [[app-template-chart-cnp-migration]] (docs/roadmap).
- [decision] Renovate coverage: already covered by the flux manager; no change.
- [observation] Other 5.3.0 features (`extraSelectorLabels`, COMMAND probes, `templateEvaluation`, templateable label keys): no consumer in the repo; nothing to do.

## Relations

- relates_to [[k8s-workloads]]
- relates_to [[networking]]
- relates_to [[AD-025-app-template-chart-generated-cnps]]
- relates_to [[app-template-chart-cnp-migration]]
