---
title: AD-021-preserved-components-inventory
type: decision
permalink: home-ops/docs/decisions/ad-021-preserved-components-inventory
decision_id: AD-021
topic: Inventory of components preserved unchanged across the migration
status: active
decided_at: '2025-10-01'
decision: 'The following components carry over to the new cluster unchanged: Envoy
  Gateway (envoy-external + envoy-internal), k8s-gateway, cert-manager + OVH DNS-01
  webhook, external-secrets + 1Password Connect (`onepassword-connect` ClusterSecretStore),
  VolSync + Kopia + OVH S3 backup pipeline, resticprofile / Backrest file-level backup
  plane, kube-prometheus-stack + Grafana + Speedtest exporter observability, Cloudflare
  Tunnel + ExternalDNS for external ingress, and the Cloudflare Terraform + OVH Terraform
  provisioning (Terraform Cloud workspaces).'
rationale: These are all working, mature components with no reason to replace them
  Capturing the preservation as an explicit decision documents intent and provides
  a single anchor for "what was deliberately kept"
tradeoffs: None — the value is in the explicit inventory itself
related_areas:
- networking
- external-secrets
- volsync-backup
- resticprofile-backup
- cloudflare
- ovh-storage
- observability
---

# AD-021 — Inventory of components preserved unchanged across the migration

## Metadata (observation-form, schema validation)
- [decision_id] AD-021
- [status] active
- [decided_at] 2025-10-01
- [topic] Inventory of components preserved unchanged across the migration

## Decision
The following components carry over to the new cluster unchanged: Envoy Gateway (envoy-external + envoy-internal), k8s-gateway, cert-manager + OVH DNS-01 webhook, external-secrets + 1Password Connect (`onepassword-connect` ClusterSecretStore), VolSync + Kopia + OVH S3 backup pipeline, resticprofile / Backrest file-level backup plane, kube-prometheus-stack + Grafana + Speedtest exporter observability, Cloudflare Tunnel + ExternalDNS for external ingress, and the Cloudflare Terraform + OVH Terraform provisioning (Terraform Cloud workspaces).

## Rationale
- These are all working, mature components with no reason to replace them
- Capturing the preservation as an explicit decision documents intent and provides a single anchor for "what was deliberately kept"

## Tradeoffs
- None — the value is in the explicit inventory itself

## Related
- relates_to [[networking]]
- relates_to [[external-secrets]]
- relates_to [[volsync-backup]]
- relates_to [[resticprofile-backup]]
- relates_to [[cloudflare]]
- relates_to [[ovh-storage]]
- relates_to [[observability]]
