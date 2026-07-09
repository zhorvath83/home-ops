---
title: cnp-per-app-audit
type: roadmap
permalink: home-ops/docs/roadmap/cnp-per-app-audit
topic: Hybrid CNP rollout runbook — label vocabulary + world-deny flip; per-app CNPs
  only for app-unique content
status: in_progress
priority: medium
scope: Execution-grade runbook for AD-023 rev2. Contains the full YAML of every cluster
  policy, the per-app label assignment for all namespaces, the exact edit/verify commands
  and acceptance criteria per phase. An executor should be able to work through V1-V5
  without making design decisions; anything undecided is explicitly marked (survey)
  or listed under Open questions.
rationale: AD-023 rev2 defines the model and the why; this note is the how, in executable
  detail. Two-tier model — 5-label vocabulary backed by generic-grant CCNPs + hand-written
  per-app CNPs only for app-unique content. Baseline egress goes fail-closed against
  internet AND LAN.
options:
- 'Phase V1: vocabulary CCNPs + labels + boilerplate migration (staged, zero-downtime)'
- 'Phase V2: survey — world-needers, LAN-consumers, DNS bypassers, apiserver entity'
- 'Phase V3: flip — world out of baseline + every grant in ONE commit'
- 'Phase V4: verify + permanent DROPPED alerting'
- 'Phase V5: remainder — downloads east-west, narrow-world tightening, LB fromCIDR'
related_areas:
- networking
- k8s-workloads
decision_link: AD-023-cnp-threat-model-audit
---

# Hybrid CNP rollout — execution runbook

## Metadata (observation-form, schema validation)

- [topic] Hybrid CNP rollout runbook — label vocabulary + world-deny flip; per-app CNPs only for app-unique content
- [status] in_progress
- [progress] Execution state lives in [[cnp-per-app-audit]] (docs/progress) — phase tracker, session summaries, Next pointer
- [priority] medium

## Definitions (use these exact strings everywhere)

- [observation] Labels: egress.home.arpa/custom-egress, egress.home.arpa/allow-world, ingress.home.arpa/gateways, ingress.home.arpa/prometheus, ingress.home.arpa/none — value is always "true"; names FROZEN after the first V1 commit
- [observation] New CCNP files (all in kubernetes/apps/kube-system/cilium/netpols/, each added to that dir's kustomization.yaml): allow-world-egress.yaml, ingress-from-gateways.yaml, ingress-from-prometheus.yaml, ingress-none.yaml
- [observation] Default pod after V3 (no labels, no CNP): full in-cluster egress + DNS; NO internet, NO LAN; ingress open until an ingress label or per-app CNP closes it

## Current state (live today)

- [observation] Baseline fail-open: allow-cluster-egress grants cluster + world (flip pending V3); allow-dns-egress live with L7 proxy
- [observation] Verified per-app CNPs live: onepassword-connect (narrow-world), external-secrets x3 (no-world) — KEEP, trim boilerplate in V1
- [observation] CNP files replaced by labels in V1: actual, paperless, home-gallery, pingvin-share-x, homepage; migrate convention: tinyauth, pocket-id, paperless-gpt
- [observation] Platform CNPs: envoy-external/internal (no egress section — world assumption surveyed in V2), cloudflare-tunnel (tight, cidrGroupRef, unaffected)
- [observation] CoreDNS autopath OFF (toFQDNs prerequisite); FluxInstance cluster.networkPolicy: false (grants come from OUR vocabulary)

## How to set pod labels (mechanics reference)

- [observation] bjw-s app-template (most apps): defaultPodOptions.labels (all pods of the release) OR controllers.<name>.pod.labels (one controller only — use for paperless main pod). Both emit into the pod template (verified with helm template app-template 5.0.1)
- [observation] external-secrets chart: per-component podLabels (controller / webhook / certController) — already carries custom-egress from Phase 2b
- [observation] other charts: find the chart's podLabels-equivalent value; ALWAYS verify emission before merge: flux-local build + helm template, grep the rendered pod template for the label
- [observation] CronJob/Job templates do NOT inherit controller pod labels automatically in all charts — check rendered output separately (paperless-backup case)

## Cluster policy YAML (V1/V3 authoritative content)

### allow-cluster-egress (V3 edit — kubernetes/apps/kube-system/cilium/netpols/allow-cluster-egress.yaml)

```yaml
spec:
  endpointSelector:
    matchExpressions:
      - {key: egress.home.arpa/custom-egress, operator: DoesNotExist}
  egress:
    - toEndpoints: [{}]
    - toEntities: [cluster]
    - toEntities: [kube-apiserver]   # explicit: probe-identity caution (AD-023)
    # 'toEntities: [world]' REMOVED at V3 — this line is the flip
```

### allow-world-egress.yaml (NEW at V1; inert until pods carry the label)

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: allow-world-egress
specs:
  - endpointSelector:
      matchLabels: {egress.home.arpa/allow-world: "true"}
    egress:
      - toCIDRSet:
          - cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12      # NOT 175.16 — gabe565 typo is the cautionary tale
              - 192.168.0.0/16
              - 100.64.0.0/10
  - endpointSelector:
      matchExpressions:
        - {key: io.kubernetes.pod.namespace, operator: In, values: [flux-system, cert-manager]}
    egress:
      - toCIDRSet:
          - cidr: 0.0.0.0/0
            except: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10]
```

### ingress-from-gateways.yaml (NEW at V1; staged)

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: ingress-from-gateways
spec:
  endpointSelector:
    matchLabels: {ingress.home.arpa/gateways: "true"}
  enableDefaultDeny:
    ingress: false        # V1 staging; REMOVE this block in the V1 activation commit
  ingress:
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: networking
            app.kubernetes.io/name: envoy
          matchExpressions:
            - {key: gateway.envoyproxy.io/owning-gateway-name, operator: In, values: [envoy-external, envoy-internal]}
```

### ingress-from-prometheus.yaml (NEW at V1; staged same way)

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: ingress-from-prometheus
spec:
  endpointSelector:
    matchLabels: {ingress.home.arpa/prometheus: "true"}
  enableDefaultDeny:
    ingress: false        # V1 staging; remove at activation
  ingress:
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: observability
            app.kubernetes.io/name: prometheus
