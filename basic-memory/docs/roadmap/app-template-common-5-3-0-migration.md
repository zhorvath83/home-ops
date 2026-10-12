---
title: app-template-common-5-3-0-migration
type: roadmap
permalink: home-ops/docs/roadmap/app-template-common-5-3-0-migration
topic: Upgrade the shared bjw-s app-template chart pin from 5.2.1 to 5.3.0 (which
  bundles common library v5.3.0), gated by a rendered-output diff of pod labels/selectors,
  and decide the follow-on questions the release raises (chart-generated CNP adoption,
  Renovate coverage of the chart pin)
status: proposed
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

# app-template 5.2.1 → 5.3.0 (common 5.3.0) migration

Migrate the shared bjw-s `app-template` chart pin from 5.2.1 to 5.3.0. app-template 5.3.0
(released 2026-10-10) is a pure library bump — its sole changelog entry is "Upgraded the common
library to v5.3.0" — so everything below is a common-5.3.0 change. The migration itself is a
one-line pin bump, but common 5.3.0 changes label/selector rendering semantics that the repo`s
36 hand-written CiliumNetworkPolicy endpointSelectors depend on, so the bump is gated by a
rendered-output diff. Two follow-on design questions (CNP adoption, Renovate coverage) are
recorded here as open, not decided.

## Metadata (observation-form)

- [topic] app-template 5.2.1 → 5.3.0 pin bump, render-diff gated; CNP adoption + Renovate coverage as open follow-on decisions
- [status] proposed
- [priority] low
- [area] k8s-workloads / networking / versions-renovate
- [created] 2026-10-12
- [effort] S — one-line bump + render-diff verification on representative apps; grows only if the CNP adoption follow-on is pulled into this item

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

## Repo state — verified facts (2026-10-12)

- [observation] The pin is a single tag: `kubernetes/components/common/repos/app-template/ocirepository.yaml:13` — `tag: 5.2.1`. 37 HelmReleases reference app-template through this shared OCIRepository.
- [observation] The pin is NOT covered by Renovate: the OCI customManager regex (`.renovate/customManagers.json5:11`) matches only `oci://...:<value>` URL shapes; the OCIRepository URL is tagless (the version lives in `ref.tag`) and the file carries no `# renovate:` annotation. The 5.3.0 bump must therefore be made manually — no Renovate PR will arrive for it.
- [observation] 36 standalone CiliumNetworkPolicy manifest files exist; endpointSelector label usage: `app.kubernetes.io/name` (36), `app.kubernetes.io/instance` (21), `app.kubernetes.io/controller` (16). No HelmRelease uses chart-level `networkpolicies`/`ciliumNetworkPolicies` values today — all per-app CNPs are hand-written manifests.
- [observation] Pod-level labels set in HelmRelease values use only custom keys (`ingress.home.arpa/*`, `egress.home.arpa/*` — e.g. homepage, actual); no HR overrides an `app.kubernetes.io/*` label. The selector-label precedence change therefore has no known collision in current values — but this is value analysis, not a rendered diff; the render-diff gate stays.
- [observation] No app uses `globalLabels` anywhere.
- [observation] LoadBalancer services under app-template apps: plex and k8s-gateway; neither sets the `clusterIP` option, so the clusterIP rendering fix has no visible effect on current values.
- [observation] No COMMAND probe consumer today: qbittorrent (the app whose probe config was inspected) uses tcpSocket probes; the `exec:` occurrences found in app-template apps are lifecycle hooks, not probes.
- [observation] Every app-template HelmRelease carries a yaml-language-server schema comment pointing at the main-branch app-template schema, which already tracks 5.3.0 shapes.

## Open design questions (to elaborate before moving to accepted)

- [question] Render-diff scope: which apps get a helm-template before/after comparison (candidates by shape: homepage — extra custom pod labels; plex — LoadBalancer service; a CronJob-based app such as crowdsec-blocklist-import; one plain Deployment). Unverified until run: whether any rendered pod labels/selectors actually change for repo values.
- [question] CNP model: keep the standalone per-app CNP manifest pattern, or migrate some/all apps to chart-generated `ciliumNetworkPolicies` values using the new `controllers` option? Whichever wins, the AD-023 label vocabulary (`ingress.home.arpa/*`, `egress.home.arpa/*`) and the custom-egress opt-out model must be preserved — this is a design decision, potentially its own ADR.
- [question] Renovate coverage: add a `# renovate:` annotation (docker datasource, depName `ghcr.io/bjw-s-labs/helm/app-template`) to the OCIRepository `ref.tag` so future chart bumps arrive as PRs instead of manual pin edits?
- [question] Any consumer for the other 5.3.0 features (`extraSelectorLabels`, COMMAND probes, `templateEvaluation` passes, templateable label keys)? None found in the repo today.

## Relations

- relates_to [[k8s-workloads]]
- relates_to [[networking]]
