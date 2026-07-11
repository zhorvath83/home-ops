---
title: cnp-per-app-audit
type: progress
permalink: home-ops/docs/progress/cnp-per-app-audit
topic: CNP per-app audit rollout — execution progress for the V1-V5 hybrid CNP rollout
  runbook
status: done
priority: medium
related_areas:
- networking
- k8s-workloads
decision_link: AD-023-cnp-threat-model-audit
tags:
- progress
- cnp
- cilium
- networking
- security
---

# CNP per-app audit — rollout progress

Execution log for the V1–V5 hybrid CNP rollout. The full runbook (YAML, per-app assignment, edit/verify/accept steps per phase) is in the Runbook section below (merged from the former docs/roadmap note on 2026-07-11). This note tracks execution state — phase status, session summaries, and the runbook. Decision basis: [[AD-023-cnp-threat-model-audit]].

## Phase tracker

| Phase | State | Notes |
|---|---|---|
| V1 commit 1 — 4 vocabulary CCNPs + kustomization entries (enableDefaultDeny: false staging) | done — reconciled + verified | kubectl get ccnp: 6/6 Valid (4 new); cilium-netpols KS Ready=True @297a0ec27 |
| V1 commit 2 — V1 labels on pods (incl. kopia/mover labels — see pre-rollout resolution) | done — reconciled + verified | labels on 18 HRs + kopia/volsync movers; Hubble FORWARDED on gateways+prometheus grants; zero DROPPED @f35a3015c |
| V1 commit 3 — activation: remove enableDefaultDeny + trim/delete per-app CNPs | done — reconciled + verified | 3050131ac on main; 3 ingress CCNPs activated; 5 CNPs deleted + 5 trimmed (3 runbook corrections: actual+paperless DELETE to TRIM, paperless-gpt TRIM to DELETE); Hubble FORWARDED, zero DROPPED ingress; all touched apps Available, op-connect Valid, ESO Synced |
| V2 — survey (results recorded into the roadmap note) | done — all flip-critical marks resolved | passive 300s + combined activity capture (triggers 2+3+4) + isponsorblocktv TV capture (trigger 1) recorded into roadmap note V2 section. kopia-maint V3-blocker CLEARED (Session 5: 995× S3 FORWARDED). VolSync mover V3-blocker CLEARED (Session 6: 10 mover pods spawned @10:00 UTC, all carry allow-world, 2518× S3 FORWARDED). prometheus→192.168.1.1:9100 V3-blocker FOUND (per-app prometheus CNP in V3 flip). isponsorblocktv: ZERO LAN ingress — TV does NOT connect over LAN, pod-to-LAN CNP unnecessary, ingress label absence NOT a blocker (Session 6 confirmed). World egress per app confirmed (allow-world labels justified). mealie api.mistral.ai NEW (V5 narrow-world candidate). envoy world-egress none; apiserver entity check OK; ovh_s3 residual RESOLVED (141.95.67.80 public); zero policy-denied DROPPED throughout. DEFERRED to V3-before/V4 soak (user decision): grafana CDN (restart capture), paperless-gpt/tuppr/pocket-id (cluster-mutating). Zero-flow apps (maintainerr/subsyncarr tentatively V3 nothing; plex-trakt-sync V3 allow-world pending; calibre-web-automated not triggered) — close under V4 soak. |
| V3 — flip (ONE commit: drop world from baseline + every V3 grant + coredns CNP + prometheus LAN CNP) | done — reconciled + verified | 953626966 on main; baseline flipped (kube-apiserver, no world); 2 CNPs (coredns, prometheus LAN) Valid; 18 allow-world labels live (21 pods incl. pre-existing kopia); Hubble 0 policy-denied DROPPED; prometheus openwrt target up; coredns CNP inert (upstream=host/kube-apiserver, baseline covers it) |
| V4 — permanent Hubble policy-verdict DROPPED alert + 7-day soak | done — soak shortened 7→1 day per user decision (2026-07-07); no firing HubblePolicyDeny alert; 2 transient POLICY_DENIED bursts logged as V5 follow-up (Session 9) | b97e8ddd5: ServiceMonitor flag + drop labelsContext + HubblePolicyDeny PrometheusRule deployed; deliberate test PASS (alert firing → Alertmanager → Pushover FIRING+RESOLVED confirmed on phone); soak 2026-07-06 → 2026-07-13 |
| V5 — remainder (downloads east-west, narrow-world tightening, LB fromCIDR) | done — all lettered items (a)–(m) complete (S22) + acceptance-critical follow-ups cleared (S23: prom label-gap CLEAN, backrest TEST-NET resolved) — (a)(d) done @2d91948dd + patches @3e1c508db/d785d2855; pocket-id GeoLite2 egress @b4535f8e8/a14879b2a; (b) grafana done @a0454ea63 + fixes @51e057d2b/@a87d23e46; (c) paperless-gpt done @c2bee75fc | (a) 8 apps gateways + 4 named-consumer CNPs (prowlarr + sonarr/radarr consumer patch); (d) plex ingress-none CNP (LAN/IoT CIDR + GDM UDP + maintainerr/seerr/plex-trakt-sync consumers); pocket-id MaxMind GeoLite2 egress (download.maxmind.com + R2 bucket); (b) grafana custom-egress + CNP (grafana.com + storage.googleapis.com plugin-archive CDN + raw.githubusercontent.com), allow-world dropped — live crash-loop surfaced missing storage.googleapis.com (plugin .zip CDN ≠ plugin API host, pocket-id R2 precedent class), fixed in follow-up commit; verified pod Ready + plugins installed + /api/health ok + HR Ready=True; (b) in-cluster datasource fix @a87d23e46 (custom-egress opt-out broke Prometheus/VictoriaLogs/Alertmanager → 3 toEndpoints grants, all datasources reachable); (c) paperless-gpt custom-egress + CNP (mistral.ai LLM/OCR + paperless:8000 in-cluster), allow-world dropped — pod Ready, Hubble paperless:8000 FORWARDED + 0 egress DROPPED, startup log "Successfully refreshed custom fields cache" + Mistral OCR provider validation ok. (f) pocket-id SMTP @278bbac6b (mail-eu.smtp2go.com:465 + MaxMind GeoLite2); (g) plex-trakt-sync narrow-world + ingress.home.arpa/none @58558db15; (h) external-dns narrow-world (api.cloudflare.com + kube-apiserver:6443) @df71cdef5; (j) calibre-web-automated narrow (smtp2go:465 + allow-gateways for OAuth) @318d61acd + plex-trakt-sync plex.tv:443 add @890ca0aa1; (i) mealie stays allow-world (open-web recipe import). Remaining: (m) gateways-split DONE @6980d2f3c(additive)+cc684029a(retire) — per-gateway allow-gateway-external/internal (singular, mirrors envoy) + allow-prometheus rename, AD-023 rev5; (l) DNS-exfil alert DONE @d9005e048 (starter: dns source labels + >30 q/s/pod warning; threshold to tune after soak); (e) victoria-logs DONE — server @d37f89f69 (custom-egress DNS-only sink + closed ingress: gateways+prometheus labels + per-app CNP for probes & collector remoteWrite) + collector @7bc05ca9a (prometheus ingress label, no CNP); no grafana datasource; (k) coredns CNP REMOVED @6b621c68b (inert world grant — baseline covers host-DNS forward + k8s-gateway split-horizon; verified zero DROPPED); tuppr DONE @0a799fde9 (custom-egress CNP) + @50764e5a6 (closed ingress — webhook/probe grant + prometheus CCNP), verified live during the v1.13.5→v1.13.6 upgrade + 2 follow-ups (backrest 192.0.2.123, prometheus scrape-target label gaps). See Session 21. |

## Pre-rollout resolutions (before V1 commit 1)

- [observation] [resolved 2026-07-04] VolSync S3 world access — CRD-verified against live v0.17.11 perfectra1n fork: ReplicationSource.spec.kopia.moverPodLabels, ReplicationDestination.spec.kopia.moverPodLabels, AND KopiaMaintenance.spec.moverPodLabels all exist. Four repo edits land in V1 commit 2 (pure allows): (1) components/volsync/replicationsource.yaml spec.kopia.moverPodLabels: {egress.home.arpa/allow-world: "true"} — covers ~21 apps; (2) components/volsync/replicationdestination.yaml same field; (3) volsync-system/volsync/maintenance/kopiamaintenance.yaml spec.moverPodLabels (top-level); (4) volsync-system/kopia/app/helmrelease.yaml defaultPodOptions.labels: allow-world + ingress.home.arpa/gateways (kopiaui Deployment, pvbackup route). volsync controller itself: nothing (in-cluster). Recorded in roadmap note Open Questions as resolved; residual V2 item: confirm ovh_s3_endpoint is a public IP.

## Workflow strategy

- [observation] [decided 2026-07-05] Working directly on `main` (no feature branch). Each commit pushes to origin/main, Flux reconciles, read-only `kubectl` verifies. Abandoned the earlier feature-branch+PR plan — simpler GitOps, each phase reconciled+verified before the next. The flip (V3) still lands as one commit so rollback = single revert.

## Session summaries

### Session 1 — 2026-07-04

- Reviewed roadmap note [[cnp-per-app-audit]] and decision [[AD-023-cnp-threat-model-audit]] against live repo/cluster state: rollout not yet started, baseline still fail-open (`toEntities: [world]` in allow-cluster-egress.yaml), 4 vocabulary CCNPs absent, per-app CNPs for migrate-convention apps still present.
- Resolved the VolSync mover-pod open question via live CRD inspection (moverPodLabels supported on all three CRDs) — see Pre-rollout resolutions above. Updated roadmap note: Open Question → resolved; kopia per-app line refined into three roles; V3 step (b) kopia reference removed (labels moved to V1 commit 2).
- Created feature branch `cnp-per-app-audit`.
- Set roadmap note status: proposed → in_progress.
- Created this progress note and cross-referenced it from the roadmap note Metadata section.

Next: Phase V1 commit 1 — add the 4 new CCNP files (allow-world-egress, ingress-from-gateways, ingress-from-prometheus, ingress-none; the 3 ingress ones with enableDefaultDeny.ingress: false staging) + netpols/kustomization.yaml entries. Validate with pre-commit + flux-local build. Push, reconcile, verify `kubectl get ccnp` shows 4 new Valid policies and zero behavior change.

### Session 2 — 2026-07-05
### Session 3 — 2026-07-05

- Implemented Phase V1 commit 2: added AD-023 ingress/egress vocabulary labels to pod templates across 18 HelmReleases + 3 volsync/kopia CR/component files. Labels: ingress.home.arpa/gateways on envoy-routed apps; ingress.home.arpa/prometheus on prometheus-scraped apps; egress.home.arpa/allow-world on kopia S3 movers (components/volsync replicationsource + replicationdestination spec.kopia.moverPodLabels; KopiaMaintenance spec.moverPodLabels; kopiaui Deployment defaultPodOptions.labels).
- Checklist-vs-ground-truth reconciliations (resume checklist had 3 inverted/under-assigned entries; verified against live CNPs + ServiceMonitors): pocket-id -> gateways+prometheus (not just gateways — its CNP has a prometheus rule + a ServiceMonitor); echo -> gateways+prometheus (not just gateways — has a ServiceMonitor); speedtest-exporter -> gateways+prometheus (not just prometheus — envoy-routed at speed.${PUBLIC_DOMAIN}). The missing label in each case would have broken the route or the scrape at V1 commit 3 activation. User confirmed the preserve-functionality choice.
- Convention: each labels block carries a single terse AD-023 vocabulary comment; for apps that already carried custom-egress, the old "paired with ciliumnetworkpolicy.yaml in the same commit" comment was replaced with an accurate combined line (the gateways/prometheus labels pair with cluster-wide CCNPs, not per-app CNPs).
- Validation: pre-commit clean on 21 touched files. Label emission verified per edited HR via `flux-local build helmreleases` (helm template inflation) — every label lands in the rendered Deployment pod template; paperless backup CronJob confirmed label-free (main-pod-only); volsync moverPodLabels verified in rendered ReplicationSource/ReplicationDestination + KopiaMaintenance CR. NOTE: `flux-local build ks` does NOT inflate helm templates (only renders the HelmRelease CR values) — must use `flux-local build helmreleases` for real pod-template emission checks.
- Committed as f35a3015c on main (21 files, +63/-5). Pushed; Flux reconciled all 18 HRs to Ready=True (UpgradeSucceeded/InstallSucceeded). Live Deployment pod-template labels confirmed for all touched apps; pods rolled out carrying the labels; paperless backup CronJob pod label-free; external-secrets 3 components (controller/webhook/cert-controller) + onepassword-connect pods carry custom-egress+prometheus; KopiaMaintenance spec.moverPodLabels allow-world live.
- Hubble FORWARDED verification: 40s cluster-wide capture while curling envoy-routed apps (pfm/grafana/echo/id/recipes/dash — all returned 200/302/401 via envoy). envoy-internal -> {mealie:9000, grafana:3000, echo:8080, actual:5006} INGRESS FORWARDED (ingress-from-gateways grant matching the new gateways label); prometheus -> grafana:3000 FORWARDED (ingress-from-prometheus grant matching the new prometheus label); zero DROPPED ingress to any labeled app (expected — ingress CCNPs still staged with enableDefaultDeny.ingress: false). One unrelated DROPPED: plex -> world SSDP multicast (TTL_EXCEEDED).

Next: Phase V1 commit 3 (activation) — remove the enableDefaultDeny.ingress: false blocks from the 3 ingress CCNPs (ingress-from-gateways, ingress-from-prometheus, ingress-none) + in the SAME commit trim/delete per-app CNPs per the runbook assignment: DELETE actual, home-gallery, pingvin-share-x, paperless, homepage, (tinyauth if its CNP is envoy-only — verify, no prometheus block found so likely DELETE); TRIM pocket-id (keep only the tinyauth->pocket-id named-consumer rule), paperless-gpt (keep its named-consumer rule, drop envoy/prometheus blocks), onepassword-connect (drop prometheus ingress block, keep ESO named-consumer + toFQDNs egress + custom-egress), external-secrets x3 (drop prometheus blocks, keep webhook fromEntities kube-apiserver + controller egress rules). Remove deleted files from their kustomizations. Acceptance per labeled app: `just k8s hubble-live-capture 120` then `just k8s hubble-analyze <pod-label> DROPPED ingress` = empty; app healthy; routed apps respond via gateway; prometheus targets Up; op-connect store Valid; ESO ExternalSecrets SecretSynced. Rollback = single `git revert` of the activation commit.

- Implemented Phase V1 commit 1: created the 4 vocabulary CCNP files under kubernetes/apps/kube-system/cilium/netpols/ (allow-world-egress with the flux-system/cert-manager infra-namespace grant spec; ingress-from-gateways; ingress-from-prometheus; ingress-none). The 3 ingress CCNPs carry enableDefaultDeny.ingress: false (V1 staging). allow-world-egress is label-gated (inert until pods carry egress.home.arpa/allow-world).
- Convention decisions: used k8s:io.kubernetes.pod.namespace (Cilium k8s: prefix) consistently in fromEndpoints selectors, matching the repo's existing CNP convention (pocket-id, external-secrets, onepassword-connect) rather than the runbook's prefix-less form. Verified live envoy proxy pods carry app.kubernetes.io/name=envoy + gateway.envoyproxy.io/owning-gateway-name in {envoy-external, envoy-internal}, and prometheus pod carries app.kubernetes.io/name=prometheus in observability — selectors match reality.
- Validation: pre-commit run on the 5 touched files — all green (yamlfmt, yamllint, gitleaks, k8s-secrets check). flux-local build of the cilium-netpols KS via `just k8s render-local-ks` — exit 0, render contains all 6 CCNPs (2 existing + 4 new). flux-local emitted non-fatal warnings (deprecation notice; postBuild cluster-settings substitute reference unresolvable — known flux-local limitation that does not affect static YAML CCNPs; dependsOn name format quirk) — none block.
- Committed as dd93c4255 on branch cnp-per-app-audit. mise.lock was touched by the flux-local pipx install side effect — restored it and staged only the 5 V1 commit 1 files (explicit pathspecs per repo rule).

