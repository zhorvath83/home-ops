---
title: forward-auth-coverage-external-data-apps
type: roadmap
permalink: home-ops/docs/roadmap/forward-auth-coverage-external-data-apps
topic: Second independent identity gate on the external data apps
status: proposed
priority: high
scope: Bring the internet-exposed personal-data apps (paperless/docs, actual/pfm,
  photos, books, subscriptions) behind the cluster-side Pocket-ID / TinyAuth layer
  that already protects the downloads apps, and scope the Cloudflare Access mobile
  service token to only what needs non-browser access.
rationale: 'A cluster-side identity gate makes the data apps defense-in-depth: access
  then requires passing both Cloudflare Access and Pocket-ID/TinyAuth, so no single
  edge credential or misconfiguration exposes personal data.'
related_areas:
- iam
- networking
- cloudflare
options:
- OIDC-native per app where supported
- forward-auth via TinyAuth for the rest
---

# Second independent identity gate on the external data apps

## Metadata (observation-form, schema validation)

- [topic] Second independent identity gate on the external data apps
- [status] proposed
- [priority] high

## What we gain

- Personal-data apps gain a second, independent, passkey-backed authn factor on top of the edge.
- The mobile service token stops being a skeleton key — its reach shrinks to exactly the app(s) that need programmatic access.
- Uniform auth posture across all externally-exposed apps.

## What to do

1. Extend the existing forward-auth component (or OIDC-native SecurityPolicy) to docs/pfm/photos/books/subscriptions with per-app Pocket-ID group ACLs.
2. Prefer OIDC-native where supported (paperless, actual), forward-auth otherwise.
3. Narrow the Cloudflare Access service-token policy so non-identity access is granted only to the specific app(s) that require it, not the whole wildcard.
4. Verify each app: browser SSO works; the service token reaches only its intended app.

## Options

1. OIDC-native per app where supported
2. forward-auth via TinyAuth for the rest

## Related

- relates_to [[sso-implementation]]
- relates_to [[iam]]
- relates_to [[networking]]
- relates_to [[cloudflare]]
