---
title: openwrt-ansible-provisioning
type: note
permalink: home-ops/docs/roadmap/openwrt-ansible-provisioning
---

# Declarative OpenWRT provisioning via Ansible community.openwrt

## Metadata (observation-form, schema validation)

- [topic] Declarative OpenWRT provisioning via Ansible community.openwrt
- [status] in_progress
- [priority] medium

## Scope

Replace imperative, unversioned SSH-driven OpenWRT router configuration with declarative Ansible playbooks using the `community.openwrt` collection (v1.5.0+). Move router config into `provision/openwrt/` as version-controlled YAML inventory and playbooks, managed alongside the rest of the repo's GitOps workflow. The existing `just openwrt maintain` and `just openwrt upgrade` recipes remain as operational entry points for backup and sysupgrade — the Ansible playbooks handle steady-state configuration only.

## Rationale

- Current state: all router config is imperatively applied via SSH/UCI or survives in `/etc/luci-uploads/` scripts on the router itself — not in the repo. Firmware upgrades risk losing FRR, DNS forwarding, firewall rules, and DHCP reservations unless the reinstall script is manually maintained.
- AD-004 (active) chose L2 announcement over BGP, but the decision's tradeoff noted that OpenWRT "could speak BGP but would need config on both sides." That config has no version-controlled home today.
- `community.openwrt` v1.5.0 provides shell-based modules (no Python on router required) including `community.openwrt.uci` (full UCI CRUD: get/set/add/del/section/find/batch/commit/revert), `community.openwrt.apk` (OpenWRT 25+ package management), `community.openwrt.service`, `community.openwrt.sysctl`, and file/copy/template modules. This covers network interfaces, firewall zones, DHCP, DNS forwarding, wireless, and — if BGP ever becomes relevant — FRR/BIRD routing config.
- Declarative playbooks give diff mode and check mode for free (`--check --diff`), matching the repo's GitOps model for steady-state validation.
- The `community.openwrt.uci` module's `section` command is particularly powerful: find-or-create with replace mode provides idempotent UCI configuration — exactly what's needed for firewall zones, DHCP reservations, and DNS forwarding rules that must survive firmware upgrades.

## Current state (evidence)

- `provision/openwrt/mod.just` (437 lines): imperative SSH recipes for backup (`maintain`), attended sysupgrade (`upgrade`), and package reinstall (`reinstall-packages`). No declarative config in the repo.
- Router-side scripts (`/etc/luci-uploads/openwrt-backup-local.sh`, `list-installed-user-packages-apk.sh`, `reinstall-user-packages-apk.sh`) live on the router, not in the repo.
- Source-of-truth copies of the router-side scripts live in `my-scripts-and-configs/OpenWRT/` (separate repo):
  - `packages/list-installed-user-packages-apk.sh` — runs `owut list -f config` to derive top-level package list, writes to `user-installed-apk-packages.txt`, Healthchecks.io ping on success/failure.
  - `packages/reinstall-user-packages-apk.sh` — reinstalls packages from the txt list via `apk add`, then executes custom install commands from `custom-install-commands.txt` (e.g. ControlD resolver installer).
  - `packages/custom-install-commands.txt` — one command per line, currently only the ControlD DNS resolver install command (`sh -c 'sh -c "$(curl -sSL https://api.controld.com/dl)" -s RESOLVER_ID forced'`).
  - `packages/user-installed-apk-packages.txt` — placeholder in git; real content generated on-router by `list-installed-user-packages-apk.sh`.
  - `backup/openwrt-backup-local.sh` — runs on the router, backs up to USB pendrive (`/mnt/sda1/backups`), verifies UUID, rotates 30 backups, Healthchecks.io ping.
  - `backup/openwrt-backup-from-mac.sh` — runs from Mac, SSHs into router for `sysupgrade -b` backup to `/Volumes/backups/openwrt`.
- `provision/CLAUDE.md` describes OpenWRT as "mod.just recipes for OpenWrt router-side maintenance (NAS mount helper, DNS forwarding sanity checks)" — no mention of declarative config.
- AD-016 (LAN LB IP range 192.168.1.15-25) and the talos-cluster area note both reference OpenWRT DHCP reservations as a drift risk — those reservations are not tracked in the repo.

## Architecture decisions

