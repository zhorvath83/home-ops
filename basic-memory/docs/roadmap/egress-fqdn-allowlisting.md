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
- [status] planned — full per-app plan worked out 2026-08-22 (16 workload families audited, waves 1-3 defined); Wave 1 blocked only on decisions D1-D3
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

Re-audited and worked out per app on 2026-08-22 against the live cluster. This section is the
whole plan: scope, the evidence method, the classification axis, every affected workload, and the
open decisions. It supersedes the earlier sketch.

### Scope — the live allow-world set (2026-08-22 re-audit)

Grant mechanism unchanged: `kubernetes/apps/kube-system/cilium/netpols/allow-world-egress.yaml:13-23`
gives `0.0.0.0/0` minus RFC1918 + CGNAT to any pod labeled `egress.home.arpa/allow-world="true"`.
Spec 2 (lines 24-38) grants world to the `flux-system` / `cert-manager` namespaces — vendored,
unlabelable controllers, explicitly **out of scope** for this roadmap item.

Sixteen labeled workload families carry the label today:

| namespace | workload | where the label sits |
|---|---|---|
| downloads | bazarr, maintainerr, prowlarr, qbittorrent, radarr, recyclarr, seerr, sonarr | `app/helmrelease.yaml` `defaultPodOptions.labels` |
| media | crosswatch, isponsorblocktv, jellyfin, plex | same |
| observability | alertmanager, speedtest-exporter | kube-prometheus-stack `alertmanagerSpec.podMetadata.labels` / app helmrelease |
| selfhosted | mealie, wallos | app helmrelease |
| volsync-system | kopia, KopiaMaintenance pods, ReplicationSource movers, ReplicationDestination movers | kopia helmrelease + `moverPodLabels` in `kopiamaintenance.yaml` and `components/volsync/replication{source,destination}.yaml` |

Corrections to the earlier audit list: **homepage is already converted** (custom-egress + a CNP
allowing only `api.openweathermap.org` and kube-apiserver) — drop it. **crosswatch, jellyfin,
alertmanager and the whole backup plane were missing** from it.

### Evidence method — use the FQDN cache, not a 300 s capture

The earlier plan started from `just k8s hubble-live-capture 300`. There is a strictly better
starting point: Cilium's own per-endpoint DNS cache, which is *exactly* the data `toFQDNs` matches
on, accumulated over the DNS TTL window instead of a five-minute slice.

- [method] dump `cilium-dbg fqdn cache list -o json` and `cilium-dbg endpoint list -o json` from
  the `cilium` DaemonSet, join them on `endpoint-id` → `k8s:app.kubernetes.io/name`, drop
  `*.cluster.local`. Cluster commands need `dangerouslyDisableSandbox: true`.
- [method] entries carry `source: lookup` (the L7 proxy saw the query) or `source: connection`
  (TTL expired, a connection still holds the mapping). Both are proxy-derived; a name that never
  appears was never resolved through the proxy.
- [method] keep `hubble-live-capture` + `hubble-analyze <label> DROPPED egress` for the **after**
  check — that is what surfaces a missing FQDN.
- [caveat] one snapshot is one TTL window. Before converting an app, take snapshots across several
  days *and* deliberately exercise the app's outbound features (a manual search, a metadata
  refresh, a notification test), otherwise the allow-list only covers the idle path.

Observed in the 2026-08-22 window (real, per-pod, non-cluster names only):

| workload | observed destinations |
|---|---|
| prowlarr | bithumen.be, libranet.org, ncore.pro |
| qbittorrent | t.ncore.sh, t1/t2/t3.bithumen.net, t2.bithumen.be |
| radarr | image.tmdb.org |
| sonarr | thexem.info |
| seerr | api.github.com |
| isponsorblocktv | www.youtube.com (all `source: connection`) |
| alertmanager | hc-ping.com |
| speedtest-exporter | www.speedtest.net, cli.speedtest.net, results.speedtest.net + 10 distinct Hungarian ISP speedtest hosts |
| onepassword-connect (already converted) | my.1password.com, b5n.1password.com |
| external-dns (already converted) | api.cloudflare.com |

Nothing was observed for bazarr, maintainerr, crosswatch, jellyfin, plex, mealie, wallos, recyclarr
or the backup plane in this window — an idle window, not proof of no need.

### The classification axis — who owns the destination list

The useful split is **not** "bounded vs unbounded destinations". Several apps have a short
destination list that is nonetheless the wrong thing to freeze in git. Three classes:

