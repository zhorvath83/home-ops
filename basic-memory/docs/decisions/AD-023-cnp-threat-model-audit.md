---
title: AD-023-cnp-threat-model-audit
type: decision
permalink: home-ops/docs/decisions/ad-023-cnp-threat-model-audit
decision_id: AD-023
topic: CiliumNetworkPolicy threat model & containment strategy
status: active
decided_at: '2026-06-20'
decision: 'Two-tier hybrid containment (rev2): a frozen 5-label cluster vocabulary
  backed by generic-grant CCNPs (allow-world [public internet only, LAN excluded],
  ingress-from-gateways, ingress-from-prometheus, ingress-none, plus the existing
  custom-egress opt-out) + hand-written per-app CNPs ONLY for app-unique content —
  full-domain toFQDNs narrow-world egress, named east-west consumer ingress, LB fromCIDR,
  LAN-egress exceptions. Baseline egress is fail-closed: allow-cluster-egress drops
  toEntities: world, so the default pod gets in-cluster + DNS egress with no internet
  and no LAN. Ingress default-deny arrives as a side effect of any ingress vocabulary
  label or per-app ingress CNP; consumer-less workers take ingress-none. Class P platform
  stays CNP-free on the narrowed baseline; world-needing infra gets explicit grants
  (pod label or infra-namespace grant). East-west stays target-side contained — source-side
  east-west egress control is explicitly rejected. Containment goal: a compromised
  pod must not turn the cluster into a thoroughfare.'
rationale: 'The atjarohaz risk is two things — east-west lateral and internet exfil/C2.
  East-west is contained target-side (per-app/label ingress: one protected target
  blocks ALL sources including future ones — better coverage economics on a sparse
  graph than source-side control); egress is contained fleet-wide at the world boundary
  by the flipped baseline, plus per-app narrow-world where the egress set is stable.
  The rev2 hybrid came from a comparative review of the gabe565 opt-in capability-label
  model (identical Cilium mechanics, inverted defaults): adopted its fail-closed world
  default and a small DRY vocabulary for the genuinely generic grants; rejected source-side
  east-west egress, per-relation capability labels, toEntities:world grants (would
  include LAN), and L3-only DNS (we keep the L7 proxy + toFQDNs). Hubble supplies
  all allowlists empirically.'
tradeoffs: 'Vocabulary labels are pointers — rule content lives in the CCNP, so names
  must stay truthful (gabe565 egress-namespace misnomer is the counterexample). Shared
  gateway/prometheus CCNPs trade port-pinning on non-jewel apps for boilerplate elimination
  (jewels keep hand-written port-precise CNPs). The flip converts silent fail-open
  into visible fail-closed breakage: a missing grant = broken app (B-csapda mirrored
  — grants must land in the SAME commit as the flip). Label names freeze at the first
  fleet commit. kube-apiserver entity coverage by toEntities:cluster must be verified
  pre-flip. Pods with no ingress label and no CNP remain ingress-open. hostNetwork
  pods stay outside pod policy scope.'
related_areas:
- networking
- k8s-workloads
---

# AD-023 — CiliumNetworkPolicy threat model & containment strategy

## Metadata (observation-form, schema validation)

- [decision_id] AD-023
- [status] active
- [decided_at] 2026-06-20
- [revised] 2026-06-21 — egress narrowed to a binary; shared ingress component dropped; narrow-world relaxed to full-domain allowlists
- [revised] 2026-06-29 — rev2 hybrid: label vocabulary for generic grants; world-deny flip committed; LAN excluded from world grants; source-side east-west explicitly rejected
- [revised] 2026-07-09 — rev3: ingress gateways vocabulary split (gateways RETIRED → gateways-dual + gateways-internal); SA/RBAC brought into the containment model (grafana sidecar cluster-wide secrets RBAC finding recorded — remediation moved OUT of the CNP rollout scope; fleet automountServiceAccountToken:false recognized as load-bearing); DNS-exfil detection added as permanent monitoring
- [topic] CiliumNetworkPolicy threat model & containment strategy

## Context — threat model

Single-node Talos home-lab, single-tenant, internet-exposed via Cloudflare Tunnel + envoy-external. The design question: **if a malicious actor lands in a pod, how do we stop the cluster from being a thoroughfare ("atjarohaz")?**

