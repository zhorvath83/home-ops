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

## Execution plan (research-backed)

### Current state
- No disk encryption: `kubernetes/talos/machineconfig.yaml.j2` has no `machine.systemDiskEncryption`. `install.wipe: false` (line 69), install disk set per-node in `kubernetes/talos/nodes/<node>.yaml.j2`. SecureBoot false (audit).
- The secretbox key for etcd secret-encryption is stored in the machine config itself (`cluster.secretboxEncryptionSecret: op://HomeOps/talos/...`, line 155) which lands on the unencrypted STATE partition — so etcd's at-rest encryption is undercut against physical disk theft.

### Target state
- STATE and EPHEMERAL partitions encrypted with a TPM-sealed key, so a removed/discarded disk reveals nothing.

### Implementation steps
1. **Verify TPM 2.0 availability** on this HP ProDesk 600 G6: `talosctl -n k8s-cp0 get securitystate` and `talosctl -n k8s-cp0 read /sys/class/tpm/tpm0/tpm_version_major` (or check dmesg). If no usable TPM, this item is blocked (fall back to a static-key provider = weaker, needs a boot secret).
2. **Add the encryption config** to `machineconfig.yaml.j2` (control-plane block):
   ```yaml
   machine:
     systemDiskEncryption:
       state:
         provider: luks2
         keys:
           - slot: 0
             tpm: {}
       ephemeral:
         provider: luks2
         keys:
           - slot: 0
             tpm: {}
   ```
   Optionally enable SecureBoot (separate schematic + installer image) for measured boot.
3. **THIS IS DESTRUCTIVE.** Encryption is applied on partition (re)creation — enabling it on an existing node requires a **wipe + reinstall of STATE and EPHEMERAL**, i.e. effectively rebuilding the node. On a single-node cluster this is a full rebuild, not an in-place change.
   Pre-req before touching anything:
   - Take an etcd snapshot: `just talos` (find the etcd-backup recipe) / `talosctl -n k8s-cp0 etcd snapshot db.snapshot`.
   - Confirm every VolSync `ReplicationSource` has a recent successful Kopia backup and the resticprofile/OVH copies are current.
   - Have the full `just cluster-bootstrap` path ready (this restores from the op-inject flow).
4. Apply via a planned rebuild window: `just talos apply-node k8s-cp0` with wipe, re-bootstrap etcd (`just talos` bootstrap recipe), restore.

### Verification
- `talosctl -n k8s-cp0 get volumestatus` → STATE + EPHEMERAL show encryption provider luks2.
- Node boots unattended (TPM auto-unseal); cluster comes back healthy.

### Rollback & safety
- Rollback = another wipe/reinstall without the encryption stanza — equally destructive. There is no cheap undo.
- **Highest-risk item in the set on a single node.** Only in a scheduled maintenance/rebuild window with verified, tested backups (etcd snapshot + VolSync + resticprofile). TPM-sealed keys are tied to this hardware/firmware state — a firmware reset or board swap can make the disk unrecoverable, so keep an off-box etcd snapshot.

### Gotchas & dependencies
- Requires a working TPM (verify in step 1) or it degrades to a static-key provider needing a boot-time secret.
- Coordinate with the Talos schematic/version flow (docs/areas/talos-cluster) if enabling SecureBoot.

### Effort
L (rebuild window; ~half a day incl. backup verification + re-bootstrap + validation).