1. **Image/git-owned** — the destinations are compiled into the app or written in this repo. A new
   destination arrives only with a version bump or a manifest edit, both of which are reviewed.
   → convert.
2. **UI-owned** — the human adds destinations by clicking in the app's own web UI (indexers,
   subtitle providers, notification agents, scraped recipe URLs). Converting installs a
   silent-breakage trap: the next indexer added in the UI resolves fine and then gets dropped, and
   the app reports a generic timeout. → do not convert without an explicit, accepted tradeoff.
3. **DNS-blind** — the pod reaches raw IPs, or its resolver bypasses Cilium's L7 DNS proxy.
   `toFQDNs` cannot see these at all. → structurally impossible, keep allow-world.

### Load-bearing finding — prowlarr is the indexer concentrator

`kubernetes/apps/downloads/prowlarr/app/ciliumnetworkpolicy.yaml` admits radarr and sonarr on
prowlarr's API port 9696, which is Prowlarr's sync-to-arr model: the indexer definitions Prowlarr
pushes into the *arr instances point back at **prowlarr**, not at the tracker. The FQDN cache
matches — the tracker hostnames (ncore.pro, bithumen.be, libranet.org) appear under **prowlarr
only**, never under sonarr or radarr.

Consequence: sonarr and radarr do not need the tracker hosts, only their metadata providers. That
moves them from "probably keep-open" to convertible, and it makes prowlarr the one app whose
permanent openness buys the closure of two others. **Confirm with a multi-day capture before
converting** — a single indexer configured directly in sonarr/radarr would break.

### Wave 1 — single-destination, image/git-owned (lowest risk, do first)

**1. recyclarr** (`kubernetes/apps/downloads/recyclarr/`, CronJob, @daily)
- Internet: the TRaSH-Guides git clone → `github.com` + `*.github.com`, `raw.githubusercontent.com`.
- In-cluster: radarr `:7878`, sonarr `:8989` (`!env_var` interpolation in `recyclarr.yml`). The
  callee-side CNPs on radarr/sonarr already admit recyclarr, so only the egress side is new.
- Lowest blast radius in the fleet: it runs once a day, and a failure is a failed Job, not a
  user-visible outage. Best first conversion.
- Selector check: the pod is a CronJob child — confirm it carries the
  `app.kubernetes.io/name|instance|controller: recyclarr` triple the house CNPs select on.

**2. Backup plane** — kopia UI + KopiaMaintenance + ReplicationSource movers + ReplicationDestination movers
- One destination for all four: the OVH S3 endpoint, `s3.de.io.cloud.ovh.net` (apex + `*.` wildcard,
  443) — the same host `kubernetes/apps/selfhosted/backrest/app/ciliumnetworkpolicy.yaml` already
  names.
- Mover pods are generated by the VolSync operator, so a per-app CNP is the wrong shape. This is
  where the roadmap's **Option 2 (shared allow-list CCNP)** wins: a new
  `kubernetes/apps/kube-system/cilium/netpols/allow-s3-egress.yaml` selecting
  `egress.home.arpa/allow-s3="true"` with the `toFQDNs` rule, then swap `allow-world` →
  `custom-egress` + `allow-s3` in four places: the kopia helmrelease, `kopiamaintenance.yaml`
  `moverPodLabels`, and both `components/volsync/replication{source,destination}.yaml`
  `moverPodLabels`.
- Rule of Three is met four times over, so the shared CCNP is not speculative machinery. But it is
  a **sixth label in the AD-023 frozen 5-label vocabulary** → needs an AD-023 revision entry, not a
  silent addition. Decision D1 below.
- [caveat] the endpoint is currently secret-delivered (`ovh_s3_endpoint` from 1Password, rendered
  into `AWS_S3_ENDPOINT` / `repository.config`). Naming it in a CNP hardcodes in git what git does
  not hold today. Backrest already set that precedent. Cost of the coupling: changing the OVH region
  silently breaks every backup until the CCNP is edited too. Decision D2 below.
- Fallback if D1/D2 are declined: convert only the kopia UI pod with a per-app CNP and leave the
  movers on allow-world. Much less value — the movers are the pods that hold the S3 credentials.

**3. alertmanager** (`kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml:72`)
- Internet: `api.pushover.net` (the only receiver, `alertmanagerconfig.yaml:58-92`) and
  `hc-ping.com` (observed). Both git-owned; nothing else.
- In-cluster: alertmanager is a receiver, not a caller — no peers at one replica. Verify no
  in-cluster egress before relying on `custom-egress` stripping the baseline.