- [observation] [entry-vector] internet -> CF Tunnel -> cloudflared -> envoy-external -> public-routed app — the realistic RCE entry is a vuln in an internet-exposed self-hosted app (auth-gating lowers but does not remove this)
- [observation] [entry-vector] LAN -> envoy-internal / k8s-gateway LB; supply chain -> a compromised container image
- [observation] [crown-jewel] onepassword-connect + external-secrets (all secrets), kube-apiserver (takeover), data PVCs (paperless/photos/actual), backup plane + S3 creds, NAS/OMV on LAN
- [observation] [adversary-goal] "atjarohaz" is TWO distinct things: (a) east-west lateral move to other pods / apiserver / LAN, and (b) egress exfil / C2 to the internet
- [decision] CNP carries two containment jobs: **ingress** contains east-west target-side; **egress** contains exfil/C2 + LAN-pivot fleet-wide at the world boundary (flipped baseline) plus per-app narrow-world. Edge L7 ingress hardening stays with the Gateway SecurityPolicy layer and is not duplicated

## Decision — baseline and default behavior

- [decision] allow-dns-egress (unchanged): selects every pod, grants kube-dns:53 via the L7 DNS proxy — the universal egress default-deny motor, per-query Hubble visibility, toFQDNs prerequisite
- [decision] allow-cluster-egress (narrowed): toEndpoints {} + toEntities cluster + explicit toEntities kube-apiserver; NO world. Opt-out via egress.home.arpa/custom-egress (DoesNotExist selector) unchanged
- [decision] default pod (no labels, no CNP): full in-cluster egress + DNS; NO internet, NO LAN; ingress open until an ingress label or per-app CNP closes it
- [decision] [lan] the allow-world grant is toCIDRSet 0.0.0.0/0 EXCEPT 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 — public internet only; LAN egress is denied for every pod by default; rare pod-to-LAN consumers get a hand-written CNP with a precise CIDR/CiliumCIDRGroup (not a vocabulary label — Rule of Three not met). Evidence for hand-auditing the except list: gabe565 egress-world has carried a 175.16.0.0/12 typo (should be 172.16.0.0/12) for years, leaving 172.16/12 reachable
- [decision] [infra-grants] world-needing infra: pod label where labeling is natural; infra-namespace grant clause (flux-system, cert-manager) where it is not; coredns gets a targeted world:53 CNP instead of full world; FluxInstance cluster.networkPolicy stays false (grants come from our vocabulary, not vendored netpols)

## Decision — label vocabulary (5 labels, frozen at first fleet commit)

- [decision] egress.home.arpa/custom-egress — opt-out of baseline: egress = DNS + own CNP only
- [decision] egress.home.arpa/allow-world — public-internet opt-in (never LAN)
- [decision] ingress.home.arpa/gateways — fromEndpoints envoy-external/internal proxies; no port pin (accepted tradeoff on non-jewel apps); side effect: ingress default-deny
- [decision] ingress.home.arpa/prometheus — fromEndpoints prometheus; same side effect
- [decision] ingress.home.arpa/none — ingress fromEntities kube-apiserver only (guaranteed-semantics near-deny for consumer-less workers; pure empty-allow-set idiom to be live-verified before reliance)
- [decision] [composition] any ingress label flips the pod ingress-default-deny — this side effect IS the east-west closure mechanism; custom-egress + allow-world = DNS + world without in-cluster (valid, rare, document each use)

## Decision — per-app CNPs (only for app-unique content)

- [decision] [class-P] platform-exempt — no CNP, rides the narrowed baseline (cilium, coredns, democratic-csi, metrics-server, flux, cert-manager, external-dns, kube-prometheus internals, reloader, snapshot-controller, intel-gpu, tuppr, volsync controller)
- [decision] [narrow-world] apps with a narrow, stable internet need (onepassword-connect, open-webui, paperless-gpt, backup plane, grafana): custom-egress + hand-written CNP with named-consumer ingress + toFQDNs at full-domain granularity (matchName apex + matchPattern "*.apex")
- [decision] [no-world] apps with no internet need (paperless, actual, home-gallery, victoria-logs, pingvin-share-x): vocabulary labels only (gateways + prometheus + custom-egress) — no CNP file unless they have named east-west consumers
- [decision] [no-world] [crown-jewel] external-secrets (controller + webhook + cert-controller): per-component CNPs; no-world valid only while every ESO provider is in-cluster
- [decision] [allow-world] apps needing open/unpredictable internet (qbittorrent, *arr stack, plex, searxng, mealie, isponsorblocktv, speedtest-exporter, homepage): allow-world label — public internet only, LAN still denied
- [decision] [named-consumers] east-west consumer rules stay per-app hand-written even within coherent namespaces (downloads, media) — enumerated from Hubble, not guessed
- [decision] [lb-apps] LoadBalancer-exposed apps (plex, k8s-gateway): hand-written CNP with fromCIDR LAN ingress
- [decision] [rejected] source-side east-west egress control (per-relation capability labels): target-side ingress covers all sources including future ones at lower cost; residual source-side freedom = observable probing without exfil — accepted

