---
title: external-secrets
type: area_reference
permalink: home-ops/docs/areas/external-secrets
area: external-secrets
status: current
confidence: high
verified_at: '2026-05-23'
summary: External Secrets Operator (ESO) plus 1Password Connect delivers all app-level
  runtime secrets. Two Flux Kustomizations under `kubernetes/apps/external-secrets/`
  layer the platform — `external-secrets` (operator) and `onepassword-connect` (Connect
  server plus the cluster-wide `ClusterSecretStore/onepassword-connect`). The store
  is the single integration point — every app ExternalSecret references it. Bootstrap-time
  Connect credentials come from 1Password via `op inject` on `resources.yaml.j2`.
verified_against:
- kubernetes/apps/external-secrets/kustomization.yaml
- kubernetes/apps/external-secrets/namespace.yaml
- kubernetes/apps/external-secrets/external-secrets/ks.yaml
- kubernetes/apps/external-secrets/external-secrets/app/helmrelease.yaml
- kubernetes/apps/external-secrets/external-secrets/app/ocirepository.yaml
- kubernetes/apps/external-secrets/onepassword-connect/ks.yaml
- kubernetes/apps/external-secrets/onepassword-connect/app/helmrelease.yaml
- kubernetes/apps/external-secrets/onepassword-connect/app/clustersecretstore.yaml
- kubernetes/apps/external-secrets/onepassword-connect/app/externalsecret.yaml
- kubernetes/apps/external-secrets/onepassword-connect/app/ocirepository.yaml
- kubernetes/apps/external-secrets/CLAUDE.md
- kubernetes/bootstrap/resources.yaml.j2
- kubernetes/bootstrap/mod.just
- kubernetes/mod.just
- .claude/skills/external-secrets/references/platform-topology.md
drift_risk: Bootstrap secret key names (`onepassword-connect-credentials-secret`,
  `onepassword-connect-vault-secret`) must stay in sync between `resources.yaml.j2`,
  the HelmRelease `credentialsName`, and the ClusterSecretStore `connectTokenSecretRef`
  — renaming any of them breaks the bootstrap chain. The vault name `HomeOps` and
  the 1Password item ID `1password-connect-kubernetes` are hardcoded across both layers.
  Connect runs with UID/GID 999 (upstream-specific) and an `emptyDir` working volume;
  rotation of the token requires a Pod restart, currently triggered by the Reloader
  annotation on the `connect` Deployment.
tags:
- area-reference
- external-secrets
- platform
---

# external-secrets — current state

## Metadata (observation-form, schema validation)

- [area] external-secrets
- [status] current
- [confidence] high
- [verified_at] 2026-05-19

## Summary

The cluster uses External Secrets Operator (ESO) as the only standard pathway to deliver app-level runtime secrets, backed by 1Password as the upstream store via the 1Password Connect server. The platform is split into two Flux Kustomizations under `kubernetes/apps/external-secrets/`:

- `external-secrets` deploys the operator (controller + cert-controller + webhook).
- `onepassword-connect` deploys the Connect server **and** the single cluster-wide `ClusterSecretStore/onepassword-connect` in the same Kustomization, with a CEL health-check expression that blocks dependents until the store reports `Ready=True`.

Bootstrap-time secrets that ESO itself depends on (Connect credentials + access token) are injected from 1Password via `op inject` against `kubernetes/bootstrap/resources.yaml.j2` during `just cluster-bootstrap cluster`. After bootstrap, ESO takes over and the Connect-issued ExternalSecrets re-own those same Secret names (`creationPolicy: Owner`) so the credentials self-rotate from 1Password going forward. The helmfile onepassword-connect release also has a postsync hook that waits for the ESO CRD (`clustersecretstores.external-secrets.io`) before applying the ClusterSecretStore manifest — this prevents a CR-before-CRD race during the bootstrap apps stage.

## Components

