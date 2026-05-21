---
title: eso-dependency-audit
type: roadmap
permalink: home-ops/docs/roadmap/eso-dependency-audit
topic: Audit ExternalSecret consumer dependsOn chains — depend on CSS-Ready gate,
  not just ESO controller
status: proposed
priority: medium
scope: 'For every Kustomization that creates ExternalSecret manifests, verify the
  dependsOn chain transitively reaches the ks that gates on the relevant ClusterSecretStore
  Ready (today: onepassword-connect). The literal "dependsOn external-secrets" form
  is rare and correct in the one case it appears; the real gap is ExternalSecret-bearing
  ks-es with no transitive ESO dependency at all.'
rationale: ClusterSecretStore Ready implies the ESO controller is running and the
  backend is reachable. An ExternalSecret depending only on "ESO controller exists"
  cannot reconcile until the CSS it references is Ready. Today only one ks declares
  dependsOn external-secrets (onepassword-connect, which is correct because it owns
  the CSS and needs the ESO CRDs but no external CSS). However flux-instance creates
  an ExternalSecret without any dependsOn pointing at the CSS-providing ks, so on
  cold boot the GitHub webhook ExternalSecret will retry-loop until onepassword-connect
  catches up.
options:
- Tighten all ExternalSecret-bearing ks-es to dependsOn onepassword-connect (recommended)
- Tighten only the known-broken case (flux-instance) and document the rule for future
  ks additions
- Status quo — accept retry-loop convergence on cold boot
related_areas:
- external-secrets
- flux-gitops
tags:
- roadmap
- external-secrets
- flux-gitops
- dependsOn
---

# Audit ExternalSecret consumer dependsOn chains — depend on CSS-Ready gate, not just ESO controller

## Metadata (observation-form, schema validation)
- [topic] Audit ExternalSecret consumer dependsOn chains
- [status] proposed
- [priority] medium

## Origin

The companion roadmap [[ks-healthchecks-rollout]] established that `ClusterSecretStore` Ready *implies* the ESO controller is running and the backend is reachable. Therefore no real consumer benefits from gating on "ESO controller Ready" alone — every `ExternalSecret` reconciliation requires the referenced CSS to be Ready. This raised the question: are there ks-es in our repo that currently depend on the controller HR ks (`external-secrets`) when they should depend on the CSS-providing ks (`onepassword-connect`)?

## Direct survey: dependsOn external-secrets

Evidence collected via `rg` over `kubernetes/apps/**/ks.yaml` on 2026-05-22.

| ks.yaml | Reason | Correct? |
|---|---|---|
| `kubernetes/apps/external-secrets/onepassword-connect/ks.yaml` | The `onepassword-connect` ks creates the `ClusterSecretStore`; it needs the ESO CRDs (`ClusterSecretStore`, `ExternalSecret`) installed by the `external-secrets` HR before its own manifests can apply. It does NOT consume any other CSS Ready (it IS the CSS provider). | **Yes** — legitimate HR-only dependency. |

Only one ks declares `dependsOn: external-secrets` and it is correct. The literal mis-routing the user suspected does not exist in the current tree.

## Inverse survey: ExternalSecret creators and their dependsOn chains

The more meaningful question is the inverse: every ks that *creates* an `ExternalSecret` must transitively depend on the ks that gates on the CSS it references. Today every `ExternalSecret` in the tree references `ClusterSecretStore/onepassword-connect`, so the rule simplifies to: "every ExternalSecret-bearing ks must transitively dependsOn the `onepassword-connect` ks".

### ExternalSecret-bearing ks inventory (18 manifests, by ks)

| ks (path) | ExternalSecret manifest(s) | dependsOn onepassword-connect? |
|---|---|---|
| `cert-manager/cert-manager/ks.yaml` (`cert-manager-issuers` sub-ks) | `issuers/externalsecret.yaml` | **Yes** (also depends on `cert-manager`) |
| `default/homepage/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `default/isponsorblocktv/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `default/mealie/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `default/paperless-gpt/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `default/paperless/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `default/plex-trakt-sync/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `default/plex/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `default/qbittorrent/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `default/resticprofile/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `external-secrets/onepassword-connect/ks.yaml` | `app/externalsecret.yaml` (two ExternalSecrets: `onepassword-connect-credentials` + `onepassword-connect-token`) | **N/A — bootstrap chicken-and-egg, see below** |
| `flux-system/flux-instance/ks.yaml` | `app/github/externalsecret.yaml` (`github-webhook-token`) | **NO — gap** |
| `flux-system/flux-provider-pushover/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `networking/cloudflare-tunnel/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `networking/external-dns/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `observability/grafana/ks.yaml` | `app/externalsecret.yaml` | Yes |
| `volsync-system/kopia/ks.yaml` | `app/externalsecret.yaml` | Yes (transitively via own ks dependsOn) |
| `volsync-system/volsync/ks.yaml` (`volsync-maintenance` sub-ks) | `maintenance/externalsecret.yaml` | Yes |

