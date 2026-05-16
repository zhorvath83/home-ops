set lazy
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

tf_dir := justfile_dir() + '/provision/ovh'

[private]
[script]
default:
    just -l ovh

[doc('terraform init -upgrade (TF_VAR_* injected from ./.env via op run)')]
[script]
init:
    cd {{ tf_dir }} && op run --no-masking --env-file=./.env -- terraform init -upgrade

[doc('terraform plan (TF_VAR_* injected from ./.env via op run)')]
[script]
plan:
    cd {{ tf_dir }} && op run --no-masking --env-file=./.env -- terraform plan

[doc('terraform apply (TF_VAR_* injected from ./.env via op run) + sync S3 outputs back to HomeOps/ovh 1Password item')]
[script]
apply:
    cd {{ tf_dir }} && op run --no-masking --env-file=./.env -- terraform apply
    cd {{ tf_dir }} && op item edit ovh --vault HomeOps \
      "ovh_s3_user_id[text]=$(op run --no-masking --env-file=./.env -- terraform output -raw s3_user_id)" \
      "ovh_s3_username[text]=$(op run --no-masking --env-file=./.env -- terraform output -raw s3_username)" \
      "ovh_s3_user_description[text]=$(op run --no-masking --env-file=./.env -- terraform output -raw s3_user_description)" \
      "ovh_s3_access_key[text]=$(op run --no-masking --env-file=./.env -- terraform output -raw s3_access_key)" \
      "ovh_s3_secret_key[password]=$(op run --no-masking --env-file=./.env -- terraform output -raw s3_secret_key)" \
      "ovh_s3_endpoint[text]=$(op run --no-masking --env-file=./.env -- terraform output -raw s3_endpoint)"

[doc('terraform force-unlock <id> (TF_VAR_* injected from ./.env via op run)')]
[script]
unlock id:
    cd {{ tf_dir }} && op run --no-masking --env-file=./.env -- terraform force-unlock {{ id }}
