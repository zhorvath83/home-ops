---
title: cnp-per-app-audit
type: roadmap
permalink: home-ops/docs/roadmap/cnp-per-app-audit
topic: Per-app CiliumNetworkPolicy rollout — blanket Szint I for user-facing apps
status: proposed
priority: medium
scope: Revised 2026-06-12. Blanket Szint I (ingress-allowlist) CNP for every user-facing
  app — any app with an HTTPRoute on envoy-external/envoy-internal, a LoadBalancer
  Service, or a ClusterIP Service consumed by other pods. Szint II stays threat-model-driven per AD-023.
rationale: The original AD-023 follow-up left coverage audit-driven and accidental.
  Revised to deterministic blanket coverage of the user-facing surface so every routed/consumed
  workload has an explicit ingress contract; supersedes the "5-8 high-value apps"
  estimate in AD-023 (the two-tier model itself stands).
options:
- 'Phase 1: externally exposed apps (envoy-external routes) — highest exposure first'
- 'Phase 2: internal-only routed apps + LoadBalancer services (k8s-gateway)'
- 'Phase 3: consumed-Service-only apps (onepassword-connect)'
- 'Deferred: media cluster + hubble-ui in a later pass'
related_areas:
- networking
- k8s-workloads
decision_link: AD-023-cnp-threat-model-audit
---

# Per-app CiliumNetworkPolicy rollout — blanket Szint I for user-facing apps

## Metadata (observation-form, schema validation)

- [topic] Per-app CiliumNetworkPolicy rollout — blanket Szint I for user-facing apps
- [status] proposed
- [priority] medium

## Scope (revised 2026-06-12)

Previous scope ("run the AD-023 audit, target count driven by findings") is **superseded**. New policy: **every user-facing app gets a dedicated CNP** with an explicit ingress allowlist (Szint I). "User-facing" means any of:

1. has an HTTPRoute attached to `envoy-external` and/or `envoy-internal`
2. has a LoadBalancer Service (Cilium L2 / lbipam)
3. has a ClusterIP Service consumed by other pods

Szint II (ingress + strict egress + `egress.home.arpa/custom-egress: ""` opt-out label) remains threat-model-driven, exactly as AD-023 defines it. AD-023's two-tier model, the cluster-wide baseline CCNPs and the B-csapda warning stay authoritative — only the "5-8 high-value apps" coverage estimate is superseded by this roadmap.

- [decision] Blanket Szint I for user-facing apps; Szint II stays opt-in per threat model
- [decision] homepage communicates with NO app — dashboard entries are plain URLs/links opened by the browser; no widget/siteMonitor probes. No "homepage → app" ingress rule is needed anywhere. The only repo-visible probe (actual siteMonitor annotation) was removed on 2026-06-12.
- [supersedes] AD-023 "5-8 high-value apps" coverage estimate (model itself unchanged)

## CNP pattern (existing precedent)

Per-app file `kubernetes/apps/<ns>/<app>/app/ciliumnetworkpolicy.yaml` (see `selfhosted/paperless`):

- `endpointSelector`: `app.kubernetes.io/name|instance|controller: <app>`
- Gateway ingress: `fromEndpoints` with `k8s:io.kubernetes.pod.namespace: networking` + matchExpressions `gateway.networking.k8s.io/gateway-name In [envoy-external, envoy-internal]`, `toPorts` to the service port
- Consumer ingress: `fromEndpoints` with namespace + `app.kubernetes.io/name` labels (see paperless ← paperless-gpt)
- Egress: none at Szint I — cluster-wide baseline (`allow-cluster-egress` + `allow-dns-egress`) applies because the opt-out label is absent
- Kubelet probes need no explicit rule at Szint I (paperless precedent: works without host allow); the envoy CNPs allow the probe port explicitly only because they are stricter

## Survey — affected apps and required ingress directions (2026-06-12)

### Cross-cutting ingress sources

- envoy-external / envoy-internal → app service port: every routed app
- prometheus → app metrics port: only for apps with ServiceMonitor (grafana, victoria-logs, speedtest-exporter, onepassword-connect); cloudflare-tunnel CNP already models this pattern
- homepage: NOT an ingress source — link-only dashboard, no probes (see decision above); its Kubernetes cluster-mode discovery talks to the kube-apiserver, not to pods

