---
title: external-secrets
type: area_reference
permalink: home-ops/docs/areas/external-secrets
area: external-secrets
status: current
confidence: high
verified_at: '2026-08-03'
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
- kubernetes/bootstrap/helmfile.d/01-apps.yaml
- kubernetes/apps/external-secrets/kustomization.yaml
- kubernetes/apps/external-secrets/external-secrets/app/kustomization.yaml
- kubernetes/apps/external-secrets/external-secrets/app/ciliumnetworkpolicy.yaml
- kubernetes/apps/external-secrets/external-secrets/app/grafanadashboard.yaml
- kubernetes/apps/external-secrets/external-secrets/app/grafanafolder.yaml
- kubernetes/apps/external-secrets/onepassword-connect/app/kustomization.yaml
- kubernetes/apps/external-secrets/onepassword-connect/app/ciliumnetworkpolicy.yaml
- kubernetes/components/common/kustomization.yaml
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
- [verified_at] 2026-08-03

## Summary

The cluster uses External Secrets Operator (ESO) as the only standard pathway to deliver app-level runtime secrets, backed by 1Password as the upstream store via the 1Password Connect server. The platform is split into two Flux Kustomizations under `kubernetes/apps/external-secrets/`:

- `external-secrets` deploys the operator (controller + cert-controller + webhook).
- `onepassword-connect` deploys the Connect server **and** the single cluster-wide `ClusterSecretStore/onepassword-connect` in the same Kustomization, with a CEL health-check expression that blocks dependents until the store reports `Ready=True`.

Bootstrap-time secrets that ESO itself depends on (Connect credentials + access token) are injected from 1Password via `op inject` against `kubernetes/bootstrap/resources.yaml.j2` during `just cluster-bootstrap cluster`. After bootstrap, ESO takes over and the Connect-issued ExternalSecrets re-own those same Secret names (`creationPolicy: Owner`) so the credentials self-rotate from 1Password going forward. The helmfile onepassword-connect release also has a postsync hook that waits for the ESO CRD (`clustersecretstores.external-secrets.io`) before applying the ClusterSecretStore manifest — this prevents a CR-before-CRD race during the bootstrap apps stage.

## Components

