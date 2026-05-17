# 10 — OMV Ansible playbook

## Cél

A jelenlegi `provision/kubernetes` Ansible (K3s install) **megszűnik**. Helyébe `provision/openmediavault` Ansible jön, ami a bare metal OpenMediaVault host-ot (M93p) install-álja és karbantartja.

## Inputs

- M93p **Debian 13 (Trixie)** alapon (jelenleg már így fut: `nas.lan`, kernel `6.19.14+deb13-amd64`).
- **OMV 8.x (Synchrony)** — Debian 13-ra épülő hivatalos stable.
- SSH access az M93p-re egy admin userrel (sudo NOPASSWD).
- Az USB DAS Toshiba HDD-vel **fizikailag dugva** a M93p-be (a bare metal OMV közvetlen USB hozzáférést kap, NEM passthrough).
- 1Password CLI bejelentkezve (deploy credentials).

## OMV automatizálás — mi támogatott

A kutatás eredménye:

- **`omv-confdbadm`** hivatalosan dokumentált CLI tool a `config.xml` read/write/delete-jére ([OMV 8.x docs](https://docs.openmediavault.org/en/latest/development/tools/omv_confdbadm.html)). Python tool, shell scriptelhető.
- **Ansible-integráció**: **NEM hivatalosan támogatott** ([GitHub issue #498](https://github.com/openmediavault/openmediavault/issues/498)). Community Ansible playbookok léteznek (pl. [DudeCalledBro/openmediavault](https://github.com/DudeCalledBro/openmediavault)), de unofficial.
- **Gyakorlat**: Ansible kezeli az OS-t (base, hardening, install), az OMV config maga UI-ból jön, vagy `config.xml` backup-restore-ból.

### Ansible hatókör (támogatott)

- Debian base hardening (hostname, timezone, sshd, UFW, packages)
- OMV alap install (apt repo + `openmediavault` package + `omv-confdbadm populate`)
- USB DAS fstab mount
- `resticprofile` + Backrest (NEM OMV-managed)
- `node_exporter` (NEM OMV-managed)

### OMV UI hatókör (saved → config.xml)

- NFS exports, SMB shares
- Users, groups, permissions
- Filesystem creation
- OMV plugin enable/disable
- S.M.A.R.T. monitoring, notifications

### Reproducibility forrás

A `/etc/openmediavault/config.xml` backup. Migráció előtt mentsd, után töltsd vissza:
```bash
# Mentés a régi VM-ből:
ssh nas.lan sudo cat /etc/openmediavault/config.xml > /tmp/omv-config-backup-$(date +%F).xml

# Restore a bare metal install után:
scp /tmp/omv-config-backup-*.xml admin@192.168.1.10:/tmp/
ssh admin@192.168.1.10 'sudo omv-confdbadm load /tmp/omv-config-backup-*.xml && sudo omv-salt deploy run'
```

A backup-ot 1Password Documents-be érdemes tárolni.

## Mikor készül el ez

**Cutover UTÁN**, lásd [15-post-cutover.md](./15-post-cutover.md). A migráció során az M93p **megmarad Proxmox+OMV VM-ként**, hogy a NAS funkció ne álljon meg. Amikor a HP cluster stabil és az új workload-ok mennek (1-2 hét megfigyelés után), az M93p átalakul.

## Tervezett fájl-layout

```
provision/openmediavault/
├── ansible.cfg
├── requirements.yaml                           # collections + roles
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
│       └── omv/
│           └── all.yml                         # OMV host config (NFS exports, mounts)
└── playbooks/
    ├── site.yml                                # main playbook (összes role)
    ├── update.yml                              # csak csomag-frissítés
    └── roles/
        ├── base/                               # Debian hardening, user, sudo, ssh
        ├── omv/                                # OMV BASE install + omv-extras
        ├── storage/                            # USB DAS fstab mount (config.xml UUID-t tisztelve)
        ├── nfs/                                # csak openmediavault-nfs csomag (config: OMV UI-ból)
        ├── backup/                             # resticprofile + Backrest
        └── monitoring/                         # node_exporter (kube-prometheus-stack scrape)
```

## `ansible.cfg`

A jelenlegi `provision/kubernetes/ansible.cfg`-t **átemeljük** változatlanul (jó konfig). A `provision/openmediavault/ansible.cfg`-be került mása:

```ini
[defaults]
nocows                      = True
executable                  = /bin/bash
stdout_callback             = default
callback_result_format      = yaml
callback_format_pretty      = true
force_valid_group_names     = ignore
log_path                    = ~/.ansible/ansible.log
inventory                   = ./inventory
roles_path                  = ~/.ansible/roles:./playbooks/roles
collections_path            = ~/.ansible/collections
remote_tmp                  = /tmp
local_tmp                   = ~/.ansible/tmp
fact_caching                = jsonfile
fact_caching_connection     = ~/.ansible/facts_cache
remote_port                 = 22
timeout                     = 60
host_key_checking           = False
vars_plugins_enabled        = host_group_vars

[inventory]
unparsed_is_failed          = true

[privilege_escalation]
become                      = True

[ssh_connection]
scp_if_ssh                  = smart
retries                     = 3
ssh_args                    = -o ControlMaster=auto -o ControlPersist=30m -o Compression=yes -o ServerAliveInterval=15s
pipelining                  = True
control_path                = %(directory)s/%%h-%%r
```

## `requirements.yaml`

```yaml
---
collections:
  - name: community.general
    version: ">=12.6.0"
  - name: ansible.posix
    version: ">=2.1.0"
```

A kubernetes.core és az xanmanning.k3s **eltűnik** (nem kell K3s install Ansible-lel).

## `inventory/hosts.yml`

```yaml
---
all:
  children:
    omv:
      hosts:
        m93p:
          ansible_host: 192.168.1.10
          ansible_user: admin                   # lokális admin user az M93p-n
```

## `inventory/group_vars/omv/all.yml`

```yaml
---
# Hostname
omv_hostname: m93p
omv_timezone: Europe/Budapest

# Storage
omv_storage_devices:
  - device: /dev/disk/by-id/usb-Toshiba_<MODEL>_<SERIAL>
    mount: /srv/dev-disk-by-uuid-<UUID>          # OMV szabványos mount path
    fs: xfs                                      # vagy ext4, jelenlegi formattól függ

# NFS exports — NEM az Ansible kezeli, OMV UI-ban konfigurálva (config.xml restore vagy manual)
# Csak referencia, hogy mely export-okat várjuk a UI-ban a `192.168.1.0/24` clientre:
omv_expected_exports:
  - /srv/dev-disk-by-uuid-<UUID>/media     # rw, sync, no_subtree_check
  - /srv/dev-disk-by-uuid-<UUID>/backup    # rw, sync, no_subtree_check

# resticprofile config
restic_profile_repos:
  - name: ovh
    type: s3
    bucket: "{{ ovh_s3_bucket }}"               # 1Password-ből
    endpoint: "{{ ovh_s3_endpoint }}"
    access_key: "{{ ovh_s3_access_key }}"
    secret_key: "{{ ovh_s3_secret_key }}"

# node_exporter
node_exporter_port: 9100
node_exporter_listen_address: "192.168.1.10:9100"
```

## Playbook `site.yml`

```yaml
---
- name: OpenMediaVault host setup
  hosts: omv
  become: true
  gather_facts: true
  roles:
    - role: base                               # Debian hardening
    - role: omv                                # OMV install + plugins
    - role: storage                            # USB DAS mount
    - role: nfs                                # NFS exports
    - role: backup                             # resticprofile / Backrest
    - role: monitoring                         # node_exporter
```

## Role: `base` (Debian hardening)

`playbooks/roles/base/tasks/main.yml`:

```yaml
---
- name: Set hostname
  ansible.builtin.hostname:
    name: "{{ omv_hostname }}"

- name: Set timezone
  community.general.timezone:
    name: "{{ omv_timezone }}"

- name: Install base packages
  ansible.builtin.apt:
    name:
      - curl
      - gnupg
      - sudo
      - ufw
      - rsync
      - vim
      - htop
      - smartmontools
    state: present
    update_cache: true

- name: Configure UFW — allow SSH, NFS, OMV web UI
  community.general.ufw:
    rule: allow
    port: "{{ item }}"
    proto: tcp
  loop:
    - "22"                                     # SSH
    - "80"                                     # OMV web UI
    - "443"                                    # OMV HTTPS
    - "2049"                                   # NFS
    - "9100"                                   # node_exporter

- name: Enable UFW
  community.general.ufw:
    state: enabled
    policy: deny
```

## Role: `omv` (OMV install)

`playbooks/roles/omv/tasks/main.yml`:

```yaml
---
- name: Check if OMV is installed
  ansible.builtin.command: dpkg -l openmediavault
  register: omv_installed
  failed_when: false
  changed_when: false

- name: Add OMV apt key
  ansible.builtin.apt_key:
    url: https://packages.openmediavault.org/public/archive.key
    state: present
  when: omv_installed.rc != 0

- name: Add OMV apt repo
  ansible.builtin.apt_repository:
    repo: "deb https://packages.openmediavault.org/public sandworm main"
    state: present
    filename: openmediavault
  when: omv_installed.rc != 0

- name: Install OMV
  ansible.builtin.apt:
    name: openmediavault-keyring
    state: present
    update_cache: true
  when: omv_installed.rc != 0

- name: Run OMV install script (idempotent)
  ansible.builtin.command:
    cmd: omv-confdbadm populate
  when: omv_installed.rc != 0

# Plugins: omv-extras + ZFS + ResticBackup (ha kell)
- name: Install omv-extras
  ansible.builtin.apt:
    name:
      - openmediavault-omvextrasorg
      - openmediavault-resetperms                # opcionális
    state: present
    update_cache: true
```

**Megjegyzés:** Az OMV install fő része egy `omv-install.sh` script-tel megy (a hivatalos OMV ajánlás). Ezt **első alkalommal manuálisan** futtatjuk, az Ansible role csak utána veszi át a config-ot.

## Role: `storage` (USB DAS mount)

```yaml
---
- name: Get USB DAS UUID
  ansible.builtin.command: blkid -s UUID -o value "{{ item.device }}"
  register: das_uuid
  loop: "{{ omv_storage_devices }}"
  changed_when: false

- name: Create mount points
  ansible.builtin.file:
    path: "{{ item.mount }}"
    state: directory
    mode: '0755'
  loop: "{{ omv_storage_devices }}"

- name: Add fstab entries
  ansible.posix.mount:
    path: "{{ item.mount }}"
    src: "UUID={{ das_uuid.results[idx].stdout }}"
    fstype: "{{ item.fs }}"
    opts: "defaults,noatime,nofail,x-systemd.device-timeout=30s"
    state: mounted
  loop: "{{ omv_storage_devices }}"
  loop_control:
    index_var: idx
```

## Role: `nfs` — minimal

Csak az OMV NFS plugin csomag, a tényleges exports OMV UI-ból:

```yaml
---
- name: Ensure OMV NFS plugin is installed
  ansible.builtin.apt:
    name: openmediavault-nfs
    state: present
```

**NEM** írunk `/etc/exports`-ot Ansible-ből — az OMV `omv-salt deploy run nfs` parancsa felülírja a `config.xml`-ből. A shares/exports az **OMV web UI**-ban kerülnek konfigurálásra, vagy a `config.xml` backup-restore-ral (lásd "Reproducibility forrás" fent).

## Role: `backup` (resticprofile + Backrest)

A jelenlegi resticprofile config-ot átemeljük. Részletek a meglévő setup-tól függnek. Skeleton:

```yaml
---
- name: Install resticprofile
  ansible.builtin.get_url:
    url: https://github.com/creativeprojects/resticprofile/releases/download/v0.30.0/resticprofile_0.30.0_linux_amd64.tar.gz
    dest: /tmp/resticprofile.tar.gz
    mode: '0644'

- name: Extract resticprofile
  ansible.builtin.unarchive:
    src: /tmp/resticprofile.tar.gz
    dest: /usr/local/bin
    remote_src: true
    include:
      - resticprofile

- name: Create resticprofile config dir
  ansible.builtin.file:
    path: /etc/resticprofile
    state: directory
    mode: '0700'

- name: Configure resticprofile
  ansible.builtin.template:
    src: profiles.yaml.j2
    dest: /etc/resticprofile/profiles.yaml
    mode: '0600'

- name: Install resticprofile systemd timer
  ansible.builtin.systemd:
    name: "resticprofile-backup@{{ item.name }}.timer"
    enabled: true
    state: started
  loop: "{{ restic_profile_repos }}"
```

A `templates/profiles.yaml.j2` 1Password-ből injektált creds-ekkel:

```yaml
{% for repo in restic_profile_repos %}
{{ repo.name }}:
  repository: "s3:{{ repo.endpoint }}/{{ repo.bucket }}"
  password-file: /etc/resticprofile/password-{{ repo.name }}
  env:
    AWS_ACCESS_KEY_ID: "{{ repo.access_key }}"
    AWS_SECRET_ACCESS_KEY: "{{ repo.secret_key }}"

  backup:
    source:
      - /srv/dev-disk-by-uuid-*/backup
    schedule: "*-*-* 03:00"
    retention:
      after-backup: true
      keep-daily: 7
      keep-weekly: 4
      keep-monthly: 6
{% endfor %}
```

A `restic_profile_repos` listában a `{{ ovh_s3_access_key }}` stb. **1Password-ből jönnek** — vagy `op inject` lokálisan a vars fájlba, VAGY `ansible-vault` (de inkább op inject).

## Role: `monitoring` (node_exporter)

```yaml
---
- name: Install node_exporter
  ansible.builtin.apt:
    name: prometheus-node-exporter
    state: present

- name: Configure node_exporter
  ansible.builtin.lineinfile:
    path: /etc/default/prometheus-node-exporter
    regexp: "^ARGS="
    line: 'ARGS="--web.listen-address={{ node_exporter_listen_address }}"'
  notify: Restart node_exporter

- name: Enable + start node_exporter
  ansible.builtin.systemd:
    name: prometheus-node-exporter
    enabled: true
    state: started

handlers:
  - name: Restart node_exporter
    ansible.builtin.systemd:
      name: prometheus-node-exporter
      state: restarted
```

A `kube-prometheus-stack` (a HP cluster-en) scrape config-ot kap egy ServiceMonitor/PodMonitor-on, ami a `192.168.1.10:9100`-ra scrape-el.

## OMV-specifikus dolgok az Ansible-en

A jelenlegi M93p OMV setup-ban valószínűleg:
- **OMV web UI** felülről állítva: shares, users, plugins.
- **SMB shares** (Windows kliensnek?) — nem említetted, de ha van, opcionális role.
- **rsnapshot** vagy más backup tool — feltételezem, hogy resticprofile elég.

Az Ansible **megőrzi** az OMV-config-ot, ami `/etc/openmediavault/config.xml`-ben él. Ha a teljes OMV-config-ot is automatizálni akarjuk, az `omv-confdbadm`-on keresztül megy — bonyolult, **out of scope** ennek a doc-nak. Default: Ansible csak a host-szintű dolgokat kezeli, az OMV web UI alól végzett config marad **manuális**, de **dokumentálva** (külön doc-ban a `docs/`-ban).

## Validation

```bash
# Ansible reach:
just omv check
# PING m93p ok
# showmount -e 192.168.1.10 mutatja az export-okat

# NFS access HP-ról:
kubectl -n default run -it --rm nfs-test --image=mirror.gcr.io/alpine:latest --command -- \
  sh -c "apk add nfs-utils && mount -t nfs 192.168.1.10:/srv/dev-disk-by-uuid-<UUID>/media /mnt && ls /mnt"

# node_exporter scrape:
curl http://192.168.1.10:9100/metrics
# Prometheus metrics output

# resticprofile dry-run:
ssh m93p sudo resticprofile -n ovh backup --dry-run
```

## Migration runbook (OMV cutover)

A HP cluster cutover UTÁN, 1-2 héttel:

1. **Régi M93p Proxmox VM (OMV) backup**: `/etc/openmediavault/config.xml` mentve, USB DAS mount unmount, Proxmox VM shutdown.
2. **M93p USB DAS fizikai elővétel**.
3. **M93p Proxmox install wipe** — Debian 13 bare metal install USB-ről.
4. **SSH access setup**: admin user, sudo, SSH key.
5. **USB DAS bedugás**.
6. `cd provision/openmediavault && just omv install`
7. **OMV web UI első login** → `/etc/openmediavault/config.xml` restore manuálisan vagy `omv-confdbadm load /path/to/config.xml`.
8. **NFS export ellenőrzés** HP-ról: `kubectl describe pv` (a régi PV-k még a VM IP-jét tartalmazzák? Nem — a VM IP `192.168.1.10` is, a bare metal is). Ha az NFS mount path változik (OMV szabványos `/srv/dev-disk-by-uuid-<UUID>/` minta), a PV-k mountpath-jét frissíteni kell — VAGY az NFS export-ban szimlinkkel a régi path-ra mutatva.

A **NFS share path változás kockázata**: lásd Open issues.

## Rollback

A bare metal install előtt:
- USB DAS-t **NE formázd újra** — ha valami félresikerül, vissza tudd dugni a régi Proxmox+OMV VM-be (visszahúzva backup-ból).
- A Proxmox VM lemezét **NE töröld** — egy hétig őrizd meg, hogy szükség esetén vissza tudd indítani.

Ha a bare metal OMV nem indul → boot Proxmox install ISO-ról, vissza-restore-old a VM-et a backup-ból, NAS megy tovább.

## Open issues

- **NFS export path változás**: az OMV bare metal install valószínűleg új UUID-vel formázott `/srv/dev-disk-by-uuid-<UUID>` path-t generál (különbözhet a Proxmox VM-ből látott path-tól). Ennek hatása: a **HP cluster-en futó pod-ok NFS PV-i** elromlik. **Mitigáció**: ne formázd az USB DAS-t újra, ugyanaz a UUID megmarad → ugyanaz a path. VAGY: szimlinkkel mappázzuk a régi path-t az újra.
- **OMV config.xml restore**: a `/etc/openmediavault/config.xml` mentését az **első bare metal install ELŐTT** kell csinálni (régi VM-en `cp /etc/openmediavault/config.xml /tmp/ && scp ...`). Backup tárolása biztonságos helyre (1Password Documents vagy git-ben encrypted).
- **OMV plugins**: a Proxmox-on használt OMV plugin set (omv-extras-on belül) reproduktív lehet, de Ansible-lel csak az `apt install`-t kezeljük. A web UI-n keresztül konfigurált plugin-beállítások manuálisan jönnek vissza a config.xml restore-ral.
- **`omv-confdbadm` apply**: Ansible-ből futtatva subprocess hibákat dobhat, ha az OMV CLI változott. Manuálisan futtatva ezt az első install-kor megfigyeljük.
- **SMB/CIFS share-ek**: ha van Windows-kliens, plusz role kell. Default tervben nincs benne.
- **A jelenlegi `task hm:openmediavault` recipe**: a régi maintenance task (update packages, restart, reboot) **megmarad** az új `just omv update` recipe-ben — egyszerűsítve.
- **`provision/kubernetes/` mappa törlése**: a régi Ansible K3s setup törölhető a talos branch-en, mert a HP cluster Talos-szal megy. Részletei a [13-cutover-runbook.md](./13-cutover-runbook.md)-ben.
