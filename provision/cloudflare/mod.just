set lazy
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

tf_dir := justfile_dir() + '/provision/cloudflare'
# Shared `op run + terraform` prefix — every recipe wraps a single
# terraform subcommand with the same 1Password env injection.
tf := "op run --no-masking --env-file=./.env -- terraform"

[private]
[script]
default:
    just -l cloudflare

[doc('terraform init -upgrade (TF_VAR_* injected from ./.env via op run)')]
[script]
init:
    cd {{ tf_dir }} && {{ tf }} init -upgrade

[doc('terraform plan (TF_VAR_* injected from ./.env via op run)')]
[script]
plan:
    cd {{ tf_dir }} && {{ tf }} plan

[doc('terraform apply (TF_VAR_* injected from ./.env via op run)')]
[script]
apply:
    cd {{ tf_dir }} && {{ tf }} apply

[doc('terraform force-unlock <id> (TF_VAR_* injected from ./.env via op run)')]
[script]
unlock id:
    cd {{ tf_dir }} && {{ tf }} force-unlock {{ id }}