- **Ansible collection**: `community.openwrt` v1.5.0+ (shell-based, no Python on router). Minimum ansible-core 2.18.0.
- **Inventory**: YAML inventory file in `provision/openwrt/inventory/` with router connection details (host vars: `ansible_host: 192.168.1.1`, `ansible_user: root`, `ansible_connection: community.openwrt.ssh`).
- **Playbook structure**: Mirror the Terraform area layout — `provision/openwrt/playbooks/` with focused playbooks per config domain:
  - `network.yml` — LAN/WAN interfaces, bonds, VLANs, bridge config
  - `firewall.yml` — firewall zones, forwarding rules, port forwards
  - `dhcp.yml` — DHCP server config, static leases (the drift risk from talos-cluster area)
  - `dns.yml` — DNS forwarding, conditional forwarding for the public domain to k8s-gateway
  - `wireless.yml` — WiFi interfaces, SSIDs, encryption
  - `packages.yml` — declarative package state via `community.openwrt.apk` (replaces the router-side reinstall script)
  - `system.yml` — hostname, timezone, SSH keys, sysctl
- **Secret handling**: Router credentials via 1Password / environment variables, consistent with the repo's External Secrets pattern. No plaintext secrets in playbooks.
- **Operational boundary**: Ansible manages steady-state config. The existing `just openwrt maintain` and `just openwrt upgrade` recipes remain for backup and firmware upgrade — those are operational, not configuration concerns. After upgrade, the reinstall-packages step is replaced by running the packages playbook.
- **Validation**: `ansible-playbook --check --diff` for dry-run; community.openwrt modules support check mode natively.

## Script migration from my-scripts-and-configs/OpenWRT

The current router-side scripts in `my-scripts-and-configs/OpenWRT/` must be assessed for integration or replacement as part of this roadmap:

| Script | Current role | Ansible replacement | Migration action |
|--------|-------------|---------------------|------------------|
| `packages/list-installed-user-packages-apk.sh` | Generates package list from `owut list -f config`, Healthchecks.io ping | `community.openwrt.apk` + `community.openwrt.package_facts` for declarative package state; Healthchecks.io ping moves to Just recipe or Ansible callback | **Replace** — Ansible manages desired package state declaratively; no need to generate lists on the router |
| `packages/reinstall-user-packages-apk.sh` | Reinstalls packages from txt list after firmware upgrade, runs custom commands | `community.openwrt.apk` playbook run post-upgrade | **Replace** — `just openwrt reinstall-packages` calls Ansible instead of the router-side script |
| `packages/custom-install-commands.txt` | ControlD DNS resolver installer (`curl -sSL api.controld.com/dl`) | Ansible task with `community.openwrt.command` or shell task | **Migrate** — ControlD resolver becomes an Ansible task in `packages.yml` or a dedicated `dns-privacy.yml` playbook |
| `packages/user-installed-apk-packages.txt` | Placeholder in git; real content generated on-router | Ansible inventory vars or group_vars listing desired packages | **Replace** — desired state is in the playbook, not in a generated list file |
| `backup/openwrt-backup-local.sh` | Router-local backup to USB pendrive, UUID check, rotation, Healthchecks.io | Keep as-is (operational, not config) — but consider adding an Ansible task that triggers the backup or verifies its healthcheck | **Keep** — operational concern, not declarative config; stays on the router |
| `backup/openwrt-backup-from-mac.sh` | Mac-initiated backup via SSH | Already wrapped by `just openwrt maintain` | **Keep** — already integrated in the Just workflow |

Key integration considerations:

- **Healthchecks.io pings**: The `list-installed-user-packages-apk.sh` and `openwrt-backup-local.sh` both use Healthchecks.io. The package list script's ping becomes unnecessary under Ansible (desired state replaces snapshot-and-reinstall). The backup script's ping should remain — it validates operational health.
- **ControlD resolver**: The custom install command is an imperative curl-pipe-sh. Under Ansible, this becomes an idempotent task that checks if the resolver is installed and configured before running. The resolver ID must be secret-managed (1Password, consistent with the repo pattern).
- **`mod.just` integration**: The existing `just openwrt reinstall-packages` recipe currently SSHes into the router to run the reinstall script. Post-migration, it should run the Ansible packages playbook instead. The `just openwrt maintain` and `just openwrt upgrade` recipes remain unchanged (operational).

## Implementation plan

### Phase 1 — Foundation

- Add `community.openwrt` collection to repo requirements (`provision/openwrt/requirements.yml`).
- Create inventory (`provision/openwrt/inventory/host_vars/router.yml`) with connection config.
- Create `provision/openwrt/ansible.cfg` pointing at the inventory and collection.
- Add a Just recipe: `just openwrt plan` — runs `ansible-playbook --check --diff` against all playbooks.
- Validate connectivity: `just openwrt plan` should reach the router and gather facts.

### Phase 2 — First playbook (packages)

### Phase 2 — First playbook (packages + script migration)