## Rollout mechanics

- [decision] [staging] new ingress vocabulary CCNPs deploy with enableDefaultDeny: false first (grants visible in Hubble, nothing closes), then flip to true in one commit
- [decision] [flip] world removal from the baseline and EVERY grant (labels, ns-grants, coredns CNP) land in the SAME commit; rollback = single revert
- [decision] [monitoring] permanent Hubble policy-verdict DROPPED alert in kube-prometheus — point-in-time captures miss startup drops

## Must-verify before the flip

- [observation] [must-verify] kube-apiserver entity coverage: apiserver traffic carries reserved:kube-apiserver on this node (NOT reserved:host) — confirm toEntities:cluster matches it; mitigated by the explicit toEntities:kube-apiserver in the baseline regardless
- [observation] [must-verify] envoy-external/internal actual world egress — their CNP comment currently assumes baseline world
- [observation] [must-verify] non-main pod templates: CronJobs/Jobs/VolSync movers (S3 = world), paperless-backup; dnsPolicy/podDnsConfig bypassers (external resolvers = world:53 post-flip); pod-to-LAN consumers
- [observation] [must-verify] IPv6: all CIDR math is v4 — confirm v4-only cluster and record in the flip commit

## Egress mechanism & discipline

- [decision] no-world and narrow-world require egress.home.arpa/custom-egress — otherwise the baseline ORs back in (policies are additive)
- [observation] [B-csapda] label WITHOUT the paired egress content breaks the pod (only DNS survives) — label and CNP land in the same commit; MIRRORED at the flip: grant missing at flip time = broken app (visible, fail-closed)
- [observation] DNS always works: allow-dns-egress applies to every pod including opted-out ones
- [observation] Reply traffic is automatic (conntrack) — removing cluster/world egress does not break replies to inbound connections

## Risk rubric

- [observation] [rubric] egress class by legitimate egress breadth: open/unpredictable -> allow-world label; narrow + stable -> narrow-world CNP; none -> custom-egress. Ingress: labels for generic sources, CNP rules for named consumers, ingress-none for consumer-less workers
- [observation] Hubble informs the rubric and supplies allowlist content; verification = DROPPED capture + app-log crosscheck (startup-time drops fall outside capture windows)

## Honest limits

- [observation] allow-world apps get no exfil/C2 protection beyond the LAN carve-out (unavoidable) — containment lives target-side on the jewels
- [observation] [residual] platform-exempt pods keep loose/no ingress by necessity; a popped pod can reach them east-west — accepted, mitigated by crown-jewel ingress
- [observation] [residual] source-side east-west freedom: a popped pod may probe in-cluster targets; blocked at every labeled/CNP-covered destination, visible in Hubble, cannot exfiltrate
- [observation] hostNetwork pods are outside pod-policy scope; the node's own IP is host identity (not CIDR) — "LAN denied" means LAN devices (NAS/router/IoT), not the node

## Load-bearing infra facts (current, the model depends on them)

- [observation] [datapath] strict ingress CNPs work only because of bpf.datapathMode: netkit + socketLB.hostNamespaceOnly: false — CT recorded with pod IP; do not revert without re-validating every ingress CNP
- [observation] [probe-identity] kubelet probes + admission webhooks carry reserved:kube-apiserver identity on this node (node IP = apiserver IP); strict ingress CNPs need no explicit probe-allow rule (local-host fast-path); if ever needed, use reserved:kube-apiserver, NOT reserved:host
- [observation] [autopath] per-app toFQDNs REQUIRES CoreDNS autopath OFF (disabled; pods verified kept) — load-bearing for every narrow-world app
- [observation] [transient] ~25s socketLB startup transient (no route to host to service ClusterIP) on every strict-egress pod restart — benign, self-heals
- [observation] [allowlist-practice] narrow-world allowlists come from Hubble AND app logs (CDN-style secondary domains surface in logs, not captures); allow the whole domain
- [observation] [envoy-external] edge ingress defense is architectural: ClusterIP-only + CNP allowlist + CF Tunnel mTLS; SecurityPolicy.principal.clientCIDRs is unworkable (cloudflared rewrites XFF); cert-based Cloudflare AOP is the only viable edge-mTLS if ever needed
- [observation] [east-west-hub] prometheus scrapes every app metrics port and kube-apiserver reaches every app port — covered by the two ingress vocabulary labels

## Rev3 addendum (2026-07-09 — security review)