```

### ingress-none.yaml (NEW at V1; staged same way)

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: ingress-none
spec:
  endpointSelector:
    matchLabels: {ingress.home.arpa/none: "true"}
  enableDefaultDeny:
    ingress: false        # V1 staging; remove at activation
  ingress:
    - fromEntities: [kube-apiserver]   # guaranteed-semantics near-deny
```

### coredns CNP (NEW file in the V3 flip commit — kubernetes/apps/kube-system/coredns/app/ciliumnetworkpolicy.yaml + kustomization entry)

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: coredns
  namespace: kube-system
spec:
  endpointSelector:
    matchLabels: {k8s-app: kube-dns}
  egress:
    - toEntities: [world]
      toPorts:
        - ports:
            - {port: "53", protocol: UDP}
            - {port: "53", protocol: TCP}
```

## Per-app assignment (label sets + CNP action per namespace)

Legend: V1 = label added in Phase V1; V3 = label/grant lands IN the flip commit; V5 = Phase V5 item; (survey) = V2 decides. HR path = kubernetes/apps/<ns>/<app>/app/helmrelease.yaml unless noted.

### downloads (bazarr, maintainerr, prowlarr, qbittorrent, radarr, seerr, sonarr, subsyncarr)

- [observation] V1: NO ingress labels — the *arr apps consume each other east-west; an ingress label would cut sibling traffic before the named-consumer CNPs exist. SEQUENCING RULE: downloads ingress closure is V5-only, together with the per-target named-consumer CNPs
- [observation] V3: egress.home.arpa/allow-world on qbittorrent, prowlarr, radarr, sonarr, bazarr, seerr (external indexers/peers/APIs); maintainerr + subsyncarr (survey — if in-cluster-only, nothing)
- [observation] V5: ingress.home.arpa/gateways + ingress.home.arpa/prometheus (where ServiceMonitor exists) on each + one hand-written CNP per TARGET listing its real sibling consumers (prowlarr->arr, arr->qbittorrent, seerr/bazarr->arr), pairs from an activity-triggered Hubble capture; PREREQUISITE: fix stale .media.svc cross-links in the *arr app configs first

### media

- [observation] plex: V3 allow-world (plex.tv); V5 hand-written CNP — ingress fromCIDR <LAN subnet> to 32400 (LB app) + prometheus; NO gateways label (not envoy-routed)
- [observation] plex-trakt-sync: V3 allow-world (trakt/plex APIs); V5 candidate: narrow-world CNP + ingress.home.arpa/none (worker, no consumers)
- [observation] isponsorblocktv: V3 allow-world (youtube/google APIs) AND its pod-to-LAN CNP MUST land in the V3 flip commit (LAN TVs unreachable otherwise): hand-written CNP, egress toCIDR <TV IPs or LAN /24> — precise CIDR from V2 survey
- [observation] calibre-web-automated: V1 gateways; V3 allow-world (metadata fetch — confirm in survey)

### selfhosted

- [observation] actual: V1 gateways (custom-egress already on pod); TRIM app/ciliumnetworkpolicy.yaml in the same commit — keep the toFQDNs enablebanking.com:443 egress (the pod custom-egress label opts it out of the baseline allow-cluster-egress CCNP, so the CNP is its only egress grant), drop the envoy ingress block (to ingress-from-gateways CCNP). No ServiceMonitor under actual (verified V1 commit 3) so no prometheus label. [corrected V1 commit 3: runbook originally said DELETE, which would have left actual with zero egress and broken bank-transaction fetch]
- [observation] home-gallery: same pattern as actual
- [observation] pingvin-share-x: same pattern as actual
- [observation] paperless: V1 gateways via controllers.paperless.pod.labels (main pod ONLY — backup CronJob must stay label-free); custom-egress stays main-pod-scoped; TRIM CNP file — keep the paperless-gpt to paperless:8000 named-consumer ingress rule (east-west, not covered by any CCNP), drop the envoy ingress block (to ingress-from-gateways CCNP); backup CronJob egress = (survey). [corrected V1 commit 3: runbook originally said DELETE, which would have dropped paperless-gpt east-west at activation]
- [observation] homepage: V1 gateways; V3 allow-world (github/openweathermap widgets); DELETE CNP file at V1
- [observation] mealie: V1 gateways; V3 allow-world (recipe import)
- [observation] wallos: V1 gateways; egress class (survey — currency APIs?)
- [observation] paperless-gpt: V1 gateways + DELETE its CNP file (the CNP is envoy-ingress-only — no named-consumer rule exists; an earlier runbook note confused paperless-gpt with paperless); the gateways CCNP fully replaces it; V3 allow-world TEMPORARY (LLM API would break at flip); V5 tighten to narrow-world toFQDNs + custom-egress, drop allow-world
- [observation] backrest: V1 gateways (browse UI); egress (survey — NFS repo traffic is host-level, likely no pod-network egress needed)
- [observation] resticprofile: (survey — worker; if pod-network egress exists, classify; else nothing + ingress.home.arpa/none candidate)

### security

- [observation] tinyauth: V1 gateways + prometheus (if scraped); its only consumer is the envoy ext-auth hop -> if its existing CNP contains ONLY envoy+prometheus blocks, DELETE it; egress to pocket-id is in-cluster (baseline covers)
- [observation] pocket-id: V1 gateways + TRIM its CNP to the named-consumer rule (tinyauth -> pocket-id) only; V2 survey: SMTP (if yes -> V5 narrow-world + custom-egress)

### observability

- [observation] grafana: V1 gateways + prometheus; V3 allow-world TEMPORARY (plugin/dashboard CDN at startup); V5 tighten to narrow-world (grafana.com + raw.githubusercontent.com) + custom-egress, drop allow-world
- [observation] kube-prometheus-stack: Class P — nothing; alertmanager outbound (survey — if it pushes to Pushover directly, V3 allow-world on alertmanager pod)
- [observation] speedtest-exporter: V1 prometheus; V3 allow-world
- [observation] victoria-logs server: V1 NO ingress labels (collector+grafana would be cut) — V5: gateways(internal)+prometheus labels + named-consumer CNP (collector, grafana) in ONE commit; egress: custom-egress + nothing (sink, DNS-only)
- [observation] victoria-logs collector: nothing — post-flip baseline covers its egress (server:9428 + apiserver + DNS, all in-cluster)

### networking

- [observation] echo: V1 gateways; nothing else
- [observation] external-dns: V3 allow-world (Cloudflare API); V5 candidate narrow-world (api.cloudflare.com)
- [observation] k8s-gateway: V5 hand-written CNP — ingress fromCIDR <LAN subnet> to 53 (LB DNS); egress in-cluster (baseline)
- [observation] envoy-gateway ext/int + cloudflare-tunnel: keep existing CNPs; V2 must confirm envoy initiates no world egress (its CNP comment assumes baseline world today)

### external-secrets

- [observation] onepassword-connect: V1 prometheus label + trim the prometheus ingress block from its CNP (keep ESO named-consumer ingress + toFQDNs egress + custom-egress)
- [observation] external-secrets x3: V1 prometheus labels (per-component podLabels) + trim prometheus blocks from the 3 CNPs (keep webhook fromEntities kube-apiserver rule and controller egress rules unchanged)

### kube-system / flux-system / cert-manager / system-upgrade / volsync-system

- [observation] coredns: V3 flip commit — targeted world:53 CNP (YAML above); NO allow-world label (full world too broad)
- [observation] cilium, democratic-csi, intel-gpu-resource-driver, metrics-server, reloader, snapshot-controller: nothing (in-cluster only / hostNetwork)
- [observation] flux-system (flux-instance, flux-operator, flux-provider-pushover): covered by the infra-namespace grant spec in allow-world-egress.yaml — no per-pod labels
- [observation] cert-manager: covered by the same namespace grant (ACME + Cloudflare DNS01)
- [observation] tuppr: V3 allow-world (factory.talos.dev, github releases — confirm in survey)
- [observation] kopia S3 access — THREE distinct pod roles, all need allow-world (OVH S3): (a) kopiaui Deployment (volsync-system/kopia/app/helmrelease.yaml, bjw-s app-template) → V1 commit 2 defaultPodOptions.labels: allow-world + ingress.home.arpa/gateways (pvbackup route, direct S3 via repository.config); (b) KopiaMaintenance CronJob (volsync-system/volsync/maintenance/kopiamaintenance.yaml, spawns kopia-maint-* pods) → V1 commit 2 spec.moverPodLabels (top-level, not under kopia); (c) VolSync kopia mover pods (app namespaces, spawned per backup/restore) → V1 commit 2 via components/volsync/{replicationsource,replicationdestination}.yaml spec.kopia.moverPodLabels — see the resolved Open Question. volsync controller itself: nothing (in-cluster only)

## Phase V1 — vocabulary (zero-downtime, 3 commits)

1. [observation] [step] Commit 1: add the 4 new CCNP files (YAML above, ingress ones WITH enableDefaultDeny staging) + kustomization.yaml entries. Validate: pre-commit run --all-files; flux-local build (as in Phase 3). Push, reconcile, check: kubectl get ccnp — 4 new, all Valid; zero behavior change expected
2. [observation] [step] Commit 2: add every V1 label from the assignment above (per-chart mechanics per the reference section); for each edited HR verify label emission (flux-local/helm template) BEFORE merge. Push, reconcile, restart pods where needed (label lands on pod template -> rollout). Check in Hubble: grants visible as FORWARDED matches, still zero denies
3. [observation] [step] Commit 3 (activation): remove the enableDefaultDeny blocks from the 3 ingress CCNPs + in the SAME commit trim/delete per-app CNPs per the assignment (delete: actual, home-gallery, pingvin, paperless, homepage, maybe tinyauth; trim: pocket-id, paperless-gpt, onepassword-connect, ESO x3) + remove deleted files from their kustomizations
4. [observation] [accept] per labeled app: just k8s hubble-live-capture 120 then hubble-analyze <real-pod-label> DROPPED ingress = empty; app healthy; routed apps respond via gateway; prometheus targets all Up; op-connect store Valid; ESO ExternalSecrets SecretSynced; cross-check app logs for connection errors
5. [observation] [rollback] any breakage: git revert the activation commit (labels+grants may stay — they are pure allows)

## Phase V2 — survey (no cluster changes; results recorded INTO this note)

1. [observation] [step] Static greps: grep -rnE 'dnsPolicy|podDnsConfig' kubernetes/ ; grep -rn 'hostNetwork: true' kubernetes/ ; grep -rln 'kind: ServiceMonitor' kubernetes/apps/ (prometheus-label completeness)
2. [observation] [step] Long activity-triggered capture: just k8s hubble-live-capture 300 while triggering: a download search+grab, paperless-backup CronJob, a VolSync sync + kopia maintenance, an ExternalSecret refresh, grafana pod restart, speedtest run, isponsorblocktv active
3. [observation] [step] Slice per candidate: just k8s hubble-analyze <label> '' egress — record every world FQDN/IP per app; separately record every 192.168.0.0/16 destination (pod-to-LAN consumers list + exact IPs for the isponsorblocktv CNP)
4. [observation] [step] apiserver entity check: from the capture, confirm pod->apiserver flows match toEntities cluster/kube-apiserver identities (mitigation already in baseline YAML)
5. [observation] [step] envoy world check: hubble-analyze the two envoy proxy labels, direction egress — expected: xDS + backends only, no world
6. [observation] [accept] this note updated: every (survey) mark above resolved to a concrete label/CNP/nothing decision

## Phase V3 — flip (ONE commit)

1. [observation] [step] The single commit contains: (a) allow-cluster-egress edit (drop world, add kube-apiserver entity — YAML above); (b) EVERY V3 label from the assignment (downloads, media, homepage, mealie, speedtest, external-dns, tuppr, grafana+paperless-gpt temporary, per V2 results) — note: kopia S3 labels (kopiaui + KopiaMaintenance + VolSync movers) already landed in V1 commit 2 as pure allows; (c) coredns CNP file; (d) NO isponsorblocktv LAN CNP — Session 6 confirmed the TV does NOT connect over LAN (the ctrld 0.0.0.0:53 listener has no Service/LB/NodePort exposure, only pod IP; the only pod→isponsorblocktv:53 ingress is cluster-internal CoreDNS forward, covered by baseline allow-cluster-ingress). isponsorblocktv's V3 action is the allow-world label in step (b) only (YouTube API + ctrld DoH egress); (e) any V2-discovered extra grant
2. [observation] [step] Pre-merge validation: pre-commit + flux-local build; grep the diff to confirm no app in the V2 world-needers list is missing its grant
3. [observation] [accept] post-reconcile: just k8s hubble-live-capture 300 under normal use -> hubble-analyze '' DROPPED egress: only expected noise (IPv6 NDP); coredns resolves external names; flux reconciles from github; cert-manager renews (or dry-run ACME check); external-dns syncs; kopia maintenance succeeds; NO app log shows new connection timeouts
4. [observation] [rollback] git revert <flip-commit> + flux reconcile — single revert restores world

## Phase V4 — verify + permanent monitoring

1. [observation] [step] Confirm Hubble metrics include policy verdicts (cilium HR: hubble.metrics.enabled must contain 'policy' or 'drop' — add if missing)
2. [observation] [step] Add a PrometheusRule (observability): alert on increase of hubble drop events with reason=policy_denied grouped by source pod, threshold tuned after 1 week baseline; route via existing alerting chain
3. [observation] [accept] alert fires on a deliberate test (curl to a denied world IP from a no-world pod), silent otherwise for 1 week
4. [observation] [step] 7-day soak: re-run the V3 acceptance capture once more at the end (startup-time and periodic-job drops surface late — capture windows lesson)

## Phase V5 — remainder (each item = one commit + verify)

- [observation] [item] downloads east-west closure: fix *arr cross-links (bare service names, app UI/DB config, NOT manifests) -> capture pairs -> per-target named-consumer CNPs + gateways/prometheus labels, one namespace-batch commit; verify DROPPED-clean under active downloading
- [observation] [item] grafana narrow-world: custom-egress label + CNP with toFQDNs (grafana.com apex + raw.githubusercontent.com apex, from V2 data) + REMOVE temporary allow-world; verify pod restart pulls plugins
- [observation] [item] paperless-gpt narrow-world: same pattern (LLM API domain from V2)
- [observation] [item] plex CNP: ingress fromCIDR <LAN /24> to 32400 + prometheus; k8s-gateway CNP: ingress fromCIDR <LAN /24> to 53; expect LB-VIP/service-identity edge cases — verify from a LAN client
- [observation] [item] victoria-logs server: gateways+prometheus labels + named-consumer CNP (collector, grafana) in one commit
- [observation] [item] pocket-id: SMTP result -> narrow-world if needed
- [observation] [item] worker isolation: ingress.home.arpa/none on plex-trakt-sync, resticprofile (if verified consumer-less)
- [observation] [item] external-dns narrow-world (api.cloudflare.com) — optional tightening
- [observation] [item] (l) DNS-exfil detection alert — full execution plan in section "V5 (l) — DNS-exfil detection alert (execution plan)" below
- [observation] [item] (m) ingress-from-gateways split into gateways-dual + gateways-internal — full execution plan in section "V5 (m) — gateways split (execution plan)" below; decision recorded in AD-023 rev3

## Operational facts (carried forward, still true)

- [observation] [tooling] just k8s hubble-live-capture <secs>, then hubble-analyze <full-cilium-label> <verdict> <direction>; use the app's REAL pod label (not always app.kubernetes.io/name)
- [observation] [transient] ~25s socketLB startup transient (no route to host to service ClusterIP) on every strict-egress pod restart — benign, self-heals
- [observation] [lesson] empty DROPPED capture is necessary but NOT sufficient — cross-check app logs
- [observation] [lesson] narrow-world allowlists from Hubble AND app logs; allow whole domains (matchName apex + matchPattern '*.apex')
- [observation] [prerequisite] CoreDNS autopath stays OFF; netkit datapath + socketLB.hostNamespaceOnly: false are load-bearing (AD-023)

## Open questions

- [observation] [resolved 2026-07-04] VolSync S3 world access — CRD-verified against live v0.17.11 perfectra1n fork: ReplicationSource.spec.kopia.moverPodLabels, ReplicationDestination.spec.kopia.moverPodLabels, AND KopiaMaintenance.spec.moverPodLabels ALL exist (type=object, "Labels added to data mover pods"). No namespace-grant / mover-targeted CCNP fallback needed. Four repo edits land in V1 commit 2 (pure allows, additive with the pre-flip baseline): (1) components/volsync/replicationsource.yaml spec.kopia.moverPodLabels: {egress.home.arpa/allow-world: "true"} — covers all ~21 apps consuming the component; (2) components/volsync/replicationdestination.yaml same field (bootstrap restore mover); (3) volsync-system/volsync/maintenance/kopiamaintenance.yaml spec.moverPodLabels (top-level, NOT under kopia) — the live kopia-maint-* pods run today without the label and break at flip without this; (4) volsync-system/kopia/app/helmrelease.yaml defaultPodOptions.labels: allow-world + ingress.home.arpa/gateways (kopiaui Deployment, pvbackup route, direct S3 via repository.config). Pre-flip verification: one full backup cycle + one kopia maintenance run after V1 commit 2, Hubble FORWARDED on the egress.home.arpa/allow-world label. Residual V2 item only: confirm ovh_s3_endpoint resolves to a public IP (record in the flip commit message)
- [observation] [open] ingress-none / pure empty-allow-set semantics — live-verify during V1 staging (fromEntities kube-apiserver variant is the committed fallback)
- [observation] [open] IPv6: CIDR math is v4-only — confirm v4-only cluster, record in flip commit message
- [observation] [governance] versions-renovate checklist: verify CNP-label emission on app-template MAJOR bumps

## V2 survey results (2026-07-05 — passive 300s capture + kopia-maint manual trigger)

- [observation] [V2-combined-capture 2026-07-05] 300s activity-triggered capture (user fired *arr indexer search + qbittorrent grab, homepage dashboard + mealie import + wallos refresh, plex-trakt-sync + speedtest). Zero policy-denied DROPPED (only pre-existing plex SSDP + IPv6 NDP).
- [observation] [V2-combined] world egress CONFIRMED → V3 allow-world for: bazarr (api.opensubtitles.com, feliratok.eu, www.feliratok.eu), prowlarr (bithumen.be, libranet.org, ncore.pro — indexer trackers), radarr (api.radarr.video, image.tmdb.org), sonarr (artworks.thetvdb.com, services.sonarr.tv, skyhook.sonarr.tv, thexem.info), seerr (api.themoviedb.org 183×, api.github.com, api.radarr.video, discover.provider.plex.tv, algolia.net), qbittorrent (t.ncore.sh:2810, t1.bithumen.net:443 + many BitTorrent peers), homepage (api.openweathermap.org), wallos (data.fixer.io:80 — currency API; runbook "wallos egress class (survey)" CONFIRMED → V3 allow-world), speedtest-exporter (cli.speedtest.net, results.speedtest.net + many HU ISP speedtest servers: telekom/yettel/digi/fiberwave/hostingbazis/opcnet/darksystems/giganet).
- [observation] [V2-combined NEW] **mealie → api.github.com + api.mistral.ai (18×) — mealie uses the Mistral AI LLM API** (AI recipe import feature). V3 allow-world covers it; V5 narrow-world candidate: toFQDNs api.github.com + api.mistral.ai + recipe-import sites + custom-egress, drop allow-world. Runbook "mealie: V3 allow-world (recipe import)" confirmed; add mistral.ai to the V5 allowlist.
- [observation] [V2-combined] maintainerr + subsyncarr: ZERO flows in the capture (not triggered / idle) — no world egress observed → tentatively V3 nothing (confirm with a targeted trigger if needed; runbook had them as survey).
- [observation] [V2-combined] plex-trakt-sync: ZERO flows — the sync trigger did not fire external API calls during the window. Still pending (runbook V3 allow-world for trakt/plex APIs). backrest + resticprofile: ZERO flows — no pod-network egress observed (backrest NFS repo is host-level → runbook survey "likely no pod-network egress" confirmed tentatively V3 nothing). paperless-gpt, tuppr, pocket-id, calibre-web-automated, grafana: not triggered this round (cluster-mutating deferred / not fired) — (survey) marks still open.
- [observation] [V2-combined] source-controller → world:100.58.78.182:443 (5×): 100.58.x.x is OUTSIDE the 100.64/10 CGNAT except (100.64.0.0/10 starts at 100.64), so treated as world → covered by the flux-system infra-namespace grant at V3. Not a blocker (likely a registry mirror on a public IP). flux-operator → pkg-containers.githubusercontent.com + 185.199.110.154, notification-controller → api.github.com: both flux-system, covered by the infra-namespace grant. ✅
- [observation] [V2-combined] LAN egress in the combined capture is IDENTICAL to the passive set (prometheus→192.168.1.1:9100 V3-blocker, kube-apiserver→192.168.1.1:53, k8s-gateway ingress :1053 from 192.168.1.1, envoy-internal ingress :10443 from 192.168.1.100) — no new pod-to-LAN consumers. The prometheus→router scrape is CONTINUOUS (20 flows in both captures), confirming the V3 grant is mandatory, not a one-off.

- [observation] [V2-step1] dnsPolicy/podDnsConfig grep: ONLY isponsorblocktv (`dnsPolicy: None` + `dnsConfig.nameservers: [127.0.0.1, \${CLUSTER_DNS_IP}]`). The `app` container's DNS goes to the localhost `ctrld` sidecar, which forwards over DoH to dns.controld.com (world egress that BYPASSES CoreDNS) — so the V3 coredns CNP does NOT cover isponsorblocktv's DNS upstream. Covered by isponsorblocktv's V3 allow-world label (see egress finding below: 76.76.2.22).
- [observation] [V2-step1] hostNetwork grep: NONE — no pod bypasses the pod network.
- [observation] [V2-step1] ServiceMonitor grep: repo `grep kind: ServiceMonitor` finds ONLY envoy-gateway/config/observability.yaml (hand-written). bjw-s app-template-generated ServiceMonitors do NOT appear as `kind: ServiceMonitor` literals in the repo — static grep UNDERCOUNTS. Use live `kubectl get servicemonitor -A` for prometheus-label completeness (the V1 commit 2 reconciliation already used the live list).
- [observation] [V2-step1] alertmanager is NOT deployed (kube-prometheus-stack has only grafana, kube-state-metrics, operator, node-exporter, prometheus, speedtest-exporter, victoria-logs-collector/server). Runbook item "alertmanager outbound (survey — Pushover)" = N/A. Pushover route is via flux notification-controller (in-cluster, covered by the infra-namespace grant in allow-world-egress). No V3 action.
- [observation] [V2-residual] ovh_s3_endpoint = s3.de.io.cloud.ovh.net (provision/ovh/buckets.tf:13, hardcoded region DE) resolves to 141.95.67.80 — PUBLIC OVH IP, not in any private CIDR (10/8, 172.16/12, 192.168/16, 100.64/10). Residual V2 item RESOLVED. kopia S3 egress is genuine world egress → the allow-world label grant is the correct model.

- [observation] [V2-kopia-maint VERIFIED] Manual trigger (user) spawned kopia-maint-...-manua4v9hm @ 2026-07-05T09:35:35Z carrying `egress.home.arpa/allow-world: true` — confirms KopiaMaintenance.spec.moverPodLabels propagates to the spawned pod (the CRD field works on a live pod, not just the CR spec). Hubble: 995× FORWARDED to fqdn:s3.de.io.cloud.ovh.net:443; zero policy-denied DROPPED (only IPv6 NDP noise); pod phase=Succeeded. V3-blocker for kopia-maint: CLEARED.
- [observation] [V2-VolSync mover UNVERIFIED] No ReplicationSource kopia mover pod has run since V1 commit 2 (all RS are trigger-only; paperless-backup CronJob @ 00:30 UTC is the next natural mover spawn — last ran 2026-07-05 00:30 UTC, pre-push). moverPodLabels propagation to a live VolSync mover pod remains UNVERIFIED. REMAINING V3-blocker: capture a VolSync backup run (manual trigger or wait for paperless-backup @ 2026-07-06 00:30 UTC), confirm the mover pod carries egress.home.arpa/allow-world AND S3 egress FORWARDED.

- [observation] [V2-step3 world egress observed → concrete V3 grant decisions]
  - qbittorrent: BitTorrent peers (many world IPs; TCP 16881/16882/22000/26566/38028/50415/55780/57836 + UDP 44333/4713/6881/15333/27435/41826/52656/54784/54811/19371) → V3 allow-world ✅ (runbook correct)
  - isponsorblocktv: YouTube/Google (142.251.13.91, 142.251.20.190, www.youtube.com) + ControlD DoH (76.76.2.22:443 — the ctrld sidecar) → V3 allow-world covers BOTH ✅
  - external-dns: api.cloudflare.com (104.19.192.174/177) → V3 allow-world ✅
  - plex: plex.tv (139.162.158.105:443) → V3 allow-world ✅
  - seerr: api.github.com:443 → V3 allow-world (downloads) ✅
  - onepassword-connect: 1password.com (13.226.244.60:443) → existing toFQDNs egress CNP kept (V1 commit 3 trimmed) ✅
  - kopia (kopiaui Deployment, volsync-system/kopia): s3.de.io.cloud.ovh.net:443 (1832 flows) → V1 commit 2 allow-world label ✅
  - kopia-maint: s3.de.io.cloud.ovh.net:443 (995 flows) → V1 commit 2 moverPodLabels ✅
  - source-controller: ghcr.io, quay.io, mirror.gcr.io, github (140.82.121.33/34, 142.251.127.82, 34.203.5.212) → flux-system infra-namespace grant in allow-world-egress CCNP ✅
  - cloudflare-tunnel: region1.v2.argotunnel.com:7844 UDP (198.41.192.x/200.x) → existing cloudflare-tunnel CNP ✅
  - kube-apiserver → world:18.117.76.15:443 (20 flows, AWS us-east-2): apiserver entity, NOT pod-selected by baseline → flip does NOT affect. OPEN: identify purpose (OIDC JWKS? webhook?) — not a V3-blocker.

- [observation] [V2-step3 LAN (192.168/16) egress observed]
  - **prometheus → 192.168.1.1:9100 (20 flows TCP) — V3-BLOCKER**: prometheus scrapes the OpenWRT router's node-exporter via additionalScrapeConfigs job `openwrt` target `\${ROUTER_IP}:9100` (kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml:452). The flipped baseline (drop world + allow-world-egress excepts 192.168/16) will DROP this at V3. ACTION: add a per-app CNP for prometheus (observability) — egress toCIDR 192.168.1.1/32 toPorts 9100/TCP — IN the V3 flip commit. Runbook "kube-prometheus-stack: Class P — nothing" CORRECTED: the prometheus pod needs this one LAN egress grant (everything else Class P).
  - kube-apiserver → 192.168.1.1:53 (154 TCP + 5 UDP): apiserver DNS to router; apiserver entity, not affected by flip. No action.
  - world:192.168.1.1 → k8s-gateway:1053 (13 UDP): LAN router DNS query to k8s-gateway on port 1053 (NOT 53). Runbook V5 k8s-gateway CNP "ingress fromCIDR LAN to 53" → CORRECTED port is 1053 (verify k8s-gateway Service port). Ingress, V5 item.
  - world:192.168.1.100 → envoy-internal:10443 (49 UDP + 6 TCP): LAN client to envoy-internal. Existing envoy-internal CNP already has fromCIDR 10/8,172.16/12,192.168/16 → 10080,10443 TCP+UDP. ✅ No action.
  - isponsorblocktv: NO pod→LAN egress observed in the passive window. Runbook "isponsorblocktv pod-to-LAN CNP MUST land in V3 (LAN TVs unreachable otherwise)" → CORRECTION PROPOSED: isponsorblocktv has NO ingress label, so its ingress stays OPEN post-flip (the 3 ingress CCNPs only select labeled pods; baseline is egress-only); TVs reach isponsorblocktv:53 without any LAN CNP. The CNP requirement appears unnecessary. Confirm with an active TV-watching capture (V2 activity-triggered) before finalizing.

- [observation] [V2-step4 apiserver entity check] pod→apiserver flows (external-secrets-cert-controller, external-dns, k8s-gateway, victoria-logs-collector, reloader, cert-manager-webhook, coredns, metrics-server → kube-apiserver:6443/10250/9100) all match the reserved:kube-apiserver identity. Baseline allow-cluster-egress `toEntities: [kube-apiserver]` (kept at V3) covers them. ✅
- [observation] [V2-step5 envoy world-egress check] CONFIRMED: envoy-internal + envoy-external egress is xDS (envoy-gateway:18000) + in-cluster backends (tinyauth, pocket-id, kopia, grafana, homepage, paperless-gpt, notification-controller) + coredns DNS only. The only "world" entry is world:10.245.0.10:53 TRACED (socketLB DNS proxy trace, not a real flow). Envoy initiates NO real world egress → existing CNPs (no egress section) are correct post-flip. No V3 grant needed for envoy.
- [observation] [V2-DROPPED] Cluster-wide DROPPED during the capture: zero policy-denied; only pre-existing plex → world:239.255.255.250:1900 SSDP multicast (TTL_EXCEEDED) + IPv6 NDP (fe80::/ff02::, UNSUPPORTED_L3_PROTOCOL). V1 commit 3 activation is clean.

- [observation] [V2-REMAINING activity-triggered] Apps with no world egress observed in the passive window (inactive) — need activity-triggered captures (Task #4) before their (survey) marks can be closed: grafana (plugin/dashboard CDN at RESTART), homepage (github/openweathermap widgets on dashboard load), mealie (recipe import), wallos (currency API refresh), paperless-gpt (LLM API workflow), plex-trakt-sync (trakt/plex sync), speedtest-exporter (speedtest run), tuppr (factory.talos.dev/github upgrade check), pocket-id (SMTP if configured), prowlarr/radarr/sonarr/bazarr (indexer search/refresh), maintainerr/subsyncarr (observe under activity), calibre-web-automated (metadata fetch), isponsorblocktv (active TV watching — confirm TV ingress IPs).

- [observation] [V2-VolSync-mover VERIFIED 2026-07-05] The 10:00 UTC ReplicationSource schedule spawned 10 VolSync mover pods (volsync-src-<app>-<id>: paperless, actual, calibre-web-automated, wallos, prowlarr, sonarr, bazarr, pocket-id, radarr, tinyauth, pingvin-share-x, plex-trakt-sync, plex, seerr, mealie, backrest, qbittorrent, maintainerr, isponsorblocktv, paperless-gpt) during the 300s capture. EVERY mover pod carries `egress.home.arpa/allow-world: true` (e.g. volsync-src-sonarr-kb7k7 Running, volsync-src-paperless-6zz5m Init) — confirms components/volsync/{replicationsource,replicationdestination}.yaml spec.kopia.moverPodLabels propagates to the LIVE spawned mover pod, not just the CR spec. Hubble: 2518× FORWARDED mover pods → 141.95.67.80:443 (s3.de.io.cloud.ovh.net); zero policy-denied DROPPED. **V2-VolSync mover UNVERIFIED → RESOLVED. V3-blocker for VolSync movers: CLEARED.** (kopia-maint was already CLEARED via manual trigger.)

- [observation] [V2-isponsorblocktv-TV-capture 2026-07-05] 300s capture while the user ran YouTube on a LAN TV. Main pod isponsorblocktv-6f999d658f-z89l4 (10.244.0.215) shows ONLY EGRESS: YouTube/Google API (142.251.13.91, 192.178.183.136, 206.253.90.145 — sponsor-segment sync) + ctrld sidecar DoH (76.76.2.22:443 = dns.controld.com). **ZERO LAN (192.168.x.x) ingress flow from the TV.** No `isponsorblocktv` Service exists in the media namespace (only calibre-web-automated ClusterIP + plex LoadBalancer) — the ctrld `0.0.0.0:53` listener is reachable only on the pod IP, with NO LoadBalancer/NodePort/ClusterIP exposing :53 to the LAN. The only pod→isponsorblocktv:53 ingress is cluster-internal: CoreDNS (10.244.0.61) ↔ mover pod (volsync-src-isponsorblocktv-zz8d7, 10.244.0.55) DNS forward. **V2-step3 CORRECTION PROPOSED → CONFIRMED: the TV does NOT connect to isponsorblocktv over LAN.** Runbook consequences: (a) "isponsorblocktv pod-to-LAN CNP MUST land in V3" is UNNECESSARY — there is no LAN ingress to allow/deny; (b) the missing ingress.home.arpa/* label is NOT a V3-blocker — ingress stays open post-flip but only cluster-internal CoreDNS forward reaches it, which the baseline allow-cluster-ingress covers; (c) the allow-world label on the main pod is justified (YouTube API + ctrld DoH are genuine world egress). isponsorblocktv V3 action = allow-world only, no per-app CNP.

## V5 (l) — DNS-exfil detection alert (execution plan)

Why: allow-dns-egress + the coredns world:53 CNP leave DNS tunneling open as an exfil channel for EVERY pod, including no-world ones. The policy layer cannot close this (DNS must work); HubblePolicyDeny only fires on DROPPED and tunneling is FORWARDED DNS. Pure detection task — no CNP change. Decision basis: AD-023 rev3.

- [observation] [step] Commit 1 — per-pod DNS metric context. Edit kubernetes/apps/kube-system/cilium/app/helmrelease.yaml: in hubble.metrics.enabled (currently line 49) change the entry "- dns" to "- dns:labelsContext=source_namespace,source_pod" (same option syntax as the existing drop entry on the next line). Do NOT add the query option — per-FQDN labels are unbounded cardinality and exfil domains are unique anyway. Validate: pre-commit run --all-files + flux-local build. NOTE: this rolls the cilium DaemonSet (rollOutPods: true — brief dataplane blip, same class as prior cilium HR edits).
- [observation] [verify] After reconcile, in Prometheus: count(hubble_dns_queries_total{source_pod!=""}) > 0 (context labels present). Also record the live rcode label values: count by (rcode) (hubble_dns_responses_total) — the NXDOMAIN alert below assumes rcode="Non-Existent Domain"; if the live string differs, use the live string in the rule.
- [observation] [step] Baseline: run at least 3 days (7 preferred). Threshold query: max_over_time((sum by (source_namespace, source_pod) (rate(hubble_dns_queries_total[5m])))[3d:5m]) — note the busiest legitimate pod. Set VOLUME_THRESHOLD = 3x that value, minimum 5 (qps). This is a (survey)-class value: it MUST come from the baseline query, never guessed; fill it into the rule before merge.
- [observation] [step] Commit 2 — NEW file kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/hubble-dns-exfil.yaml + add "- ./hubble-dns-exfil.yaml" to prometheusrules/kustomization.yaml (sibling of hubble-policy-deny.yaml). Full content (replace VOLUME_THRESHOLD with the baseline-derived number):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/monitoring.coreos.com/prometheusrule_v1.json
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: hubble-dns-exfil
spec:
  groups:
    - name: hubble-dns
      rules:
        - record: hubble_dns_qps_by_pod:rate5m
          expr: |
            sum by (source_namespace, source_pod) (
              rate(hubble_dns_queries_total[5m])
            )
        - alert: HubbleDnsQueryVolumeHigh
          expr: hubble_dns_qps_by_pod:rate5m > VOLUME_THRESHOLD
          for: 10m
          labels:
            severity: critical
          annotations:
            summary: "Sustained high DNS query rate from a single pod (possible DNS tunneling)"
            description: |-
              {{ $labels.source_namespace }}/{{ $labels.source_pod }} DNS rate is high (5m rate) for 10m+.
              Investigate: hubble observe --from-pod {{ $labels.source_namespace }}/{{ $labels.source_pod }} --protocol dns --last 200
        - alert: HubbleDnsNxdomainRatioHigh
          expr: |
            (
              sum by (source_namespace, source_pod) (rate(hubble_dns_responses_total{rcode="Non-Existent Domain"}[15m]))
              /
              sum by (source_namespace, source_pod) (rate(hubble_dns_responses_total[15m]))
            ) > 0.5
            and on (source_namespace, source_pod)
            sum by (source_namespace, source_pod) (rate(hubble_dns_responses_total[15m])) > 0.2
          for: 15m
          labels:
            severity: critical
          annotations:
            summary: "High NXDOMAIN ratio from a single pod (possible DNS tunneling/DGA)"
            description: |-
              {{ $labels.source_namespace }}/{{ $labels.source_pod }}: over 50 percent of DNS responses are NXDOMAIN over 15m at non-trivial volume.
              Investigate: hubble observe --from-pod {{ $labels.source_namespace }}/{{ $labels.source_pod }} --protocol dns --last 200
```

