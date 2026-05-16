set lazy
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

tf_dir := justfile_dir() + '/provision/cloudflare'

[private]
[script]
default:
    just -l cloudflare

[doc('terraform init -upgrade (TF_VAR_* injected from ./.env via op run)')]
[script]
init:
    cd {{ tf_dir }} && op run --no-masking --env-file=./.env -- terraform init -upgrade

[doc('terraform plan (TF_VAR_* injected from ./.env via op run)')]
[script]
plan:
    cd {{ tf_dir }} && op run --no-masking --env-file=./.env -- terraform plan

[doc('terraform apply (TF_VAR_* injected from ./.env via op run)')]
[script]
apply:
    cd {{ tf_dir }} && op run --no-masking --env-file=./.env -- terraform apply

[doc('terraform force-unlock <id> (TF_VAR_* injected from ./.env via op run)')]
[script]
unlock id:
    cd {{ tf_dir }} && op run --no-masking --env-file=./.env -- terraform force-unlock {{ id }}
