---
title: renovate-config-modernization
type: note
permalink: home-ops/docs/roadmap/renovate-config-modernization
tags:
- renovate
- roadmap
- config
- survey
---

# Renovate Config Modernization Roadmap

## Status: draft
## Status: in-progress
## Priority: medium
## Area: renovate
## Implementation started: 2025-05-25

### Completed changes:
- Removed :separatePatchReleases from .renovaterc.json5 extends
- Removed minimumReleaseAge and minimumReleaseAgeBehaviour from root config
- Changed rebaseWhen from "conflicted" to "auto"
- Added commitBodyTable: true and prEditedNotification to suppressNotifications
- Restructured autoMerge.json5: removed global Helm automerge, added selective kube-prometheus-stack rule, added GitHub Actions automerge (3d + fast-track), removed redundant automergeType
- Replaced 6 label rules (renovate/image + dep/*) with 8 composable rules (type/* + renovate/*) in overrides.json5
- Added 5 Renovate labels to .github/labels.yaml (renovate/container, renovate/helm, renovate/github-action, renovate/github-release, renovate/talos)

### Deferred:
- home-operations/renovate-presets adoption (revisit after current changes stabilize)
- Grafana dashboard manager (add when repo has GrafanaDashboard CRs)
- platformAutomerge (only meaningful with PR-based automerge)
- helpers:pinGitHubActionDigestsToSemver upgrade
## Priority: medium
## Area: renovate

## Survey Date: 2025-05-25

## Reference Repos Surveyed

| Repo | Shared Preset | Local Fragments |
|------|--------------|-----------------|
| buroa/k8s-gitops | home-operations/renovate-presets#1.3.1 | autoMerge, groups, labels |
| szinn/k8s-homelab | home-operations/renovate-presets#1.3.1 | allowedVersions, autoMerge, clusters, customManagers, disabledDatasources, grafanaDashboards, groups, labels, overrides, packageRules, semantic-commits |
| billimek/k8s-gitops | None (fully local) | allowedVersions, autoMerge, customManagers, grafanaDashboards, overrides, groups, labels, semanticCommits |
| onedr0p/home-ops | home-operations/renovate-presets#1.3.1 | None (all inline in root) |
| heavybullets8/heavy-ops | None (fully local) | autoMerge, customManagers, grafanaDashboards, groups, labels, minecraft, packageRules, semanticCommits |
| bjw-s-labs/home-ops | bjw-s/renovate-config (personal shared preset) | autoMerge, customManagers, grafanaDashboards, groups, overrides |

## Our Current State

Fully local config: .renovaterc.json5 + 9 fragments (allowedVersions, autoMerge, customManagers, disabledDatasources, groups, overrides, prBodyNotes, semanticCommits, talosFactory).

---

## Comparison Table: Base Presets

| Setting | buroa | szinn | billimek | onedr0p | heavybullets | bjw-s-labs | zhorvath83 | Consensus |
|---------|-------|-------|----------|---------|-------------|------------|------------|------------|
| config:recommended | via preset | via preset | explicit | via preset | explicit | via preset | explicit | ALL |
| docker:enableMajor | via preset | via preset | explicit | via preset | explicit | via preset | explicit | ALL |
| :disableRateLimiting | via preset | via preset | explicit | via preset | explicit | via preset | explicit | ALL |
| :dependencyDashboard | via preset | via preset | explicit | via preset | explicit | via preset | explicit | ALL |
| :semanticCommits | via preset | via preset | explicit | via preset | explicit | via preset | explicit | ALL |
| :automergeBranch | via preset | via preset | explicit | via preset | explicit | via preset | explicit | ALL |
| :separatePatchReleases | NO | NO | NO | NO | NO | NO | YES | ONLY us |
| :enablePreCommit | NO | NO | NO | via preset | YES | via preset | YES | 3/7 |
| helpers:pinGitHubActionDigests | toSemver | toSemver | digests | toSemver | digests | digests | digests | Mix |
| platformAutomerge | NO | NO | YES | NO | NO | YES | NO | 2/7 |
| commitBodyTable | NO | NO | NO | NO | NO | YES | NO | 1/7 |
| minimumReleaseAge | NO | NO | NO | NO | NO | NO | 3 days | ONLY us |
| rebaseWhen | auto | default | auto | auto | default | auto | conflicted | conflicted is safest |

## Comparison Table: Automerge

| Feature | buroa | szinn | billimek | onedr0p | heavybullets | bjw-s-labs | zhorvath83 | Gap? |
|---------|-------|-------|----------|---------|-------------|------------|------------|------|
| Trusted container digests | pr | branch | pr (scheduled) | pr | pr | branch | branch | OK |
| Trusted container minor/patch | NO | NO | pr (per-app) | NO | NO | pr (select) | branch (prefix) | OK |
| Helm chart minor/patch | NO | NO | NO | NO | NO | NO | branch | UNIQUE — evaluate risk |
| GitHub Actions | branch, 3d | branch, 3d | pr, 3d | branch, 3d | branch, 3d | NO | branch | OK |
| Trusted GH Actions fast (1min) | YES | YES | NO | YES | NO | NO | NO | GAP |
| Grafana dashboards | branch | branch | branch | branch | branch | branch | NONE | GAP — add manager + automerge |
| Renovate Presents | branch | branch | NO | branch | NO | NO | NONE | GAP — add if adopting shared preset |

## Comparison Table: Custom Managers

| Manager | buroa | szinn | billimek | onedr0p | heavybullets | bjw-s-labs | zhorvath83 | Gap? |
|--------|-------|-------|----------|---------|-------------|------------|------------|------|
| Annotated deps (# renovate:) | preset | preset | local | preset | local | preset | local | OK |
| OCI refs | preset | local | NO | preset | local | local | local | OK |
| Talos Factory | preset | NO | NO | preset | NO | NO | local | OK |
| Grafana dashboards | preset | local | local | preset | local | local | NONE | GAP |
| CNPG imageName/reference | preset | NO | NO | preset | local (imageName) | NO | NONE | GAP — if using CNPG |
| GitHub raw URLs | NO | local | local | NO | NO | preset | NO | LOW |
| registry.k8s.io images | NO | NO | NO | NO | NO | NO | local | UNIQUE — keep |
| Inline YAML annotations | NO | NO | local | NO | NO | NO | NO | LOW |

## Comparison Table: Groups

| Group | buroa | szinn | billimek | onedr0p | heavybullets | bjw-s-labs | zhorvath83 | Note |
|-------|-------|-------|----------|---------|-------------|------------|------------|------|
| Kubernetes (5 images) | YES | YES | YES | YES | NO | YES | YES (4) | Ours excludes kube-proxy |
| Flux Operator | YES | YES | YES | YES | YES | YES | YES | OK |
| 1Password | NO | YES | YES | NO | YES | YES | YES | OK |
| Cilium | NO | NO | YES | NO | YES | NO | YES | OK |
| cert-manager | NO | NO | YES | NO | YES | NO | YES | OK |
| External Secrets | NO | NO | YES | NO | YES | NO | YES | OK |
| Prometheus stack | NO | NO | NO | NO | NO | NO | YES | UNIQUE |
| Envoy Gateway | NO | NO | NO | NO | NO | NO | YES | UNIQUE |
| Talos | NO | YES | YES | NO | NO | YES | YES (custom datasource) | OK |
| Rook-Ceph | YES | YES | YES | YES | NO | NO | NO | N/A for us |

## Comparison Table: Labels

| Pattern | buroa | szinn | billimek | onedr0p | heavybullets | bjw-s-labs | zhorvath83 |
|---------|-------|-------|----------|---------|-------------|------------|------------|
| type/major, type/minor, type/patch, type/digest | YES | YES | YES | YES | YES | YES | NO |
| renovate/container | YES | YES | YES | YES | YES | YES | YES (via datasource) |
| renovate/helm | YES | YES | YES | YES | YES | YES | YES (via datasource) |
| renovate/github-action | YES | YES | YES | YES | YES | YES | YES (via manager) |
| renovate/github-release | YES | YES | YES | YES | YES | YES | YES (via datasource) |
| dep/major, dep/minor, dep/patch | NO | NO | NO | NO | NO | NO | YES (unique) |
| renovate/image | NO | NO | NO | NO | NO | NO | YES (unique) |

## Comparison Table: Semantic Commits

All repos use nearly identical semantic commit patterns. Our config aligns with the community consensus. Minor difference: szinn has more granular per-datasource/per-manager rules; our config has helmfile and pre-commit scopes that others lack.

## Comparison Table: Special Features

| Feature | buroa | szinn | billimek | onedr0p | heavybullets | bjw-s-labs | zhorvath83 | Recommendation |
|---------|-------|-------|----------|---------|-------------|------------|------------|----------------|
| registryAliases (mirror.gcr.io) | preset | root | NO | preset | NO | NO | root | OK |
| minimumReleaseAge | NO | NO | NO | NO | NO | NO | 3 days | Consider removing |
| pinDigests: false selective | NO | YES | NO | NO | NO | NO | NO | CONSIDER |
| separateMinorPatch (Helm) | NO | YES (select) | NO | NO | NO | NO | YES | OK |
| ignoreDeprecated (Helm) | NO | NO | NO | NO | NO | NO | YES | Good practice |
| prBodyNotes (changelog links) | NO | NO | NO | YES | NO | NO | YES | CONSIDER migrating to changelogUrl |
| changelogUrl overrides | preset | NO | NO | preset | NO | NO | NO | Adopt with shared preset |
| helmfile .gotmpl pattern | preset | NO | NO | preset | NO | NO | YES (.yaml only) | GAP — add .gotmpl/.j2 |
| Renovate config automerge | YES | YES | NO | YES | NO | NO | NO | ADD with shared preset |
| Docker pinDigests variant | toSemver | pin | pin | toSemver | pin | pin | pin | CONSIDER upgrading to toSemver |

---

## Recommendations (Priority Order)

### P1 - High Impact, Community Aligned

1. **Adopt home-operations/renovate-presets shared preset** (3/6 reference repos). Eliminates duplicated local configs (annotated manager, OCI manager, CNPG manager, semantic commits, helmfile override, changelogs). Keep local fragments for repo-specific needs (autoMerge, groups, overrides, allowedVersions, prBodyNotes, talosFactory).
   - Effort: Medium
   - Risk: Low (version-pinned)

2. **Add Grafana Dashboard custom datasource and manager** (5/6 repos have it). If we deploy Grafana dashboards, this auto-updates them.
   - Effort: Small
   - Risk: None

3. **Add GitHub Actions trusted fast-track automerge** (3/6). Automerge actions/* and renovatebot/* with 1-minute minimumReleaseAge.
   - Effort: Small
   - Risk: Low

4. **Add Renovate Presents automerge**. If adopting shared preset, add automerge for renovate-config manager updates.
   - Effort: Small
   - Risk: None

### P2 - Medium Impact, Polish

5. **Migrate prBodyNotes changelog links to changelogUrl**. The shared preset uses native Renovate changelogUrl field. More maintainable and better PR rendering.
   - Effort: Small
   - Risk: Low

6. **Add selective pinDigests: false**. For packages that do not publish digests (siderolabs/installer, siderolabs/kubelet, siderolabs/talosctl, flux-manifests).
   - Effort: Small
   - Risk: Low

7. **Upgrade helpers:pinGitHubActionDigests to helpers:pinGitHubActionDigestsToSemver** (3/6 use toSemver). Produces cleaner action pinning.
   - Effort: Small
   - Risk: Low (verify all actions support semver)

8. **Extend helmfile managerFilePatterns**. Add .gotmpl and .j2 patterns.
   - Effort: Small
   - Risk: None

### P3 - Low Impact, Consider

9. **Remove :separatePatchReleases from extends**. Only we use this. It increases dashboard noise.
   - Effort: Small
   - Risk: Medium (changes PR behavior)

10. **Re-evaluate minimumReleaseAge: 3 days**. Only we use this. Consider removing or reducing, relying on automerge schedules instead.
    - Effort: Small
    - Risk: Medium (changes update cadence)

11. **Consider removing Helm auto-merge (minor/patch)**. No other repo automerges ALL Helm chart minor/patch. Chart value changes can break things.
    - Effort: Small
    - Risk: Medium (changes review workflow)

12. **Align label pattern with community**. Switch from dep/major+renovate/image to type/major+renovate/container.
    - Effort: Small
    - Risk: Low (cosmetic, may affect dashboard filters)

---

## Kubernetes Group: Image List

Our Kubernetes group has 4 images (kube-apiserver, kube-controller-manager, kube-scheduler, kubelet) with minimumGroupSize=4. Community consensus is 5 images including kube-proxy with minimumGroupSize=5. We intentionally exclude kube-proxy because we run it via Cilium helm values, not as a standalone workload. This is correct for our setup.

## CNPG Manager Decision

The CNPG custom manager (detecting imageName and reference fields) is in the shared preset and used by 3/6 repos. Add only if we deploy CloudNativePG clusters.

## Key Observations

- No other repo automerges ALL Helm chart minor/patch updates. This is unique to our config and carries risk.
- Our :separatePatchReleases preset is unique. It increases granularity but also dashboard noise.
- Our minimumReleaseAge: 3 days is unique. Others rely on automerge schedules for throttling.
- Our rebaseWhen: conflicted is the safest setting. Some use auto which can cause unnecessary rebases.
- The community is converging on home-operations/renovate-presets as the standard starting point.

## Relations

- implements [[AD-020-renovate-cloud-fragments]]
- relates_to [[docs/areas/flux-gitops]]
- relates_to [[docs/areas/k8s-workloads]]