- [observation] [accept] Deliberate test (user-run, exec into an existing pod that has a shell and nslookup, e.g. homepage): loop "for i in $(seq 1 600); do nslookup ${i}.deadbeef.example.com; done" sustained ~12 minutes → BOTH alerts fire → Pushover FIRING then RESOLVED (same acceptance shape as the V4 HubblePolicyDeny test). Then silent for 1 week under normal use.
- [observation] [rollback] revert Commit 2 (alerts). Commit 1 (labelsContext) can stay — pure observability, no policy effect.

## V5 (m) — gateways split (execution plan): gateways-dual + gateways-internal

Why (AD-023 rev3): every externally-routed app is ALSO internal-routed, but 9 label-carriers are internal-ONLY — exactly the weak/no-auth admin-UI class (qbittorrent, *arr, prometheus). The shared gateways CCNP admits envoy-external to all of them; a compromised envoy-external must not have a network path to internal-only apps. New vocabulary labels: ingress.home.arpa/gateways-dual (admits envoy-external + envoy-internal) and ingress.home.arpa/gateways-internal (admits envoy-internal only). The old ingress.home.arpa/gateways label + ingress-from-gateways CCNP are RETIRED at the end. Label-freeze exception is documented in AD-023 rev3; the migration is additive (add-both → retire-old), so it is zero-downtime.

