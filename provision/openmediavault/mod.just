set lazy
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

omv_dir := justfile_dir() + '/provision/openmediavault'

[private]
[script]
default:
    just -l omv

[doc('Install / configure OMV via Ansible (idempotent)')]
[script]
install:
    cd {{ omv_dir }} && \
    ansible-playbook -i inventory/hosts.yml playbooks/site.yml

[doc('Run only the package update role')]
[script]
update:
    cd {{ omv_dir }} && \
    ansible-playbook -i inventory/hosts.yml playbooks/update.yml

[doc('Sanity check: ping host and verify NFS export list')]
[script]
check:
    cd {{ omv_dir }} && \
    ansible -i inventory/hosts.yml omv -m ping && \
    showmount -e 192.168.1.10

[doc('Run OMV package upgrade + apply changes over SSH, then re-mount NAS shares locally (pre-Phase-10 path)')]
[script]
update-host host="192.168.1.10" user="zhorvath83" nas_share_mount_script_on_mac="~/Projects/personal/my-scripts-and-configs/macOS/btt-scripts/nas-share-mount.sh":
    set -eu

    LOCAL_NAS_SHARE_MOUNT_SCRIPT_ON_MAC="$(eval printf '%s' "{{ nas_share_mount_script_on_mac }}")"

    echo "Running OpenMediaVault maintenance on {{ host }}"
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=ask {{ user }}@{{ host }} '
      set -eu
      if [ ! -x /usr/sbin/omv-upgrade ]; then
        echo "omv-upgrade was not found at /usr/sbin/omv-upgrade"
        exit 1
      fi
      sudo -n /usr/sbin/omv-upgrade
      sudo -n omv-rpc -u admin Config applyChanges "{\"modules\":[],\"force\":false}"
      sudo -n fstrim -av
    '

    if [ ! -x "${LOCAL_NAS_SHARE_MOUNT_SCRIPT_ON_MAC}" ]; then
      echo "NAS share mount script is not executable: ${LOCAL_NAS_SHARE_MOUNT_SCRIPT_ON_MAC}"
      exit 1
    fi

    echo "Re-mounting NAS shares locally"
    "${LOCAL_NAS_SHARE_MOUNT_SCRIPT_ON_MAC}"