### Repo-verified app-to-app directions (file evidence)

- paperless-gpt → paperless:8000 (paperless-gpt/app/helmrelease.yaml:35; already in paperless CNP)
- open-webui → searxng:8080 (open-webui/app/helmrelease.yaml:47)
- grafana → kube-prometheus-stack-prometheus:9090 and victoria-logs-server:9428 (grafana/app/helmrelease.yaml:109,116)
- victoria-logs-collector → victoria-logs-server:9428 (victoria-logs/collector/helmrelease.yaml:20)
- external-secrets controller → onepassword-connect:8080 (onepassword-connect/app/clustersecretstore.yaml:10)
- cloudflared → envoy-external:443 (cloudflare-tunnel/app/helmrelease.yaml:22; already in envoy-external CNP)

### LAN ingress (LoadBalancer services in scope)

- k8s-gateway ← LAN on 53 TCP+UDP (LB `\${K8S_GATEWAY_IP}`, split-DNS for the public domain; externalTrafficPolicy Local → fromCIDR LAN / fromEntities world)

### Inventory — new CNPs required (17)

| Namespace | App | Port(s) | Exposure | Ingress to allow |
|---|---|---|---|---|
| selfhosted | actual | 5006 | route ext+int | gateways |
| selfhosted | backrest | 9898 | route ext+int | gateways |
| selfhosted | calibre-web-automated | 80 | route ext+int | gateways |
| selfhosted | home-gallery | 3000 | route ext+int | gateways |
| selfhosted | homepage | 3000 | route ext+int | gateways |
| selfhosted | mealie | 9000 | route ext+int | gateways |
| selfhosted | wallos | 80 | route ext+int | gateways |
| selfhosted | open-webui | 8080 | route ext+int | gateways |
| selfhosted | searxng | 8080 | route ext+int | gateways, open-webui |
| observability | grafana | 3000 | route ext+int | gateways, prometheus (ServiceMonitor) |
| observability | victoria-logs | 9428 | route int + consumers | gateway int, grafana, victoria-logs-collector, prometheus |
| observability | speedtest-exporter | 9798 | route ext+int | gateways, prometheus |
| networking | echo | 80 | route ext+int | gateways |
| networking | k8s-gateway | 53 TCP+UDP | LB | LAN clients |
| flux-system | flux-instance webhook-receiver | 80 | route ext only (/hook/) | envoy-external only |
| volsync-system | kopia | 8080 | route ext+int | gateways |
| external-secrets | onepassword-connect | 8080 | consumed Service | external-secrets controller, prometheus |

### Existing per-app CNPs (keep as-is)

- selfhosted/paperless (Szint I; gateways + paperless-gpt on 8000)
- selfhosted/paperless-gpt (Szint I; gateways on 8080)
- selfhosted/pingvin-share-x (Szint II; gateways on 3333+8080, strict egress + opt-out label)
- networking/cloudflare-tunnel (prometheus ingress + egress rules)
- networking/envoy-gateway external + internal (ingress allowlists, baseline egress)

### Deferred — media cluster + hubble-ui (later pass)

Deferred apps: **hubble-ui** (kube-system).

- hubble-ui: helm-managed pod labels (not app-template trio) — endpointSelector must match the actual deployment labels

### Not affected (no route, no consumed Service)

volsync controller; reloader, snapshot-controller, democratic-csi, intel-gpu-resource-driver (kube-system); flux-provider-pushover; victoria-logs-collector (egress-only)

### Platform components intentionally out of this pass (optional follow-up)

coredns, metrics-server, cert-manager, kube-prometheus-stack internals, external-dns, flux-operator, external-secrets controller, tuppr, cilium agent/operator — infrastructure plane, not user-facing; a separate platform-CNP pass may cover them later.

## Rollout plan

1. **Phase 1 — externally exposed**: all envoy-external routed apps from the inventory (highest exposure)
2. **Phase 2 — internal + LB**: victoria-logs (envoy-internal-only) + k8s-gateway (LB)
3. **Phase 3 — consumed-only Services**: onepassword-connect
5. Each phase: write CNPs → commit+push → flux reconcile → verify with hubble observe (drops) → fix → next phase

## Related

- relates_to [[networking]]
- relates_to [[k8s-workloads]]
- decided_in [[AD-023-cnp-threat-model-audit]]
