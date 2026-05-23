---
title: eso-dependency-audit
type: note
permalink: home-ops/progress/eso-dependency-audit
tags:
- progress
- external-secrets
- flux-gitops
- dependsOn
---

# ESO dependsOn audit — completed (no code change)

## Conclusion

Audited all 20 ExternalSecret manifests (18 app-level + 2 component-level) for dependsOn chain correctness against the ClusterSecretStore-providing ks (`onepassword-connect`).

**Result: no code change needed.** The original roadmap identified `flux-instance` as a gap (missing `dependsOn: onepassword-connect`), but after comparing with the bjw-s reference cluster and analyzing the tradeoffs, the decision is to **keep flux-instance at `dependsOn: [flux-operator]` only** — matching bjw-s parity.

### Why not add the dependency?

1. bjw-s reference cluster has the same ExternalSecret (`github-webhook-token` referencing `ClusterSecretStore/onepassword-connect`) in `flux-instance` but does NOT declare `dependsOn: onepassword-connect`.
2. Adding the dependency couples FluxInstance reconciliation to CSS availability — a broken 1Password Connect would block FluxInstance updates, removing `flux-instance` as a fallback early-boot path.
3. The `flux-instance` ks contains both the FluxInstance HelmRelease (does NOT need CSS Ready) and the GitHub webhook ExternalSecret (does). Adding the dependency delays the entire ks including the non-secret-bearing HelmRelease.
4. The ESO retry-loop on `github-webhook-token` is benign — it converges once CSS becomes Ready.
5. Bootstrap already sequences correctly: helmfile installs ESO + 1Password Connect BEFORE Flux Instance (`01-apps.yaml`).

### No circular dependency

The dependsOn chain is a DAG with no cycles:

```
flux-operator ──────────────────────────────┐
                                             ├──→ flux-instance
external-secrets ──→ onepassword-connect ────┘
```

`onepassword-connect` depends on `external-secrets` (CRDs only), not on `flux-instance`. No circular dependency possible.

### dependsOn Convention (documented in docs/areas/external-secrets)

Every Flux Kustomization that contains an ExternalSecret manifest MUST declare `dependsOn` on the ks that gates on the referenced ClusterSecretStore Ready. Two intentional exceptions:

1. **`onepassword-connect`** — bootstrap chicken-and-egg (`op inject` breaks the cycle)
2. **`flux-instance`** — bjw-s parity, retry-loop convergence is acceptable

Component-level ExternalSecrets (pushover, github alerts in `components/common/alerts/`) are applied at the cluster-apps Kustomization level and are implicitly sequenced by the Flux boot chain.

### Inventory (2026-05-23)

- 16 ks-es declare `dependsOn: onepassword-connect` — correct
- `onepassword-connect` — bootstrap exception (N/A)
- `flux-instance` — intentional exemption (bjw-s parity)
- 2 component-level ExternalSecrets (pushover, github alerts) — implicitly covered by Flux boot chain
- No gaps remain

## Related

- continues [[ks-healthchecks-rollout]]
- relates_to [[external-secrets]]
- relates_to [[flux-gitops]]