- Selector: the Prometheus-Operator StatefulSet pod labels, **not** the app-template triple.
- Payoff note: the comment on line 67 already says "observability is NOT free-world" — this
  conversion is that comment becoming true.

### Wave 2 — multi-destination, image/git-owned (one app per session)

**4. crosswatch** (`kubernetes/apps/media/crosswatch/`) — highest payoff, do it first in this wave.
Its own progress note already flags round-1's allow-world as "WIDER than the roadmap P2 expectation"
and requires narrowing "before the app holds Plex/Jellyfin/SIMKL credentials". Candidate set:
`api.trakt.tv` + `*.trakt.tv`, `api.simkl.com` + `*.simkl.com`, `api.themoviedb.org` +
`image.tmdb.org`, `plex.tv` + `*.plex.tv`; in-cluster plex `:32400` and jellyfin `:8096`. The plex
CNP already admits crosswatch. Narrow only the providers actually enabled — the importer called
none of them at round-1.

**5. sonarr** — metadata only, given the prowlarr finding: `services.sonarr.tv` (Skyhook),
`thexem.info` (observed), `*.thetvdb.com` (artwork), `github.com` + `api.github.com` (update check).
In-cluster: prowlarr `:9696`, qbittorrent `:8080`.

**6. radarr** — same shape: `api.themoviedb.org` + `image.tmdb.org` (observed), `api.radarr.video`,
`github.com` + `api.github.com`. In-cluster: prowlarr `:9696`, qbittorrent `:8080`.

**7. seerr** — `api.themoviedb.org` + `image.tmdb.org`, `plex.tv` + `*.plex.tv`, `api.github.com`
(observed, release check). In-cluster: radarr `:7878`, sonarr `:8989`, plex `:32400`. **Check the
configured notification agents first** — those are UI-owned and would demote seerr to class 2.

**8. maintainerr** — `api.themoviedb.org` + `image.tmdb.org`; in-cluster plex `:32400` and
seerr `:5055`. The plex CNP already admits maintainerr. Smallest Wave-2 unit.

### Wave 3 — keep allow-world, documented exceptions

Each of these gets a one-line rationale comment next to its label so the exception reads as a
decision, not an oversight. No CNP, no conversion attempt.

| workload | class | why it stays open |
|---|---|---|
| qbittorrent | DNS-blind | DHT/PEX peers are raw IPs with no DNS lookup; `toFQDNs` never sees them. Permanent. |
| isponsorblocktv | DNS-blind | `dnsPolicy: None` + a ctrld DoH sidecar (`nameservers: 127.0.0.1, ${CLUSTER_DNS_IP}`). Names resolved by ctrld never reach Cilium's L7 proxy. The cache did record `www.youtube.com` for this pod (all `source: connection`), so part of the resolution falls through to cluster DNS — but the split is not deterministic, so an allow-list would be non-deterministically enforced. Permanent while the DoH sidecar stays. |
| prowlarr | UI-owned | The tracker list is the app's purpose and is edited in its UI; several indexers move between mirrors. Keeping prowlarr open is what lets sonarr and radarr close — an accepted, deliberate concentration. |
| plex | UI-owned + churn | `*.plex.direct` per-server certs plus a large upstream metadata CDN set that Plex changes without notice. |
| jellyfin | already decided | `docs/progress/jellyfin` records the decision: metadata providers plus the plugin catalog would be "a fragile, high-maintenance list". Cross-referenced here so the two notes cannot drift; revisit only by revisiting that decision. |
| mealie | UI-owned by design | Recipe import scrapes arbitrary user-supplied URLs — open egress *is* the feature. |
| speedtest-exporter | churn | The server is chosen per run from speedtest.net's dynamic pool; 13 distinct hosts appeared in a single TTL window. Pinning it would pin the measurement. |

**Deferred, not classified — needs a human call:**

- **bazarr** — subtitle providers are toggled in the UI (opensubtitles, podnapisi, feliratok.eu, …)
  and there is a `git-sync` sidecar pulling a provider repo from GitHub. Convertible in principle,
  class 2 in practice.
- **wallos** — the exchange-rate provider and the logo fetches are configuration/vendor-driven. Its
  observed set is empty so far. Re-classify after a capture that exercises a subscription add.

### The per-app work unit

One commit per app, containing **both** halves — AD-023's B-csapda rule: a label swap without its
CNP is a broken app, and the two must never be split across commits.

