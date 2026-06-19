# cert-manager Guide

This guide applies to `kubernetes/apps/cert-manager/`. It captures durable guardrails for cluster TLS certificate issuance. There is no dedicated Basic Memory area-reference; the issuer's DNS-01 dependency is described in `docs/areas/cloudflare` and the certificate it issues is consumed by `docs/areas/networking` (read via the `basic-memory` MCP).

## Scope

cert-manager issues the TLS certificates the cluster serves — platform, not app workload:

- `cert-manager/app/` — the cert-manager controller HelmRelease
- `cert-manager/issuers/` — the `ClusterIssuer/letsencrypt-production` (ACME) plus its credential `ExternalSecret`

## Cross-Cutting Dependency (Do Not Break)

The `ClusterIssuer/letsencrypt-production` issues the wildcard certificate for `*.${PUBLIC_DOMAIN}` that the networking `https` Gateway listener serves. A broken issuer silently breaks ingress TLS for the whole cluster, so treat the issuer chain as load-bearing:

- Issuance uses **ACME DNS-01 via Cloudflare**, with the API token read from Secret `cert-manager-issuer-secret` (key `api-token`).
- That Secret comes from an `ExternalSecret` backed by the `onepassword-connect` ClusterSecretStore — the `cert-manager-issuers` Kustomization therefore `dependsOn` both `cert-manager` and `onepassword-connect`. Keep that ordering and keep the secret name and key aligned across the ExternalSecret, the ClusterIssuer `apiTokenSecretRef`, and the Cloudflare token's scope.
- `solvers.dns01.cloudflare` is scoped to `dnsZones: ${PUBLIC_DOMAIN}`; the ACME profile is `shortlived`. Preserve these unless the certificate strategy is intentionally changing.

## Guardrails For Edits Here

- Distinguish controller config (`app/`) from issuer config (`issuers/`); the staging ACME server line is kept commented next to production — switch deliberately, do not delete it.
- A Cloudflare API token scope or 1Password field change must be coordinated with `provision/cloudflare/` and `docs/areas/cloudflare`.

## Validation

- After issuer edits, confirm the `ClusterIssuer` reaches `Ready` (the Kustomization already gates on it) rather than only checking the controller pod.
