---
title: cnp-per-app-audit
type: progress
permalink: home-ops/docs/progress/cnp-per-app-audit
topic: CNP per-app audit rollout — execution progress for the V1-V5 hybrid CNP rollout
  runbook
status: in_progress
priority: medium
related_areas:
- networking
- k8s-workloads
decision_link: AD-023-cnp-threat-model-audit
roadmap_link: docs/roadmap/cnp-per-app-audit
tags:
- progress
- cnp
- cilium
- networking
- security
---

# CNP per-app audit — rollout progress

Execution log for the V1–V5 hybrid CNP rollout. The full runbook (YAML, per-app assignment, edit/verify/accept steps per phase) lives in [[cnp-per-app-audit]] (docs/roadmap). This note tracks only execution state — phase status, session summaries, and the Next pointer. Decision basis: [[AD-023-cnp-threat-model-audit]].

## Phase tracker

| Phase | State | Notes |
|---|---|---|
| V1 commit 1 — 4 vocabulary CCNPs + kustomization entries (enableDefaultDeny: false staging) | done — reconciled + verified | kubectl get ccnp: 6/6 Valid (4 new); cilium-netpols KS Ready=True @297a0ec27 |
| V1 commit 2 — V1 labels on pods (incl. kopia/mover labels — see pre-rollout resolution) | done — reconciled + verified | labels on 18 HRs + kopia/volsync movers; Hubble FORWARDED on gateways+prometheus grants; zero DROPPED @f35a3015c |
| V1 commit 3 — activation: remove enableDefaultDeny + trim/delete per-app CNPs | done — reconciled + verified | 3050131ac on main; 3 ingress CCNPs activated; 5 CNPs deleted + 5 trimmed (3 runbook corrections: actual+paperless DELETE to TRIM, paperless-gpt TRIM to DELETE); Hubble FORWARDED, zero DROPPED ingress; all touched apps Available, op-connect Valid, ESO Synced |
| V2 — survey (results recorded into the roadmap note) | pending | residual: ovh_s3_endpoint public-IP confirmation |
| V3 — flip (ONE commit: drop world from baseline + every V3 grant + coredns CNP + isponsorblocktv LAN CNP) | pending | single revert = rollback |
| V4 — permanent Hubble policy-verdict DROPPED alert + 7-day soak | pending | |
| V5 — remainder (downloads east-west, narrow-world tightening, LB fromCIDR) | pending | |

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
