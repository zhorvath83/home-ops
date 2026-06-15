---
title: envoy-crowdsec-bouncer
type: note
permalink: envoy-crowdsec-bouncer
status: pending
priority: medium
tags:
- networking
- security
- crowdsec
---

# Envoy CrowdSec Bouncer Integration

Integrate the `envoy-proxy-crowdsec-bouncer` into the Envoy Gateway pipeline to enable automated IP banning and request inspection based on CrowdSec decisions.

## Goal
Automate the blocking of malicious actors at the Envoy Gateway edge, reducing the attack surface for all backend applications.

## Technical Approach

### Architecture
- **CrowdSec Engine**: Deployed via Helm chart. Uses **SQLite** for state storage (optimized for single-node).
- **Log Analysis**: CrowdSec deployed as a **DaemonSet** to read Envoy JSON access logs directly from the host (`/var/log/pods/`).
- **Bouncer**: `envoy-proxy-crowdsec-bouncer` as a standalone service in the `networking` namespace.
- **Envoy Integration**: Use `ext_authz` filter via `EnvoyPatchPolicy` to intercept requests.

### Configuration Plan
1. **CrowdSec Setup**:
   - Helm install `crowdsec/crowdsec` with `sqlite` backend.
   - Configure community blocklists and `envoy` parser for JSON logs.
   - Generate LAPI key for the bouncer via `ExternalSecret`.
2. **Bouncer Deployment**:
   - Deploy `envoy-proxy-crowdsec-bouncer`.
   - Inject LAPI URL and Key via `ExternalSecret`.
   - Expose via ClusterIP service.
3. **Envoy Gateway Wiring**:
   - Add `envoy.filters.http.ext_authz` to the listener filter chain.
   - Configure `fail_closed: false` (Availability > Security tradeoff).
   - Verify `CF-Connecting-IP` detection in `ClientTrafficPolicy`.

### Observability & Alerting
- **Metrics**: Deploy `ServiceMonitor` for both CrowdSec LAPI and the Bouncer.
- **Tracking**: Monitor `crowdsec_decisions_total` and `bouncer_requests_total`.
- **Alerting**: Integrate with Pushover for high-frequency ban events.

### Phase 2: CAPTCHA Workflow
- **Mechanism**: Use Cloudflare Turnstile for "suspicious" IPs.
- **Flow**: Redirect to CAPTCHA page $  o$ Token verification $ o$ Temporary "allow" in LAPI.
- **Scope**: Implement only after Phase 1 (403 blocking) is stable.

## Security Review
- **Availability**: `fail_closed: false`. Traffic persists if bouncer is down.
- **Isolation**: `CiliumNetworkPolicy` restricting LAPI (port 8080) access to only Bouncer and Analyzer pods.
- **Secret Management**: LAPI keys managed via 1Password $  o$ External Secrets.
- **Trust Boundary**: Relies on Envoy's client IP detection; trusted via Cloudflare Tunnel.

## Resource Profile
| Component | CPU Req/Lim | RAM Req/Lim | Note |
| :--- | :--- | :--- | :--- |
| LAPI | 50m / 200m | 128Mi / 256Mi | Core API |
| Analyzer | 100m / 500m | 256Mi / 512Mi | Log processing burst |
| Bouncer | 20m / 100m | 64Mi / 128Mi | Lightweight proxy |

## Verification Steps
- [ ] Verify bouncer is healthy and connected to LAPI.
- [ ] Manually ban a test IP in CrowdSec.
- [ ] Confirm the test IP receives a 403 Forbidden response from Envoy.
- [ ] Verify Prometheus metrics for bans are flowing.
- [ ] Verify `CiliumNetworkPolicy` blocks unauthorized LAPI access.

## Relations
- relates_to [[docs/areas/networking]]
- relates_to [[docs/areas/k8s-workloads]]
- relates_to [[docs/areas/observability]]
