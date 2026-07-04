---
title: cnp-per-app-audit
type: roadmap
permalink: home-ops/docs/roadmap/cnp-per-app-audit
topic: Hybrid CNP rollout runbook — label vocabulary + world-deny flip; per-app CNPs
  only for app-unique content
status: proposed
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
- [status] proposed
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

- [observation] actual: V1 gateways (custom-egress already on pod); DELETE app/ciliumnetworkpolicy.yaml in the same commit; prometheus label only if a ServiceMonitor exists (check: grep -rl ServiceMonitor kubernetes/apps/selfhosted/actual/)
- [observation] home-gallery: same pattern as actual
- [observation] pingvin-share-x: same pattern as actual
- [observation] paperless: V1 gateways via controllers.paperless.pod.labels (main pod ONLY — backup CronJob must stay label-free); custom-egress stays main-pod-scoped; DELETE CNP file; backup CronJob egress = (survey)
- [observation] homepage: V1 gateways; V3 allow-world (github/openweathermap widgets); DELETE CNP file at V1
- [observation] mealie: V1 gateways; V3 allow-world (recipe import)
- [observation] wallos: V1 gateways; egress class (survey — currency APIs?)
- [observation] paperless-gpt: V1 gateways + trim envoy/prometheus blocks from its CNP; V3 allow-world TEMPORARY (LLM API would break at flip); V5 tighten to narrow-world toFQDNs + custom-egress, drop allow-world
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
- [observation] kopia (volsync-system): V3 allow-world (OVH S3 maintenance jobs — confirm label emission on the CronJob template); volsync controller: nothing; mover pods in app namespaces: OPEN QUESTION below

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

1. [observation] [step] The single commit contains: (a) allow-cluster-egress edit (drop world, add kube-apiserver entity — YAML above); (b) EVERY V3 label from the assignment (downloads, media, homepage, mealie, speedtest, external-dns, tuppr, kopia, grafana+paperless-gpt temporary, per V2 results); (c) coredns CNP file; (d) isponsorblocktv LAN CNP (from V2 IPs); (e) any V2-discovered extra grant
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

## Operational facts (carried forward, still true)

- [observation] [tooling] just k8s hubble-live-capture <secs>, then hubble-analyze <full-cilium-label> <verdict> <direction>; use the app's REAL pod label (not always app.kubernetes.io/name)
- [observation] [transient] ~25s socketLB startup transient (no route to host to service ClusterIP) on every strict-egress pod restart — benign, self-heals
- [observation] [lesson] empty DROPPED capture is necessary but NOT sufficient — cross-check app logs
- [observation] [lesson] narrow-world allowlists from Hubble AND app logs; allow whole domains (matchName apex + matchPattern '*.apex')
- [observation] [prerequisite] CoreDNS autopath stays OFF; netkit datapath + socketLB.hostNamespaceOnly: false are load-bearing (AD-023)

## Open questions

- [observation] [open] VolSync mover pod templates (app namespaces) need world for S3 post-flip — check moverPodLabels support in ReplicationSource/our component; else namespace grants or a mover-targeted CCNP; resolve in V2
- [observation] [open] ingress-none / pure empty-allow-set semantics — live-verify during V1 staging (fromEntities kube-apiserver variant is the committed fallback)
- [observation] [open] IPv6: CIDR math is v4-only — confirm v4-only cluster, record in flip commit message
- [observation] [governance] versions-renovate checklist: verify CNP-label emission on app-template MAJOR bumps

## Related

- implements [[AD-023-cnp-threat-model-audit]]
- relates_to [[networking]]
- relates_to [[k8s-workloads]]
