set lazy
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

tf_dir := justfile_dir() + '/provision/ovh'

[private]
[script]
default:
    just -l ovh

[doc('terraform init -upgrade')]
[script]
init:
    cd {{ tf_dir }} && terraform init -upgrade

[doc('terraform plan')]
[script]
plan:
    cd {{ tf_dir }} && terraform plan

[doc('terraform apply')]
[script]
apply:
    cd {{ tf_dir }} && terraform apply

[doc('terraform force-unlock <id>')]
[script]
unlock id:
    cd {{ tf_dir }} && terraform force-unlock {{ id }}
