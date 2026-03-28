# Layout

Use this reference to rebuild the provisioning area structure before editing.

## Main Areas

- `inventory/`: inventory and host-specific data
- `playbooks/`: playbooks and templates for cluster lifecycle work
- `requirements.txt`: Python package dependencies
- `requirements.yml`: Ansible roles and collections

## Working Model

- keep the current single-cluster assumptions unless the repo itself expands
- preserve 1Password-driven host access and secret lookup patterns
- inspect related templates when a playbook renders external files
