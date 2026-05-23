---
title: AD-009-bootstrap-runtime-secrets-split
type: decision
permalink: home-ops/docs/decisions/ad-009-bootstrap-runtime-secrets-split
decision_id: AD-009
topic: Hybrid secret model — op inject at bootstrap, ExternalSecret + SOPS at runtime
status: superseded
decided_at: '2025-10-01'
superseded_at: '2026-05-17'
decision: 'Three-source hybrid secrets: op inject for 3 bootstrap Secrets (Connect
  creds + sops-age), SOPS-encrypted git for cluster-secrets and homepage config, ExternalSecret
  + 1Password Connect for app runtime secrets.'
rationale: 1Password Connect chicken-and-egg requires op inject for its own init creds;
  SOPS preserved for cluster-secrets substitution targets and Homepage config UX;
  app-level runtime secrets continue via 1Password ExternalSecret.
tradeoffs: Two secret-input mechanisms at bootstrap (op-inject + Flux SOPS reconcile);
  op CLI required locally for bootstrap; cluster-secrets→ESO migration filed as post-cutover
  follow-up (became Phase 6.7).
related_areas:
- external-secrets
- flux-gitops
---

# AD-009 — Hybrid secret model: op inject at bootstrap, ExternalSecret + SOPS at runtime

## Metadata (observation-form, schema validation)

- [decision_id] AD-009
- [status] superseded
- [decided_at] 2025-10-01
- [topic] Hybrid secret model — op inject at bootstrap, ExternalSecret + SOPS at runtime

## Decision

Three-source hybrid secrets pattern:

- `op inject` at bootstrap time for three Secrets: `onepassword-connect-credentials-secret`, `onepassword-connect-vault-secret`, and `sops-age` (age private key for SOPS)
- SOPS-encrypted in git for `cluster-secrets.sops.yaml` and `homepage/secret.sops.yaml`, decrypted by Flux at reconcile time using the `sops-age` Secret
- ExternalSecret + 1Password Connect (`onepassword-connect` ClusterSecretStore) for all app-level runtime secrets

## Rationale

- 1Password Connect itself runs in-cluster — chicken-and-egg requires `op inject` for Connect's own init creds
- SOPS pattern preserved for cluster-secrets (substitution targets) and Homepage config (large YAML, `sops edit` UX)
- App-level runtime secrets continue going through 1Password ExternalSecret, matching the pre-existing model

## Tradeoffs

- Two different secret-input mechanisms at bootstrap time (op-inject + Flux SOPS reconcile) — acceptable complexity
- `op` CLI must be available locally wherever bootstrap is run
- Eventual migration of `cluster-secrets` to 1Password ESO filed as post-cutover follow-up (became Phase 6.7)

## Superseded by

Phase 6.7 (2026-05-17) collapsed the runtime SOPS layer entirely. The live state no longer matches this decision:

- `cluster-secrets.sops.yaml` migrated to ExternalSecret
- `homepage/secret.sops.yaml` migrated to ExternalSecret
- `kubernetes/flux/vars/` directory removed
- `sops-age` Secret removed from `bootstrap/resources.yaml.j2`
- Bootstrap-time `op inject` reduced to 2 Connect Secrets only (no `sops-age` anymore)

No standalone successor ADR was written; the new state is documented in the [[external-secrets]] and [[flux-gitops]] AreaReferences.

## Related

- relates_to [[external-secrets]]
- relates_to [[flux-gitops]]