1. In `app/helmrelease.yaml`, swap `egress.home.arpa/allow-world: "true"` →
   `egress.home.arpa/custom-egress: "true"`. Keep every `ingress.home.arpa/*` label as-is.
2. Add `app/ciliumnetworkpolicy.yaml` and register it in `app/kustomization.yaml`.
3. Commit: `🔒 refactor(<app>): scope egress to an FQDN allow-list`.

Template — modelled on the live `backrest` / `plex-trakt-sync` / `homepage` CNPs, with the house
comment style (why, not what) and AD-023's full-domain granularity (`matchName` apex +
`matchPattern "*.apex"`):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/cilium.io/ciliumnetworkpolicy_v2.json
# <app> (AD-023): custom-egress opt-out makes this CNP the sole egress source. DNS rides the cluster-wide allow-dns-egress CCNP.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: <app>
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: <app>
      app.kubernetes.io/instance: <app>
      app.kubernetes.io/controller: <app>
  egress:
    - toFQDNs:
        - matchName: "api.example.com"
        - matchPattern: "*.example.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: <ns>
            app.kubernetes.io/name: <peer>
      toPorts:
        - ports:
            - port: "<peer-port>"
              protocol: TCP
```

**Correction to the earlier sketch**: it re-granted `toEndpoints: [{}]` + `toEntities: [cluster]`,
which hands back full in-cluster egress and throws away half the containment. `custom-egress`
removes the baseline on purpose — name the specific peers instead, the way every live CNP in the
repo does. `kube-apiserver` is re-granted only if the app actually calls it (homepage does; none of
the apps above do).

### Verification (per app)

1. **Before** — multi-day FQDN-cache snapshots plus a deliberate exercise of the app's outbound
   features. Build the allow-list from that, not from upstream docs alone.
2. **After commit + reconcile** — `kubectl get cnp -n <ns> <app>` exists; the endpoint shows egress
   enforcement in `cilium endpoint list`.
3. **After** — `just k8s hubble-live-capture 300` during normal use, then
   `just k8s hubble-analyze k8s:app.kubernetes.io/name=<app> DROPPED egress`. Any DROP to a public
   IP is a missing FQDN. `... FORWARDED egress` should show only the allow-listed names.
4. **Functional** — exercise the feature the destinations serve (a recyclarr sync run, a Pushover
   test alert, a manual search, a backup run) and confirm success, not just absence of drops.
5. **Standing monitoring** — the `dns-exfil` and `hubble-policy-deny` PrometheusRules already alert
   on policy denies, so a regression that only shows up days later still surfaces.

Rollback is `git revert` of the single commit: the label swap and the CNP go back together.

### Open decisions (need a human call before Wave 1)

- **D1 — AD-023 vocabulary extension.** Add a sixth label, `egress.home.arpa/allow-s3`, with a
  shared `allow-s3-egress` CCNP for the four backup-plane pod families? The vocabulary was frozen
  at the first fleet commit, so this is an AD-023 revision (rev4), not a manifest edit. Rule of
  Three is met. Recommend yes — the alternative leaves the credential-holding mover pods on open
  egress.
- **D2 — the OVH S3 endpoint in git.** Naming `s3.de.io.cloud.ovh.net` in a CCNP couples the
  backup plane's policy to a value 1Password currently owns. Backrest already does it. Recommend
  yes, with the coupling written into the file's comment.
- **D3 — the UI-owned apps.** Convert bazarr (and wallos) accepting the silent-breakage trap, or
  leave them open? Recommend leaving them open until there is a reason to change; the trap costs
  more than the two apps' exposure.

### Adjacent finding (not part of this item — needs its own issue)

`mealie` and `wallos` both do **server-side** OIDC discovery against `idm.${PUBLIC_DOMAIN}`
(`OIDC_CONFIGURATION_URL` / `OIDC_ISSUER`), which split DNS resolves to the internal gateway VIP on
the LAN. The allow-world CCNP explicitly *excepts* `192.168.0.0/16`, and neither pod carries
`egress.home.arpa/allow-gateways` — unlike actual, homepage, paperless and pingvin-share-x, which
all do. Either their server-side discovery is failing, or it takes a path not yet traced. Worth
testing an OIDC login on both; it is a live-behaviour question, not an egress-narrowing one.

### Effort

Wave 1 ≈ one session for all three units (recyclarr, backup plane, alertmanager), assuming D1–D2
are answered. Wave 2 ≈ one app per session, five sessions. Wave 3 is comment-only. Low urgency,
high ratio: Wave 1 alone removes open egress from the pods holding the S3 backup credentials and
the Pushover token.

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