- Pushed main to origin (e8e7b24a2..297a0ec27); Flux reconciled cilium-netpols KS — Ready=True @297a0ec27. `kubectl get ccnp`: 6/6 Valid (allow-cluster-egress, allow-dns-egress + 4 new allow-world-egress, ingress-from-gateways, ingress-from-prometheus, ingress-none). Zero behavior change confirmed by inert design (allow-world-egress label-gated; 3 ingress CCNPs carry enableDefaultDeny.ingress: false).

### Session 4 — 2026-07-05

- Implemented Phase V1 commit 3 (activation): removed the enableDefaultDeny.ingress: false staging blocks from the 3 ingress CCNPs (ingress-from-gateways, ingress-from-prometheus, ingress-none) — ingress is now closed for label-selected pods. In the same commit, trimmed/deleted per-app CNPs whose envoy + prometheus ingress blocks are now redundant (replaced by the cluster-wide CCNPs matching the ingress.home.arpa/{gateways,prometheus} labels landed in V1 commit 2).
- Runbook corrections (evidence-backed, vs the per-app assignment in docs/roadmap/cnp-per-app-audit — ground-truth CNP contents forced three DELETE/TRIM changes): (1) actual DELETE to TRIM — its CNP has a toFQDNs enablebanking.com:443 egress and the pod carries egress.home.arpa/custom-egress (opts out of the baseline allow-cluster-egress CCNP), so deleting would have left actual with zero egress and broken bank-transaction fetch; kept the egress rule, dropped only the envoy ingress block. (2) paperless DELETE to TRIM — its CNP has a paperless-gpt to paperless:8000 named-consumer ingress; deleting would have dropped paperless-gpt east-west at activation; kept the named-consumer rule, dropped only the envoy ingress block. (3) paperless-gpt TRIM to DELETE — its CNP is envoy-ingress-only (no named-consumer rule exists; an earlier runbook note confused paperless-gpt with paperless); the gateways CCNP fully replaces it. Net: DELETE set = home-gallery, pingvin-share-x, homepage, tinyauth, paperless-gpt (5); TRIM set = actual, paperless, pocket-id, onepassword-connect, external-secrets x3 (5).
- Deleted 5 CNP files + removed their - ./ciliumnetworkpolicy.yaml line from each app/kustomization.yaml. Trimmed 5 CNP files to keep only unique content (actual: enablebanking egress; paperless: paperless-gpt named-consumer ingress; pocket-id: tinyauth named-consumer ingress; onepassword-connect: ESO named-consumer ingress + 1password toFQDNs egress; external-secrets x3: controller/cert-controller egress + webhook kube-apiserver ingress). Header comments updated to reflect the new CCNP-backed ingress model. allow-dns-egress CCNP has endpointSelector: {} so DNS still covers custom-egress pods (actual, home-gallery, pingvin, paperless) — verified.
- Validation: pre-commit clean on all 18 touched files. flux-local build of cilium-netpols KS renders 6 CCNPs with NO enableDefaultDeny; each touched app KS renders the expected trimmed/deleted CNP set; kustomizations resolve with no dangling CNP refs. mise.lock untouched (explicit pathspec staging per repo rule).
- Committed as 3050131ac on main (18 files, +12/-253). Pushed; Flux reconciled cilium-netpols KS + all 10 touched app KSs to Ready=True @3050131ac. Live: 6/6 CCNPs present; the 3 ingress CCNP specs carry no enableDefaultDeny (activated); 5 deleted CNPs gone; 5 trimmed CNPs live with only kept rules (verified via kubectl get cnp -o jsonpath).
- Live Hubble verification (90s cluster-wide capture while curling pfm/id/share/dash/paperless-gpt via the public Cloudflare Tunnel then envoy-external path): envoy to actual:5006, envoy to paperless-gpt:8080, envoy to pocket-id:1411, envoy to tinyauth:3000 INGRESS FORWARDED (gateways CCNP matching the gateways label); prometheus to onepassword-connect:8080 + prometheus to cert-manager/envoy-gateway/victoria-logs/metrics-server/tuppr egress FORWARDED, prometheus DROPPED egress empty (prometheus CCNP); paperless-gpt to paperless:8000 FORWARDED (8 flows — the trimmed named-consumer rule, correction 2 validated live); onepassword-connect to world:443 FORWARDED (1password toFQDNs egress preserved). DROPPED ingress empty for every touched app (actual, paperless, paperless-gpt, pocket-id, tinyauth, home-gallery, pingvin-share-x, homepage, onepassword-connect, external-secrets). All curl responses 200/307 (share redirect) via envoy. actual + paperless-gpt pod logs clean (no connection errors). ClusterSecretStore onepassword-connect Valid; all ExternalSecrets SecretSynced; all touched workloads Available=True. One pre-existing unrelated DROPPED: plex to world SSDP multicast (TTL_EXCEEDED).

Next: Phase V2 — survey (no cluster changes). Static greps (dnsPolicy/podDnsConfig, hostNetwork, ServiceMonitors) + long activity-triggered Hubble capture (download search+grab, paperless-backup CronJob, VolSync sync + kopia maintenance, ExternalSecret refresh, grafana restart, speedtest run, isponsorblocktv active) + per-candidate egress slicing (record every world FQDN/IP + every 192.168.0.0/16 destination per app) + apiserver entity check + envoy world-egress check. Record every (survey) mark in the roadmap note as a concrete label/CNP/nothing decision. Residual V2 item already known: confirm ovh_s3_endpoint resolves to a public IP.

### Session 5 — 2026-07-05

- Started Phase V2 (survey, no cluster changes). Static greps: dnsPolicy/podDnsConfig → only isponsorblocktv (`dnsPolicy: None` + nameservers 127.0.0.1 + ${CLUSTER_DNS_IP}); the ctrld sidecar's DoH to dns.controld.com bypasses CoreDNS (V3 coredns CNP won't cover it — handled by isponsorblocktv's allow-world label). hostNetwork: none. ServiceMonitor repo-grep undercounts (only envoy-gateway hand-written; bjw-s-generated ones need live `kubectl get servicemonitor -A`). alertmanager NOT deployed → runbook "alertmanager outbound" item N/A (Pushover via flux notification-controller, in-cluster).
- Residual V2 item RESOLVED: ovh_s3_endpoint = s3.de.io.cloud.ovh.net → 141.95.67.80 (public OVH IP, outside all private CIDRs) — kopia S3 egress is genuine world egress, allow-world label model correct.
- User triggered a manual kopia-maint run during the capture window. Spawned pod kopia-maint-...-manua4v9hm carried `egress.home.arpa/allow-world: true` (KopiaMaintenance.spec.moverPodLabels propagates to the spawned pod — verified on a LIVE pod, not just the CR spec). Hubble: 995× FORWARDED to fqdn:s3.de.io.cloud.ovh.net:443; zero policy-denied DROPPED; pod Succeeded. **kopia-maint V3-blocker CLEARED.** VolSync mover (ReplicationSource kopia mover) live-pod verification still PENDING (next natural spawn: paperless-backup CronJob @ 2026-07-06 00:30 UTC, or manual trigger).
- Passive 300s Hubble capture (41737 flows) sliced per-app. World egress confirmed (V3 grant decisions): qbittorrent (BitTorrent peers), isponsorblocktv (YouTube/Google + ControlD DoH 76.76.2.22), external-dns (api.cloudflare.com), plex (plex.tv), seerr (api.github.com), onepassword-connect (1password.com, existing CNP), kopia kopiaui (OVH S3, V1c2 label), kopia-maint (OVH S3, V1c2 moverPodLabels), source-controller (ghcr/quay/mirror.gcr/github, infra-namespace grant), cloudflare-tunnel (argotunnel, existing CNP).
- **V3-BLOCKER FOUND: prometheus → 192.168.1.1:9100** (20 flows) — scrapes the OpenWRT router node-exporter via additionalScrapeConfigs job `openwrt` target `${ROUTER_IP}:9100` (kube-prometheus-stack HR line 452). The flipped baseline will DROP this. ACTION: add a per-app prometheus CNP (observability) egress toCIDR 192.168.1.1/32 toPorts 9100/TCP IN the V3 flip commit. Runbook "kube-prometheus-stack: Class P — nothing" CORRECTED.
- LAN corrections: k8s-gateway ingress port is 1053 not 53 (runbook V5 CNP correction). envoy-internal already covers LAN ingress 192.168/16→10443 via its existing CNP (no action). isponsorblocktv had NO pod→LAN egress — runbook "pod-to-LAN CNP MUST land in V3" likely unnecessary (ingress stays open post-flip, no ingress label); PROPOSED correction, confirm with active TV capture.
- V2 step 4 (apiserver entity): pod→apiserver flows match reserved:kube-apiserver; baseline toEntities kube-apiserver (kept at V3) covers them. V2 step 5 (envoy world-egress): CONFIRMED none (xDS + in-cluster backends + DNS only) — no V3 grant for envoy. Cluster-wide DROPPED: zero policy-denied (only pre-existing plex SSDP + IPv6 NDP).
- All V2 results recorded into the roadmap note (new "## V2 survey results (2026-07-05)" section inserted before Related).

