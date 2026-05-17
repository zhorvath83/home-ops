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
    cd {{ tf_dir }}
    op run --no-masking --env-file=./.env -- terraform apply
    # Pull all outputs in one shot — replaces six separate
    # `op run -- terraform output -raw <name>` invocations.
    outputs="$(op run --no-masking --env-file=./.env -- terraform output -json)"
    # Pre-fetch into variables so jq's non-zero exit (missing/null value)
    # aborts the recipe instead of being swallowed by `$(…)` substitution
    # inside the `op item edit` argument list.
    get() { printf '%s' "${outputs}" | jq -er --arg k "$1" '.[$k].value'; }
    s3_user_id="$(get s3_user_id)" || exit 1
    s3_username="$(get s3_username)" || exit 1
    s3_user_description="$(get s3_user_description)" || exit 1
    s3_access_key="$(get s3_access_key)" || exit 1
    s3_secret_key="$(get s3_secret_key)" || exit 1
    s3_endpoint="$(get s3_endpoint)" || exit 1
    op item edit ovh --vault HomeOps \
      "ovh_s3_user_id[text]=${s3_user_id}" \
      "ovh_s3_username[text]=${s3_username}" \
      "ovh_s3_user_description[text]=${s3_user_description}" \
      "ovh_s3_access_key[text]=${s3_access_key}" \
      "ovh_s3_secret_key[password]=${s3_secret_key}" \
      "ovh_s3_endpoint[text]=${s3_endpoint}"

[doc('terraform force-unlock <id> (TF_VAR_* injected from ./.env via op run)')]
[script]
unlock id:
    cd {{ tf_dir }} && op run --no-masking --env-file=./.env -- terraform force-unlock {{ id }}