- [component] external-secrets operator — HelmRelease in namespace `external-secrets`, chart `ghcr.io/external-secrets/charts/external-secrets` tag 2.5.0 via OCIRepository, `installCRDs: true`, ServiceMonitor + Grafana dashboard enabled (external-secrets/app/helmrelease.yaml, external-secrets/app/ocirepository.yaml)
- [component] 1Password Connect — HelmRelease in namespace `external-secrets`, chart `oci://ghcr.io/1password/connect` tag 2.4.1, two containers `api` (port 8080) and `sync`, Reloader auto annotation, `credentialsName: onepassword-connect-credentials-secret` (onepassword-connect/app/helmrelease.yaml, onepassword-connect/app/ocirepository.yaml)
- [component] ClusterSecretStore/onepassword-connect — single cluster-wide store, points at `http://onepassword-connect.external-secrets.svc.cluster.local:8080`, vault `HomeOps`, token from Secret `onepassword-connect-vault-secret` key `token` (onepassword-connect/app/clustersecretstore.yaml)
- [component] ExternalSecret `onepassword-connect-credentials` — re-renders `1password-credentials.json` into Secret `onepassword-connect-credentials` from 1P item `1password-connect-kubernetes` (onepassword-connect/app/externalsecret.yaml:1-21)
- [component] ExternalSecret `onepassword-connect-token` — re-renders `token` into Secret `onepassword-connect-token` from the same 1P item (onepassword-connect/app/externalsecret.yaml:22-40)
- [component] Bootstrap shim — `kubernetes/bootstrap/resources.yaml.j2` ships placeholder Secrets `onepassword-connect-credentials-secret` and `onepassword-connect-vault-secret` in namespace `external-secrets`, rendered via `op inject` during the `just cluster-bootstrap cluster` chain (kubernetes/bootstrap/resources.yaml.j2, kubernetes/bootstrap/mod.just `resources` stage)
- [component] Namespace marker — `kubernetes/apps/external-secrets/namespace.yaml` defines `metadata.name: _` with `kustomize.toolkit.fluxcd.io/prune: disabled`; the actual namespace name comes from the Flux Kustomization `spec.targetNamespace`. All namespaces use the `_` placeholder pattern (2026-05-23)
- [component] flux-alerts component — pulled in via `kubernetes/apps/external-secrets/kustomization.yaml` `components` (per-namespace Pushover Alert+Provider+ExternalSecret bundle)
- [component] Operational just recipe — `just k8s sync-es <name> <ns>` annotates an ExternalSecret with `force-sync=$(date +%s)` to trigger an out-of-band refresh (kubernetes/mod.just)

## Claims (verified against repo)