- [observation] [assignment] gateways-dual (15 HRs — all currently carry ingress.home.arpa/gateways): calibre-web-automated (media), echo (networking), grafana (observability), pocket-id (security), tinyauth (security — MUST stay dual: it is the ext-auth hop for envoy-external), actual, backrest, home-gallery, homepage, mealie, paperless-gpt, paperless, pingvin-share-x, wallos (selfhosted), kopia (volsync-system)
- [observation] [assignment] gateways-internal (9 HRs): bazarr, maintainerr, prowlarr, qbittorrent, radarr, seerr, sonarr, subsyncarr (downloads), kube-prometheus-stack (observability)
- [observation] [assignment] victoria-logs server (V5 item e, not yet labeled): give it ingress.home.arpa/gateways-internal from the start — do NOT introduce the old label anywhere new
- [observation] [out-of-scope] flux-instance github webhook route is envoy-external-only but its receiver pod is unlabeled (flux-system, ingress open) — unchanged here; hubble-ui (cilium httproute, envoy-internal) also unlabeled — unchanged
- [observation] [mechanics] The complete edit set for both commits is exactly the file list from: grep -rln "ingress.home.arpa/gateways" kubernetes/apps --include=helmrelease.yaml (24 files as of 2026-07-09) plus the netpols dir. In each HR the label lives in the SAME block as the existing line (defaultPodOptions.labels / podLabels / podMetadata.labels) — add or remove a sibling line, do not move blocks.

