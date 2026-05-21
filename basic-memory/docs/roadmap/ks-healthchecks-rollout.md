---
title: ks-healthchecks-rollout
type: roadmap
permalink: home-ops/docs/roadmap/ks-healthchecks-rollout
topic: Roll out Flux Kustomization healthChecks / healthCheckExprs on every dependsOn
  target
status: proposed
priority: high
scope: Add explicit healthChecks (and where required healthCheckExprs) to every Kustomization
  that is referenced via dependsOn, so dependents wait on actual resource Readiness
  rather than only on the parent manifest being applied. Mirrors the bjw-s-labs /
  home-operations reference pattern already used in external-secrets, onepassword-connect,
  volsync, kopia.
rationale: 'All 43 ks.yaml currently use wait: false. Without healthChecks, a parent
  Kustomization reports Ready as soon as its manifests apply — not when the underlying
  HelmRelease/CRD is actually Ready. Consumers (dependsOn) therefore proceed too early,
  e.g. 20 default apps depend on democratic-csi but start reconciling before its HR
  is rolled out, and the cert-manager → envoy-gateway chain has no health gating end-to-end.'
options:
- bjw-s pattern (recommended) — wait false everywhere, explicit healthChecks on every
  dependsOn target, healthCheckExprs colocated with the CR manifest on the existing
  sub-ks for ClusterIssuer / Certificate / Gateway. No new splits.
- Minimum-impact subset — only the four CRD CELs (ClusterIssuer, Certificate, Gateway
  already split today; ClusterSecretStore already in place) plus democratic-csi HR
  healthCheck. Skip the rest until an incident motivates them.
- Status quo — accept that dependsOn is leaky and rely on retry loops to eventually
  converge
related_areas:
- flux-gitops
- networking
- external-secrets
- k8s-workloads
tags:
- roadmap
- flux-gitops
- healthchecks
- dependsOn
---

# Roll out Flux Kustomization healthChecks / healthCheckExprs on every dependsOn target

## Metadata (observation-form, schema validation)
- [topic] Roll out Flux Kustomization healthChecks / healthCheckExprs on every dependsOn target
- [status] proposed
- [priority] high

## Current state

All 43 ks.yaml in `kubernetes/apps/` use `wait: false`. Only four declare explicit `healthChecks`:

| ks.yaml | healthChecks | healthCheckExprs | Consumers (dependsOn) |
|---|---|---|---|
| `external-secrets/external-secrets/ks.yaml` | HelmRelease | — | 1 (onepassword-connect) |
| `external-secrets/onepassword-connect/ks.yaml` | HelmRelease + ClusterSecretStore | ClusterSecretStore Ready CEL | 27 |
| `volsync-system/volsync/ks.yaml` | HelmRelease | — | 3 |
| `volsync-system/kopia/ks.yaml` | HelmRelease | — | (per-app VolSync components) |

The pattern matches the bjw-s-labs `home-ops` reference and the broader home-operations community: `wait: false` (avoid the expensive "wait for every reconciled resource" default) plus opt-in `healthChecks` on Kustomizations that act as `dependsOn` targets, so dependents see Ready only when the key resources are actually Ready. `healthCheckExprs` is the escape hatch for CRDs that `kstatus` cannot natively evaluate — the canonical example is `ClusterSecretStore`, where the Ready condition is controller-specific.

## Gap analysis (dependsOn target → missing healthChecks)

Evidence collected via `rg` over `kubernetes/apps/**/ks.yaml` on 2026-05-21.

| Target Kustomization | Consumers | Key resource(s) | CEL needed? |
|---|---|---|---|
| `democratic-csi` (kube-system) | **20** default apps | HelmRelease democratic-csi, StorageClass | No — HR + StorageClass are kstatus-native |
| `cert-manager-issuers` (cert-manager) | 1 (envoy-gateway-certificate, chain node) | ClusterIssuer letsencrypt-* | **Yes** — `status.conditions[?(@.type=="Ready")].status` |
| `envoy-gateway-certificate` (networking) | 1 (envoy-gateway) | Certificate envoy-{internal,external} | **Yes** — `Certificate.status.conditions[Ready]` |
| `envoy-gateway-config` (networking) | 1 (k8s-gateway) | Gateway internal/external | **Yes** — `Gateway.status.conditions[Programmed,Accepted]` |
| `cert-manager` (cert-manager) | 1 (cert-manager-issuers) | HelmRelease cert-manager | No |
| `envoy-gateway` (networking) | 1 (envoy-gateway-config) | HelmRelease envoy-gateway | No |
| `cilium` (kube-system) | 1 (democratic-csi) | HelmRelease cilium | No |
| `flux-operator` (flux-system) | 1 (flux-instance) | HelmRelease flux-operator | No (FluxInstance is kstatus-native with Flux Operator) |
| `kube-prometheus-stack` (observability) | 1 (grafana) | HelmRelease kube-prometheus-stack | No |
| `snapshot-controller` (kube-system) | 1 (volsync) | HelmRelease snapshot-controller | No |