Next: Finish V2 activity-triggered captures (Task #4) — open a capture window per trigger: grafana rollout restart (approval), homepage dashboard load, mealie recipe import, wallos refresh, paperless-gpt workflow, plex-trakt-sync sync, speedtest run, tuppr upgrade check, pocket-id SMTP test, *arr indexer search, isponsorblocktv active TV watching. Plus verify VolSync mover live-pod label propagation (manual VolSync trigger or wait for paperless-backup @ 2026-07-06 00:30 UTC). Each trigger: `just k8s hubble-live-capture 300` (sandbox disabled) while the activity runs, then per-app egress slice + record the (survey) decision into the roadmap note. V2 acceptance = every (survey) mark resolved.

### Session 6 — 2026-07-05

- Finished Phase V2 activity-triggered captures (Task #4) and the VolSync mover live-pod verification (Task #2). Two capture windows, both 300s with sandbox disabled (`dangerouslyDisableSandbox: true`) per the user instruction.
- **V2-combined-capture** (user fired triggers 2+3+4 in one window: *arr indexer search + qbittorrent grab, homepage dashboard + mealie import + wallos refresh, speedtest run). World egress CONFIRMED → V3 allow-world for: bazarr (api.opensubtitles.com, feliratok.eu), prowlarr (bithumen/libranet/ncore trackers), radarr (api.radarr.video, image.tmdb.org), sonarr (thetvdb, sonarr.tv, skyhook, thexem), seerr (api.themoviedb.org 183×, api.github.com, algolia.net, discover.provider.plex.tv), qbittorrent (t.ncore.sh, t1.bithumen.net + BitTorrent peers), homepage (api.openweathermap.org), wallos (data.fixer.io:80 currency API — runbook CONFIRMED), speedtest-exporter (cli/results.speedtest.net + many HU ISP speedtest servers). NEW finding: **mealie → api.mistral.ai (18×) — Mistral AI LLM API for recipe import** — V3 allow-world covers it, V5 narrow-world candidate (api.github.com + api.mistral.ai + recipe-import sites). maintainerr + subsyncarr + plex-trakt-sync + backrest + resticprofile: ZERO flows (idle / not triggered) — tentatively V3 nothing (maintainerr/subsyncarr) and V3 allow-world still pending (plex-trakt-sync trakt/plex APIs). source-controller → world:100.58.78.182:443 (outside 100.64/10 CGNAT) covered by the flux-system infra-namespace grant, not a blocker. LAN egress identical to the passive set (prometheus→192.168.1.1:9100 V3-blocker, k8s-gateway:1053, envoy-internal:10443). Zero policy-denied DROPPED.
- **V2-VolSync-mover VERIFIED** (Task #2 CLEARED): the 10:00 UTC ReplicationSource schedule spawned 10 mover pods (volsync-src-<app>-<id>) during the capture. EVERY mover pod carries `egress.home.arpa/allow-world: true` (verified on volsync-src-sonarr-kb7k7 Running + volsync-src-paperless-6zz5m Init) — confirms components/volsync spec.kopia.moverPodLabels propagates to the LIVE spawned mover pod. Hubble: 2518× FORWARDED mover pods → 141.95.67.80:443 (s3.de.io.cloud.ovh.net); zero policy-denied DROPPED. **VolSync mover V3-blocker: CLEARED.** (kopia-maint was already CLEARED in Session 5.)
- **V2-isponsorblocktv-TV-capture** (user ran YouTube on a LAN TV during a 300s capture — trigger 1). Main pod isponsorblocktv-6f999d658f-z89l4 (10.244.0.215) shows ONLY EGRESS: YouTube/Google API (142.251.13.91, 192.178.183.136, 206.253.90.145) + ctrld sidecar DoH (76.76.2.22:443 = dns.controld.com). **ZERO LAN (192.168.x.x) ingress flow from the TV.** No `isponsorblocktv` Service exists in the media namespace — the ctrld `0.0.0.0:53` listener is reachable only on the pod IP, with NO LoadBalancer/NodePort/ClusterIP exposing :53 to the LAN. The only pod→isponsorblocktv:53 ingress is cluster-internal: CoreDNS (10.244.0.61) ↔ mover pod (volsync-src-isponsorblocktv-zz8d7, 10.244.0.55) DNS forward. **User hypothesis CONFIRMED: the TV does NOT connect to isponsorblocktv over LAN.** Runbook consequences: (a) "isponsorblocktv pod-to-LAN CNP MUST land in V3" is UNNECESSARY — no LAN ingress to allow/deny; (b) the missing ingress.home.arpa/* label is NOT a V3-blocker — ingress stays open post-flip but only cluster-internal CoreDNS forward reaches it (covered by baseline allow-cluster-ingress); (c) allow-world label on the main pod is justified (YouTube + DoH). isponsorblocktv V3 action = allow-world only, no per-app CNP.
- **Cluster-mutating triggers DEFERRED** (user decision "Egyiket se most"): grafana rollout restart (plugin/dashboard CDN), paperless-gpt workflow (LLM API), tuppr upgrade-check (factory.talos.dev/github), VolSync manual trigger (moot — 10:00 UTC schedule already verified), pocket-id SMTP. These move to V3-before or V4 soak. grafana is the notable one: it has gateways+prometheus labels but NOT allow-world — if its plugin CDN egress surfaces under V4 soak as DROPPED, add allow-world in a V4 follow-up; conservatively could pre-grant allow-world at V3, but survey mark stays open until a restart capture.
- All V2 results recorded into the roadmap note (V2-combined-capture bullets appended to the V2 survey results section in Session 5; V2-VolSync-mover VERIFIED + V2-isponsorblocktv-TV-capture bullets inserted before Related in this session).

Next: Phase V3 — flip (ONE commit, single revert = rollback). Commit contents: (1) drop `toEntities: [world]` from the baseline allow-cluster-egress CCNP; (2) add the per-app prometheus CNP (observability) egress toCIDR 192.168.1.1/32 toPorts 9100/TCP for the openwrt scrape; (3) add the coredns CNP if any new cluster-internal DNS path needs it (probably none — allow-dns-egress already endpointSelector: {}); (4) NO isponsorblocktv LAN CNP (confirmed unnecessary); (5) every V3 grant is already in place via the V1 commit 2 allow-world labels + the V1 commit 3 CCNPs — the flip is the single baseline edit + the prometheus LAN CNP. Pre-flip: re-confirm 6/6 CCNPs Valid + all touched apps Available + Hubble zero policy-denied DROPPED on a passive capture. Post-flip: Hubble capture + verify every world-egress app still FORWARDED (allow-world label), prometheus→192.168.1.1:9100 FORWARDED (new CNP), no new DROPPED except expected. Then V4 (permanent policy-verdict DROPPED alert + 7-day soak) and V5 (downloads east-west, narrow-world tightening, k8s-gateway:1053 fromCIDR LAN CNP).

## V1 commit 2 — resume checklist (next session)

Edit set, grouped by mechanic. CNP deletes/trims are V1 commit 3, NOT here — commit 2 is labels only (zero behavior change: ingress CCNPs still staged with enableDefaultDeny false; allow-world additive with the pre-flip baseline that still carries toEntities: world).

1. selfhosted gateways label (bjw-s app-template): actual, home-gallery, pingvin-share-x, paperless (main pod ONLY via controllers.paperless.pod.labels — backup CronJob stays label-free), homepage, mealie, wallos, paperless-gpt, backrest, calibre-web-automated. Add ingress.home.arpa/gateways: "true" via defaultPodOptions.labels (or controllers.<name>.pod.labels for paperless main). actual/home-gallery/pingvin-share-x already carry custom-egress — add gateways alongside.
2. security: tinyauth (gateways + prometheus if ServiceMonitor exists; check), pocket-id (gateways).
3. observability: grafana (gateways + prometheus), speedtest-exporter (prometheus only). victoria-logs server: NO V1 labels (V5). kube-prometheus-stack: nothing (Class P).
4. networking: echo (gateways).
5. external-secrets: onepassword-connect (prometheus label via defaultPodOptions.labels), external-secrets x3 (per-component podLabels prometheus: controller / webhook / certController).
6. kopia/mover (4 files from Session 1 resolution): components/volsync/replicationsource.yaml spec.kopia.moverPodLabels; components/volsync/replicationdestination.yaml same; volsync-system/volsync/maintenance/kopiamaintenance.yaml spec.moverPodLabels (top-level); volsync-system/kopia/app/helmrelease.yaml defaultPodOptions.labels (allow-world + ingress.home.arpa/gateways).
7. Verify label emission per edited HR: flux-local/helm template, grep the rendered pod template for the label BEFORE push.
8. pre-commit + commit (labels only) + push + Flux reconcile + Hubble FORWARDED on the new labels + update this progress note.

(Superseded — V1 commit 2 done in Session 3. See the Next pointer in Session 3 for V1 commit 3.)

## Related

- implements [[cnp-per-app-audit]]
- decided_in [[AD-023-cnp-threat-model-audit]]
- relates_to [[networking]]
- relates_to [[k8s-workloads]]

### Session 7 — 2026-07-05

- Implemented Phase V3 flip as ONE commit (rollback = single `git revert`). Committed as **953626966** on main (23 files, +99/-12); pushed (`52b4d5830..953626966`). Working directly on `main` per the decided workflow strategy. Flux auto-reconciled ~4 min after push — no explicit `just k8s flux-reconcile` needed; the cilium-netpols, coredns, kube-prometheus-stack, and every labeled-app KS rolled to Ready=True on the new commit.
- Baseline edit (`kubernetes/apps/kube-system/cilium/netpols/allow-cluster-egress.yaml`): dropped `- toEntities: [world]`, added `- toEntities: [kube-apiserver]` with the `# explicit: probe-identity caution (AD-023)` inline comment; header comment rewritten to the post-flip model (in-cluster egress only; internet via allow-world label or per-app CNP). After this the default pod (no labels, no CNP) has in-cluster egress + DNS only — no internet, no LAN.
- Two new per-app CNPs landing in the same commit (B-csapda — grants + flip together so a missing grant = visible fail-closed breakage):
  - **coredns CNP** (`kubernetes/apps/kube-system/coredns/app/ciliumnetworkpolicy.yaml`): `toEntities: [world]` port 53 UDP+TCP for the upstream forwarders (`forward . /etc/resolv.conf`). Selector `k8s-app: kube-dns`; no `metadata.namespace` (repo convention — coredns ks `targetNamespace: kube-system` places it).
  - **prometheus LAN CNP** (`kubernetes/apps/observability/kube-prometheus-stack/app/ciliumnetworkpolicy.yaml`): `toCIDRSet: 192.168.1.1/32` port 9100/TCP for the OpenWRT router node-exporter scrape (KPS helmrelease `additionalScrapeConfigs` job `openwrt`, target `${ROUTER_IP}:9100` — the V3-blocker found in Session 5). Selector `app.kubernetes.io/name=prometheus + app.kubernetes.io/instance=kube-prometheus-stack` (verified on live pod).
  - Both added to their `app/kustomization.yaml` before `./helmrelease.yaml` (sibling CNP-first pattern).
- 18 allow-world labels landed (the grant MECHANISM `allow-world-egress` CCNP was inert from V1 commit 1; the pod labels were NOT — correction below). 15 bjw-s app-template via `defaultPodOptions.labels`; 3 non-bjw-s via chart-native `podLabels` (external-dns, grafana, tuppr). Label emission verified per non-bjw-s app via `flux-local build helmreleases` (1 occurrence each in the rendered pod template).
- **5 TEMPORARY pre-grants** (V2 had no confirming capture; V4 soak to verify, V5 to narrow): grafana (plugin CDN), paperless-gpt (LLM API), tuppr (factory.talos.dev + github releases), plex-trakt-sync (trakt + plex APIs), calibre-web-automated (book metadata). All 5 carry the `TEMPORARY (...; V5 narrow-world)` comment marker for V4-soak traceability. User decision: pre-grant all 5 (runbook stance), tighten in V5.
- Static validation green: pre-commit (yamlfmt/yamllint/gitleaks/just-fmt/k8s-secrets) clean on all 23 files; `flux-local build ks cilium-netpols` renders the flipped baseline (no `world` entity, kube-apiserver present); `flux-local build ks coredns` + `kube-prometheus-stack` render the new CNPs; yamlfmt -dry = no drift.

**Corrections to the Session 6 Next pointer (two inaccuracies, both resolved in this commit):**
1. "every V3 grant is already in place via V1 commit 2 allow-world labels" — FALSE. V1 commit 2 placed allow-world only on kopia (kopiaui Deployment + KopiaMaintenance) and the volsync mover components (`components/volsync/{replicationsource,replicationdestination}.yaml`, `kopiamaintenance.yaml`). The 18 world-needer apps did NOT carry it — the labels had to land in the V3 commit (done here).
2. "coredns CNP probably none — allow-dns-egress already endpointSelector: {}" — FALSE (and see finding 3 below for a further refinement). `allow-dns-egress` grants pods egress TO in-cluster kube-dns; it does NOT grant coredns egress to its UPSTREAM resolvers. After the flip the baseline drops world, so coredns upstream egress would break cluster-wide external name resolution without an explicit grant. The coredns CNP was added.

**Finding 3 (NEW, from live post-flip capture): the coredns CNP is currently INERT.** The 300s post-flip Hubble capture shows coredns's ONLY upstream destination is `169.254.116.108:53` (link-local, carrying `reserved:host` + `reserved:kube-apiserver` — the AD-023 probe-identity observation: on this node the node IP = apiserver IP, so host-network destinations carry the kube-apiserver identity). That flow is FORWARDED by the **baseline `toEntities: [kube-apiserver]` / `cluster` grant**, NOT by the coredns CNP's `toEntities: [world]:53` (world does not match reserved:host/kube-apiserver). The plan's "coredns CNP MANDATORY" rationale (V2 assumption that coredns forwards to public resolvers / the LAN router 192.168.1.1) was inaccurate — coredns forwards to the node's host-network resolver, which the baseline still covers. The CNP is kept as defense-in-depth: harmless (a valid allow rule that simply is not currently exercised), and it covers a future change where /etc/resolv.conf points to a public resolver. No action needed at V3; record for V5 cleanup review (keep vs remove).

**Post-flip live Hubble verification (300s capture, 36746 flows, sandbox disabled per user instruction):**
- **0 policy-denied DROPPED egress.** The only DROPPED verdicts are pre-existing noise: IPv6 NDP (`UNSUPPORTED_L3_PROTOCOL`, INGRESS) and plex SSDP multicast (`TTL_EXCEEDED` to 239.255.255.250:1900). Neither is a Cilium policy-deny (reason ≠ `policy`).
- world-egress apps FORWARDED via the allow-world label: qbittorrent 908× to `reserved:world` (BitTorrent peers + trackers); external-dns to Cloudflare (104.19.192.175/176, 104.19.193.29, `reserved:world`) — external-dns logs "All records are already up to date" (functional).
- prometheus → 192.168.1.1:9100: 20× FORWARDED (the new LAN CNP); prometheus API confirms the `openwrt` target `health=up`, `lastError=""`. New CNP works end-to-end.
- coredns upstream DNS: FORWARDED (via baseline kube-apiserver — see finding 3).
- allow-world label on pods: 18 app pods + 3 pre-existing (kopia + 2 kopia-maint) = 21 pods carry `egress.home.arpa/allow-world=true`.
- Functional spot-checks: external-dns synced; prometheus openwrt target up; cluster CCNPs 6/6 Valid, both new CNPs Valid; all touched workloads Available.

**Verification verdict: V3 flip PASS — reconciled + verified.**

Next: V4 — permanent Hubble policy-verdict DROPPED alert + 7-day soak (watch the 5 TEMPORARY pre-grants for confirming captures; surface any genuine world-denied as a V4 follow-up grant or narrow-world). V5 — narrow-world tightening (5 TEMPORARY grants + mealie api.mistral.ai), downloads east-west ingress closure, LB fromCIDR. Ingress closure is a separate phase (the user confirmed ingress is intentionally open at V3; ~29 of 49 apps have no ingress label/CNP — AD-023 accepted residual risk, crown-jewels closed, egress flip stops exfil) — track as its own V4/V6 item, not bundled into the V3 flip revert unit.

### Session 8 — 2026-07-06

- Implemented Phase V4 steps 1-3 (Hubble policy-verdict DROPPED alert + deliberate test). Step 4 (7-day soak) STARTED.
- **Step 1 (Hubble metrics scraping — the blocker)**: KPS Prometheus uses ServiceMonitor/PodMonitor discovery only (no annotation-based), so Hubble metrics were not scraped at all before this. Enabled the Cilium chart-native `hubble.metrics.serviceMonitor.enabled: true` flag in the cilium HelmRelease (kubernetes/apps/kube-system/cilium/app/helmrelease.yaml) — replaced the initial hand-written ServiceMonitor that was redundant with the chart's own. Also extended the drop metric to `- drop:labelsContext=source_namespace,source_pod,destination_namespace,destination_pod` so per-pod context (the CNP audit's whole point) lands on `hubble_drop_total` and reaches the Pushover notification.
- **Step 2 (PrometheusRule)**: new kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/hubble-policy-deny.yaml — alert `HubblePolicyDeny`, `expr: increase(hubble_drop_total{reason="POLICY_DENIED"}[5m]) > 0`, `severity: critical` (routes to pushover via alertmanagerconfig.yaml), no `for:` (sensitive `> 0` threshold — a single policy_denied drop is actionable post-V3 baseline=0). **Source-validated correction**: the `reason` label value is `"POLICY_DENIED"` (UPPERCASE) for the deployed Cilium 1.19.5, NOT `"policy_denied"` (lowercase belongs to the cilium *agent* metric `cilium_drop_count_total`, not the Hubble `hubble_drop_total`). Live-confirmed: reason label values include POLICY_DENIED, TTL_EXCEEDED, UNSUPPORTED_L3_PROTOCOL (all uppercase). `hubble_drop_total` carries NO `verdict` label (that lives on `hubble_flows_processed_total`) — no verdict filter is valid on it.
- **Commit**: b97e8ddd5 on main ("cnp alerting") — cilium HelmRelease (ServiceMonitor flag + drop labelsContext) + hubble-policy-deny.yaml + prometheusrules/kustomization.yaml. Pushed by user.
- **Step 3 (deliberate test — end-to-end acceptance)**: test pod `victoria-logs-server-0` (observability) has NO `egress.home.arpa/allow-world`/`custom-egress` label → world egress DENIED by the flipped baseline. `wget https://1.1.1.1` burst → `hubble_drop_total{reason="POLICY_DENIED",source_pod="victoria-logs-server-0"}` counter increased (20→48→96) → `increase(...[5m]) > 0` → HubblePolicyDeny `firing` (t+30s) → Alertmanager `active`, receiver `observability/alertmanager/pushover` → Pushover delivered. User confirmed BOTH FIRING (gamelan sound) and RESOLVED notifications received on phone.
- **Key design finding from the test**: `increase(...[5m]) > 0` fires only while the counter is actively increasing within the 5m window. An isolated burst (single boot-time wget then silence) fires for ~5m then resolves (`sendResolved: true` → RESOLVED notification). The real threat (a missing world-egress label) produces CONTINUOUS retry → counter grows continuously → `increase > 0` stays true → sustained FIRING. Alertmanager `groupBy: [alertname, job]` + `repeatInterval: 12h` means a re-notification within 12h requires a resolved→firing cycle, which the isolated-burst pattern naturally produces — acceptable for the homelab threat model.
- **Annotation note**: `destination_namespace`/`destination_pod` labels are EMPTY for world-IP drops (labelsContext requests them but world IPs have no pod identity); `source_namespace`/`source_pod` are populated. In-cluster pod→pod drops will fill the destination labels. Not blocking — the source pod is the actionable signal.
- **Step 4 (7-day soak) STARTED 2026-07-06 → 2026-07-13**: watch for genuine post-flip POLICY_DENIED drops, especially from the 5 V3 TEMPORARY pre-grants (grafana, paperless-gpt, tuppr, plex-trakt-sync, calibre-web-automated) — confirming captures or genuine denies. At soak end: re-run the V3 acceptance Hubble capture (300s, `just k8s hubble-live-capture`) to catch startup-time/periodic-job denies that surface late. Tune the `> 0` threshold if noisy. Re-query distinct `reason` label values after any future Cilium chart upgrade (stringer drift safety).

Next: V4 step 4 soak in progress (2026-07-06 → 2026-07-13). At soak end, re-run the V3 acceptance Hubble capture (300s) + review any HubblePolicyDeny notifications received during the soak; then proceed to V5 (downloads east-west, narrow-world tightening, LB fromCIDR).

### Session 9 — 2026-07-07

- **V4 soak closed early (7→1 day) per user decision** ("nem volt érdemi alert, menjünk tovább"). Soak window: 2026-07-06 → 2026-07-07. Alerting pipeline already end-to-end validated in Session 8 (deliberate victoria-logs burst → FIRING → Alertmanager → Pushover → RESOLVED on phone).
- End-of-soak verification (read-only): `HubblePolicyDeny` PrometheusRule live (observability, group=hubble); Prometheus alerts API shows **no firing HubblePolicyDeny alert** — confirms the "no meaningful alert" observation. `hubble_drop_total{reason="POLICY_DENIED"}` cumulative counters since the V4-step1 ServiceMonitor enablement: **backrest=176, prometheus=22 (two series)**. `increase(...[5m])` = **0 for all three right now** → the drops are NOT actively growing; transient bursts, not sustained retries. This is why the `> 0` alert did not sustain-fire.
- **Two transient burst findings → V5 follow-up investigation items (NOT V4 blockers):**
  1. **backrest → 192.0.2.123:443 (TCP egress, 176 drops).** 192.0.2.0/24 = RFC 5737 TEST-NET-1 (treated as world by the allow-world-egress except-list). backrest's per-app CNP allows only `s3.de.io.cloud.ovh.net:443` + `hc-ping.com:443` (toFQDNs; `custom-egress` label opts out of baseline). 192.0.2.123 matches NEITHER allowlist entry → denied. No `192.0.2.x` reference anywhere in backrest manifests (helmrelease/CNP). Likely a startup-time update/telemetry/connectivity check from the backrest binary that resolved to / hardcodes a TEST-NET address; it self-healed (increase5m=0). V5 action: identify the destination via backrest pod logs / a DNS-query Hubble capture, then decide keep-denied (undesired telemetry) vs add a narrow toFQDNs grant (functional). Do NOT widen to allow-world.
  2. **prometheus → 10.244.0.153 + 10.244.0.14 (in-cluster pod IPs, 22 drops).** Both target pods no longer exist at those IPs (rescheduled/rolled) → drops are stale. Indicates prometheus scraped two pods at startup that lacked the `ingress.home.arpa/prometheus` label (or whose per-app CNP does not admit prometheus) — a scrape target missed in the V1 commit 2 label pass. Non-blocking now (targets gone) but will recur if the same workload is re-scheduled and re-scraped. V5 action: enumerate ServiceMonitors/PodMonitors and confirm every scrape-target pod carries the prometheus ingress label or is admitted by its CNP.
- **V4 verdict: done.** Alerting deployed + tested (Session 8); soak closed early per user decision with zero sustained policy-denied; the two transient bursts are logged as V5 follow-up items, not V4 blockers.

Next: **V5 — remainder** (each item = one commit + verify, per roadmap runbook §V5): (a) downloads east-west closure (*arr cross-links → named-consumer CNPs + gateways/prometheus labels, one namespace-batch commit, verify DROPPED-clean under active downloading); (b) grafana narrow-world (custom-egress label + CNP toFQDNs grafana.com + raw.githubusercontent.com + REMOVE temp allow-world; verify pod-restart plugin pull); (c) paperless-gpt narrow-world (LLM API domain from V2); (d) plex CNP (ingress fromCIDR LAN/24 → 32400 + prometheus) + k8s-gateway CNP (ingress fromCIDR LAN/24 → 53; expect LB-VIP/service-identity edge cases — verify from a LAN client); (e) victoria-logs server (gateways+prometheus labels + named-consumer CNP for collector + grafana, one commit); (f) pocket-id SMTP result → narrow-world if needed; (g) worker isolation (ingress.home.arpa/none on plex-trakt-sync, resticprofile if verified consumer-less); (h) external-dns narrow-world (api.cloudflare.com) — optional; (i) mealie narrow-world (api.github.com + api.mistral.ai + recipe-import sites + custom-egress, drop allow-world); (j) the 5 V3 TEMPORARY pre-grants (grafana/paperless-gpt/tuppr/plex-trakt-sync/calibre-web-automated) tightened into narrow-world; (k) coredns CNP keep-vs-remove review (currently inert — baseline kube-apiserver covers the node-resolver forward). Plus the two V5 follow-up investigations above (backrest 192.0.2.123, prometheus scrape-target label gaps). Recommended starting item: (b) grafana narrow-world — it removes the broadest temp allow-world exposure and is self-contained (single app, V2 data already recorded).
### Session 10 — 2026-07-08

- **V5 item (a) downloads east-west closure — DONE (commit 2d91948dd "cnp" on main).** 8 downloads apps got `ingress.home.arpa/gateways: "true"` (subsyncarr got only that — no *arr consumer, no internet; the other 7 kept `egress.home.arpa/allow-world`). 4 named-consumer CNPs created: sonarr:8989 ← bazarr/prowlarr/seerr; radarr:7878 ← bazarr/prowlarr/seerr; qbittorrent:8080 ← sonarr/radarr; prowlarr:9696 ← radarr (initially flagged — in capture but not the app-UI connection list). 4 kustomizations got `- ./ciliumnetworkpolicy.yaml` (CNP-first sibling pattern). Convention: pocket-id-style `endpointSelector` (name+instance+controller) + `fromEndpoints` OR'd array (`k8s:io.kubernetes.pod.namespace: downloads` + `app.kubernetes.io/name`), `toPorts`, NO `enableDefaultDeny` (the `ingress-from-gateways` CCNP supplies default-deny for the gateways-labeled pods). Static validation green (pre-commit + kustomize render). Reconciled topology source = user-provided *arr cross-link map + Hubble capture, with the radarr→prowlarr reverse-flow included as safe-default (later confirmed + extended to sonarr by user — see patch 1).
- **V5 item (d) plex CNP — DONE (commit 2d91948dd).** Plex is LB-only (LoadBalancer PLEX_IP, `externalTrafficPolicy: Local`; NO HTTPRoute — confirmed by user: "a plex-nek ma már nincs httproute-ja, csak régen volt, kivettem most a domaint is"; PLEX_ADVERTISE_URL trimmed to `http://PLEX_IP:32400`). Used `ingress.home.arpa/none: "true"` (NOT `gateways`) — the `ingress-none` CCNP triggers ingress default-deny via its `fromEntities: [kube-apiserver]` rule WITHOUT the gateways CCNP's envoy admitt, which would be a no-op on a non-envoy-routed app. plex CNP: `fromEndpoints` [maintainerr (downloads), seerr (downloads)] TCP 32400 + `fromCIDRSet` [LAN_SUBNET, IOT_SUBNET] TCP 32400 + UDP GDM (32410/32412/32413/32414, the LoadBalancer-exposed discovery ports). CIDR placeholders are Flux-substituted by the cluster-settings ConfigMap via the cluster-apps root ks.yaml `substituteFrom` patch injected into every child Kustomization. The plex.tv relay is outbound (allow-world egress, already present) — NO inbound from remote clients.
- **AD-023 model refinements surfaced this session (recorded for the runbook):**
  1. **`ingress-none` vs `gateways` for LB-only apps.** The `gateways` CCNP admits envoy (useful for HTTPRoute-routed apps); on a LoadBalancer-only app like plex its envoy admitt is a harmless no-op. `ingress-none` is the correct label for apps that need ingress default-deny but are NOT envoy-routed — it triggers default-deny (via its kube-apiserver rule) without the redundant envoy grant. Use `gateways` only when the app has an HTTPRoute (envoy actually forwards to it).
  2. **Cilium default-deny is IMPLICIT.** Any policy (CNP/CCNP) that selects a pod AND contains at least one ingress rule activates ingress default-deny on that pod — no `enableDefaultDeny: true` needed (that field is only for default-deny WITHOUT an ingress rule, e.g. an egress-only policy). Both `ingress-none` (its `fromEntities: kube-apiserver` rule) AND the per-app CNP (its `fromEndpoints`/`fromCIDRSet` rules) activate default-deny on the plex pod. Consequence: the `ingress-none` CCNP's default-deny is REDUNDANT once the per-app CNP exists; `ingress-none`'s sole added value is the kube-apiserver "guaranteed-semantics fallback". The CCNP's real purpose is for CONSUMER-LESS workers (apps with no per-app CNP that still need default-deny).
  3. **`egress.home.arpa/custom-egress` is an OPT-OUT label, not an admit label.** The `allow-cluster-egress` baseline CCNP `endpointSelector: matchExpressions: [{key: egress.home.arpa/custom-egress, operator: DoesNotExist}]` — the label's ABSENCE gets the baseline (in-cluster + kube-apiserver); its PRESENCE opts the pod out so its per-app CNP becomes the sole egress source (default-deny for anything not listed). ASYMMETRIC with ingress (where `gateways`/`prometheus`/`none` are ADMIT labels adding CCNP grants), because the two directions start from opposite defaults: egress defaults open (baseline gives normal in-cluster ops; tight apps opt out + custom CNP), ingress defaults closed (default-deny; labels add admit CCNPs). backrest/resticprofile/paperless etc. use `custom-egress` + a narrow toFQDNs/toCIDRSet CNP.
- **Two PATCHES in the working tree (NOT in commit 2d91948dd — both fix live breakage if Flux already reconciled the labels):**
  1. **prowlarr CNP + kustomization were MISSING from the commit** (only the prowlarr helmrelease gateways label landed). With the gateways label live but no CNP, radarr/sonarr → prowlarr:9696 indexer sync is BLOCKED by default-deny. Patched: re-created `prowlarr/app/ciliumnetworkpolicy.yaml` + added it to `prowlarr/app/kustomization.yaml`. **User then requested sonarr be admitted too** ("a prowlarr ingresst engedjük a sonarr és a radarr felől") — the CNP now admits BOTH radarr and sonarr on 9696 (the reverse direction of the app-UI "prowlarr → radarr/sonarr" sync config), and the "flagged, not in app-UI list" comment caveat was dropped.
  2. **plex-trakt-sync consumer was MISSING from the committed plex CNP** (only maintainerr/seerr + LAN/IoT landed). The plex-trakt-sync app (media ns, `PLEX_BASEURL: http://plex.media.svc.cluster.local:32400`) is a consumer of the plex API on 32400; with the plex CNP live and plex-trakt-sync not admitted, the trakt sync is BLOCKED. Patched: added `fromEndpoints {namespace: media, name: plex-trakt-sync}` to the plex CNP's 32400 rule. NOTE: plex-trakt-sync currently has a TEMPORARY allow-world egress (trakt + plex APIs; V5 narrow-world) — tightened in V5 item (g)/(j).
- **Static validation green** on both patches (pre-commit yamlfmt/yamllint/gitleaks + kustomize render confirms the new fromEndpoints entries).
- **Live verification still PENDING (needs commit + push + Flux reconcile + sandbox-disabled Hubble):** for both (a) and (d), confirm DROPPED-clean under active load — downloads: trigger an *arr manual search → qbittorrent grab, watch `hubble_drop_total{reason="POLICY_DENIED"}` in downloads ns; plex: maintainerr/seerr/plex-trakt-sync → plex:32400 flows FORWARDED, LAN client → PLEX_IP:32400 FORWARDED, GDM UDP discovery (32410/32412/32413/32414) FORWARDED.

Next: commit the two working-tree patches (prowlarr CNP+kustomization, plex CNP plex-trakt-sync consumer) — these are live-breakage fixes, prioritize over the next interval. Then live Hubble verification (sandbox-disabled, user-run) of (a) + (d). Then continue V5: (b) grafana narrow-world, (c) paperless-gpt narrow-world, (e) victoria-logs server, (f) pocket-id SMTP, (g) worker isolation (plex-trakt-sync allow-world already flagged for narrowing), (h) external-dns, (i) mealie narrow-world, (j) the 5 TEMPORARY pre-grants, (k) coredns CNP review + the two V5 follow-ups (backrest 192.0.2.123, prometheus scrape-target label gaps).
### Session 11 — 2026-07-08

- **(a) downloads + (d) plex live Hubble verification — DONE (user-confirmed).** User ran the active-trigger Hubble capture: downloads (*arr search → qbittorrent grab) + plex (maintainerr/seerr/plex-trakt-sync → plex:32400, LAN client → PLEX_IP:32400, GDM UDP discovery) — all FORWARDED, zero POLICY_DENIED DROPPED. V5 items (a) and (d) closed.

- **V5 item (b) grafana narrow-world — DONE (commit a0454ea63 + fix 51e057d2b).** Replaced the temporary `egress.home.arpa/allow-world` pre-grant with `egress.home.arpa/custom-egress` (opt-out of the baseline) + a per-app CiliumNetworkPolicy `kubernetes/apps/observability/grafana/app/ciliumnetworkpolicy.yaml` with toFQDNs egress on 443/TCP. endpointSelector = `app.kubernetes.io/name: grafana` + `app.kubernetes.io/instance: grafana` (verified against chart 12.7.2 templates — the upstream grafana chart has NO `controller` label; that is bjw-s app-template specific). Added to app/kustomization.yaml.
  - Initial allowlist: grafana.com (plugin marketplace API + gnetId dashboard downloads) + raw.githubusercontent.com (URL-style flux/envoy dashboards). The download-dashboards INIT CONTAINER shares the pod, so the single endpointSelector covers it; the init container Completed successfully (gnetId + URL dashboards fetched).
  - **Live crash-loop surfaced the missing host.** The plugin installer (main container, GF_PLUGINS_PREINSTALL_SYNC=victoriametrics-logs-datasource@0.26.3) fetches the plugin .zip from `storage.googleapis.com/grafana-plugins-catalog/...` — the grafana.com API only returns the metadata + download URL, the archive itself is on GCS. That host was missing → DROPPED → `dial tcp 142.251.13.207:443: i/o timeout` → grafana exit 1 crash loop (restarts=2). Fix commit 51e057d2b added `matchName: storage.googleapis.com` + `matchPattern: *.storage.googleapis.com`. After Flux reconciled the updated CNP the pod recovered: plugin install succeeded (`Plugin successfully installed pluginId=victoriametrics-logs-datasource version=0.26.3 duration=7.69s` + bundled lokiexplore/pyroscope/exploretraces/metricsdrilldown), HTTP Server Listen :3000, `/api/health` → `{"database":"ok","version":"13.1.0"}`, HR Ready=True.
  - **AD-023 model refinement (same class as pocket-id MaxMind R2, Session-adjacent b4535f8e8/a14879b2a): the archive/asset CDN host ≠ the API host.** A narrow-world toFQDNs allowlist built from the config-visible API domains is a starting point, NOT the final set — the download redirect target (GCS bucket, R2 bucket) is only observable live. Workflow: ship the config-derived allowlist, watch the pod start, add the redirect-CDN host in a follow-up commit when the install/download errors with a timeout to an unlisted host. This is now the third occurrence (pocket-id MaxMind R2, grafana plugin GCS) — worth recording as a general narrow-world step in the runbook rather than re-discovering per app.
- **Verification basis:** pod-logs + live pod state (not a formal Hubble capture) — the plugin install success log line, the init container Completed state, /api/health ok, and the pod reaching Ready=true after the CNP fix together constitute functional acceptance. A formal `just k8s hubble-live-capture` under a restart is optional follow-up; no behavior gap remains (grafana is serving, all configured plugins + dashboards loaded).

Next: continue V5 — recommended next item **(c) paperless-gpt narrow-world** (same custom-egress + toFQDNs pattern; LLM API domain from V2 = api.mistral.ai + paperless API; verify pod-restart workflow). Then (e) victoria-logs server, (f) pocket-id SMTP (GeoIP already narrowed this session), (g) worker isolation (plex-trakt-sync/resticprofile), (h) external-dns, (i) mealie, (j) 5 TEMPORARY pre-grants (grafana now removed from this set — 4 remain: paperless-gpt/tuppr/plex-trakt-sync/calibre-web-automated), (k) coredns CNP review + the 2 V5 follow-ups (backrest 192.0.2.123, prometheus scrape-target label gaps).

### Session 11 — addendum (2026-07-08, cont.)

- **(b) grafana in-cluster datasource fix — DONE (commit a87d23e46).** Surfaced while starting paperless-gpt: the V5 (b) custom-egress opt-out removed grafana from the baseline allow-cluster-egress CCNP, which broke the in-cluster datasource queries (Prometheus:9090, VictoriaLogs:9428, Alertmanager:9093 all timed out from the grafana pod). `/api/health` did NOT surface this — it only checks the local DB, not datasource reachability (same "health endpoint masks egress breakage" shape as the earlier plugin-CDN crash, but quieter: no crash, no log error, just dead dashboards). Asked the user for the architectural fix (AskUserQuestion): **Option A chosen** — keep custom-egress (tight, per-app sole egress source) and add 3 explicit toEndpoints egress grants to the grafana CNP for the in-cluster datasources. Labels verified live against the running pods: prometheus/alertmanager = name+instance=kube-prometheus-stack; victoria-logs-server pod = name=victoria-logs-single + instance=victoria-logs (Service is victoria-logs-server:9428). Fix verified: Prometheus "Prometheus Server is Healthy.", victoria-logs "OK", alertmanager "OK" from the grafana UI datasource test buttons. **Model note: any custom-egress opt-out app that consumes in-cluster services needs those services as explicit toEndpoints grants in the per-app CNP — the baseline allow-cluster-egress CCNP no longer covers it.** This is a fourth narrow-world lesson (after archive-CDN ≠ API host ×2): the custom-egress opt-out is a full egress-baseline divorce, not just a world-egress narrowing.

- **V5 item (c) paperless-gpt narrow-world — DONE (commit c2bee75fc).** Replaced the temporary `egress.home.arpa/allow-world` pre-grant with `egress.home.arpa/custom-egress` (opt-out) + a per-app CiliumNetworkPolicy `kubernetes/apps/selfhosted/paperless-gpt/app/ciliumnetworkpolicy.yaml`. endpointSelector = name+instance+controller=paperless-gpt (bjw-s app-template, controller label present — unlike upstream grafana). Egress: toFQDNs mistral.ai + *.mistral.ai:443 (LLM mistral-large-latest + OCR mistral-ocr-latest) + toEndpoints paperless:8000 (in-cluster PAPERLESS_BASE_URL, labels name+instance+controller=paperless verified live). DNS via the cluster-wide allow-dns-egress CCNP. Applied Option A (same as grafana): custom-egress + explicit in-cluster grant rather than dropping back to baseline. Verified: CNP VALID=True, pod 1/1 Running 0 restarts, Hubble 4× FORWARDED paperless-gpt→paperless:8000 + 0 egress DROPPED (only ICMPv6 link-local ingress noise), startup log "Successfully refreshed custom fields cache with 1 fields" (Paperless API reachable) + "Validating OCR provider 'mistral_ocr'" → no error → "Server started" (Mistral provider init ok). Note: Mistral was NOT exercised by a real document during the window — the startup validation call is the only Mistral touch; a real OCR job may yet surface a Mistral CDN host (like grafana's storage.googleapis.com) — that would be a follow-up add (committed message flags it). Mistral api.mistral.ai is the documented API host; no separate CDN known yet.

Next: continue V5 — recommended next item **(e) victoria-logs server** (observability in-cluster, likely needs only in-cluster egress grants, no world). Then (f) pocket-id SMTP (GeoIP already narrowed this session), (g) worker isolation (plex-trakt-sync allow-world → narrow; resticprofile), (h) external-dns, (i) mealie, (j) the 4 remaining TEMPORARY pre-grants (grafana + paperless-gpt now removed from this set — 3 remain: tuppr/plex-trakt-sync/calibre-web-automated), (k) coredns CNP review + the 2 V5 follow-ups (backrest 192.0.2.123, prometheus scrape-target label gaps).

### Session 11 — addendum 2 (2026-07-08, cont.): grafana sidecar kube-apiserver breakage + gravatar

- **V5 (b) grafana — second/third follow-up (commits 9f758270f → 75505559c).** The V5 (b) custom-egress opt-out broke MORE than the in-cluster datasources (addendum 1): it also dropped grafana from the baseline `allow-cluster-egress` CCNP's `toEntities: [kube-apiserver]` grant. The kiwigrid sidecars (`grafana-sc-dashboard` + `grafana-sc-datasources`) discover dashboards/datasources stored as labeled Secrets (`grafana_dashboard`/`grafana_datasource`) via the Kubernetes API (service `10.245.0.1:443` → backend kube-apiserver:6443). With kube-apiserver egress gone, both sidecars crash-looped (exit=1, `ConnectTimeoutError: Connection to 10.245.0.1 timed out`). The main grafana container stayed healthy and `/api/health` stayed green — the sidecar crash was masked at the health-endpoint level (sidecar readiness is its OWN local health server on :8080, NOT the API connection, so `ready=true` lied about the broken API path).
  - **Fix 1 (9f758270f) was WRONG**: I added `toEntities: [kube-apiserver]` with `toPorts: port "443"`. The sidecars still timed out. Root cause: Cilium evaluates egress policy **post-DNAT on the backend port (6443)**, not the service frontend port (443) — the DROPPED flow showed `kube-apiserver:6443`. Port 443 in the grant never matched.
  - **Fix 2 (75505559c) correct**: changed to `toPorts: port "6443"`, matching the established repo pattern in `kubernetes/apps/external-secrets/external-secrets/app/ciliumnetworkpolicy.yaml` (`toEntities: [kube-apiserver]` + `toPorts: 6443/TCP`). Verified: sidecar log `"Initial sync complete, sidecar is ready"` + dashboard files written (`victorialogs-single-node.json`, `tuppr.json`, `cilium-dashboard`, etc.) + `"Dashboards config reloaded" 200 OK`. Pod 3/3 Running 0 restarts. Hubble 0 DROPPED to kube-apiserver.
  - **gravatar.com**: user pointed out Hubble also DROPPED `secure.gravatar.com` (grafana fetches user avatars from gravatar). Added `matchName: gravatar.com` + `matchPattern: *.gravatar.com` to the toFQDNs allowlist (443). Structurally covers secure.gravatar.com; no DROPPED after the fix.
- **FIFTH narrow-world lesson (the custom-egress divorce is broader than world/datasources):** a custom-egress opt-out app with kiwigrid-style sidecars (or any container that does K8s API discovery, watches, or controller-runtime calls) ALSO needs an explicit `toEntities: [kube-apiserver]:6443` egress grant in the per-app CNP — the baseline `allow-cluster-egress` CCNP no longer covers it. Audit any custom-egress app for: (1) world FQDNs, (2) in-cluster service endpoints (toEndpoints), (3) kube-apiserver (toEntities 6443) if any container uses the K8s API. The health endpoint can mask this — verify via container logs + Hubble, not just pod Ready.
- **Port convention (repo standard):** kube-apiserver egress is always `toEntities: [kube-apiserver]` + `toPorts: 6443/TCP` (external-secrets CNP is the reference). Never 443 (frontend) — Cilium evaluates post-DNAT on the backend 6443.

Next: (e) victoria-logs server, (f) pocket-id SMTP, (g) worker isolation (plex-trakt-sync/resticprofile), (h) external-dns, (i) mealie, (j) 3 remaining TEMP pre-grants (tuppr/plex-trakt-sync/calibre-web-automated), (k) coredns CNP review + 2 V5 follow-ups (backrest 192.0.2.123, prometheus scrape-target labels). NOTE for (e): victoria-logs server is custom-egress already? check; if it has no sidecars and no K8s API use, kube-apiserver grant not needed — apply the 3-point custom-egress audit (world / in-cluster / kube-apiserver) per app.

### Session 12 — 2026-07-09

- **Security review of the full AD-023 direction (user request): direction CONFIRMED, no redesign needed.** Deviations from the gabe565 model are deliberate and mostly stronger (LAN carve-out in allow-world, L7 DNS proxy + toFQDNs kept, permanent DROPPED alerting). Residual risks ranked and dispositioned below.
- **SA/RBAC audit (review finding #5): fleet is clean except grafana.** automountServiceAccountToken: false on effectively all app HRs; homepage is the accepted exception (read-only ClusterRole, no secrets — live can-i verified no/no). **GRAFANA FINDING (HIGH): sidecar searchNamespace: ALL → chart ClusterRole with cluster-wide secrets get/list/watch; live-verified can-i list secrets -A = yes (external-secrets ns included).** Internet-routed pod with all-secrets read = network-containment bypass. Remediation planned as V5 (n).
- **Three new execution-grade V5 items recorded in the roadmap note** (full YAML, exact file paths, verify/accept/rollback per step — written so a less capable executor can implement without design decisions):
  - (l) DNS-exfil detection alert: cilium HR dns:labelsContext edit + baseline-derived VOLUME_THRESHOLD + hubble-dns-exfil.yaml PrometheusRule (volume + NXDOMAIN-ratio alerts) + deliberate nslookup-loop test.
  - (m) ingress-from-gateways split into gateways-dual/gateways-internal (user decision, names carry the exposure class): 2 new CCNPs, 24-HR migration table (15 dual / 9 internal; tinyauth must stay dual — ext-auth hop), 2-commit additive→retire plan, victoria-logs (e) takes gateways-internal from the start.
  - (n) grafana sidecar RBAC removal: configmaps-only hand-written ClusterRole via rbac.useExistingClusterRole + datasources sidecar disabled (live fact: zero grafana_datasource objects exist; datasources are inline) + dashboards resource: configmap; chart 12.7.2 values keys verified.
- **AD-023 rev3 recorded**: gateways vocabulary split decision, SA/RBAC-containment addendum (incl. governance rule: check chart RBAC for secrets verbs on adoption), DNS-exfil detection as permanent monitoring.
- Roadmap V5 remainder list now points to the three new sections; the earlier one-liner DNS item was replaced.

Next: user picks the first implementation among V5 (m) commit 1 (additive CCNPs + labels), (n) grafana RBAC (single commit, highest security value), or (l) commit 1 (cilium dns labelsContext — can land anytime, starts the baseline clock). Then continue V5 (e)(f)(g)(h)(i)(j)(k) + the 2 follow-ups. BM docs commit pending (basic-memory/ changes from this session).

### Session 12 — addendum (2026-07-09, cont.): V5 (n) removed from the CNP plan

- **User decision: the grafana RBAC remediation is OUT of the CNP rollout scope.** The V5 (n) section and its remainder-list pointer were removed from the roadmap note; V5 items are now (a)-(m) with (e)-(k) + (l)(m) + 2 follow-ups remaining. AD-023 rev3 [rbac-containment] updated: the grafana finding (cluster-wide secrets get/list/watch on an internet-routed pod, live-verified) stays OPEN and documented, remediation direction candidate is a grafana-operator migration (assessed this session: operator pushes via Grafana HTTP API → grafana pod loses ALL K8s API access, CNP drops the kube-apiserver:6443 grant, sidecar failure class disappears; cost: full HR refactor + wrapper GrafanaDashboard CRs for the 6 chart-emitted ConfigMaps + operator CRD bootstrap + admin-credential secret flow). If/when decided, it becomes its own roadmap item — not part of this rollout.

Next: user picks the first implementation among V5 (m) commit 1 (additive gateways-dual/internal CCNPs + labels) or (l) commit 1 (cilium dns labelsContext — starts the baseline clock); then continue V5 (e)(f)(g)(h)(i)(j)(k) + the 2 follow-ups. BM docs commit pending.


### Session 13 — 2026-07-10

- **AD-023 rev4 (uniform public-issuer OIDC convention) DEPLOYED + VERIFIED live.** Committed as 409242998 ("CNP") on main and pushed (user-driven); Flux reconciled. This session picked up the rev4 work that was sitting uncommitted in the working tree (no prior session summary), ran the pre-deploy safety checks, then verified post-deploy.
- **What rev4 does:** every native OIDC client (grafana, tinyauth, pingvin-share-x) uses the PUBLIC issuer https://id.${PUBLIC_DOMAIN} for ALL endpoints (auth/token/userinfo/discovery); the split internal/public config is retired. NEW vocabulary label egress.home.arpa/allow-gateways + NEW CCNP allow-gateways-egress (envoy :10443) for custom-egress OIDC clients (grafana, pingvin). CoreDNS split-horizon: the ${PUBLIC_DOMAIN} zone forwards to ${K8S_GATEWAY_IP} (k8s-gateway) so pods resolve public hostnames to the envoy-internal VIP without the node-resolver→router hop. pocket-id CNP ingress section removed (tinyauth now arrives via envoy, not east-west); MaxMind GeoLite2 egress preserved. New tool: just k8s show-cnp-matrix.
- **Static pre-deploy checks (all green):** pre-commit clean on all 10 touched files; flux-local build of cilium-netpols KS (7 CCNPs incl. new allow-gateways-egress), coredns, grafana-instance, pocket-id all exit 0. OIDC migration completeness: zero remaining in-cluster OIDC endpoint refs, zero direct pocket-id service refs — all three clients on the public issuer. **CoreDNS split-horizon NXDOMAIN risk assessed NIL:** k8s-gateway resolves ONLY envoy-internal HTTPRoute hostnames (watchedResources HTTPRoute + filters.gatewayClasses envoy-internal); enumerated every workload egress target under ${PUBLIC_DOMAIN} — no pod egress-depends on a non-envoy-internal public host. flux-webhook.${PUBLIC_DOMAIN} is external-only but inbound-only (GitHub→tunnel), not a pod egress. All other ${PUBLIC_DOMAIN} hits are self-advertise URLs / forward-auth cookie-domain metadata / browser-side favicon. id.${PUBLIC_DOMAIN} (hairpin target) is dual-routed (envoy-internal + envoy-external) → resolves in-cluster.
- **Post-deploy live verification (read-only kubectl/flux/Hubble, sandbox disabled for cluster + LAN API access):** 7 CCNPs Valid=True incl. allow-gateways-egress (correct endpointSelector allow-gateways + toEndpoints envoy :10443). coredns Corefile carries the split-horizon block (dns://horvathzoltan.me:53 { forward . 192.168.1.19 }); coredns pod rolled. DNS from grafana AND pingvin pods: id.horvathzoltan.me → 192.168.1.18 (envoy-internal LB VIP) — split-horizon live. Live label posture: grafana pod = custom-egress + allow-gateways; pingvin pod = custom-egress + allow-gateways; tinyauth = baseline-egress (ingress gateways only, no CNP) so allow-cluster-egress covers its hairpin. pocket-id CNP ingress section empty (removed), egress keeps MaxMind FQDNs.
- **LB-VIP identity caveat RESOLVED (the single biggest open unknown, roadmap-flagged).** User logged into pingvin-share-x (discovery-only client, custom-egress + allow-gateways) during a 150s Hubble capture: login OK. Capture confirms pingvin → envoy pod (10.244.0.136, k8s:app.kubernetes.io/name=envoy, gateway envoy-internal) :10443 FORWARDED. So the socketLB translates the envoy-internal LB VIP (192.168.1.18) to the envoy POD identity BEFORE egress policy evaluation → the allow-gateways-egress toEndpoints (app=envoy) matches → the hairpin is FORWARDED. **No toCIDR VIP grant is needed** — the toEndpoints model is correct. (Consistent with the netkit + socketLB.hostNamespaceOnly:false prerequisite from AD-023.)
- **Finding DELEGATED to the grafana-operator-migration roadmap (user decision — out of CNP-rollout scope):** the grafana pod tries to install 5 default preinstalled plugins (grafana-metricsdrilldown-app, elasticsearch, grafana-lokiexplore-app, grafana-pyroscope-app, grafana-exploretraces-app) from grafana.com/api/plugins at startup → resolves to 34.120.177.193 (GCP) → the tight rev4 grafana CNP (D13 "no plugins", grafana.com/GCS egress removed) DROPS it → HubblePolicyDeny (critical) fired. grafana pod itself is Running 1/1 0 restarts (the background plugin installer failures are non-fatal). Clean fix would be grafana.ini [plugins] preinstall_disabled=true (Context7-confirmed) OR preinstall_auto_update=false, but the user owns this on the grafana-operator-migration thread; NOT fixed here.
- **Transient/unrelated (self-healed):** FluxOCIRepository OCIArtifactPullFailed alerts (external-secrets/app-template, observability/victoria-logs-collector) fired during the window but both are Ready=True again — a brief ghcr.io pull hiccup, not rev4-related (source-controller ghcr egress is the unchanged flux-system infra-namespace world grant; no flux-system policy drops in the Hubble buffer).

Next: continue V5 remainder. Per the rev4 naming-grammar decision, V5(m) is AMENDED (new labels ingress.home.arpa/allow-gateways-dual + allow-gateways-internal; ingress.home.arpa/prometheus → allow-prometheus rides the same staged batch). Candidate next items: **V5(m)** gateways-split (large, 2-commit additive→retire, ~24 HRs — full plan + migration table in the roadmap) or **V5(l)** DNS-exfil detection alert (smaller, independent, starts the baseline clock — cilium dns labelsContext + PrometheusRule). Plus the smaller wins: (e) victoria-logs server, (f) pocket-id SMTP, (g) worker isolation (plex-trakt-sync/resticprofile ingress.home.arpa/none), (h) external-dns narrow-world, (i) mealie narrow-world, (j) remaining 3 TEMPORARY pre-grants (tuppr/plex-trakt-sync/calibre-web-automated), (k) coredns CNP keep-vs-remove review, + 2 follow-ups (backrest 192.0.2.123, prometheus scrape-target label gaps). User picks the next item.


### Session 14 — 2026-07-10

- **V5(j) first app + V5(g) — plex-trakt-sync narrow-world + worker isolation DONE (commit 58558db15) and verified.** Replaced the TEMPORARY egress.home.arpa/allow-world label with egress.home.arpa/custom-egress + ingress.home.arpa/none. New per-app CNP kubernetes/apps/media/plex-trakt-sync/app/ciliumnetworkpolicy.yaml: egress toFQDNs api.trakt.tv + *.trakt.tv:443 + toEndpoints plex(media):32400; DNS via the cluster-wide allow-dns-egress CCNP; ingress default-deny via the ingress.home.arpa/none label (ingress-none CCNP). endpointSelector = name+instance+controller=plex-trakt-sync (bjw-s app-template, controller label present).
- **Allowlist rationale:** live config.yml has watchlist=false, collection=false, liked_lists=false → no plex.tv/MyPlexAccount calls; sync is local Plex (in-cluster PLEX_BASEURL) ↔ Trakt only. So api.trakt.tv is the sole world dependency. xbmc-providers imdb/tvdb are ID-matching via the Trakt API, not separate egress.
- **(j) sequencing decision:** started with plex-trakt-sync (not tuppr) — its egress is finite/documented (Trakt) and it is a periodically-active worker, and it doubled as the V5(g) worker-isolation item (consumer-less → ingress.home.arpa/none). tuppr DEFERRED to a planned Talos/K8s upgrade window: its egress is idle between upgrades (versions pinned) and includes the Talos-API path that only surfaces during an upgrade, so tightening it now would let a break surface only at the next upgrade (late-surfacing lesson) — tighten it live during an upgrade instead. calibre-web-automated is the next (j) candidate, but verify its metadata-egress breadth first (may be mealie-like open-web, in which case allow-world stays).
- **Static validation:** pre-commit clean on the 3 files; flux-local render exit 0 — CNP correct (selector + trakt FQDNs + plex:32400), app pod labels = custom-egress + ingress.home.arpa/none (allow-world gone from the app pod; the two remaining allow-world in the render are the VolSync mover moverPodLabels, expected/unrelated). Committed 58558db15 on main; pushed (user); Flux reconciled.
- **Live verification (read-only kubectl + Hubble, sandbox disabled):** CNP plex-trakt-sync VALID=True. Pod rolled (plex-trakt-sync-8679c9845f-sb2hm) carrying custom-egress + ingress.home.arpa/none, allow-world gone. `just k8s show-cnp-matrix plex-trakt-sync` = e:dns ✓, e:cluster ·, e:world ·, e:open ·, i:none ✓, i:open ·, APP-CNP=plex-trakt-sync(e) — exactly the designed posture. Zero DROPPED egress from the pod. **Plex in-cluster path POSITIVELY confirmed via pod logs**: "Connecting with url: http://plex.media.svc.cluster.local:32400" → "Server connected: PlexServer (1.43.2.10687)" → "Websocket connected" → "Listening for events!" (the toEndpoints :32400 grant covers both HTTP and the notifications websocket).
- **Deferred positive check (low risk, monitored):** the Trakt egress (api.trakt.tv) is NOT exercised at startup — plextraktsync `watch` only calls Trakt on a Plex scrobble event (threshold 90%). So Trakt FORWARDED will be observable only after a real playback. The CNP allowlist + DNS are in place and the V4 HubblePolicyDeny alert is the safety net — any missed host DROPs and fires. If a scrobble-time DROP to an unlisted trakt/plex host appears, add it (Session 11 archive-CDN lesson class).

Next: continue V5(j) — calibre-web-automated (verify metadata-egress breadth first; if open-web like mealie, keep allow-world and note it). Then the remaining V5 items: (e) victoria-logs server, (f) pocket-id SMTP, (h) external-dns narrow-world, (k) coredns CNP review, tuppr (at an upgrade window), the bigger (m) gateways-split and (l) DNS-exfil alert, + the 2 follow-ups (backrest 192.0.2.123, prometheus scrape-target label gaps). BM progress note updated this session is ready for a docs commit.


## Update — 2026-07-10: Grafana plugin-preinstall finding RESOLVED

- [observation] The finding delegated to the grafana-operator-migration roadmap (grafana pod attempting 5 default preinstall app-plugin downloads from grafana.com at startup → blocked by the rev4 CNP → HubblePolicyDeny critical alert) is **resolved**: `preinstall_disabled: "true"` was added to the Grafana CR config (commit 4ba4c9ce8). Grafana no longer attempts the startup plugin fetch, so the grafana → grafana.com egress denies stop firing. Aligns with roadmap D13 (no plugins). The 4 explore/drilldown apps require backends (Loki/Tempo/Pyroscope) not present in this cluster; metrics-drilldown (Prometheus) was unused. See [[grafana-operator-migration]].


### Session 15 — 2026-07-10

- **V5(j) second app — calibre-web-automated narrow egress DONE and verified (commits 318d61acd → NETWORK_SHARE_MODE fix, all pushed).** User requirements: no general internet (it does not download book metadata), allow SMTP to mail-eu.smtp2go.com, and add egress.home.arpa/allow-gateways for upcoming OAuth. Result: dropped egress.home.arpa/allow-world → egress.home.arpa/custom-egress + egress.home.arpa/allow-gateways; kept ingress.home.arpa/gateways (dual-routed books.PUBLIC_DOMAIN). New per-app CNP: sole egress = toFQDNs mail-eu.smtp2go.com + *.smtp2go.com :465 (SSL, port from user). DNS via allow-dns-egress; OIDC hairpin via the allow-gateways-egress CCNP; NFS to the NAS is node-level (not pod egress) so no rule.
- **Molyhu metadata provider disabled (per user "comment out, don't delete"):** the git-sync initContainer cloned github.com/crash5/calibre-molyhu on every boot (github.com egress, incompatible with no-internet). Commented out the two initContainers AND the molyhu-repo/molyhu-provider persistence volumes (the app subPath-mounted moly_hu.py from molyhu-provider — leaving the mount without the populating init would break startup). Commented (not deleted) with a re-enable note. yamlfmt-safe by placing the commented volumes before a real key (nfs-calibre-library).
- **INCIDENT (deploy-time, resolved) — NFS-library chown vs startup probe.** After removing allow-world, the pod restart-looped (0/1, exit 137 SIGKILL). Root cause CONFIRMED and NOT the CNP (zero DROPPED egress; a live `chown -R abc:abc /calibre-library` process was running 186s+): the CWA-init runs a recursive chown of the NFS ebook library on every boot, which exceeded the startup probe budget (~285s) so the web server never bound :8083. This chown is hardcoded in the CWA image init (ran on the old pod too); it is not caused by the molyhu removal (chown runs regardless).
- **Fix — CWA NETWORK_SHARE_MODE=true (researched, first-party, cited).** CWA's cwa-init/run skips the recursive chown of the network-share paths (/calibre-library, /config, /cwa-book-ingest) when NETWORK_SHARE_MODE=true, and additionally disables SQLite WAL + switches ingest/metadata watchers from inotify to polling — all correct for an NFS-backed library (README "Deploying on Network Shares"; guard in root/etc/s6-overlay/s6-rc.d/cwa-init/run; accepts true/1/yes/on). Caveat: CWA no longer normalizes library ownership, so NFS files must already be usable by PUID/PGID (1000/100) — satisfied (calibre already read/wrote the library). NFS was NOT modified (user constraint). An emergency startup-probe bump (failureThreshold 120 x periodSeconds 10 ≈ 20m) was applied first as immediate mitigation; the final merged state on origin keeps that widened probe as a safety margin alongside NETWORK_SHARE_MODE.
- **Live verification:** pod 1/1 Running, 0 restarts, stable. Logs confirm NETWORK_SHARE_MODE active: "Skipping PRAGMA quick_check ... NETWORK_SHARE_MODE=true", "WAL mode disabled ... NETWORK_SHARE_MODE=true", "polling watcher instead of inotify", and "Starting Gevent server on [::]:8083" + "Connection to 8083 succeeded" (web server binds fast, no chown block). CNP Valid=True; live labels custom-egress + allow-gateways + ingress gateways (allow-world gone). show-cnp-matrix: e:dns ✓, e:gateways ✓ (OIDC hairpin grant in place), e:world ·, i:gateways ✓ — exact designed posture. Zero DROPPED egress. Deferred/monitored positive checks: SMTP :465 fires only on a real mail send; the OIDC hairpin activates only once OAuth is configured — both covered by the HubblePolicyDeny alert.
- **plex-trakt-sync refinement (user edit, commit 890ca0aa1):** user added a second toFQDNs egress rule plex.tv:443 to the plex-trakt-sync CNP — plextraktsync calls the MyPlex account API (/api/v2/user) to resolve/validate PLEX_TOKEN, in addition to api.trakt.tv. CNP Valid=True, zero DROPPED. This closes the deferred Trakt/Plex world-egress question from Session 14.
- **Git note:** heavy parallel user commits/merges this session (grafana-operator-migration + these fixes); final origin/main state is clean and in sync. Per user instruction, no further history rewriting — what is pushed stays.

Next: V5(j) remaining = tuppr (defer to a planned Talos/K8s upgrade window — idle egress, Talos-API path surfaces only at upgrade; tighten live with a Hubble capture during the upgrade). Then (e) victoria-logs server, (f) pocket-id SMTP, (h) external-dns narrow-world, (k) coredns CNP review, the larger (m) gateways-split and (l) DNS-exfil alert, + the 2 follow-ups (backrest 192.0.2.123, prometheus scrape-target label gaps).


### Session 16 — 2026-07-10

- **V5(h) external-dns narrow-world DONE + verified (commit df71cdef5, pushed).** Dropped egress.home.arpa/allow-world → egress.home.arpa/custom-egress + ingress.home.arpa/prometheus (it has a ServiceMonitor, so ingress is now default-denied except the Prometheus scrape). New per-app CNP (endpointSelector name+instance=external-dns, official chart — no controller label): sole egress = toFQDNs api.cloudflare.com:443 (Cloudflare DNS record sync) + toEntities kube-apiserver:6443 (watches Ingress/HTTPRoute/Gateway sources); DNS via allow-dns-egress. Static: pre-commit clean, render exit 0. Live verification: CNP Valid=True; pod carries custom-egress + prometheus, allow-world gone; **logs are the definitive positive proof** — external-dns retrieved the full Cloudflare zone record set and logged "All records are already up to date" (api.cloudflare.com reached) and is reading HTTPRoutes/Ingress (kube-apiserver reached), with NO connection errors; zero DROPPED egress. (Hubble FORWARDED buffer was empty at check time — long-lived/aged flows — but the sync-success log is stronger evidence.)
- **V5(f) pocket-id SMTP DONE (user edit).** User added a second toFQDNs egress rule to the pocket-id CNP: mail-eu.smtp2go.com + *.smtp2go.com :465 (implicit TLS), alongside the existing MaxMind GeoLite2 egress. Verified: CNP Valid=True, pod 1/1 Running, zero DROPPED. This resolves the V2 "pocket-id SMTP (survey)" item — pocket-id does send mail via SMTP2GO, now granted narrowly. Same pattern as calibre.
- **(j)/(h)/(f) status:** narrow-world tightenings complete for plex-trakt-sync, calibre-web-automated, external-dns, grafana (S11), paperless-gpt (S11), pocket-id GeoIP (S11) + SMTP (this session). mealie intentionally stays allow-world (open-web recipe import). Remaining allow-world holders that stay: the *arr/download apps (indexers/trackers/peers), plex/seerr (external APIs), speedtest-exporter, homepage/wallos (widgets), kopia/volsync movers (S3), source-controller/cert-manager/flux (infra grant).

Next: (k) coredns CNP keep-vs-remove review (currently inert — baseline kube-apiserver covers the node-resolver forward; rev4 added the split-horizon so re-check the interaction); the larger (m) gateways-split (2-commit, ~24 HRs, amended label names per rev4) and (l) DNS-exfil detection alert; tuppr (defer to a Talos/K8s upgrade window, tighten live with a Hubble capture); + the 2 follow-ups (backrest 192.0.2.123 TEST-NET egress investigation, prometheus scrape-target label-gap audit).


### Session 17 — 2026-07-10

- **V5(tuppr) DONE + verified live during a real Talos upgrade.** User signalled the deferred upgrade window ("van tuppr-hez talos upgrade-em"); executed the full capture→analyze→tighten flow this session. Merged Renovate PR #3979 (Talos v1.13.5→v1.13.6 patch, squash @d3683e81) → forced Flux reconcile → tuppr triggered the single-node powercycle upgrade. Ran a cluster-wide Hubble capture (sandbox disabled) across the pre-reboot window; the port-forward broke exactly at reboot (as expected), leaving the full pre-reboot egress/ingress set. Node upgraded clean v1.13.5→v1.13.6, ~3.5 min outage (20:48:07→20:51:32Z).
- **Egress evidence (definitive, from the live upgrade):** only `factory.talos.dev:443` (installer image availability check) + `kube-apiserver:6443` (K8s API — watch TalosUpgrade/nodes) + `kube-apiserver:50000` (Talos apid) + DNS. On the single node the Talos apid (kubernetesTalosAPIAccess) shares the apiserver IP, so both the K8s API and the Talos API land on the `reserved:kube-apiserver` identity — one `toEntities: kube-apiserver` (ports 6443+50000) covers both. **The old "factory.talos.dev + github releases" comment was WRONG on github** — tuppr resolves the pinned version into a factory image URL and never touches GitHub. No github egress in the capture.
- **Commit 1 @0a799fde9** (`feat(tuppr): custom-egress CNP`): dropped `egress.home.arpa/allow-world` → `custom-egress`; new per-app CNP (endpointSelector name+instance=tuppr, official chart — no controller label) = sole egress source (factory.talos.dev + kube-apiserver 6443/50000). DNS via allow-dns-egress. Ingress initially left open. Verified: CNP Valid, pod rolled to custom-egress, matrix e:world· e:open· e:dns✓, live kube-apiserver:6443 FORWARDED.
- **User challenge — "ingress-none nem kellene rá?"** Investigated: NO. tuppr runs a `ValidatingWebhookConfiguration` (`vtalosupgrade.kb.io` + `vkubernetesupgrade.kb.io`, **failurePolicy=Fail**) that the apiserver calls on :9443 for every TalosUpgrade/KubernetesUpgrade CREATE/UPDATE (fired 20× on the v1.13.6 apply), plus kubelet liveness/readiness probes + Prometheus scrape on :8081 (container ports: webhook-server:9443, metrics:8081). `ingress-none` (deny-all) would make the webhook unreachable → failurePolicy=Fail → the apiserver would REJECT every upgrade-CR write (self-lock: recoverable only by kubectl-deleting the CNP), and break the probes. Wrong tool.
- **Commit 2 @50764e5a6** (`feat(tuppr): close ingress`): closed ingress the correct way. Prometheus scrape (:8081) via the `ingress.home.arpa/prometheus` label + matching CCNP (all-ports grant — external-dns/echo precedent). The app-unique part in the per-app CNP: `fromEntities: kube-apiserver` → :9443 (webhook) + :8081 (probes; node IP = apiserver identity), `fromEntities: host` → :8081 (probe-path fallback if ever classified reserved:host).
- **Verification (ingress default-deny now on):** CNP Valid; new pod Ready, 0 restarts (readiness httpGet:8081 passes → probe path works); matrix `e:world· e:open· e:dns✓ | i:prometheus✓ i:open· | tuppr(ei)`. **Webhook reachability proven** via `kubectl apply --dry-run=server` round-trip of the live TalosUpgrade — tuppr's own webhook warnings echoed back ("Powercycle reboot mode selected", "Debug mode enabled", …) + "configured (server dry run)", i.e. the apiserver reached :9443 through the closed ingress. Live 35s capture: kube-apiserver→9443/8081 + prometheus→8081 all FORWARDED; zero policy DROPPED (only pre-existing IPv6 NDP ff02::2 ICMPv6/133 UNSUPPORTED_L3_PROTOCOL noise).
- **external-dns (h) + pocket-id SMTP (f):** already recorded in Session 16 (commits df71cdef5 / 278bbac6b) — confirmed present in the V5 tracker; no re-recording needed. tuppr was the last deferred narrow-world holder.

Next: V5 remaining = (e) victoria-logs server, (k) coredns CNP keep-vs-remove review (inert; baseline covers node-resolver forward — re-check rev4 split-horizon interaction), (m) gateways-split (2-commit, ~24 HRs, rev4 label names), (l) DNS-exfil detection alert; + 2 follow-ups (backrest 192.0.2.123 TEST-NET egress, prometheus scrape-target label-gap audit).


### Session 18 — 2026-07-10

- **V5(k) coredns CNP review DONE → CNP REMOVED.** Reviewed keep-vs-remove with live evidence; the CNP's only rule (`toEntities: world` :53, selector k8s-app=kube-dns) is **never the enforcement point**:
  - `.` upstream forward: Talos `hostDNS.enabled + forwardKubeDNSToHost: true` → coredns forwards `.` to the **host DNS on the node**; the host does the real upstream resolution. Live coredns egress = `kube-apiserver:53` (UDP+TCP) — node IP = kube-apiserver identity on the single node, covered by the allow-cluster-egress baseline (`toEntities: [cluster, kube-apiserver]`, no port limit). The coredns pod never egresses to the LAN router / public resolvers.
  - rev4 split-horizon: `${PUBLIC_DOMAIN}` → `${K8S_GATEWAY_IP}` (192.168.1.19, k8s-gateway LB VIP). Forced cache-miss forwards showed `coredns → k8s-gateway pod:1053 FORWARDED` — socket-LB DNAT'd to the in-cluster backend, covered by baseline `toEndpoints: [{}]`. The `world:192.168.1.19:53` representation is only a **TRACED datapath artifact** (pre-DNAT L3 dst), not a policy verdict.
  - kubernetes plugin: `kube-apiserver:6443` — baseline covers.
- **prune: false gotcha.** The coredns ks carries `prune: false # Never delete this` (coredns is critical — Flux must never GC it). So removing the resource from the kustomization does NOT auto-delete the live CNP; it required a **one-time manual `kubectl delete cnp coredns -n kube-system`** after the git removal. Documented here so future prune:false resources are handled the same way.
- **Removal commits:** @3ec936cba (delete ciliumnetworkpolicy.yaml) + @6b621c68b (drop the kustomization ./ciliumnetworkpolicy.yaml entry) + manual kubectl delete.
- **Self-inflicted incident (resolved, no cluster impact):** @3ec936cba was created via `git rm` (deletion staged) followed by `git add kustomization.yaml ciliumnetworkpolicy.yaml` — the already-rm'd second pathspec hit a `fatal:` that **aborted staging kustomization.yaml**, so the commit deleted the file but left the dangling kustomization reference → coredns ks build failed on main (`no such file`), ks stuck, so the live CNP lingered (hence DNS was never at risk). Fixed in @6b621c68b. Lesson: never pass an already-`git rm`'d path to `git add`; stage the kustomization edit separately.
- **Verified baseline-only (CNP deleted live):** DNS from a pod — internal (kubernetes.default) OK, external (one.one.one.one) OK, github.com OK, **public-domain split-horizon (auth.horvathzoltan.me → 192.168.1.18) OK**. coredns egress = kube-apiserver:53/6443 + k8s-gateway pod:1053, all FORWARDED; **zero DROPPED**. Baseline CCNPs (allow-cluster-egress, allow-dns-egress) intact. Rollback CNP was staged in scratch but not needed.

Next: V5 remaining = (e) victoria-logs server, (m) gateways-split (2-commit, ~24 HRs, rev4 label names), (l) DNS-exfil detection alert; + 2 follow-ups (backrest 192.0.2.123 TEST-NET egress, prometheus scrape-target label-gap audit).


### Session 19 — 2026-07-10

- **V5(e) victoria-logs DONE + verified** (@d37f89f69). Only the **server** needed work; the **collector** is untouched (live: its egress = server:9428 + kube-apiserver:6443 + DNS, all baseline-covered — matches roadmap).
- **Design (user chose Option B — existing `gateways` label):** the rev4 `gateways-internal` CCNP does not exist yet (the (m) split hasn't landed), so per user decision the server uses the existing `ingress.home.arpa/gateways` label now (migrate to gateways-internal when (m) lands). Server labels: `egress.home.arpa/custom-egress` + `ingress.home.arpa/gateways` + `ingress.home.arpa/prometheus` (chart values key = `server.podLabels`, emission confirmed via helm template on victoria-logs-single 0.13.8).
- **Per-app CNP (ingress-only, NO egress section → DNS-only sink):** `fromEntities: [kube-apiserver, host]` → :9428 (kubelet probes) + `fromEndpoints: victoria-logs-collector` → :9428 (remoteWrite). The envoy-internal route + Prometheus scrape come via the gateways/prometheus labels + CCNPs. Everything on VictoriaLogs' single port :9428.
- **Roadmap correction:** the planned "grafana named-consumer" is NOT needed — grafana has no victoria-logs datasource (live capture never showed grafana; grep confirms D13 no-plugins, vlogs datasource absent). Dropped that rule.
- **Egress lockdown evidence:** the server initiated ZERO egress in a 40s capture → pure sink; custom-egress + empty-egress CNP leaves DNS-only (allow-dns-egress). Confirmed safe.
- **Deploy note:** the Flux ks apply alone did not roll the StatefulSet pod (helm-controller upgrades the release on its own interval); forced `flux reconcile helmrelease victoria-logs -n observability` to trigger the pod roll with the new labels.
- **Verification:** server pod rolled with all 3 labels, Ready, 0 restarts (probe path works under ingress default-deny); CNP Valid; matrix server = e:dns✓/e:world·/e:open· + i:gateways✓/i:prometheus✓/i:open· + victoria-logs(i), collector = baseline (APP-CNP -). Logs UI returns 200 via envoy-internal; live ingress = kube-apiserver(probes)+envoy-internal+collector+prometheus all :9428 FORWARDED; server egress DNS-only; zero policy DROPPED (only pre-existing IPv6 NDP ff02::2 ICMPv6/133 noise).

Next: V5 remaining = (m) gateways-split (2-commit, ~24 HRs, rev4 gateways-external/internal labels — victoria-logs + others migrate off the combined `gateways` label here), (l) DNS-exfil detection alert; + 2 follow-ups (backrest 192.0.2.123 TEST-NET egress, prometheus scrape-target label-gap audit).


### Session 20 — 2026-07-10

- **V5(e) collector ingress CLOSED** (@7bc05ca9a) — completes (e); the whole victoria-logs stack ingress is now default-deny. The collector's only ingress is the Prometheus podMonitor scrape (:9429) and it has **no health probes**, so a single `ingress.home.arpa/prometheus` label suffices (chart values key = top-level `podLabels`, victoria-logs-collector 0.3.6, emission verified via helm template). No per-app CNP needed (no probes, no other consumers). Egress stays baseline (server:9428 + apiserver:6443 + DNS, in-cluster). Verified: DaemonSet pod rolled with the label + Ready; matrix collector = e:cluster✓/e:dns✓ + i:prometheus✓/i:open· + APP-CNP `-`; prometheus→collector:9429 FORWARDED; zero policy DROPPED (only IPv6 NDP noise).
- **HubblePolicyDeny (critical) — TRANSIENT, resolved, not a policy gap.** During the S19 server StatefulSet roll a single `prometheus→victoria-logs-server-0:9428` scrape landed in the window after the new pod came up under the CNP's ingress default-deny but before Cilium associated the new endpoint with the `ingress.home.arpa/prometheus` label/CCNP → one POLICY_DENIED → the sensitive alert fired. Investigated with the alert's own command (`hubble observe --to-pod victoria-logs-server-0 --verdict DROPPED --print-policy-names --last 300`): empty (no ongoing denies); current server pod carries the prometheus label; live scrape FORWARDED. Same rollout-transient class the V4 note logged (Session 9: 2 transient bursts). Auto-resolves. Rolling a pod that is selected by an ingress-default-deny policy can momentarily deny a scrape before the identity/policy map catches up — expected, not a misconfiguration.

Next: V5 remaining = (m) gateways-split (2-commit, ~24 HRs, rev4 gateways-external/internal labels — victoria-logs server migrates off the combined `gateways` label), (l) DNS-exfil detection alert; + 2 follow-ups (backrest 192.0.2.123 TEST-NET egress, prometheus scrape-target label-gap audit).


### Session 21 — 2026-07-11

- **V5(l) DNS-exfil detection DONE (starter)** (@d9005e048 + a cilium-agent reload). User scoped this as "B only" — the HubblePolicyDeny `for:`-tuning (option A) was explicitly **declined**, so rollout-transient POLICY_DENIED pages remain accepted for now (HubblePolicyDeny left as `> 0`, no `for:`).
- **Prerequisite — per-pod DNS attribution:** added `dns:labelsContext=source_namespace,source_pod,source_workload` to the Cilium `hubble.metrics` `dns` entry (it was bare → only node-level, no source). Verified: `hubble_dns_queries_total` now carries source_namespace/source_pod/source_workload. **Required a manual `kubectl rollout restart ds/cilium`** — the chart does not auto-roll the agent on a hubble-metrics configmap change (agent kept the old config after the helm upgrade). Post-restart health verified: node Ready, agent Ready, external + in-cluster DNS resolve OK, existing connectivity intact (eBPF datapath persists across agent restart).
- **Alert — `HubbleDNSExfilSuspected` (warning):** `sum by (source_namespace,source_workload,source_pod) (rate(hubble_dns_queries_total{source_workload!="coredns"}[5m])) > 30` for 10m. Design rationale: query-VOLUME per pod is the robust signal; NXDOMAIN is NOT usable as primary (baseline NXDOMAIN fraction ~35% = normal ndots search-domain misses); coredns excluded (it aggregates every upstream forward). Starter threshold 30 q/s ≈ 4x the whole cluster's current ~7/s and ~25x the current top talker (source-controller ~1.2 q/s) → effectively zero false positives while catching gross exfil. Rule loaded in Prometheus.
- **Tuning follow-up:** after a few days of per-pod baseline, tighten to a per-pod relative-spike + NXDOMAIN-per-pod corroboration; keep severity warning (heuristic).
- **Note:** the cilium-agent restart itself may have produced a transient HubblePolicyDeny burst (BPF reload window); since option A was declined, that class of transient still pages — offered as a future tuning if the noise becomes annoying.

Next: V5 remaining = (m) gateways-split (2-commit, ~24 HRs, rev4 gateways-external/internal labels — victoria-logs server migrates off the combined `gateways` label); + 2 follow-ups (backrest 192.0.2.123 TEST-NET egress, prometheus scrape-target label-gap audit). Optional deferred: HubblePolicyDeny `for:`-tuning (A), DNS-exfil threshold tightening.


### Session 22 — 2026-07-11

- **V5(m) gateways split IMPLEMENTED + verified.** Reworked per user decision to mirror the envoy gateway names PER-GATEWAY (singular `gateway`) instead of the rev3 `gateways-dual`/`gateways-internal` model: `ingress.home.arpa/allow-gateway-external` + `ingress.home.arpa/allow-gateway-internal`. Dual-routed apps carry BOTH labels — the "dual" concept dissolves into label composition (Cilium ingress allows union). Bundled the `ingress.home.arpa/prometheus` → `allow-prometheus` rename into the same rollout (user decision; grammar allow-* = grant). Decision recorded as AD-023 rev5.
- **Ground-truth assignment correction (did NOT trust the stale 2026-07-09 rev3 list).** Verified each carrier against live HTTPRoute parentRefs. rev3 placed grafana, backrest, paperless-gpt, kopia in the DUAL set, but all four are `envoy-internal` ONLY → assigned `allow-gateway-internal` only. Blindly following rev3 would have granted them an envoy-external path, defeating the split. Final: **11 dual** (calibre-web-automated, echo, pocket-id, tinyauth, actual, home-gallery, homepage, mealie, paperless, pingvin-share-x, wallos), **14 internal-only** (8 *arr, grafana, kube-prometheus-stack, victoria-logs, backrest, paperless-gpt, kopia).
- **Commit 1 additive (6980d2f3c, 37 files):** 2 new CCNPs `ingress-from-gateway-external` (envoy-external only) / `ingress-from-gateway-internal` (envoy-internal only) + `allow-prometheus` label; `ingress-from-prometheus` given a transitional dual `specs:` selector. New labels added alongside legacy → grant union unchanged, zero behavior change. Verified: 2 new CCNPs Valid, 11/25/15 pods labeled, show-cnp-matrix correct additive overlap, Hubble 0 policy-denied DROPPED.
- **Commit 2 retire (cc684029a, 45 files):** dropped legacy `gateways`/`prometheus` labels from all 33 carriers, deleted `ingress-from-gateways.yaml` + kustomization entry, collapsed `ingress-from-prometheus` to a single `allow-prometheus` selector, refreshed manifest comments (envoy-internal vs dual per app; cluster-noop). Behavior change: 14 internal-only apps no longer admit envoy-external.
- **Verified live after both pushes:** 8 CCNPs Valid, `ingress-from-gateways` gone; old labels drained to 0; matrix — bazarr/grafana `i:gateway-external ·`+`internal ✓`, echo `i:gateway-external ✓`+`internal ✓`; negative test — zero `envoy-external → internal-only-app` flows (only prometheus→envoy-external:19001 metrics scrape, envoy as dest); 11 dual apps retain `allow-gateway-external`. **HubblePolicyDeny fired 2× transient** during the retire rollout (prometheus scraping a terminating pod's stale IP @10.244.0.159; calibre startup) — both self-healed, 0 policy-denied in last 300 flows, alert resolved. Full pre-commit + yamllint/yamlfmt green on both commits.

Next: V5(m) complete — last major V5 label-vocabulary item. Remaining V5 follow-ups (non-blocking): backrest 192.0.2.123 TEST-NET egress, prometheus scrape-target label-gap audit, optional HubblePolicyDeny `for:`-tuning + DNS-exfil threshold. Consider a V5 → done review + roadmap status flip.


### Session 23 — 2026-07-11

- **Both acceptance-critical V5 follow-ups CLEARED (read-only cluster + 60s Hubble); no manifest change needed.**
- **(1) Prometheus scrape-target label-gap audit → CLEAN.** Ground truth: Prometheus `/api/v1/targets?state=active` = all targets UP, zero DOWN → no scrape is CNP-dropped. Exhaustive cross-check: enumerated 30 ServiceMonitors + 4 PodMonitors; every target pod that sits under ingress default-deny (carries an `ingress.home.arpa/*` label) also carries `ingress.home.arpa/allow-prometheus`. The default-deny pods WITHOUT the prometheus label (8× *arr/downloads gw-internal, calibre-web-automated, plex/plex-trakt-sync/resticprofile i:none, tinyauth, backrest, home-gallery, homepage, mealie, paperless, paperless-gpt, pingvin-share-x, wallos, kopia) have NO ServiceMonitor/PodMonitor → correctly unlabeled, no scrape to drop. The V5(m) `prometheus`→`allow-prometheus` rename left zero gaps.
- **(2) backrest → 192.0.2.123 (TEST-NET-1) egress → RESOLVED by absence.** Read the live `/data/config.json` (BACKREST_CONFIG): the only external reference is the allowed OVH S3 endpoint (`s3.de.io.cloud.ovh.net`) — NO `192.0.2.123`, no hc-ping/healthcheck hook. The Session 21 flow came from a since-removed placeholder hook. 60s live Hubble capture: ZERO backrest egress DROPPED, and ZERO flows to `192.0.2.0/24` cluster-wide. Follow-up closed.
- [observation] [optional] backrest CNP still allows `hc-ping.com` egress, now unused by config — left in place (harmless, forward-looking for a re-added Healthchecks.io hook; removing would be scope creep and could break a future ping). Not acted on.
- **V5 → done.** All lettered items (a)–(m) complete (Session 22) + both acceptance-critical follow-ups cleared (this session). Phase tracker V5 flipped to done; roadmap + this progress note status: in_progress → done (user decision, 2026-07-11).
- **Remaining (optional, non-blocking, NOT acceptance criteria):** DNS-exfil alert threshold tightening (starter `HubbleDNSExfilSuspected` @d9005e048 live at >30 q/s/pod; tighten to per-pod relative-spike + NXDOMAIN corroboration after a multi-day per-pod baseline) and the previously-declined HubblePolicyDeny `for:`-tuning (rollout-transient pages accepted). Tracked here as a standalone tuning follow-up; does not reopen the roadmap.

Next: Roadmap DONE. Only optional post-baseline tuning remains (DNS-exfil threshold; HubblePolicyDeny `for:` if transient pages become annoying). No further CNP rollout work pending.
## Runbook (merged from docs/roadmap/cnp-per-app-audit on 2026-07-11)

The authoritative execution runbook — label vocabulary, cluster-policy YAML, per-app assignment, and the V1–V5 phase edit/verify/accept steps. Merged in from the former roadmap note after the rollout completed (status: done).

## Metadata (observation-form, schema validation)

- [topic] Hybrid CNP rollout runbook — label vocabulary + world-deny flip; per-app CNPs only for app-unique content
- [status] in_progress
- [progress] Execution state lives in [[cnp-per-app-audit]] (docs/progress) — phase tracker, session summaries, Next pointer
- [priority] medium

## Definitions (use these exact strings everywhere)

- [observation] Labels (V1 frozen set, EVOLVED at V5(m) — see rev5): egress.home.arpa/custom-egress, egress.home.arpa/allow-world, egress.home.arpa/allow-gateways; ingress.home.arpa/allow-gateway-external, ingress.home.arpa/allow-gateway-internal (replaced ingress.home.arpa/gateways at V5(m)), ingress.home.arpa/allow-prometheus (renamed from ingress.home.arpa/prometheus at V5(m)), ingress.home.arpa/none — value is always "true". The V1 gateways/prometheus names were retired in the V5(m) split (AD-023 rev5), a documented label-freeze exception.
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
- [observation] [resolved 2026-07-11] ingress-none / pure empty-allow-set semantics — verified live since V1: plex, plex-trakt-sync, resticprofile carry ingress.home.arpa/none and are healthy under ingress default-deny (kubelet probes via fromEntities kube-apiserver/host); no consumer ingress needed
- [observation] [resolved 2026-07-11] IPv6: CIDR math is v4-only — confirmed v4-only cluster (cilium-config enable-ipv6=false; single v4 podCIDR 10.244.0.0/24), so the v4-only fromCIDR/toCIDR rules are correct
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

## OIDC endpoint convention (2026-07-10 — AD-023 rev4)

- [observation] [decision 2026-07-10] Uniform public-issuer convention: EVERY native OIDC client uses https://id.<PUBLIC_DOMAIN> for ALL endpoints (auth/token/userinfo/discovery). The backchannel is ordinary gateway traffic (client -> envoy VIP -> pocket-id), covered by baseline egress + pocket-id's gateways label. NO OIDC vocabulary label exists.
- [observation] [rationale] The token endpoint is world-exposed by design (envoy-external + tunnel) and any baseline-egress pod can hairpin through envoy — a pod->pocket-id:1411 grant is explicitness, not a security boundary. The split internal/public endpoint config (grafana/tinyauth pattern, pre-rev4) created a two-class rule that discovery-only clients (pingvin-share-x) cannot follow (single oidc-discoveryUri knob; discovery doc advertises public endpoints; issuer must stay public).
- [observation] [changes 2026-07-10, working tree] grafana + tinyauth token/userinfo URLs reverted to public; the oidc-backchannel CCNP + label drafted earlier the same day was DISCARDED before commit; pocket-id CNP ingress section removed entirely (tinyauth named-consumer rule obsolete — tinyauth arrives via envoy; gateways/prometheus CCNPs remain the ingress sources); grafana CNP gained an egress rule to the envoy pods :10443 (custom-egress apps must grant the hairpin explicitly); pingvin-share-x custom-egress label removed (baseline covers its hairpin).
- [observation] [coredns] Split horizon added to the coredns HR: a ${PUBLIC_DOMAIN} server zone forwards to ${K8S_GATEWAY_IP} (k8s-gateway) — pods resolve public hostnames to the envoy-internal VIP without the node-resolver -> router hop. CAVEAT: public-zone names that are NOT envoy-internal HTTPRoutes (external-only routes, Cloudflare-hosted records: Workers/Pages/mail hosts) now NXDOMAIN for pods; verify no pod depends on one before/at deploy (static grep + hubble DNS slice).
- [observation] [rule] New-app rule: native OIDC client -> public issuer URLs, nothing else needed. custom-egress OIDC client -> add the envoy :10443 egress rule to its per-app CNP. Split internal/public endpoint configs are RETIRED.
- [observation] [verify] Post-deploy acceptance: grafana login (exercises custom-egress + envoy egress rule), tinyauth forward-auth login, pingvin-share-x OIDC login (pre-change it was custom-egress with no CNP -> token exchange should have been DROPPED; login test confirms the fix), hubble DROPPED empty during the logins; from a pod: id.<PUBLIC_DOMAIN> resolves to the envoy-internal VIP (coredns split horizon active). Possible edge: if the VIP->envoy translation surfaces as a non-envoy identity in hubble (LB-VIP identity caveat, AD-023), grafana's CNP needs a toCIDR VIP grant instead — capture will show it.

## rev4 refinement (2026-07-10, same day): allow-gateways vocabulary label

- [observation] [decision] NEW vocabulary label egress.home.arpa/allow-gateways backed by NEW CCNP allow-gateways-egress (kubernetes/apps/kube-system/cilium/netpols/allow-gateways-egress.yaml): grants labeled pods egress to the envoy proxy pods :10443. Vocabulary is now 6 labels. Rationale: custom-egress OIDC clients (grafana + pingvin-share-x) all need the identical envoy-hairpin grant — generic CCNP beats per-app hand-written rules (same doctrine as allow-world).
- [observation] [rule UPDATED] Locked-down (custom-egress) OIDC client → carry BOTH egress.home.arpa/custom-egress AND egress.home.arpa/allow-gateways; no hand-written envoy rule in its CNP. Baseline OIDC clients still need nothing (allow-cluster-egress covers envoy).
- [observation] [changes] pingvin-share-x RE-TIGHTENED: custom-egress restored + allow-gateways added → effective egress is DNS + envoy hairpin ONLY (the brief baseline loosening from earlier today is reverted); grafana: allow-gateways label added, the hand-written envoy :10443 egress rule removed from its CNP (CNP keeps gravatar toFQDNs + Prometheus/Alertmanager datasources).
- [observation] [verify] show-cnp-matrix after deploy: pingvin row = e:dns ✓ + e:gateways ✓ (cluster ·), grafana row gains e:gateways ✓; pingvin OIDC login + grafana login clean under a Hubble capture.

## Naming grammar + V5(m) amendment (2026-07-10)

- [observation] [decision 2026-07-10] Vocabulary grammar: allow-* = grant, unprefixed = marker (custom-egress, none). Full ingress-label rename is DEFERRED to V5(m) — no standalone migration.
- [observation] [V5(m) AMENDED] The new labels in the gateways split are renamed: ingress.home.arpa/allow-gateways-dual and ingress.home.arpa/allow-gateways-internal (was: gateways-dual / gateways-internal in the rev3 plan). Additionally the SAME staged batch renames ingress.home.arpa/prometheus -> ingress.home.arpa/allow-prometheus (duplicate-selector spec in ingress-from-prometheus during the add-both stage, label swap in the HR set, trim old spec at retire). ingress.home.arpa/none stays (marker, not a grant).
- [observation] [tooling] just k8s show-cnp-matrix [app] — live per-app policy grant matrix (dynamic CCNP columns per direction, ✓/·, open = no policy selects that direction, APP-CNP column with e/i marks); app arg matches app name, namespace, or app/controller variants. Primary acceptance tool for label/CNP changes.


## rev4 verification result (2026-07-10 — deployed + live-verified)

- [observation] [verified 2026-07-10] AD-023 rev4 deployed (commit 409242998) and verified live. 7 CCNPs Valid incl. allow-gateways-egress. CoreDNS split-horizon live: id.${PUBLIC_DOMAIN} → 192.168.1.18 (envoy-internal VIP) from grafana + pingvin pods, no router hop. Pingvin OIDC login OK; Hubble confirms pingvin (custom-egress + allow-gateways) → envoy pod :10443 FORWARDED. **LB-VIP identity caveat RESOLVED**: socketLB translates the LB VIP to the envoy pod identity before egress policy, so the allow-gateways-egress toEndpoints (app=envoy) matches — the earlier "may need a toCIDR VIP grant" possibility is DISPROVEN, toEndpoints is correct. Label posture live-correct (grafana + pingvin custom-egress+allow-gateways; tinyauth baseline). pocket-id CNP ingress removed, MaxMind egress kept. Static NXDOMAIN risk assessed nil (no pod egress-depends on a non-envoy-internal public host). Full detail: [[cnp-per-app-audit]] (docs/progress) Session 13.
- [observation] [delegated 2026-07-10] grafana default-plugin preinstall (5 apps) → grafana.com DROPPED → HubblePolicyDeny; grafana pod healthy (installer failures non-fatal). Resolution owned by the grafana-operator-migration roadmap item (user decision), NOT this rollout.


## V5(m) IMPLEMENTED (2026-07-11 — supersedes the rev3 + rev4-naming plan above)

- [observation] [decision] Shipped with PER-GATEWAY labels mirroring the envoy gateway names (user decision), NOT the rev3 `gateways-dual`/`gateways-internal` nor the rev4-naming `allow-gateways-dual`/`allow-gateways-internal`. Final: `ingress.home.arpa/allow-gateway-external` (CCNP ingress-from-gateway-external, envoy-external only) + `ingress.home.arpa/allow-gateway-internal` (CCNP ingress-from-gateway-internal, envoy-internal only), singular `gateway`. Dual app = BOTH labels (union). `prometheus` -> `allow-prometheus` rode the same batch. Decision: AD-023 rev5.
- [observation] [assignment — LIVE HTTPRoute ground-truth, NOT the stale rev3 list] 11 dual (allow-gateway-external + -internal): calibre-web-automated, echo, pocket-id, tinyauth, actual, home-gallery, homepage, mealie, paperless, pingvin-share-x, wallos. 14 internal-only (allow-gateway-internal): bazarr, maintainerr, prowlarr, qbittorrent, radarr, seerr, sonarr, subsyncarr, grafana, kube-prometheus-stack, victoria-logs, backrest, paperless-gpt, kopia. CORRECTION vs rev3: grafana/backrest/paperless-gpt/kopia are envoy-internal ONLY (rev3 wrongly listed them dual).
- [observation] [execution] Commit 1 additive @6980d2f3c (2 new CCNPs + labels alongside legacy + ingress-from-prometheus transitional dual `specs:` selector; zero behavior change). Commit 2 retire @cc684029a (drop legacy gateways/prometheus labels, delete ingress-from-gateways.yaml, collapse ingress-from-prometheus to single allow-prometheus selector, comment refresh). Verified live: 8 CCNPs Valid, matrix internal apps i:gateway-external ·, negative test zero envoy-external->internal-only flows, Hubble 0 policy-denied DROPPED (2 transient rollout drops self-healed). Detail: [[cnp-per-app-audit]] (docs/progress) Session 22.