- Write `packages.yml` — declarative package state for all currently installed user packages. Source the desired package list from the router's current state (audit via `community.openwrt.package_facts`) and encode it as Ansible vars in `group_vars/` or `host_vars/`.
- Add the ControlD DNS resolver task: idempotent install via `community.openwrt.command` or shell task, with the resolver ID sourced from 1Password (consistent with the repo's External Secrets pattern). This replaces `custom-install-commands.txt`.
- Remove the Healthchecks.io ping from the package list workflow — Ansible's desired-state model makes the snapshot-and-reinstall pattern unnecessary.
- Update `just openwrt reinstall-packages` to invoke the Ansible packages playbook instead of SSHing the router-side `reinstall-user-packages-apk.sh`. The `mod.just` recipe wrapper stays; the underlying mechanism changes.
- Validate: `just openwrt plan` shows current packages as converged; adding/removing a package from the playbook changes the diff.

### Phase 3 — Network and DHCP

- Write `network.yml` — interfaces, bonds, DHCP client config.
- Write `dhcp.yml` — static leases (the DHCP reservations currently drifting, referenced in AD-016 and talos-cluster area).
- Validate: diff against current running config should be minimal (convergence, not divergence).

### Phase 4 — Firewall and DNS

- Write `firewall.yml` — zones, rules, port forwards.
- Write `dns.yml` — DNS forwarding config including the conditional forward for the public domain to the k8s-gateway VIP.
- Validate: firewall rules converge; DNS resolution from LAN clients unchanged.

### Phase 5 — System and wireless

- Write `system.yml` — hostname, timezone, SSH authorized keys, sysctl.
- Write `wireless.yml` — SSID, encryption, channel config.
- Validate: full convergence, no untracked drift.

### Phase 6 — Documentation and Just integration

- Update `provision/CLAUDE.md` and `provision/openwrt/` subtree guide to reflect the new declarative workflow.
- Add Just recipes: `just openwrt apply` (run all playbooks), `just openwrt plan` (dry-run), `just openwrt converge <playbook>` (single playbook).
- Update BM area-reference for OpenWRT if one is created, or add an `openwrt` section to the networking area-reference.

## Risks and open questions

- **Firmware upgrade persistence**: OpenWRT sysupgrade preserves UCI config by default. Ansible-managed config is idempotent — re-running after upgrade converges to desired state. But custom files in `/etc/luci-uploads/` are not guaranteed to survive. The packages playbook replaces the reinstall script; other custom scripts need assessment.
- **ansible-core 2.18.0 requirement**: Verify compatibility with the version in `.mise.toml` or the system Ansible. May need a mise plugin or venv.
- **Router connectivity during playbook run**: SSH must be reachable; if a playbook breaks LAN networking, subsequent tasks fail. Use `--check` before `--diff` before apply. Consider adding a rollback task or just-recipe guard.
- **Secret rotation**: If the router root password or SSH key changes, the Ansible inventory must be updated. 1Password integration for secrets follows the repo's existing pattern.
- `community.openwrt` is relatively new (v1.5.0) — the `uci` module is well-tested (original gekmihesg role), but other modules may have edge cases. Start with packages and network, validate incrementally.
- **Script migration boundary**: The router-side scripts in `my-scripts-and-configs/OpenWRT/` are the source-of-truth for current operational behavior. The backup scripts (`openwrt-backup-local.sh`, `openwrt-backup-from-mac.sh`) remain as-is (operational, not config). The package management scripts (`reinstall-user-packages-apk.sh`, `list-installed-user-packages-apk.sh`, `custom-install-commands.txt`) are replaced by Ansible. Decide whether to delete them from `my-scripts-and-configs` post-migration or keep as fallback documentation.
- **ControlD resolver ID**: Currently a placeholder (`RESOLVER_ID_HERE`) in `custom-install-commands.txt`. Under Ansible, this must be secret-managed via 1Password. The imperative curl-pipe-sh install pattern becomes an idempotent Ansible task.

## Explicit scope-bounds (NOT in this roadmap)

- BGP / FRR routing config on the router — AD-004 is active (L2 announcement, no BGP). If multi-node arrives, the Ansible playbooks would be the natural place to add it, but it is explicitly not part of this roadmap.
- Replacing `just openwrt maintain` / `just openwrt upgrade` — those are operational concerns (backup + sysupgrade), not steady-state config. They stay as Just recipes.
- OpenWRT web UI (LuCI) configuration — Ansible manages UCI directly; LuCI is a read-only view of the same config.
- Multiple routers — inventory is designed for one router. Adding more is a YAML change, not an architectural one.

## Related

- relates_to [[networking]]
- relates_to [[talos-cluster]]
- depends_on [[AD-004-cilium-l2-not-bgp]]
- depends_on [[AD-016-lan-lb-ip-range]]


## Implementation status (2026-05-30)


### Repository relocation (2026-05-30, post-implementation)

The entire `provision/openwrt/` directory was moved out of the public `home-ops` repo into the private `github.com/zhorvath83/my-scripts-and-configs` repo under `OpenWRT/provision/`. The move was triggered by the realisation that `home-ops` is a public repository while the OpenWRT material contains a non-trivial amount of secret-adjacent topology:

- 38 static DHCP leases including family device hostnames + MACs + IPs
- 8 family device MACs in the LAN WiFi allowlist
- Router HW MAC repeated across all `network.j2` device entries
- WiFi SSIDs (`LordOfThePings*`)
- ULA prefix
- The public domain reference in `dhcp` UCI (`rebind_domain`)
- The SSH public key in `files/authorized_keys`

What changed in this repo:

- `provision/openwrt/` directory deleted.
- `.justfile`: `mod openwrt "provision/openwrt"` replaced by a shim recipe `openwrt *args` that forwards to `~/Projects/personal/my-scripts-and-configs/openwrt` — operator-facing surface `just openwrt <recipe> [args]` stays identical.
- `provision/CLAUDE.md` and root `CLAUDE.md` updated to point at the private repo and document the shim.

The "Done", "Design deviations", "Open / deferred" and "Validation checklist" sections below describe the implementation as it now lives in `my-scripts-and-configs/OpenWRT/provision/` — substitute that path mentally wherever an older `provision/openwrt/` path is referenced.

### Done (this session)

- **Phase 1 — foundation**: `ansible.cfg` (TOFU SSH via `StrictHostKeyChecking=accept-new`, ControlMaster/ControlPersist, pipelining), `requirements.yml` (`community.openwrt >=1.5.0,<2.0.0`), `inventory/hosts.yml` + `inventory/host_vars/router.yml` (root, SSH key-only, `ansible_python_interpreter: /usr/bin/python3`), `group_vars/all.yml`, `playbooks/site.yml`, `playbooks/ping.yml` (raw uname connectivity test).
- **Phase 2 — packages + ControlD**: `playbooks/packages.yml` with 5-minute WAN-ready wait loop + `community.openwrt.apk` declarative state (72 packages including `python3-light`) + idempotent ControlD installer (resolver ID env-injected from 1Password via `op run`).
- **Phase 3 — network + dhcp**: `playbooks/network.yml` deploys `templates/uci/network.j2` (PPPoE creds Jinja-injected); `playbooks/dhcp.yml` deploys the full `files/uci/dhcp` including 38 static lease entries (drift risk from AD-016 / talos-cluster addressed).
- **Phase 4 — firewall + DNS**: `playbooks/firewall.yml` deploys `files/uci/firewall` (zones, forwarding, DNS interception rules, NAT). DNS forwarding lives inside the `dhcp` UCI (dnsmasq) — no separate `dns.yml`.
- **Phase 5 — system + wireless**: `playbooks/system.yml` (hostname, TZ, NTP, log dest); `playbooks/wireless.yml` with `templates/uci/wireless.j2` (PSKs + country code + MAC allowlist all sourced from `group_vars` / env).
- **Phase E — non-UCI files-and-scripts**: `playbooks/files-and-scripts.yml` deploys `rc.local`, `/etc/dropbear/authorized_keys`, `/etc/avahi/avahi-daemon.conf` (reflector + `allow-interfaces=br-iot.20,br-lan.10`), `/etc/crontabs/root` (template, only `/etc/init.d/acme renew` survives).
- **Service UCIs**: `playbooks/services.yml` deploys 13 service-layer UCIs (`dropbear`, `uhttpd`, `luci`, `fstab` (templated, UUID env-injected), `rpcd`, `attendedsysupgrade`, `socat`, `irqbalance`, `sqm`, `vnstat`, `ucitrack`, `ubihealthd`, `prometheus-node-exporter-lua`) with per-file mode tracking and a loop-driven restart task.
- **NextDNS deprecation cleanup**: `playbooks/cleanup.yml` removes the deprecated `nextdns` APK package + the `/etc/config/nextdns{,.bckup,.ori}` cruft (deprecated, ControlD replaced it; user-confirmed).
- **Backup playbook**: `playbooks/backup.yml` replaces both router-side scripts (`openwrt-backup-local.sh` + `openwrt-backup-from-mac.sh`) — `sysupgrade --create-backup` via `raw`, then `scp` via `delegate_to: localhost` to `/Volumes/backups/openwrt`. Setup-free (`gather_facts: false`), works on a fresh router without Python.
- **`mod.just` integration**: new recipes `galaxy`, `ping`, `plan`, `apply`, `converge <playbook>`; legacy `backup` recipe now wraps `ansible-playbook backup.yml` after the NAS mount preflight; `reinstall-packages` now wraps `just openwrt converge packages`; `upgrade` flow unchanged but its inner `backup` / `reinstall-packages` hops are now Ansible-driven.
- **1Password integration**: `.env.sample` with 7 op:// references (`CONTROLD_RESOLVER_ID`, `PPPOE_{USERNAME,PASSWORD}`, `WIFI_PSK_{LAN,IOT,GUEST}`, `OPENWRT_USB_UUID`), `plan`/`apply`/`converge` recipes wrap `op run --no-masking --env-file=./.env --` (mirror of `provision/cloudflare/mod.just` pattern).
- **Phase 6 doc-step partial**: `provision/CLAUDE.md` updated to reflect the Ansible flow.

### Design deviations from the roadmap

- **`python3-light` on the router** instead of strictly shell-based `community.openwrt.uci section`-per-section tasks. Trade-off: ~4 MB Python footprint on the router; gain: `ansible.builtin.copy`/`template`/`file` available, so non-UCI files (`rc.local`, `authorized_keys`, `avahi-daemon.conf`, `/etc/crontabs/root`) can be deployed cleanly without ad-hoc `scp + raw chmod` workarounds. Reversible: deleting `python3-light` from `apk_packages` and rewriting the UCI playbooks to use `community.openwrt.uci` section-by-section is a contained refactor.
- **Full-file UCI template/copy approach** instead of `community.openwrt.uci section` per logical section. Pragmatic for cold-start rebuild (complete-state overwrite, single deploy task per UCI file). Loses per-section idempotent diffs — every UCI deploy triggers the full service restart even on a no-op change. Same reversibility note as above.
- **Cold-start playbook order**: `ping → network → packages → cleanup → system → files → services → dhcp → firewall → wireless` — diverges from the roadmap's phase numbering because `network.yml` must run *before* `packages.yml` so the PPPoE WAN comes up before `apk update`.

### Open / deferred

- **ACME flow**: `/etc/config/acme` in the backup contained only placeholder values; `services.yml` deliberately skips it so a real cert configuration on the router is not clobbered. A real ACME flow (account email, FreeDNS / DNS-validation creds, cert list) is a follow-up — would land as `templates/uci/acme.j2` + new env vars.
- **`ansible-lint` pre-commit hook**: not wired up yet — would add `pipx:ansible-lint` to `.mise.toml` and a hook entry to `.pre-commit-config.yaml`.
- **Family hostname anonymisation in `files/uci/dhcp`**: 38 static leases include personal-name hostnames (`eszter-iphone`, `aliz-ipad`, …). CLAUDE.md permits private LAN hostnames in-repo; revisit only if the repository is ever made public.
- **Connectivity validation on the live router**: operator-driven smoke test (`just openwrt galaxy && just openwrt ping && just openwrt plan`) — not exercised in this session because the implementation was done locally from the 2026-05-27 backup tarball.
- **Cluster wakeup verification**: after a real apply, confirm that the cluster (`pve-0`, `k8s-cp0`, `nas`) gets its expected static lease and that `192.168.1.20` (Plex/Emby target referenced from `files/uci/firewall`) is consistent with the current LAN reality.

### Validation checklist (next step for the operator)

1. `ssh 192.168.1.1` once to populate `~/.ssh/known_hosts` (TOFU is accept-new only, so this is one-time).
2. Create the 1Password `HomeOps/router` item with the 7 fields referenced by `.env.sample`.
3. `cd ~/Projects/personal/my-scripts-and-configs && cp OpenWRT/provision/.env.sample OpenWRT/provision/.env` and adjust op:// references if vault layout differs.
4. `just openwrt galaxy` — install the `community.openwrt` collection into `./collections`.
5. `just openwrt ping` — Python-free raw `uname` connectivity test.
6. `just openwrt plan` — full `--check --diff` site dry-run (note: `raw` tasks skip in check mode, so several diffs will not show).
7. `just openwrt converge packages` — bootstrap `python3-light` + ControlD on a fresh router before the full `apply`.
8. `just openwrt apply` — full convergence.
9. `just openwrt backup` — verify the new Ansible-driven backup path lands a fresh `.tar.gz` in `/Volumes/backups/openwrt`.
