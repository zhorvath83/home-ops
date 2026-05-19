---
title: AD-022-flux-root-vars-apps-split
type: decision
permalink: home-ops/docs/decisions/ad-022-flux-root-vars-apps-split
decision_id: AD-022
topic: 'Flux root: `cluster-vars` + `cluster-apps` Kustomization split'
status: superseded
decided_at: '2025-10-01'
decision: '`kubernetes/flux/cluster/ks.yaml` contains TWO Kustomizations: (1) `cluster-vars`
  reconciles `./kubernetes/flux/vars/` with SOPS decryption (via the `sops-age` Secret),
  creating a `cluster-settings` ConfigMap and a `cluster-secrets` Secret; (2) `cluster-apps`
  reconciles the `./kubernetes/apps/` tree with `dependsOn: cluster-vars` and `substituteFrom:
  [cluster-settings, cluster-secrets]`.'
rationale: '`cluster-apps` `substituteFrom` sources (a ConfigMap and a Secret) are
  only usable if both already exist in the cluster — `dependsOn` guarantees the order
  `cluster-vars` decrypts `cluster-secrets.sops.yaml` via `decryption: { provider:
  sops, secretRef: { name: sops-age } }` The previous single-Kustomization setup (`kubernetes/flux/config/cluster.yaml`
  + manual `flux/vars/` apply in the bootstrap task) goes away — Flux handles both
  natively as part of GitOps'
tradeoffs: Two Kustomizations to debug instead of one — minimal extra complexity `cluster-vars`
  is NOT part of the `./kubernetes/apps/` tree (sibling, not child) — so the refactor
  does not muddle the apps tree organization
superseded_at: '2026-05-17'
related_areas:
- flux-gitops
---

# AD-022 — Flux root: `cluster-vars` + `cluster-apps` Kustomization split

## Metadata (observation-form, schema validation)
- [decision_id] AD-022
- [status] superseded
- [decided_at] 2025-10-01
- [topic] Flux root: `cluster-vars` + `cluster-apps` Kustomization split

## Decision
`kubernetes/flux/cluster/ks.yaml` contains TWO Kustomizations: (1) `cluster-vars` reconciles `./kubernetes/flux/vars/` with SOPS decryption (via the `sops-age` Secret), creating a `cluster-settings` ConfigMap and a `cluster-secrets` Secret; (2) `cluster-apps` reconciles the `./kubernetes/apps/` tree with `dependsOn: cluster-vars` and `substituteFrom: [cluster-settings, cluster-secrets]`.

## Rationale
- `cluster-apps` `substituteFrom` sources (a ConfigMap and a Secret) are only usable if both already exist in the cluster — `dependsOn` guarantees the order
- `cluster-vars` decrypts `cluster-secrets.sops.yaml` via `decryption: { provider: sops, secretRef: { name: sops-age } }`
- The previous single-Kustomization setup (`kubernetes/flux/config/cluster.yaml` + manual `flux/vars/` apply in the bootstrap task) goes away — Flux handles both natively as part of GitOps

## Tradeoffs
- Two Kustomizations to debug instead of one — minimal extra complexity
- `cluster-vars` is NOT part of the `./kubernetes/apps/` tree (sibling, not child) — so the refactor does not muddle the apps tree organization

## Superseded by
Phase 6.7 (2026-05-17) collapsed the implementation back to a single `cluster-apps` Kustomization (bjw-s parity). The `cluster-vars` Kustomization was eliminated, `kubernetes/flux/vars/` was deleted, and the `substituteFrom` patch was removed. The live `kubernetes/flux/cluster/ks.yaml` now contains a single `cluster-apps` KS with only the HelmRelease defaults patch.

No standalone successor ADR was written; the new state is documented in the [[flux-gitops]] AreaReference.

## Related
- relates_to [[flux-gitops]]
