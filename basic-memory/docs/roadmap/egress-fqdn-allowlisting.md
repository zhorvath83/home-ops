---
title: egress-fqdn-allowlisting
type: roadmap
permalink: home-ops/docs/roadmap/egress-fqdn-allowlisting
topic: FQDN-scoped egress for internet-facing apps
status: proposed
priority: medium
scope: Narrow world-egress for the apps that do not truly need open internet by moving
  them onto toFQDNs allow-lists (the L7 DNS proxy already makes this observable),
  leaving genuinely open-egress apps as a small documented exception.
rationale: Replacing open egress with named-destination allow-lists turns the outbound
  path from a blank cheque into an auditable list, shrinking exfil/C2 options for
  a compromised app to a handful of known hosts.
related_areas:
- networking
options:
- Per-app toFQDNs allow-lists
- Shared allow-list CCNP for common destinations
---

# FQDN-scoped egress for internet-facing apps

## Metadata (observation-form, schema validation)

- [topic] FQDN-scoped egress for internet-facing apps
- [status] proposed
- [priority] medium

## What we gain

- Compromised apps can only reach pre-approved destinations — the exfil/C2 surface collapses.
- Outbound intent becomes explicit and auditable per app.
- The genuinely open-egress apps (torrent clients) stay a small, known exception instead of the default.

## What to do

1. Use Hubble / L7 DNS logs to derive each apps real FQDN destinations.
2. Convert bounded-need allow-world apps (updaters, metadata refreshers) to toFQDNs policies.
3. Leave qbittorrent-style peer traffic on world egress but document it as an accepted exception.
4. Optionally tighten the universal DNS matchPattern for opt-out pods.
5. Verify: apps still function; Hubble shows drops to non-allowed destinations.

## Options

1. Per-app toFQDNs allow-lists
2. Shared allow-list CCNP for common destinations

## Related

- relates_to [[networking]]
- relates_to [[AD-023-cnp-threat-model-audit]]
