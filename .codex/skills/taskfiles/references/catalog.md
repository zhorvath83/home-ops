# Catalog

Use this reference to rebuild the current Taskfile surface before editing.

## Root Model

`Taskfile.yml` is the command index. It defines shared vars and includes the domain task files.

Current include targets:

- `.taskfiles/Ansible/Tasks.yaml`
- `.taskfiles/ExternalSecrets/Tasks.yaml`
- `.taskfiles/Flux/Tasks.yaml`
- `.taskfiles/HostMaintenance/Tasks.yaml`
- `.taskfiles/Kubernetes/Tasks.yaml`
- `.taskfiles/PreCommit/Tasks.yaml`
- `.taskfiles/Sops/Taskfile.yaml`
- `.taskfiles/Terraform/Tasks.yaml`
- `.taskfiles/VolSync/Tasks.yaml`

## Current Namespaces

- `an:` Ansible host and cluster lifecycle tasks
- `es:` External Secrets sync helpers
- `fx:` Flux bootstrap, reconcile, and inspection tasks
- `hm:` host maintenance tasks
- `ku:` Kubernetes utility tasks
- `list:` grouped task discovery
- `pc:` pre-commit tasks
- `so:` SOPS helpers
- `tf:` Cloudflare Terraform tasks
- `vs:` VolSync snapshot, restore, and maintenance tasks

The root `list` task groups these domains for discovery. Preserve that role when adding new namespaces or changing descriptions.