- [component] external-secrets operator — HelmRelease in namespace `external-secrets`, chart `ghcr.io/external-secrets/charts/external-secrets` via OCIRepository (tag `2.8.0`), `installCRDs: true`, ServiceMonitor + Grafana dashboard enabled at chart level, plus the consumer CRs `grafanadashboard.yaml` (reads the chart-emitted `external-secrets-dashboard` ConfigMap) and `grafanafolder.yaml` (`folderRef: external-secrets`) (external-secrets/app/helmrelease.yaml, ocirepository.yaml, grafanadashboard.yaml, grafanafolder.yaml, kustomization.yaml)
- [component] 1Password Connect — HelmRelease in namespace `external-secrets`, chart `oci://ghcr.io/1password/connect` (tag `2.4.1`), two containers `api` (port 8080) and `sync`, Reloader auto annotation, `credentialsName: onepassword-connect-credentials-secret`, and a `postRenderers` kustomize patch that sets `automountServiceAccountToken: false` on the rendered Deployment — Connect serves ESO from its local cache and never calls the Kubernetes API, so the projected SA token is dropped (onepassword-connect/app/helmrelease.yaml:45-59, onepassword-connect/app/ocirepository.yaml, onepassword-connect/app/kustomization.yaml)
- [component] ClusterSecretStore/onepassword-connect — single cluster-wide store, points at `http://onepassword-connect.external-secrets.svc.cluster.local:8080`, vault `HomeOps`, token from Secret `onepassword-connect-vault-secret` key `token` (onepassword-connect/app/clustersecretstore.yaml)
- [component] ExternalSecret `onepassword-connect-credentials` — re-renders `1password-credentials.json` into Secret `onepassword-connect-credentials` from 1P item `1password-connect-kubernetes` (onepassword-connect/app/externalsecret.yaml:1-21)
- [component] ExternalSecret `onepassword-connect-token` — re-renders `token` into Secret `onepassword-connect-token` from the same 1P item (onepassword-connect/app/externalsecret.yaml:22-40)
- [component] Bootstrap shim — `kubernetes/bootstrap/resources.yaml.j2` ships placeholder Secrets `onepassword-connect-credentials-secret` and `onepassword-connect-vault-secret` in namespace `external-secrets`, rendered via `op inject` during the `just cluster-bootstrap cluster` chain (kubernetes/bootstrap/resources.yaml.j2, kubernetes/bootstrap/mod.just `resources` stage)
- [component] Namespace marker — `kubernetes/apps/external-secrets/namespace.yaml` defines `metadata.name: _` with `kustomize.toolkit.fluxcd.io/prune: disabled`; the actual namespace name comes from the Flux Kustomization `spec.targetNamespace`. All namespaces use the `_` placeholder pattern (2026-05-23)
- [component] common components umbrella — `kubernetes/apps/external-secrets/kustomization.yaml:6-7` lists ONE component, `../../components/common`, which itself aggregates `./alerts`, `./repos` and `./vars`. The Flux `type:alertmanager` Provider/Alert therefore reaches this namespace TRANSITIVELY (components/common -> alerts -> alertmanager), not as a directly-listed alertmanager component
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
- [claim] "External Secrets operator chart `ghcr.io/external-secrets/charts/external-secrets` pinned, with `installCRDs: true` and ServiceMonitor enabled across controller, certController, and webhook" (evidence: repo, ref: external-secrets/app/ocirepository.yaml:12-14 + external-secrets/app/helmrelease.yaml:16-49, verified: 2026-05-19)
- [claim] "1Password Connect chart `oci://ghcr.io/1password/connect` pinned; chart-default security context (seccompProfile=RuntimeDefault, runAsNonRoot, readOnlyRootFilesystem, drop ALL caps, UID/GID 999) is intentionally left unchanged" (evidence: repo, ref: onepassword-connect/app/ocirepository.yaml:12-14 + onepassword-connect/app/helmrelease.yaml:13-14 + kubernetes/apps/external-secrets/CLAUDE.md:32-44, verified: 2026-05-19)
- [claim] "Cross-app ExternalSecret pattern: `spec.refreshInterval: 12h` (vs chart default 1h), `secretStoreRef.kind: ClusterSecretStore`, `secretStoreRef.name: onepassword-connect`, `target.creationPolicy: Owner`, no `metadata.namespace` (the Flux Kustomization `spec.targetNamespace` places the ES at apply time)" (evidence: repo, ref: kubernetes/apps/external-secrets/CLAUDE.md:46-58, verified: 2026-05-19)
- [claim] "Operational recipe `just k8s sync-es <name> <ns>` triggers an out-of-band ExternalSecret refresh by annotating with `force-sync=$(date +%s)` via the flux-client-side-apply field manager" (evidence: repo, ref: kubernetes/mod.just (sync-es recipe), verified: 2026-05-19)
- [claim] "The `external-secrets` namespace reaches the shared alertmanager alerting plane TRANSITIVELY: `kubernetes/apps/external-secrets/kustomization.yaml:6-7` lists only `../../components/common`, and that umbrella Component aggregates `./alerts` which in turn contains `./alertmanager`. Reconciliation failures here surface through the in-cluster Alertmanager (Flux type:alertmanager Provider), the same channel as the rest of the cluster" (evidence: repo, ref: kubernetes/apps/external-secrets/kustomization.yaml:6-7 + kubernetes/components/common/kustomization.yaml + components/common/alerts/kustomization.yaml, verified: 2026-08-03)

## Drift Risk

