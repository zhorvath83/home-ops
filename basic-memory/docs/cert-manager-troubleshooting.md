---
title: cert-manager-troubleshooting
type: note
permalink: home-ops/docs/cert-manager-troubleshooting
tags:
- cert-manager
- troubleshooting
- runbook
---

# cert-manager troubleshooting

Quick reference for diagnosing cert-manager issues in the home-ops cluster. The cert-manager subtree (`kubernetes/apps/cert-manager/cert-manager/`) deploys the operator plus a single ClusterIssuer (`letsencrypt-production`) that uses Cloudflare DNS-01 with the API token sourced from the `cloudflare` 1Password item via ExternalSecret. CRDs are chart-managed (`crds.enabled: true`), DNS-01 recursive nameservers are pinned to Cloudflare DoH (`https://1.1.1.1:443/dns-query`, `https://1.0.0.1:443/dns-query`).

## Listing certificates

```bash
kubectl get certificate --all-namespaces
```

## Diagnosing a stuck Certificate

```bash
kubectl describe certificate <CERTIFICATE_NAME> -n <NAMESPACE>
```

The `Events` section names the associated `CertificateRequest`. Dig deeper:

```bash
kubectl describe certificaterequest <CERTIFICATE_REQUEST_NAME> -n <NAMESPACE>
```

## Diagnosing ACME challenges

```bash
kubectl describe challenges --all-namespaces
```

This is the right surface when DNS-01 propagation is slow, Cloudflare API auth fails, or the recursive nameserver can't reach the challenge TXT record.

## Common failure modes

- Cloudflare API token revoked / rotated — the `cert-manager-issuer-secret` ExternalSecret pulls from 1P item `cloudflare` field `apitoken_1`; rotate at the 1P side, the runtime Secret refreshes within the 12h ExternalSecret cadence (or force with `just k8s sync-es cert-manager-issuer cert-manager`).
- DNS-01 propagation delay — the issuer is configured with `dns01RecursiveNameserversOnly: true` pointed at Cloudflare DoH; the challenge only completes once the TXT record propagates through Cloudflare's own resolvers.
- Stuck `CertificateRequest` after issuer change — delete the request to force re-issuance; the parent `Certificate` will create a new one.

## Related

- [[cloudflare]] — DNS zone, API token storage
- [[external-secrets]] — ExternalSecret pattern for the issuer API token
- [[k8s-workloads]] — cert-manager is the only non-default non-platform subtree under `kubernetes/apps/`

## Source

Migrated from `docs/cert-manager-readme.md` (deleted in the same commit batch).