- [observation] [step] Commit 1 (additive, zero behavior change): (a) NEW files kubernetes/apps/kube-system/cilium/netpols/ingress-from-gateways-dual.yaml and ingress-from-gateways-internal.yaml (full YAML below); (b) add both to netpols/kustomization.yaml resources ("- ./ingress-from-gateways-dual.yaml", "- ./ingress-from-gateways-internal.yaml"); (c) in each of the 24 HRs add the new label line directly under the existing ingress.home.arpa/gateways line per the assignment above (value always "true"). The old CCNP still admits both gateways, so the grant union is unchanged. Validate: pre-commit run --all-files + flux-local build; verify label emission per edited HR (helm template + grep the rendered pod template) as in V1 commit 2. Push, reconcile — pods roll on the label change.

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/cilium.io/ciliumclusterwidenetworkpolicy_v2.json
# Ingress from BOTH envoy gateways (label ingress.home.arpa/gateways-dual="true").
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: ingress-from-gateways-dual
spec:
  endpointSelector:
    matchLabels:
      ingress.home.arpa/gateways-dual: "true"
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: networking
            app.kubernetes.io/name: envoy
          matchExpressions:
            - key: gateway.envoyproxy.io/owning-gateway-name
              operator: In
              values:
                - envoy-external
                - envoy-internal
