---
title: kopia-ui-forward-auth
type: roadmap
permalink: home-ops/docs/roadmap/kopia-ui-forward-auth
topic: Authenticated Kopia browse UI
status: proposed
priority: low
scope: Put the Kopia web UI behind the cluster forward-auth pattern (as already done
  for hubble-ui) so backup browsing/restore requires identity even on the LAN.
rationale: Gating the Kopia UI ensures backup contents can only be browsed or restored
  by authenticated users, matching the sensitivity of the data it exposes.
related_areas:
- volsync-backup
- iam
---

# Authenticated Kopia browse UI

## Metadata (observation-form, schema validation)

- [topic] Authenticated Kopia browse UI
- [status] proposed
- [priority] low

## What we gain

- Backup browse/restore requires login — LAN presence alone is no longer enough.
- Consistent authentication across all internal admin UIs.
- Reuses an existing, proven pattern (hubble-ui).

## What to do

1. Add the forward-auth component/SecurityPolicy to the pvbackup route.
2. Keep the Kopia repo-password model unchanged (client-side encryption is unaffected).
3. Verify: pvbackup prompts for auth and restore still works after login.

## Related

- relates_to [[volsync-backup]]
- relates_to [[iam]]