- [claim] "The platform deploys two Flux Kustomizations: `external-secrets` (operator) and `onepassword-connect` (Connect server + ClusterSecretStore), wired through `kubernetes/apps/external-secrets/kustomization.yaml`" (evidence: repo, ref: kubernetes/apps/external-secrets/kustomization.yaml:5-9, verified: 2026-05-19)
- [claim] "`onepassword-connect` Kustomization `dependsOn` `external-secrets` and has both a HelmRelease health check and a CEL-based `ClusterSecretStore Ready` healthCheckExpr — dependents on `onepassword-connect` block until the store is Ready" (evidence: repo, ref: onepassword-connect/ks.yaml:11-25, verified: 2026-05-19)
- [claim] "The single cluster-wide store is named `onepassword-connect` (kind `ClusterSecretStore`); every app ExternalSecret references it via `secretStoreRef.kind=ClusterSecretStore` + `secretStoreRef.name=onepassword-connect`" (evidence: repo, ref: onepassword-connect/app/clustersecretstore.yaml:5-18 + kubernetes/apps/external-secrets/CLAUDE.md:50-51, verified: 2026-05-19)
- [claim] "The ClusterSecretStore targets vault `HomeOps` over plain HTTP at `http://onepassword-connect.external-secrets.svc.cluster.local:8080` and authenticates with Secret `onepassword-connect-vault-secret` key `token` in namespace `external-secrets`" (evidence: repo, ref: onepassword-connect/app/clustersecretstore.yaml:8-18, verified: 2026-05-19)
- [claim] "1Password Connect HelmRelease pins `credentialsName: onepassword-connect-credentials-secret` — this is the Secret name both bootstrap (`resources.yaml.j2`) and the runtime ExternalSecret (`onepassword-connect-credentials`) must produce/maintain" (evidence: repo, ref: onepassword-connect/app/helmrelease.yaml:37 + kubernetes/bootstrap/resources.yaml.j2:1-12, verified: 2026-05-19)
- [claim] "Bootstrap-time Connect Secrets (`onepassword-connect-credentials-secret` and `onepassword-connect-vault-secret`) reference 1P paths `op://HomeOps/1password-connect-kubernetes/credentials` and `op://HomeOps/1password-connect-kubernetes/token` and are rendered via `op inject` in the bootstrap `resources` stage" (evidence: repo, ref: kubernetes/bootstrap/resources.yaml.j2:1-21 + kubernetes/bootstrap/mod.just `resources` stage, verified: 2026-05-19)
- [claim] "Both runtime ExternalSecrets (`onepassword-connect-credentials` and `onepassword-connect-token`) extract from 1P item `1password-connect-kubernetes` with `creationPolicy: Owner`, so post-bootstrap they re-own the same Secret names previously seeded by `op inject`" (evidence: repo, ref: onepassword-connect/app/externalsecret.yaml:18-21 + :37-39, verified: 2026-05-19)
- [claim] "The helmfile onepassword-connect release postsync hook explicitly waits for the ESO CRD `clustersecretstores.external-secrets.io` before applying the ClusterSecretStore manifest, preventing CR-before-CRD race during bootstrap (onedr0p pattern: needs chain ordering + explicit CRD wait as belt-and-suspenders)" (evidence: repo, ref: kubernetes/bootstrap/helmfile.d/01-apps.yaml:84-105, verified: 2026-05-23)
- [claim] "External Secrets operator chart `ghcr.io/external-secrets/charts/external-secrets` pinned at tag 2.5.0, with `installCRDs: true` and ServiceMonitor enabled across controller, certController, and webhook" (evidence: repo, ref: external-secrets/app/ocirepository.yaml:12-14 + external-secrets/app/helmrelease.yaml:16-49, verified: 2026-05-19)
- [claim] "1Password Connect chart `oci://ghcr.io/1password/connect` pinned at tag 2.4.1; chart-default security context (seccompProfile=RuntimeDefault, runAsNonRoot, readOnlyRootFilesystem, drop ALL caps, UID/GID 999) is intentionally left unchanged" (evidence: repo, ref: onepassword-connect/app/ocirepository.yaml:12-14 + onepassword-connect/app/helmrelease.yaml:13-14 + kubernetes/apps/external-secrets/CLAUDE.md:32-44, verified: 2026-05-19)
- [claim] "Cross-app ExternalSecret pattern: `spec.refreshInterval: 12h` (vs chart default 1h), `secretStoreRef.kind: ClusterSecretStore`, `secretStoreRef.name: onepassword-connect`, `target.creationPolicy: Owner`, no `metadata.namespace` (the Flux Kustomization `spec.targetNamespace` places the ES at apply time)" (evidence: repo, ref: kubernetes/apps/external-secrets/CLAUDE.md:46-58, verified: 2026-05-19)
- [claim] "Operational recipe `just k8s sync-es <name> <ns>` triggers an out-of-band ExternalSecret refresh by annotating with `force-sync=$(date +%s)` via the flux-client-side-apply field manager" (evidence: repo, ref: kubernetes/mod.just (sync-es recipe), verified: 2026-05-19)
- [claim] "The `external-secrets` namespace also gets the shared Pushover `flux-alerts` component via `kubernetes/apps/external-secrets/kustomization.yaml` components list — so reconciliation failures here surface through the same Pushover channel as the rest of the cluster" (evidence: repo, ref: kubernetes/apps/external-secrets/kustomization.yaml:10-11, verified: 2026-05-19)

## Drift Risk