```

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/cilium.io/ciliumclusterwidenetworkpolicy_v2.json
# Ingress from envoy-internal ONLY (label ingress.home.arpa/gateways-internal="true").
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: ingress-from-gateways-internal
spec:
  endpointSelector:
    matchLabels:
      ingress.home.arpa/gateways-internal: "true"
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: networking
            app.kubernetes.io/name: envoy
          matchExpressions:
            - key: gateway.envoyproxy.io/owning-gateway-name
              operator: In
              values:
                - envoy-internal
```

- [observation] [accept commit 1] kubectl get ccnp → 8 total, all Valid; spot-check pod labels: kubectl get pod -A -l ingress.home.arpa/gateways-dual and -l ingress.home.arpa/gateways-internal (expect 15 vs 9 app pod sets); Hubble zero policy-denied DROPPED; all routed apps still respond via gateway.
- [observation] [step] Commit 2 (flip + retire): remove the old ingress.home.arpa/gateways line from the same 24 HRs; DELETE kubernetes/apps/kube-system/cilium/netpols/ingress-from-gateways.yaml; remove its kustomization entry. Behavior change: the 9 internal-set pods stop admitting envoy-external.
- [observation] [accept commit 2] internal-only UIs reachable from LAN via internal hostnames (spot: prometheus, qbittorrent); dual apps reachable via BOTH public and internal hostnames (spot: grafana, homepage); negative check with Hubble: no FORWARDED flow from the envoy-external proxy pod to any downloads/kube-prometheus-stack pod after the flip; HubblePolicyDeny stays silent — if it fires here, the source app was mis-assigned: move it to gateways-dual in a follow-up commit rather than reverting, unless breakage is widespread.
- [observation] [rollback] revert Commit 2 (restores the old label + CCNP; the new grants are additive and harmless to leave in place).
- [observation] [post] update the Definitions section of THIS note: label vocabulary now lists ingress.home.arpa/gateways-dual + ingress.home.arpa/gateways-internal instead of ingress.home.arpa/gateways (6-label vocabulary; AD-023 rev3 records the decision). versions-renovate governance line unchanged — the label-emission check on app-template MAJOR bumps now covers the two new labels.

## Related

- implements [[AD-023-cnp-threat-model-audit]]
- relates_to [[networking]]
- relates_to [[k8s-workloads]]