### Findings

**1 — Confirmed gap: `flux-instance`**

`kubernetes/apps/flux-system/flux-instance/ks.yaml` has `dependsOn: [flux-operator]` only. The ks creates an `ExternalSecret` named `github-webhook-token` that resolves the GitHub webhook token from 1Password (`secretStoreRef: ClusterSecretStore/onepassword-connect`). On cold cluster boot the `FluxInstance` and its bundled GitHub webhook ExternalSecret apply before `onepassword-connect` is Ready; the ExternalSecret enters error state and retries until eventual convergence. Fix: add `onepassword-connect` (namespace `external-secrets`) to the dependsOn list.

**2 — Documented chicken-and-egg: `onepassword-connect/app/`**

The `onepassword-connect` ks creates two ExternalSecrets — `onepassword-connect-credentials` and `onepassword-connect-token` — that pull the 1Password Connect server's own credentials *from* 1Password. The CSS that resolves them IS `ClusterSecretStore/onepassword-connect`, which the same ks creates. This works because cluster bootstrap (`just cluster-bootstrap`) uses `op inject` to deliver the initial credentials Secret out-of-band; ESO then takes over and the ExternalSecrets refresh on the normal schedule. The dependsOn correctly points only at `external-secrets` (the CRDs); a dependsOn back to itself would be a deadlock. Document this as the canonical exception, not a gap.

**3 — All 16 other ExternalSecret-bearing ks-es already declare `dependsOn onepassword-connect`** (sometimes with additional dependencies like `cert-manager` or `democratic-csi`). No further action needed for these.

## Plan

### Phase 1 — Fix the confirmed gap

1. `kubernetes/apps/flux-system/flux-instance/ks.yaml` — add `onepassword-connect` (namespace `external-secrets`) to `dependsOn`. After the [[ks-healthchecks-rollout]] Phase 1 lands, `onepassword-connect` will gate on CSS Ready, which is exactly what the github-webhook-token ExternalSecret needs.

### Phase 2 — Document the rule

2. Update `docs/areas/external-secrets` BM area-reference with the convention: "Any Kustomization that contains an ExternalSecret manifest MUST declare `dependsOn` on the ks that gates on the referenced ClusterSecretStore Ready. For our cluster today, that ks is `onepassword-connect` in namespace `external-secrets`. The one exception is `onepassword-connect` itself, which uses bootstrap-time `op inject` to break the chicken-and-egg cycle."
3. Add a pre-commit / CI check (optional) that greps `kubernetes/apps/**/externalsecret.yaml` and verifies the owning ks's `dependsOn` chain reaches `onepassword-connect`. Out of scope for the manual fix; flag as a follow-up only if violations recur.

### Phase 3 — Generalize for future CSSes

4. If the cluster ever introduces a second ClusterSecretStore (e.g. a Vault-backed CSS, an additional 1P Connect tenant), the rule generalizes: each ExternalSecret-bearing ks transitively depends on the ks that gates on the specific CSS it references. The audit table above becomes per-CSS in that world.

## Tradeoffs and risks

- **Bootstrap ordering**: tightening flux-instance's dependsOn means the `FluxInstance` CR will apply later in the bootstrap chain. Today `flux-instance` is one of the first things to come up; with the new dependency it waits for the entire `external-secrets → onepassword-connect` chain. The GitHub webhook ExternalSecret is the only meaningful consumer of CSS Ready inside `flux-instance/app/`, so the delay should be acceptable, but worth measuring on the first cold boot after the change.
- **Coupling**: flux-instance becoming dependent on the ESO chain means a broken `onepassword-connect` blocks Flux reconciliation of the cluster-apps tree. This is structurally fine because every other ks already has the same dependency (and a broken CSS already breaks the whole cluster's secret delivery), but it removes flux-instance as a "fallback" early-boot path.
- **Document-only Phase 2 is the actual lasting value**: the convention codified in `docs/areas/external-secrets` is what prevents the next ks from re-introducing the gap. The flux-instance fix is a one-time correction; the convention is the durable artifact.

## Options

1. **Tighten all + document (recommended)** — fix flux-instance, document the rule. Phase 1 + Phase 2.
2. **Tighten only the known-broken case** — just the flux-instance fix; defer documentation until another instance proves the need. Lower upfront cost, higher chance of recurrence.
3. **Status quo** — accept retry-loop convergence on cold boot. The github-webhook ExternalSecret will eventually resolve; the cost is some reconciliation noise and a window of broken webhook delivery during cluster startup.

## Related
- continues [[ks-healthchecks-rollout]]
- relates_to [[external-secrets]]
- relates_to [[flux-gitops]]