- [drift] The bootstrap secret names `onepassword-connect-credentials-secret` and `onepassword-connect-vault-secret` are duplicated across `kubernetes/bootstrap/resources.yaml.j2`, the HelmRelease `credentialsName`, the ClusterSecretStore `connectTokenSecretRef`, and the post-bootstrap ExternalSecrets — renaming any of them silently breaks bootstrap or the post-bootstrap re-ownership flow. No automated check exists; the relationship is documented only in `kubernetes/apps/external-secrets/CLAUDE.md`.
- [drift] Vault name `HomeOps` and the 1Password item ID `1password-connect-kubernetes` are hardcoded in both the ClusterSecretStore spec and `resources.yaml.j2`. Any 1P-side rename requires a coordinated change in both places.
- [drift] 1Password Connect runs with UID/GID 999 (upstream-specific) and uses an `emptyDir` for working data; chart upgrades that change either are silent breaks. The CLAUDE.md guide for this subtree explicitly calls this out.
- [drift] The bootstrap Connect token is **issued out-of-band** at 1Password Connect provisioning time and **does not auto-rotate**. Rotation requires manual re-issue in 1Password, then a Pod restart of the Connect Deployment (handled by the Reloader annotation when the runtime Secret `onepassword-connect-token` changes).
- [drift] OCIRepository tag pins (operator `2.5.0`, Connect `2.4.1`) are Renovate-tracked but **no inline `# renovate:` annotations** are present in the OCIRepository files. Confirm that Renovate's chart datasource picks them up automatically before assuming version updates are tracked.

## Open Questions / Gaps

- [gap] No verification was run against the live cluster in this pass — claims about `Ready=True` semantics and live token rotation behavior are repo-evidence only. Use `.claude/skills/external-secrets/references/validation.md` for live-state validation.
- [gap] The relationship between the cluster-wide `onepassword-connect` store and any app-local `SecretStore` (none currently declared, but the ESO CRD allows it) was not traced — assume "cluster store is the only path" until proven otherwise.
- [gap] The Pushover/flux-alerts cross-tie deserves its own review under the flux-gitops area; that note already flags a gap on how Pushover credentials flow.

## Relations

- depends_on [[talos-cluster]]
- relates_to [[flux-gitops]]
- relates_to [[volsync-backup]]
- relates_to [[k8s-workloads]]
- part_of [[home-ops-platform]]

## dependsOn Convention for ExternalSecret-bearing Kustomizations

Any Flux Kustomization that contains an ExternalSecret manifest MUST declare `dependsOn` on the ks that gates on the referenced ClusterSecretStore Ready. Today every ExternalSecret in the cluster references `ClusterSecretStore/onepassword-connect`, so the rule simplifies to: every ExternalSecret-bearing ks must transitively dependsOn the `onepassword-connect` ks in namespace `external-secrets`.

Two intentional exceptions:

1. **`onepassword-connect` itself** — it creates the ClusterSecretStore and its own ExternalSecrets (credentials + token) use bootstrap-time `op inject` to break the chicken-and-egg cycle. Adding a dependsOn back to itself would deadlock.

2. **`flux-instance`** — contains a GitHub webhook ExternalSecret referencing ClusterSecretStore/onepassword-connect, but deliberately does NOT declare dependsOn onepassword-connect. This matches the bjw-s reference cluster pattern. Rationale: adding the dependency couples FluxInstance reconciliation to CSS availability, removing flux-instance as a fallback early-boot path. The ESO retry-loop on the github-webhook-token ExternalSecret is benign — it converges once the CSS becomes Ready. Bootstrap already sequences ESO + 1Password Connect before Flux Instance (see helmfile.d/01-apps.yaml).

Additionally, 2 component-level ExternalSecrets (pushover and github alerts in `components/common/alerts/`) reference ClusterSecretStore/onepassword-connect but are applied at the cluster-apps Kustomization level, not as individual ks resources. They are implicitly sequenced by the Flux boot chain.

Audit result (2026-05-23): 18 app-level + 2 component-level ExternalSecret manifests surveyed (20 total). 16 ks-es declare dependsOn onepassword-connect. `onepassword-connect` is the bootstrap exception (N/A). `flux-instance` is intentionally exempt (bjw-s parity, retry-loop convergence is acceptable). Component-level ExternalSecrets are implicitly covered by the Flux boot chain. No gaps remain.

- [claim] "Every Flux Kustomization that contains an ExternalSecret manifest must transitively dependsOn the ks that gates on the referenced ClusterSecretStore Ready — for the current cluster, that ks is onepassword-connect in namespace external-secrets — with two intentional exceptions: onepassword-connect itself (bootstrap chicken-and-egg) and flux-instance (bjw-s parity, retry-loop convergence is acceptable for the github-webhook-token ExternalSecret)." (evidence: repo audit of 20 ExternalSecret manifests, ref: kubernetes/apps/flux-system/flux-instance/ks.yaml + bjw-s reference cluster, verified: 2026-05-23)
