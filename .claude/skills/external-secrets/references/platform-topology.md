# Platform Topology

Use this reference when the external-secrets platform itself is changing.

## Current Layers

1. the External Secrets operator
2. the onepassword-backed `ClusterSecretStore`
3. application `ExternalSecret` resources elsewhere in the repo

The store is intentionally separate from random app trees. Preserve that separation unless the repo is explicitly being redesigned.

## OnePassword Connect

Observed live assumptions:

- runs in namespace `external-secrets`
- uses upstream-specific UID and GID `999`
- stores working data in an `emptyDir`
- reads credentials from `onepassword-secret`

If editing OnePassword Connect, verify both `api` and `sync` containers before changing ports, probes, or env vars.