- [drift] The bootstrap secret names `onepassword-connect-credentials-secret` and `onepassword-connect-vault-secret` are duplicated across `kubernetes/bootstrap/resources.yaml.j2`, the HelmRelease `credentialsName`, the ClusterSecretStore `connectTokenSecretRef`, and the post-bootstrap ExternalSecrets — renaming any of them silently breaks bootstrap or the post-bootstrap re-ownership flow. No automated check exists; the relationship is documented only in `kubernetes/apps/external-secrets/CLAUDE.md`.
- [drift] Vault name `HomeOps` and the 1Password item ID `1password-connect-kubernetes` are hardcoded in both the ClusterSecretStore spec and `resources.yaml.j2`. Any 1P-side rename requires a coordinated change in both places.
- [drift] 1Password Connect runs with UID/GID 999 (upstream-specific) and uses an `emptyDir` for working data; chart upgrades that change either are silent breaks. The CLAUDE.md guide for this subtree explicitly calls this out.
- [drift] The bootstrap Connect token is **issued out-of-band** at 1Password Connect provisioning time and **does not auto-rotate**. Rotation requires manual re-issue in 1Password, then a Pod restart of the Connect Deployment (handled by the Reloader annotation when the runtime Secret `onepassword-connect-token` changes).
- [drift] OCIRepository tag pins (operator + Connect) are Renovate-tracked but **no inline `# renovate:` annotations** are present in the OCIRepository files. Confirm that Renovate's chart datasource picks them up automatically before assuming version updates are tracked.

## Open Questions / Gaps

- [gap] No verification was run against the live cluster in this pass — claims about `Ready=True` semantics and live token rotation behavior are repo-evidence only. Use `.claude/skills/external-secrets/references/validation.md` for live-state validation.
- [gap] The relationship between the cluster-wide `onepassword-connect` store and any app-local `SecretStore` (none currently declared, but the ESO CRD allows it) was not traced — assume "cluster store is the only path" until proven otherwise.
- [gap] (Resolved 2026-07-05) Pushover credentials flow through the observability `alertmanager` ExternalSecret (1Password `pushover` item); the flux-gitops area documents the unified type:alertmanager Provider model.

## Network Containment (per AD-023, added 2026-06-22)

- [observation] [current] onepassword-connect carries a per-app CiliumNetworkPolicy declaring TWO things only: ingress from external-secrets (ESO) on 8080 (ciliumnetworkpolicy.yaml:13-21) and egress restricted via `toFQDNs` to `1password.com` + `1passwordusercontent.com` (ciliumnetworkpolicy.yaml:22-31). Prometheus scrape is NOT in this CNP — it rides the cluster-wide `ingress-from-prometheus` CCNP, opted into by the pod label `ingress.home.arpa/allow-prometheus: "true"` (helmrelease.yaml:18). Kubelet probes take the local-host fast-path (no explicit rule). The pod opts out of the baseline egress with `egress.home.arpa/custom-egress: "true"`. Verified live (DROPPED-clean, store Valid, sync complete)
- [observation] [prerequisite] this requires CoreDNS `autopath` to be disabled — autopath rewrites query names and Cilium cannot correlate them to toFQDNs (see AD-023)
- [observation] [current] external-secrets (ESO controller + webhook + cert-controller) carry per-component no-world CNPs (`external-secrets/app/ciliumnetworkpolicy.yaml`, commit 76ea396c9, 2026-06-24): egress in-cluster only — controller→onepassword-connect:8080 + kube-apiserver:6443, cert-controller→kube-apiserver:6443, webhook initiates nothing; DNS via the cluster-wide allow-dns-egress CCNP; world denied. All three pods carry the `egress.home.arpa/custom-egress: "true"` opt-out label (HelmRelease podLabels, same commit). The webhook ingress allows `kube-apiserver` explicitly on 10250/8081 (failurePolicy=Fail admission, not host fast-path). Allowlists derived from a live Hubble capture. Live-verified 2026-06-24: all 3 CNP Valid, controller egress no-world (connect:8080 + apiserver:6443 + DNS), cert-controller/webhook DROPPED-clean, webhook admission proven via server dry-run, store Valid, all ExternalSecrets SecretSynced. Expect a ~25s startup-transient "no route to host" to the connect ClusterIP on every no-world pod restart (socketLB endpoint-programming lag, self-heals). See roadmap cnp-per-app-audit Phase 2b
- relates_to [[AD-023-cnp-threat-model-audit]]
- relates_to [[cnp-per-app-audit]]

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

