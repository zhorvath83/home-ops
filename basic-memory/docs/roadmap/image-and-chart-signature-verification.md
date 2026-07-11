---
title: image-and-chart-signature-verification
type: roadmap
permalink: home-ops/docs/roadmap/image-and-chart-signature-verification
topic: Verified image & chart provenance — cosign verification + digest pinning
status: proposed
priority: high
scope: Add cosign spec.verify to the OCIRepositories whose publishers sign (Flux controllers,
  cert-manager, Cilium, …) and move critical/platform workloads from mutable tags
  to digest pins.
rationale: Signature verification and digest pinning guarantee the cluster runs exactly
  the artifact the publisher released — the supply-chain equivalent of the verified
  git source, extending that trust anchor to containers.
related_areas:
- flux-gitops
options:
- Keyless (Fulcio/Rekor OIDC identity) — no key to manage
- Key-based cosign — for publishers without keyless
---

# Verified image & chart provenance — cosign verification + digest pinning

## Metadata (observation-form, schema validation)

- [topic] Verified image & chart provenance — cosign verification + digest pinning
- [status] proposed
- [priority] high

## What we gain

- Only publisher-signed, unmodified charts/images reconcile — a re-pushed or poisoned tag is rejected.
- Immutable digests mean what was reviewed is exactly what runs, now and on every future restart.
- Extends the git provenance guarantee to the container supply chain.

## What to do

1. Inventory which OCIRepository sources publish cosign signatures (controlplaneio Flux, jetstack, cilium, …).
2. Add spec.verify (cosign; keyless/OIDC or key) to those OCIRepositories.
3. Pin critical/platform images by digest — Renovate already supports digest pinning; keep tag+digest for readability.
4. Verify: pointing a test source at an unsigned/modified tag makes reconcile fail closed.

## Options

1. Keyless (Fulcio/Rekor OIDC identity) — no key to manage
2. Key-based cosign — for publishers without keyless

## Related

- relates_to [[flux-gitops]]
- relates_to [[main-branch-protection-and-commit-signing]]
