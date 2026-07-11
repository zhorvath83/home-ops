---
title: default-deny-ingress-baseline
type: roadmap
permalink: home-ops/docs/roadmap/default-deny-ingress-baseline
topic: Default-deny ingress baseline — make ingress opt-in like egress already is
status: proposed
priority: high
scope: Add a clusterwide default-deny ingress posture mirroring the existing allow-cluster-egress
  model, then grant explicit ingress per observed need, starting with the control-plane
  and infra pods.
rationale: Egress is already enforced on 100% of pods; extending the same opt-in model
  to ingress gives symmetric containment, so a compromised app can only reach the
  workloads it is explicitly allowed to.
related_areas:
- networking
options:
- Clusterwide default-deny CCNP + per-app allows — consistent with the current CCNP
  model
- Per-namespace default-deny where a big-bang clusterwide flip feels risky
---

# Default-deny ingress baseline — make ingress opt-in like egress already is

## Metadata (observation-form, schema validation)

- [topic] Default-deny ingress baseline — make ingress opt-in like egress already is
- [status] proposed
- [priority] high

## What we gain

- Symmetric, complete containment — lateral reach is allow-listed in both directions.
- The most sensitive infra (Flux controllers, cert-manager, metrics-server) stops being reachable from arbitrary app pods.
- A predictable, auditable ingress map — Hubble already provides the observability to build it safely.

## What to do

1. Use Hubble to enumerate the real ingress each infra/control-plane pod needs (ports + source identities).
2. Introduce a default-deny-ingress CCNP, then explicit allow policies per observed need.
3. Roll out staged, starting with the crown-jewel namespaces (flux-system, cert-manager, kube-system).
4. Verify with a Hubble capture: legitimate flows still forward, cross-namespace app→infra attempts drop.

## Options

1. Clusterwide default-deny CCNP + per-app allows — consistent with the current CCNP model
2. Per-namespace default-deny where a big-bang clusterwide flip feels risky

## Related

- relates_to [[networking]]
- relates_to [[AD-023-cnp-threat-model-audit]]
- relates_to [[iam]]

## Execution plan (research-backed)

### Current state
- Egress is opt-in-enforced on every pod: `kubernetes/apps/kube-system/cilium/netpols/allow-cluster-egress.yaml:26-36` selects `egress.home.arpa/custom-egress DoesNotExist` and grants cluster + kube-apiserver egress.
- There is **no ingress default-deny**. The netpols kustomization (`kubernetes/apps/kube-system/cilium/netpols/kustomization.yaml:5-13`) has `ingress-from-gateway-external`, `-internal`, `-prometheus`, and `ingress-none` — but `ingress-none` (`ingress-none.yaml:9-15`) only selects pods **labeled** `ingress.home.arpa/none="true"`. Pods with no selecting ingress policy are allow-all ingress.
- Audit: 22/65 endpoints are ingress-unenforced, including `flux-system/{source,kustomize,helm}-controller`, `cert-manager/*`, `kube-system/metrics-server`, `coredns`, `observability/prometheus`.
- **Cilium semantic that makes this safe:** a pod becomes default-deny-ingress the moment *any* ingress rule selects it. So we can protect the crown jewels selectively without a risky cluster-wide flip.

### Target state
- The sensitive control-plane/infra pods enforce ingress and admit only their real clients. Eventually, ingress is opt-in like egress (a clusterwide default-deny with a per-pod opt-out label).

### Implementation steps (staged, lowest-risk first)
1. **Baseline the real ingress each target needs** using Hubble (dangerouslyDisableSandbox):
   ```bash
   just k8s hubble-status
   just k8s hubble-live-capture 120
   just k8s hubble-analyze k8s:io.kubernetes.pod.namespace=flux-system FORWARDED ingress
   just k8s hubble-analyze k8s:io.kubernetes.pod.namespace=cert-manager FORWARDED ingress
   just k8s hubble-analyze k8s:app.kubernetes.io/name=metrics-server FORWARDED ingress
   ```
   Record the (source-identity, port) pairs actually used (expect: source-controller:9090 from kustomize/helm-controller; webhooks from kube-apiserver; metrics-server:10250 from kube-apiserver; :8080/:9440 healthz from kubelet/prometheus).
2. **Author per-target ingress CNPs.** For each crown-jewel namespace add a `CiliumNetworkPolicy` alongside the app (pattern mirrors `kubernetes/apps/external-secrets/onepassword-connect/app/ciliumnetworkpolicy.yaml`). Example `kubernetes/apps/flux-system/flux-instance/app/ciliumnetworkpolicy-ingress.yaml` (adjust to Hubble findings):
   ```yaml
   ---
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   metadata:
     name: flux-controllers-ingress
   spec:
     endpointSelector:
       matchLabels: { app.kubernetes.io/part-of: flux }
     ingress:
       - fromEntities: [kube-apiserver]          # webhooks/health
       - fromEndpoints:
           - matchLabels: { app.kubernetes.io/part-of: flux }   # inter-controller (source-controller:9090)
       - fromEndpoints:
           - matchLabels: { app.kubernetes.io/name: kube-prometheus-stack-prometheus, io.kubernetes.pod.namespace: observability }
         toPorts: [{ ports: [{ port: "8080", protocol: TCP }, { port: "9440", protocol: TCP }] }]
   ```
   Add the file to the owning `app/kustomization.yaml`. Selecting the pod flips it to default-deny-ingress automatically. Repeat for cert-manager and metrics-server.
3. **Verify each target in isolation** before moving on (see Verification), then proceed to the next namespace.
4. **(End-state, optional) Clusterwide opt-in ingress.** Once the crown jewels are covered and stable, add a `CiliumClusterwideNetworkPolicy` `default-deny-ingress` selecting `ingress.home.arpa/custom-ingress DoesNotExist` with an empty/near-empty ingress, mirroring `allow-cluster-egress`, and grant explicit allows per app. This is a big behavioral change — do it last, in a maintenance window, with a Hubble capture running.

### Verification
- `kubectl get cnp -A | grep -E 'flux|cert-manager|metrics'` → policies present.
- `cilium endpoint list` (via `kubectl -n kube-system exec ds/cilium -- cilium-dbg endpoint list`) → target endpoints show ingress-enforced=Enabled.
- Post-apply Hubble capture: legitimate flows still FORWARDED; a test from a media/downloads pod to source-controller:9090 shows DROPPED.
- Flux still reconciles (`flux get kustomizations -A`), cert-manager still issues, Prometheus still scrapes (targets Up).

### Rollback & safety
- Remove the CNP file + kustomization entry and reconcile → pod reverts to allow-all ingress.
- **Primary risk:** an incomplete allow-list drops legitimate traffic (e.g. Flux controllers can't reach source-controller → reconciliation stalls; Prometheus targets go Down). Mitigation: derive rules from Hubble FIRST, apply one namespace at a time, keep a capture running, and know the rollback is a single file removal.
- socketLB startup transient (~25s "no route to host to ClusterIP") on strict-egress pod restart is benign/self-healing (documented in cnp-per-app-audit) — don't mistake it for a policy error.

### Gotchas & dependencies
- Do NOT start with the clusterwide flip. Cilium's "selected ⇒ default-deny" semantic is the safe lever.
- Coordinates with `egress-fqdn-allowlisting` (same Hubble workflow) and AD-023 model.

### Effort
M–L (~1 day for the crown-jewel namespaces; the clusterwide end-state is a separate maintenance-window task).
