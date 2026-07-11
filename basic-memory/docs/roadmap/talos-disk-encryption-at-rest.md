---
title: talos-disk-encryption-at-rest
type: roadmap
permalink: home-ops/docs/roadmap/talos-disk-encryption-at-rest
topic: Encryption at rest for the node disks — TPM-backed STATE/EPHEMERAL
status: proposed
priority: medium
scope: Enable Talos machine.systemDiskEncryption (TPM-backed) for the STATE and EPHEMERAL
  partitions.
rationale: 'Disk encryption closes the physical-possession threat and completes the
  at-rest story: the secretbox key and etcd data become unreadable from a removed
  or discarded disk, making the already-enabled etcd secret encryption fully effective
  end to end.'
related_areas:
- talos-cluster
- volsync-backup
options:
- TPM-only unseal — unattended boot
- TPM + additional key — stronger, needs a secret at boot
---

# Encryption at rest for the node disks — TPM-backed STATE/EPHEMERAL

## Metadata (observation-form, schema validation)

- [topic] Encryption at rest for the node disks — TPM-backed STATE/EPHEMERAL
- [status] proposed
- [priority] medium

## What we gain

- A stolen, RMA-returned, or discarded disk yields nothing — machine config, secretbox key, and etcd data are all sealed.
- The existing etcd secret-encryption becomes end-to-end meaningful (the key no longer sits in cleartext beside the data).
- Minimal ongoing cost with TPM auto-unseal — no manual passphrase at boot.

## What to do

1. Add machine.systemDiskEncryption for STATE and EPHEMERAL with the TPM provider.
2. Confirm the board TPM 2.0 is usable by Talos; consider enabling SecureBoot for measured boot.
3. Plan a maintenance reboot/reinstall window (encryption applies on wipe/upgrade); ensure etcd + VolSync backups are current first.
4. Verify: talosctl shows encrypted volumes and the node boots unattended via TPM.

## Options

1. TPM-only unseal — unattended boot
2. TPM + additional key — stronger, needs a secret at boot

## Related

- relates_to [[talos-cluster]]
- relates_to [[volsync-backup]]
