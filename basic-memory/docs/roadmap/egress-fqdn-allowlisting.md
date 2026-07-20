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

## Execution plan (research-backed)

### Current state
- Open egress is granted by label: `kubernetes/apps/kube-system/cilium/netpols/allow-world-egress.yaml:13-23` — pods labeled `egress.home.arpa/allow-world="true"` get `0.0.0.0/0` (LAN + CGNAT carved out via `except`). A second spec (lines 24-38) grants world to `flux-system`/`cert-manager` namespace pods (unlabelable vendored controllers).
- Audit: allow-world apps include qbittorrent, prowlarr, sonarr, radarr, bazarr, maintainerr, seerr, plex, isponsorblocktv, mealie, wallos, homepage.
- The **stricter pattern already exists**: apps that opt out of the baseline (`egress.home.arpa/custom-egress`) plus a per-app CNP with `toFQDNs`. Canonical example: a per-app `ciliumnetworkpolicy.yaml` with `toFQDNs` (e.g. maxmind + smtp2go FQDNs only). The L7 DNS proxy (`allow-dns-egress`, matchPattern:"*") makes toFQDNs resolvable for every pod.

### Target state
- Apps with bounded outbound needs use `toFQDNs` allow-lists instead of open world egress; only genuinely-open apps (torrent peer traffic) keep `allow-world`, documented as an accepted exception.

### Implementation steps (per app, incremental)
1. **Classify each allow-world app** by observing real destinations:
   ```bash
   just k8s hubble-live-capture 300     # run during normal use
   just k8s hubble-analyze k8s:app.kubernetes.io/name=<app> FORWARDED egress
   ```
   Bounded (convertible): mealie, wallos, homepage, isponsorblocktv, maintainerr, seerr (API/metadata endpoints). Keep-open: qbittorrent (DHT/peer swarm — unbounded IPs), arguably prowlarr/sonarr/radarr/bazarr (many indexer/tracker hosts — evaluate, may be large but enumerable).
2. **Convert a bounded app.** In the app's `helmrelease.yaml` pod labels, replace `egress.home.arpa/allow-world: "true"` with `egress.home.arpa/custom-egress: "true"`. Then add `kubernetes/apps/<ns>/<app>/app/ciliumnetworkpolicy.yaml` modeled on that pattern:
   ```yaml
   ---
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   metadata:
     name: <app>
   spec:
     endpointSelector:
       matchLabels: { app.kubernetes.io/name: <app> }
     egress:
       - toEndpoints: [{}]                 # in-cluster (custom-egress removed baseline)
       - toEntities: [cluster, kube-apiserver]
       - toFQDNs:
           - matchName: "api.example.com"
           - matchPattern: "*.example.com"
         toPorts: [{ ports: [{ port: "443", protocol: TCP }] }]
   ```
   Add it to the app's `app/kustomization.yaml`. (custom-egress removes cluster/world baseline, so the CNP must re-grant cluster egress + DNS is already covered by allow-dns-egress.)
3. **Leave keep-open apps as-is**, but add a one-line `# renovate`-style comment / BM note documenting them as an accepted open-egress exception.
4. Commit per app: `🔒 refactor(<app>): scope egress to FQDN allow-list`.

### Verification
- `kubectl get cnp -n <ns> <app>` present; `cilium endpoint list` shows the pod egress-enforced.
- App functions normally (exercise its outbound features).
- `just k8s hubble-analyze k8s:app.kubernetes.io/name=<app> DROPPED egress` → drops only to non-allowed hosts; `FORWARDED` shows the allowed FQDNs. Watch for unexpected DROPs = missing an FQDN.

### Rollback & safety
- Revert the label swap + delete the CNP → app returns to open egress.
- **Risk:** a missing FQDN breaks the app's outbound calls. Convert one app at a time, capture first, verify after. FQDN policy depends on DNS going through Cilium's proxy (it does, cluster-wide).
- toFQDNs matches on observed DNS answers — an app that connects to a raw IP (no DNS) won't be covered; such apps must stay allow-world or use toCIDR.

### Gotchas & dependencies
- qbittorrent peer traffic is intentionally unbounded — do not attempt to pin it.
- Shares the Hubble workflow with `default-deny-ingress-baseline`.

### Effort
M (~0.5 day per batch of apps; spread it out, low urgency).