Additionally there are 3 component-level ExternalSecrets — `components/common/alerts/github/externalsecret.yaml`, `components/gateway-oidc/externalsecret.yaml` and `components/volsync/externalsecret.yaml` — which reference ClusterSecretStore/onepassword-connect but are applied through the component mechanism rather than as individual ks resources. They are implicitly sequenced by the Flux boot chain. Pushover is NOT among them: it is an app-level ExternalSecret in `kubernetes/apps/observability/kube-prometheus-stack/app/externalsecret.yaml` (1Password key `pushover`).

Audit result (re-measured 2026-08-03): **23 app-level files carrying 24 ExternalSecret objects** under `kubernetes/apps`, plus **3 component-level** ones (github alerts, gateway-oidc, volsync). **31 `ks.yaml` files reference `name: onepassword-connect`** — 30 consumers plus the store's own ks. `onepassword-connect` is the bootstrap exception (N/A). `flux-instance` is intentionally exempt (bjw-s parity, retry-loop convergence is acceptable). ES-bearing Kustomizations without a direct `dependsOn` (e.g. crowdsec-bouncer, crowdsec-web-ui) reach the store transitively through their parent (`crowdsec/ks.yaml` declares it). Component-level ExternalSecrets are implicitly covered by the Flux boot chain. **No gaps remain** — the conclusion from the 2026-05-23 pass still holds; only the counts moved (app-level 18 -> 23 files, dependsOn 16 -> ~30).

- [claim] "Every Flux Kustomization that contains an ExternalSecret manifest must transitively dependsOn the ks that gates on the referenced ClusterSecretStore Ready — for the current cluster, that ks is onepassword-connect in namespace external-secrets — with two intentional exceptions: onepassword-connect itself (bootstrap chicken-and-egg) and flux-instance (bjw-s parity, retry-loop convergence is acceptable for the github-webhook-token ExternalSecret)." (evidence: repo audit of 20 ExternalSecret manifests, ref: kubernetes/apps/flux-system/flux-instance/ks.yaml + bjw-s reference cluster, verified: 2026-05-23)

## Update 2026-08-03 — staleness re-verification

Full re-verification against the live repo as part of the `area-reference-staleness-audit`
roadmap item. Previous `verified_at` was 2026-05-23. Verdict: MINOR-DRIFT — this note held up
structurally (every `verified_against` path still existed, the whole `summary` was accurate,
22 claims re-verified true). Corrections were factual details, not architecture.

- [correction] The note claimed "2 component-level ExternalSecrets (pushover and github)". Pushover
  is NOT component-level — it is an app-level ES in observability/kube-prometheus-stack, exactly as
  this note's own 2026-07-05 gap-resolution already said. The note contradicted itself. There are
  THREE component-level ES: github alerts, gateway-oidc, volsync.
- [correction] The dependsOn audit numbers were a 2026-05-23 snapshot and had grown: app-level ES
  18 -> 23 files (24 objects), component-level 2 -> 3, ks files referencing onepassword-connect
  16 -> 31 (30 consumers + the store's own ks). Re-measured today. The CONCLUSION (no gaps,
  transitive coverage holds, flux-instance intentionally exempt) still stands — only the counts moved.
- [correction] The alertmanager wiring was described as a directly-listed component with a wrong line
  ref (`kustomization.yaml:10-11` is the `resources:` block). The file lists exactly ONE component at
  :6-7, `../../components/common`; alertmanager arrives transitively through it. Substance was right,
  mechanism and evidence were not.
- [correction] The onepassword-connect CNP does NOT contain a prometheus ingress rule. Scrape rides
  the cluster-wide `ingress-from-prometheus` CCNP via the `ingress.home.arpa/allow-prometheus` pod
  label. The note conflated two different mechanisms into one manifest.
- [addition] Uncovered before: the Connect HelmRelease `postRenderers` patch setting
  `automountServiceAccountToken: false` on the rendered Deployment (a real security control — Connect
  serves ESO from local cache and never calls the K8s API), the GrafanaDashboard/GrafanaFolder consumer
  CRs, the two `app/kustomization.yaml` gates, and the pinned chart tags (operator 2.8.0, Connect 2.4.1).
- [observation] Chart-default Connect security context (seccomp/runAsNonRoot/readOnlyRootFilesystem/
  drop ALL/UID 999) remains asserted from the chart, not rendered in-repo — still not repo-verifiable.