### Highest-impact gaps

1. **`democratic-csi`** — 20 `default` apps `dependsOn` it (sonarr, radarr, prowlarr, qbittorrent, plex, paperless, mealie, actual, ...). Without healthChecks, on a cold cluster boot all 20 start reconciling while the HR is still rolling out → PVC mount races, transient ImagePullBackOff cascades, noisy reconciliation churn until eventual convergence.
2. **cert-manager → envoy-gateway chain** — `cert-manager → cert-manager-issuers → envoy-gateway-certificate → envoy-gateway → envoy-gateway-config → k8s-gateway` is six links, none of them health-gated. If `cert-manager-issuers` is slow (ACME order pending) the `envoy-gateway-certificate` Kustomization applies a Certificate manifest before the ClusterIssuer is Ready, producing a transient CertificateRequest failure that resolves only on a later reconcile.

## Plan

### Phase 1 — Highest-impact gaps (recommended starting point)

1. `kubernetes/apps/kube-system/democratic-csi/ks.yaml` — add `healthChecks` for the `democratic-csi` HelmRelease in namespace `kube-system`. No CEL needed.
2. `kubernetes/apps/cert-manager/cert-manager/ks.yaml` — add `healthChecks` for the cert-manager HR. Also add `healthChecks` and `healthCheckExprs` to the `cert-manager-issuers` Kustomization (same file, second document) for the `ClusterIssuer` resources (`letsencrypt-production`, `letsencrypt-staging`).
3. `kubernetes/apps/networking/envoy-gateway/ks.yaml` — add `healthChecks` + `healthCheckExprs` for the `envoy-gateway-certificate` Kustomization (Certificate resources), then `healthChecks` for the `envoy-gateway` HR, then `healthChecks` + `healthCheckExprs` for `envoy-gateway-config` (Gateway resources, `Programmed` + `Accepted` conditions).

### Phase 2 — Lower-priority single-consumer chains

4. `kubernetes/apps/kube-system/cilium/ks.yaml` — HR healthCheck (single consumer is democratic-csi, but cluster networking should be visibly Ready before storage).
5. `kubernetes/apps/kube-system/snapshot-controller/ks.yaml` — HR healthCheck (volsync depends on it).
6. `kubernetes/apps/flux-system/flux-operator/ks.yaml` — HR healthCheck (flux-instance depends on it; today the operator → instance handover is racy on bootstrap).
7. `kubernetes/apps/observability/kube-prometheus-stack/ks.yaml` — HR healthCheck (grafana depends on it).

### Phase 3 — Documentation and convention

8. Update `docs/areas/flux-gitops` BM area-reference with a "healthChecks convention" section: `wait: false` is default, healthChecks are mandatory on `dependsOn` targets, `healthCheckExprs` is for CRDs without kstatus-native Ready computation.
9. Add a brief note to `kubernetes/CLAUDE.md` pointing at the convention so future ks.yaml additions follow it.

## Canonical patterns

### HR-only gate (the simplest case)

```yaml
healthChecks:
  - apiVersion: helm.toolkit.fluxcd.io/v2
    kind: HelmRelease
    name: <release-name>
    namespace: <target-namespace>
```

### HR + CRD with kstatus-native Ready (no CEL needed)

Add the resource to `healthChecks` and stop — `kstatus` evaluates the standard `Ready` condition.

### HR + CRD with controller-specific Ready (CEL needed)

Mirror the existing onepassword-connect pattern:

```yaml
healthChecks:
  - apiVersion: helm.toolkit.fluxcd.io/v2
    kind: HelmRelease
    name: <release-name>
    namespace: <target-namespace>
  - apiVersion: <crd-api>
    kind: <CRD>
    name: <crd-name>
    namespace: <crd-namespace>  # omit for cluster-scoped CRDs
healthCheckExprs:
  - apiVersion: <crd-api>
    kind: <CRD>
    failed:  status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'False')
    current: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
```

Gateway-API needs a different CEL (multiple condition types must all be True):

