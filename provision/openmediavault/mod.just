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