- [decision] [gateways-split] ingress.home.arpa/gateways is RETIRED, replaced by ingress.home.arpa/gateways-dual (admits envoy-external + envoy-internal) and ingress.home.arpa/gateways-internal (admits envoy-internal only). Rationale: every externally-routed app is also internal-routed, but the internal-ONLY carrier set (downloads *arr/qbittorrent, kube-prometheus-stack; victoria-logs upcoming) is exactly the weak/no-auth admin-UI class — a compromised envoy-external must not have a network path to them. Label-freeze exception: executed additively (add-both → retire-old, two commits, single-revert rollback), names chosen so the exposure class is readable from the label itself. Execution: roadmap V5 item (m).
- [decision] [rbac-containment] SA/RBAC is part of the containment model, not only network policy: a pod SA token is an east-west path that bypasses every CNP (via kube-apiserver, which many CNPs must allow). Fleet state verified 2026-07-09: automountServiceAccountToken: false on effectively all app HRs — load-bearing, keep it on every new app. homepage is the accepted exception (automount true + read-only ClusterRole: namespaces/pods/nodes/ingresses/httproutes/metrics, NO secrets, no write verbs — recon-only exposure; live can-i checks: list secrets no, patch pods no). grafana FINDING (HIGH): the chart sidecar ClusterRole granted cluster-wide secrets get/list/watch (live can-i list secrets -A = yes, external-secrets ns included) — an internet-routed pod with all-secrets read defeats the crown-jewel network containment. Remediation: removed from the CNP rollout scope (user decision 2026-07-09) — the finding stays OPEN and is NOT part of the V1-V5 runbook; candidate direction is a grafana-operator migration (operator pushes dashboards/datasources via the Grafana HTTP API; the grafana pod then needs no K8s API access at all, and its CNP drops the kube-apiserver:6443 grant), to be decided and tracked as its own roadmap item. Governance: any chart creating RBAC for a routed app must be checked for secrets verbs before adoption.
- [decision] [dns-exfil-detection] DNS tunneling through the universal allow-dns-egress + coredns world:53 path is the acknowledged residual exfil channel for no-world pods; the policy layer cannot close it (DNS must work). Mitigation is detection: per-pod Hubble DNS metrics (dns:labelsContext=source_namespace,source_pod) + per-pod query-volume and NXDOMAIN-ratio alerts. Complements (does not replace) the HubblePolicyDeny DROPPED alert. Execution: roadmap V5 item (l).

## Related

- relates_to [[networking]]
- relates_to [[k8s-workloads]]
- elaborated_in [[cnp-per-app-audit]]

## rev4 (2026-07-10) — uniform public-issuer OIDC convention

- [observation] [decision] All native OIDC clients use the public issuer (https://id.<PUBLIC_DOMAIN>) for every endpoint; the OIDC backchannel is ordinary gateway traffic. The oidc-backchannel vocabulary label + CCNP drafted the same day was discarded before commit.
- [observation] [rationale] Token endpoint is world-exposed by design; the envoy hairpin is reachable from every baseline-egress pod, so per-client network grants add explicitness, not a boundary. Discovery-only clients cannot split endpoints, so the split-endpoint pattern froze a permanent two-class rule.
- [observation] [consequence] grafana/tinyauth reverted to public token/userinfo; pocket-id CNP carries no ingress section (gateways + prometheus CCNPs only); custom-egress OIDC clients grant envoy :10443 in their own CNP; coredns forwards ${PUBLIC_DOMAIN} to k8s-gateway (in-cluster split horizon, removes the router hop from hairpins).
- [observation] [detail] Execution detail and acceptance steps recorded in [[cnp-per-app-audit]] (docs/roadmap), section "OIDC endpoint convention".

- [observation] [rev4-refinement 2026-07-10] Added egress.home.arpa/allow-gateways vocabulary label + allow-gateways-egress CCNP (egress to envoy pods :10443) for custom-egress pods that consume cluster-hosted services via public hostnames — the public-issuer OIDC hairpin class (grafana, pingvin-share-x). Replaces per-app hand-written envoy egress rules; pingvin-share-x stays custom-egress (DNS + gateways only) instead of falling back to baseline.

- [observation] [rev4-naming 2026-07-10] Label grammar decision: allow-* prefix = grant (backed by a generic CCNP), unprefixed = behavior marker (custom-egress, none); direction lives in the key prefix (ingress.home.arpa/ vs egress.home.arpa/). Live ingress labels stay as-is for now; the FULL rename executes inside the V5(m) gateways-split migration (which retires ingress.home.arpa/gateways anyway): the rev3 label names are AMENDED to ingress.home.arpa/allow-gateways-dual + ingress.home.arpa/allow-gateways-internal, and ingress.home.arpa/prometheus -> allow-prometheus rides in the same staged batch (same HR set, pods roll once). No standalone rename migration.