```yaml
healthCheckExprs:
  - apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    failed:  status.conditions.exists(e, e.type == 'Programmed' && e.status == 'False')
    current: status.conditions.all(e, (e.type != 'Programmed' && e.type != 'Accepted') || e.status == 'True')
```

## Tradeoffs and risks

- **Bootstrap blast radius**: once Phase 1 is in, a stuck `cert-manager-issuers` will block the entire `envoy-gateway → k8s-gateway → external-dns → cloudflare-tunnel → apps` chain visibly. That is the desired behavior (it's already broken silently today) but it makes incidents louder. Cold-boot times will become **observable** rather than masked by retry storms.
- **`timeout: 5m` default**: every existing ks already has `timeout: 5m`. With healthChecks active, slow HRs (cert-manager Helm hooks, kube-prometheus-stack CRD install) may need a longer timeout. Audit per-ks; bump to `10m` only where evidence shows the HR exceeds 5m.
- **CEL evaluation correctness**: the onepassword-connect CEL is the only existing reference. Any new CEL must be tested against the actual CRD status shape (`kubectl get <crd> -o yaml | yq .status.conditions`) before commit — incorrect CEL can either falsely block forever or pass before the resource is truly Ready.
- **Gateway-API CEL nuance**: a Gateway is Ready only when both `Programmed` and `Accepted` are True; the CEL above is more complex than the ClusterSecretStore pattern. Worth a quick test in a dev branch before landing.
- **Cilium chicken-and-egg**: `cilium` is the CNI itself; the kstatus HR check requires the API server to be reachable, which requires Cilium. In practice this works because the Kustomization controller retries until the API server is back, but the first reconciliation after a full restart may be noisy.
- **Convention drift**: without Phase 3 documentation, future contributors will keep adding bare `dependsOn` without healthChecks. The BM area-reference + `kubernetes/CLAUDE.md` pointer prevents that.

## Options

1. **Full rollout** — Phase 1 + 2 + 3. Every `dependsOn` target gets an explicit gate. Maximum determinism; mirrors the bjw-s reference 1:1.
2. **Minimum-impact rollout (recommended start)** — Phase 1 only (`democratic-csi` + cert-manager/envoy chain) plus Phase 3 documentation. Covers ~90% of observable churn (the 20-app democratic-csi fanout and the cert-manager chain), defers the single-consumer chains until a concrete incident motivates them.
3. **Status quo** — accept that `dependsOn` is leaky and rely on retry loops. Cheapest; loses the contract that `dependsOn` actually means "waited for Ready".

## Reference

- bjw-s-labs canonical example: `https://raw.githubusercontent.com/bjw-s-labs/home-ops/refs/heads/main/kubernetes/apps/external-secrets/onepassword-connect/ks.yaml`
- Flux docs: `https://fluxcd.io/flux/components/kustomize/kustomizations/#health-assessment`

## Related
- relates_to [[flux-gitops]]
- relates_to [[networking]]
- relates_to [[external-secrets]]
- relates_to [[k8s-workloads]]
## Comparative survey — reference repos (added 2026-05-21)

After the initial draft, three community reference repos were surveyed to validate the proposed approach. Three distinct models emerged.

### Model A — bjw-s-labs/home-ops (the repo originally cited)

- `wait` distribution: **60 `wait: false` / 3 `wait: true`** — explicit opt-out of the default
- 16 ks.yaml carry `healthChecks` (vs our 4)
- Pattern: every `dependsOn` target that owns a HelmRelease gets explicit `healthChecks: [HR]`. CRDs (`ClusterIssuer`, `ClusterSecretStore`) get `healthCheckExprs` colocated with the HR.
- Examples: `cert-manager`, `envoy-gateway`, `multus`, `snapshot-controller`, `openebs`, `dragonfly-operator`, `silence-operator`, `renovate-operator` all carry an explicit HR healthCheck.
- Tradeoff: maximum explicitness, lots of boilerplate, every reviewer can read off a ks.yaml whether it gates dependents.

### Model B — onedr0p/home-ops

- `wait` distribution: **54 `wait: false` / 12 `wait: true`** — mixed
- Only 8 ks.yaml carry `healthChecks` — much sparser than bjw-s.
- Pattern: `healthChecks` is reserved for cases that actually require a CRD-level Ready gate or CRD-existence assertion. HR-only platform ks (`envoy-gateway`, `flux-instance`, `coredns`, ...) get plain `dependsOn` + `wait: false` and rely on the Kustomization controller's retry loop to eventually converge.
- Notable patterns:
  - `cert-manager`: HR + ClusterIssuer Ready CEL (same as bjw-s and our planned approach)
  - `multus`: HR + `CustomResourceDefinition` existence check (not Ready; just "CRD registered")
  - `cloudflare-dns`: HR + `DNSEndpoint` CRD existence check
  - `rook-ceph-cluster`: HR + `CephCluster` with `status.ceph.health` CEL — domain-specific health, not standard `conditions[Ready]`
- Tradeoff: minimal boilerplate; accepts some reconciliation noise for non-critical ks.

### Model C — buroa/k8s-gitops (cleanest model)

- `wait` distribution: **17 `wait: true` / ZERO `wait: false`** — Flux default everywhere
- Only 4 ks.yaml carry `healthCheckExprs` and none carry plain `healthChecks`
- Pattern: rely on Flux's native `wait: true` to gate on all reconciled resources (HR Ready, etc., via `kstatus`). Add `healthCheckExprs` ONLY for CRDs that `kstatus` cannot natively evaluate.
- Structural innovation: **split** the CRD-instance manifests into their own Kustomization, separate from the HR. The split colocates the `healthCheckExprs` with exactly the resource that needs it:
  - `cert-manager` (HR, `app/`, `wait: true`) → `cert-manager-issuers` (separate ks, `issuers/` path, `healthCheckExprs` on `ClusterIssuer`, `dependsOn cert-manager`)
  - `onepassword-connect` (HR, `app/`, `wait: true`) → `onepassword-connect-store` (separate ks, `store/` path, `healthCheckExprs` on `ClusterSecretStore`, `dependsOn onepassword-connect + external-secrets`)
  - `rook-ceph` (HR, `app/`, `wait: true`) → `rook-ceph-cluster` (separate ks, `cluster/` path, `healthChecks` + `healthCheckExprs` on `CephCluster` with Ceph health CEL)
- Tradeoff: minimum boilerplate, every HR is implicitly Ready-gated, CRDs that need CEL get their own focused ks.

### Comparison vs our current state

home-ops today has `wait: false` on all 43 ks.yaml and only the four `external-secrets / onepassword-connect / volsync / kopia` carry `healthChecks`. That is closer to Model A in form (`wait: false` + opt-in healthChecks) but only half-applied — every other `dependsOn` target is bare. Our `cert-manager-issuers` is already split into a separate Kustomization at path `issuers/` — a Model-C-shaped split that just lacks the `healthCheckExprs`.

## Revised plan

### Option re-statement (was three, now four)

1. **Model A (full bjw-s parity)** — Add explicit `healthChecks: [HR]` to every `dependsOn` target Kustomization, plus `healthCheckExprs` on the three CRD cases (ClusterIssuer, Certificate, Gateway). Keep `wait: false` default. Maximum explicitness, ~10 files to touch.
2. **Model C (buroa-style, recommended)** — Flip default to `wait: true` on the platform ks that act as `dependsOn` targets (so the HR Ready gate is implicit via `kstatus`). Split `onepassword-connect/app/` into `app/` (HR) + `store/` (ClusterSecretStore + CEL). Add `healthCheckExprs` to `cert-manager-issuers` (already split) and to a new sub-ks for envoy-gateway Gateway resources. Minimum boilerplate, ~5 files to touch, structurally cleaner.
3. **Model B (onedr0p-style minimal)** — Only add CRD-specific gates: `healthCheckExprs` on `cert-manager-issuers` (ClusterIssuer), `envoy-gateway-certificate` (Certificate), `envoy-gateway-config` (Gateway). Leave HR-only platform ks bare and accept retry-loop convergence. Smallest surface, accepts some reconciliation noise. 3 files.
4. **Status quo** — keep what's working, do nothing.

### Recommended path: pure bjw-s pattern, phased

**Phase 1 — Add CEL to the existing sub-ks that own CRDs**

No splits are introduced. The CEL is added to the existing Kustomization that already owns the CR manifest.

1. `kubernetes/apps/cert-manager/cert-manager/ks.yaml` — the `cert-manager-issuers` Kustomization (path `issuers/`) gains `healthChecks: [ClusterIssuer letsencrypt-production]` + `healthCheckExprs` on `ClusterIssuer` Ready (matches bjw-s and onedr0p exactly). The `cert-manager` Kustomization itself (path `app/`) gains `healthChecks: [HR cert-manager]`.
2. `kubernetes/apps/networking/envoy-gateway/ks.yaml` — three documents, three additions:
   - `envoy-gateway-certificate` (path `certificate/`) gains `healthChecks` + `healthCheckExprs` for `Certificate` Ready.
   - `envoy-gateway` (path `app/`) gains `healthChecks: [HR envoy-gateway]`.
   - `envoy-gateway-config` (path `config/`) gains `healthChecks` + `healthCheckExprs` for `Gateway` (`Programmed` and `Accepted` both True).
3. `kubernetes/apps/external-secrets/onepassword-connect/ks.yaml` — already correct (HR + CSS healthChecks, CSS CEL). No change.
4. `kubernetes/apps/external-secrets/external-secrets/ks.yaml`, `kubernetes/apps/volsync-system/volsync/ks.yaml`, `kubernetes/apps/volsync-system/kopia/ks.yaml` — already have HR healthChecks. No change.

**Phase 2 — HR Ready gates for the high-fanout HR-only platform ks**

5. `kubernetes/apps/kube-system/democratic-csi/ks.yaml` — add `healthChecks: [HR democratic-csi]`. 20 default apps benefit immediately.
6. `kubernetes/apps/kube-system/snapshot-controller/ks.yaml` — add `healthChecks: [HR snapshot-controller]` (volsync depends).

**Phase 3 — Defer (single consumer, retry-loop already acceptable)**

7. `cilium`, `flux-operator`, `kube-prometheus-stack` — leave bare unless an incident motivates them. onedr0p does the same on most of these.

**Phase 4 — Documentation and convention**

8. Update `docs/areas/flux-gitops` BM area-reference with the chosen convention: "Every Kustomization that is a `dependsOn` target carries explicit `healthChecks`; CRDs that `kstatus` cannot evaluate (ClusterSecretStore, ClusterIssuer, Certificate, Gateway) carry `healthCheckExprs` colocated with the CR manifest's Kustomization."
9. Add a brief note to `kubernetes/CLAUDE.md` pointing at the convention.

### Decision criteria (technical, not effort-based)

The original "Model C beats Model A because fewer files" framing is a weak criterion. The real axes are:

1. **What semantics should `dependsOn X` enforce?**
   - "X's manifest applied" (current state in home-ops, all `wait: false` + no healthChecks): too loose; `dependsOn` collapses to ordering hint and consumers race against half-ready dependencies.
   - "X's HelmRelease is Ready" (HR healthCheck or `wait: true` on an HR-only ks): correct for *most* dependents — they need the controller running, not necessarily a specific CR.
   - "X's primary CRD instance is usable" (CRD healthCheckExpr): correct for the dependents that actually invoke the CRD (cert-manager-issuers' ClusterIssuer for Certificate-requesting apps; onepassword-connect's ClusterSecretStore for ExternalSecret consumers; envoy-gateway-config's Gateway for HTTPRoute consumers).
   - **Implication**: different consumers want different gates. Lumping HR-Ready and CRD-Ready into the same Kustomization erases that choice. The buroa split is *semantically* correct, independent of effort cost.

2. **Where should the cost of a stalled leaf be paid?**
   - `wait: true` (Model C default everywhere): a single slow Deployment under any reconciled resource stalls the parent ks past `timeout`, which cascades to every dependent. Blast radius = the whole tree below the stall point.
   - `wait: false` + explicit `healthChecks` (Model A): only the explicitly listed resources can stall the parent. A slow non-critical Deployment in the same ks does not block dependents. Blast radius = explicit and bounded.
   - **Implication**: for a single-node home cluster where one HR can take minutes to roll out (kube-prometheus-stack CRD install, cert-manager hooks), bounded blast radius is more valuable than implicit completeness. Model A's explicit gate matches our reliability model better.

3. **How readable is the contract from the ks.yaml alone?**
   - Model A: every gate is a literal list of resources in the ks. A reviewer reads the contract directly.
   - Model C `wait: true`: the contract is "everything in path/" — readable only by walking the path. `kstatus` rules for unknown CRDs are also non-obvious (some treat no-conditions as Current, some as InProgress).
   - **Implication**: explicit healthChecks improve incident debuggability. "Why is consumer Y stuck on dependsOn X?" has a direct answer in X's ks.

4. **Does `kstatus` know what Ready means for this resource?**
   - HelmRelease, Deployment, StatefulSet, DaemonSet, Job, native workloads: yes — `wait: true` is enough.
   - ClusterSecretStore, ClusterIssuer, Certificate, Gateway, CephCluster, custom operator CRDs: no — `kstatus` either passes immediately (no conditions to check) or stalls indefinitely. **healthCheckExprs is mandatory**, regardless of wait mode.
   - **Implication**: the CRD-CEL question is orthogonal to the wait-mode question. Both Model A and Model C need the same healthCheckExprs blocks.

5. **Does the buroa-style split-ks pattern (HR ks + separate CR ks) add semantic value?**
   - The original argument for the split was "different consumers want different gates: HR Ready vs CR Ready". Under inspection this does not hold for our cases:
     - **ESO**: `ClusterSecretStore` Ready *implies* ESO controller running (the controller is what flips CSS to Ready) AND 1P Connect API reachable (CSS Ready requires successful backend probe). Every `ExternalSecret` consumer needs CSS Ready; none can usefully gate on "HR Ready only".
     - **cert-manager**: `ClusterIssuer` Ready implies the controller is running and the ACME account is registered. No `Certificate` consumer benefits from gating on the HR alone.
     - **envoy-gateway**: `Gateway` Programmed + Accepted implies the controller is running and the listener is bound. No `HTTPRoute` consumer benefits from gating on the HR alone.
   - **Implication**: the buroa split is purely organizational (CEL colocated with the CR manifest). It provides no real consumer-side choice. Where the CR is already a separate ks for *other* reasons — different deploy artifact, different bootstrap dependencies, different timing — keep the split and put the CEL on the CR ks. Where it is not (e.g., `onepassword-connect` today, where HR + CSS are bundled in `app/`), do not split.

### Revised recommendation

**Adopt the pure bjw-s pattern**: `wait: false` + explicit `healthChecks: [HR (+ CR if already separate)]` + `healthCheckExprs` on CRDs that `kstatus` cannot evaluate (ClusterSecretStore, ClusterIssuer, Certificate, Gateway). Do not introduce splits for their own sake.

- **Bounded blast radius** (Model A's `wait: false` + explicit healthChecks) over implicit `wait: true`-everywhere, because our HRs vary widely in startup time and dependents should fail fast on the *specific* resource they need, not on incidental slow Deployments.
- **Bundled HR + CR healthChecks where the bundled shape already exists** (current `onepassword-connect/ks.yaml` is correct: HR + CSS both listed in `healthChecks`, CSS gets the CEL). This is exactly the bjw-s cert-manager shape.
- **Use the existing sub-ks split only where it already serves a separate deploy or dependency need**: `cert-manager-issuers` (separate path, separate dependsOn on `onepassword-connect`), `envoy-gateway-certificate` and `envoy-gateway-config` (separate paths). Add the CEL to those existing splits; do not create new ones.
- **healthCheckExprs only where `kstatus` cannot evaluate the CRD**: identical under any model.

### Tradeoffs of the bjw-s pattern

- **Per-ks timeout audit**: with strict healthChecks, `timeout: 5m` becomes a real gate. Slow HRs (cert-manager Helm hooks, kube-prometheus-stack CRD install) may need `timeout: 10m`. Audit on first reconciliation after rollout, bump only where evidence shows it's needed.
- **CEL correctness risk**: every new `healthCheckExprs` block must be verified against the live CRD's `.status.conditions` shape before commit. ClusterIssuer, Certificate, Gateway each have their own condition vocabulary; ClusterSecretStore is already validated in our existing ks.
- **No `onepassword-connect` refactor needed**: the current bundled ks is the right shape. Earlier drafts proposed splitting it into `app/` + `store/`; that work is dropped.

## Action items

- [ ] Land Phase 1 (CEL on existing sub-ks for cert-manager-issuers, envoy-gateway-certificate, envoy-gateway-config; HR healthChecks on cert-manager and envoy-gateway) in a single MR. Verify each CEL against the live CRD's `.status.conditions` shape before commit.
- [ ] Land Phase 2 (democratic-csi + snapshot-controller HR healthChecks) separately so democratic-csi's 20-app fanout can be observed in isolation on cold reconcile.
- [ ] Audit per-ks `timeout` values after Phase 1+2; bump from `5m` to `10m` only where evidence shows the HR needs it.
- [ ] Land Phase 4 documentation last (`docs/areas/flux-gitops` + pointer in `kubernetes/CLAUDE.md`).
- [ ] No splits: the onepassword-connect ks stays bundled (HR + CSS) as today. Earlier drafts proposed a split into `app/` + `store/`; that work is explicitly dropped because no consumer benefits from gating on HR-only without CSS Ready.
