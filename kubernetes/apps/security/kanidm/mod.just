set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

app_dir := justfile_dir() + '/kubernetes/apps/security/kanidm'
cluster_settings := justfile_dir() + '/kubernetes/components/common/vars/cluster-settings.yaml'

[private]
[script]
default:
    just -l kanidm

# === server ===

[doc('Kanidm server health: pod status + server version')]
[group('server')]
[script]
status:
    kubectl -n security get pods -l app.kubernetes.io/name=kanidm -o wide
    kubectl -n security exec statefulset/kanidm -- kanidmd version

[doc('Follow kanidm server logs')]
[group('server')]
[script]
logs:
    kubectl -n security logs statefulset/kanidm -f --tail=100

[arg('account', pattern='admin|idm_admin')]
[doc('Reset a built-in account (account=admin|idm_admin) server-side — prints a new generated password')]
[group('server')]
[script]
recover-account account:
    kubectl -n security exec -it statefulset/kanidm -- kanidmd recover-account "{{ account }}"

# === client ===
#
# The kanidm/server image ships no client CLI and there is no macOS package, so all
# client commands run in an ad-hoc kanidm/tools pod. It reaches the server on the
# public URL: split-horizon DNS resolves idm.* to the envoy-internal VIP, whose CNP
# admits cluster pods. The login session lives in the pod until client-down.

[private]
[script]
ensure-client:
    phase="$(kubectl -n security get pod kanidm-client -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [ "${phase}" = "Running" ]; then exit 0; fi
    if [ -n "${phase}" ]; then kubectl -n security delete pod kanidm-client --wait; fi
    domain="$(yq -r '.data.PUBLIC_DOMAIN' '{{ cluster_settings }}')"
    # client tag follows the server tag in helmrelease.yaml — one Renovate pin for both
    tag="$(yq -r '.spec.values.controllers.kanidm.containers.app.image.tag' '{{ app_dir }}/app/helmrelease.yaml')"
    just log info "Starting kanidm client pod" image "docker.io/kanidm/tools:${tag}"
    kubectl -n security run kanidm-client \
      --image="docker.io/kanidm/tools:${tag}" \
      --restart=Never \
      --overrides="$(cat <<EOF
    {
      "spec": {
        "automountServiceAccountToken": false,
        "containers": [{
          "name": "kanidm-client",
          "image": "docker.io/kanidm/tools:${tag}",
          "command": ["/bin/sh", "-c", "exec sleep infinity"],
          "env": [
            {"name": "KANIDM_URL", "value": "https://idm.${domain}"},
            {"name": "HOME", "value": "/tmp"}
          ],
          "securityContext": {
            "runAsNonRoot": true,
            "runAsUser": 10001,
            "runAsGroup": 10001,
            "allowPrivilegeEscalation": false,
            "capabilities": {"drop": ["ALL"]},
            "seccompProfile": {"type": "RuntimeDefault"}
          }
        }]
      }
    }
    EOF
    )"
    kubectl -n security wait pod/kanidm-client --for=condition=ready --timeout=2m

[doc('Log in inside the client pod (positional arg: [account=idm_admin]); session persists until client-down')]
[group('client')]
[script]
login account="idm_admin": ensure-client
    kubectl -n security exec -it kanidm-client -- kanidm login -D "{{ account }}"

[doc('Remove the kanidm client pod (and its cached login session)')]
[group('client')]
[script]
client-down:
    kubectl -n security delete pod kanidm-client --ignore-not-found

[doc('Run any kanidm client command (append -D <account>; e.g. just kanidm run service-account list -D idm_admin)')]
[group('client')]
[script]
run *args: ensure-client
    kubectl -n security exec -it kanidm-client -- kanidm "$@"

[private]
[script]
ensure-login: ensure-client
    if ! kubectl -n security exec kanidm-client -- kanidm self whoami -D idm_admin >/dev/null 2>&1; then
      just log info "No valid idm_admin session in the client pod (missing or expired — default lifetime is 1h) — logging in"
      just kanidm login
    fi

# Existence probe via read-back: the kanidm CLI exits 0 even on HTTP errors (verified
# on 1.10.4, group create → 409 → exit 0), so wizards verify state instead of exit codes.
# Call via `just -q` — "missing" is a legit exit-1 answer, -q mutes just's failure banner.
[private]
[script]
entity-exists kind name: ensure-client
    case "$1" in
      group)  cmd='group get' ;;
      person) cmd='person get' ;;
      oauth2) cmd='system oauth2 get' ;;
      *)      just log error "Unknown entity kind: $1"; exit 2 ;;
    esac
    kubectl -n security exec kanidm-client -- kanidm ${cmd} "$2" -D idm_admin 2>/dev/null | grep -q '^name:'

# === person ===

[doc('List persons')]
[group('person')]
[script]
person-list: ensure-client
    kubectl -n security exec kanidm-client -- kanidm person list -D idm_admin

[doc('Show one person')]
[group('person')]
[script]
person-get username: ensure-client
    kubectl -n security exec kanidm-client -- kanidm person get "$1" -D idm_admin

[doc('Create a person (positional args: username displayname)')]
[group('person')]
[script]
person-create username displayname: ensure-client
    kubectl -n security exec kanidm-client -- kanidm person create "$1" "$2" -D idm_admin

[doc('Generate a credential reset token/link for a person — use it to set a password or enroll a passkey')]
[group('person')]
[script]
person-reset-token username: ensure-client
    kubectl -n security exec kanidm-client -- kanidm person credential create-reset-token "$1" -D idm_admin

[doc('Delete a person — asks for confirmation, irreversible')]
[group('person')]
[script]
person-delete username: ensure-client
    gum confirm "Delete person '$1'? This is irreversible." || { just log info "Aborted"; exit 0; }
    kubectl -n security exec -it kanidm-client -- kanidm person delete "$1" -D idm_admin

[doc('Interactive wizard: create a person, add to groups, issue a credential reset token — offers defaults, one summary confirm; re-run skips an existing person')]
[group('person')]
[script]
person-new-wf: ensure-login
    username="$(gum input --header 'Username' --placeholder 'jdoe')"
    [ -n "${username}" ] || { just log error "Username is required"; exit 1; }
    exists=''
    if just -q kanidm entity-exists person "${username}"; then
      exists='yes'
      just log info "Person '${username}' already exists — the create step will be skipped"
    fi
    displayname=''; mail=''
    if [ -z "${exists}" ]; then
      displayname="$(gum input --header 'Display name' --value "${username}")"
      mail="$(gum input --header 'Mail address (empty to skip)' --placeholder 'user@example.com')"
    fi
    groups="$(gum input --header 'Groups to add the person to (space-separated; empty to skip)')"
    mail_self_write='yes'
    if ! gum confirm --default=true 'Allow the person to edit their own mail attribute (idm_people_self_mail_write)?'; then mail_self_write='no'; fi
    reset_token='no'
    if gum confirm --default=true 'Generate a credential reset token (password / passkey enrollment)?'; then reset_token='yes'; fi
    printf '\n── Summary ─────────────────────────────\n'
    if [ -z "${exists}" ]; then
      printf 'person:      %s — "%s"\n' "${username}" "${displayname}"
      printf 'mail:        %s\n' "${mail:-—}"
    else
      printf 'person:      %s (existing — create skipped)\n' "${username}"
    fi
    printf 'groups:      %s\n' "${groups:-—}"
    printf 'mail edit:   %s\n' "${mail_self_write}"
    printf 'reset token: %s\n\n' "${reset_token}"
    gum confirm 'Proceed?' || { just log info "Aborted — nothing changed"; exit 0; }
    if [ -z "${exists}" ]; then
      just kanidm person-create "${username}" "${displayname}"
      just -q kanidm entity-exists person "${username}" || { just log error "Person creation failed — see the error above"; exit 1; }
      if [ -n "${mail}" ]; then just kanidm run person update "${username}" --mail "${mail}" -D idm_admin; fi
    fi
    if [ -n "${groups}" ]; then
      for g in ${groups}; do just kanidm group-add-members "${g}" "${username}"; done
    fi
    if [ "${mail_self_write}" = 'yes' ]; then just kanidm group-add-members idm_people_self_mail_write "${username}"; fi
    just kanidm person-get "${username}"
    if [ "${reset_token}" = 'yes' ]; then just kanidm person-reset-token "${username}"; fi

# === groups ===

[doc('List groups')]
[group('groups')]
[script]
group-list: ensure-client
    kubectl -n security exec kanidm-client -- kanidm group list -D idm_admin

[doc('Show one group')]
[group('groups')]
[script]
group-get name: ensure-client
    kubectl -n security exec kanidm-client -- kanidm group get "$1" -D idm_admin

[doc('Create a group')]
[group('groups')]
[script]
group-create name: ensure-client
    kubectl -n security exec kanidm-client -- kanidm group create "$1" -D idm_admin

[doc('Delete a group — asks for confirmation; scope maps referencing it stop granting access')]
[group('groups')]
[script]
group-delete name: ensure-client
    gum confirm "Delete group '$1'? This is irreversible." || { just log info "Aborted"; exit 0; }
    kubectl -n security exec -it kanidm-client -- kanidm group delete "$1" -D idm_admin

[doc('Add members to a group (positional args: group member...)')]
[group('groups')]
[script]
group-add-members name +members: ensure-client
    kubectl -n security exec kanidm-client -- kanidm group add-members "$@" -D idm_admin

[doc('Remove members from a group (positional args: group member...)')]
[group('groups')]
[script]
group-remove-members name +members: ensure-client
    kubectl -n security exec kanidm-client -- kanidm group remove-members "$@" -D idm_admin

[doc('Interactive wizard: create a group and add initial members — one summary confirm; re-run skips an existing group and just adds members')]
[group('groups')]
[script]
group-new-wf: ensure-login
    name="$(gum input --header 'Group name' --placeholder 'grafana-users')"
    [ -n "${name}" ] || { just log error "Group name is required"; exit 1; }
    exists=''
    if just -q kanidm entity-exists group "${name}"; then
      exists='yes'
      just log info "Group '${name}' already exists — the create step will be skipped"
    fi
    members="$(gum input --header 'Members to add (space-separated; empty to skip)')"
    printf '\n── Summary ─────────────────────────────\n'
    printf 'group:   %s%s\n' "${name}" "${exists:+ (existing — create skipped)}"
    printf 'members: %s\n\n' "${members:-—}"
    gum confirm 'Proceed?' || { just log info "Aborted — nothing changed"; exit 0; }
    if [ -z "${exists}" ]; then
      just kanidm group-create "${name}"
      just -q kanidm entity-exists group "${name}" || { just log error "Group creation failed — see the error above"; exit 1; }
    fi
    if [ -n "${members}" ]; then just kanidm group-add-members "${name}" ${members}; fi
    just kanidm group-get "${name}"

# === oauth2 ===
#
# Minimal client-onboarding flow: oauth2-create → oauth2-add-redirect-url →
# oauth2-update-scope-map (group gates who may log in) → oauth2-show-secret.
# Rarer toggles (claim maps, PKCE/strict-redirect switches, key rotation) go
# through `just kanidm run system oauth2 ...`.

[doc('List OAuth2 clients')]
[group('oauth2')]
[script]
oauth2-list: ensure-client
    kubectl -n security exec kanidm-client -- kanidm system oauth2 list -D idm_admin

[doc('Show one OAuth2 client')]
[group('oauth2')]
[script]
oauth2-get name: ensure-client
    kubectl -n security exec kanidm-client -- kanidm system oauth2 get "$1" -D idm_admin

[doc('Create a confidential OAuth2 client with a basic secret (positional args: name displayname origin-url)')]
[group('oauth2')]
[script]
oauth2-create name displayname origin: ensure-client
    kubectl -n security exec kanidm-client -- kanidm system oauth2 create "$1" "$2" "$3" -D idm_admin

[doc('Create a public PKCE-only OAuth2 client — no secret; prefer confidential clients when possible (positional args: name displayname origin-url)')]
[group('oauth2')]
[script]
oauth2-create-public name displayname origin: ensure-client
    kubectl -n security exec kanidm-client -- kanidm system oauth2 create-public "$1" "$2" "$3" -D idm_admin

[doc('Delete an OAuth2 client — asks for confirmation; the consuming app loses login immediately')]
[group('oauth2')]
[script]
oauth2-delete name: ensure-client
    gum confirm "Delete OAuth2 client '$1'? This is irreversible." || { just log info "Aborted"; exit 0; }
    kubectl -n security exec -it kanidm-client -- kanidm system oauth2 delete "$1" -D idm_admin

[doc('Add a redirect URL to an OAuth2 client — must match the app callback exactly (positional args: name url)')]
[group('oauth2')]
[script]
oauth2-add-redirect-url name url: ensure-client
    kubectl -n security exec kanidm-client -- kanidm system oauth2 add-redirect-url "$1" "$2" -D idm_admin

[doc('Remove a redirect URL from an OAuth2 client (positional args: name url)')]
[group('oauth2')]
[script]
oauth2-remove-redirect-url name url: ensure-client
    kubectl -n security exec kanidm-client -- kanidm system oauth2 remove-redirect-url "$1" "$2" -D idm_admin

[doc('Map a group to the scopes it grants — members-only login gate (positional args: name group scopes... e.g. openid profile email groups)')]
[group('oauth2')]
[script]
oauth2-update-scope-map name group +scopes: ensure-client
    kubectl -n security exec kanidm-client -- kanidm system oauth2 update-scope-map "$@" -D idm_admin

[doc('Remove a group→scopes mapping (positional args: name group)')]
[group('oauth2')]
[script]
oauth2-delete-scope-map name group: ensure-client
    kubectl -n security exec kanidm-client -- kanidm system oauth2 delete-scope-map "$1" "$2" -D idm_admin

[doc('Show the client basic secret — deliver it via 1Password → ExternalSecret, never commit it')]
[group('oauth2')]
[script]
oauth2-show-secret name: ensure-client
    kubectl -n security exec kanidm-client -- kanidm system oauth2 show-basic-secret "$1" -D idm_admin

[doc('Reset the client basic secret — the consuming app breaks until its stored secret is updated')]
[group('oauth2')]
[script]
oauth2-reset-secret name: ensure-client
    kubectl -n security exec kanidm-client -- kanidm system oauth2 reset-basic-secret "$1" -D idm_admin

[doc('Send the short username instead of SPN (user@domain) as preferred_username')]
[group('oauth2')]
[script]
oauth2-prefer-short-username name: ensure-client
    kubectl -n security exec kanidm-client -- kanidm system oauth2 prefer-short-username "$1" -D idm_admin

[doc('Disable the first-authorize OIDC consent prompt (re-enable: just kanidm run system oauth2 enable-consent-prompt <name> -D idm_admin)')]
[group('oauth2')]
[script]
oauth2-disable-consent-prompt name: ensure-client
    kubectl -n security exec kanidm-client -- kanidm system oauth2 disable-consent-prompt "$1" -D idm_admin

[doc('Interactive wizard: create a fully wired OAuth2 client (type, redirects, access group, scopes, secret) — offers defaults, one summary confirm; re-run skips create and converges the wiring')]
[group('oauth2')]
[script]
oauth2-new-wf: ensure-login
    name="$(gum input --header 'Client name (short, lowercase)' --placeholder 'grafana')"
    [ -n "${name}" ] || { just log error "Client name is required"; exit 1; }
    exists=''
    if just -q kanidm entity-exists oauth2 "${name}"; then
      exists='yes'
      just log info "OAuth2 client '${name}' already exists — create will be skipped, the remaining steps converge its wiring"
    fi
    domain="$(yq -r '.data.PUBLIC_DOMAIN' '{{ cluster_settings }}')"
    displayname=''; type=''; origin=''
    if [ -z "${exists}" ]; then
      displayname="$(gum input --header 'Display name' --value "${name}")"
      type="$(gum choose --header 'Client type' confidential public)"
      origin="$(gum input --header 'Origin (landing) URL' --value "https://${name}.${domain}")"
    fi
    redirects=()
    url="$(gum input --header 'Redirect URL (exact app callback; empty to skip)' --value "${origin:-https://${name}.${domain}}/oauth2/callback")"
    if [ -n "${url}" ]; then redirects+=("${url}"); fi
    while gum confirm --default=false 'Add another redirect URL?'; do
      url="$(gum input --header 'Redirect URL')"
      if [ -n "${url}" ]; then redirects+=("${url}"); fi
    done
    group="$(gum input --header 'Access group (scope map = login gate)' --value "${name}_users")"
    [ -n "${group}" ] || { just log error "Access group is required"; exit 1; }
    create_group=''
    members=''
    if ! just -q kanidm entity-exists group "${group}"; then
      gum confirm "Group '${group}' does not exist — create it?" \
        || { just log error "An existing access group is required — aborting, nothing changed"; exit 1; }
      create_group='yes'
      members="$(gum input --header 'Members to add (space-separated; empty to skip)' --value "${USER}")"
    fi
    scopes="$(gum input --header 'Scopes granted to the group' --value 'openid profile email groups')"
    short_username='no'
    if gum confirm --default=true 'Prefer short username (instead of user@domain SPN)?'; then short_username='yes'; fi
    consent_prompt='disabled'
    if ! gum confirm --default=true 'Disable the OIDC consent prompt (consent is implicit in a single-operator homelab)?'; then consent_prompt='enabled'; fi
    printf '\n── Summary ─────────────────────────────\n'
    if [ -z "${exists}" ]; then
      printf 'client:   %s (%s) — "%s"\n' "${name}" "${type}" "${displayname}"
      printf 'origin:   %s\n' "${origin}"
    else
      printf 'client:   %s (existing — create skipped)\n' "${name}"
    fi
    if [ "${#redirects[@]}" -gt 0 ]; then printf 'redirect: %s\n' "${redirects[@]}"; fi
    if [ -n "${create_group}" ]; then
      printf 'group:    %s (new%s)\n' "${group}" "${members:+, members: ${members}}"
    else
      printf 'group:    %s (existing)\n' "${group}"
    fi
    printf 'scopes:   %s\n' "${scopes}"
    printf 'prefer-short-username: %s\n' "${short_username}"
    printf 'consent prompt: %s\n\n' "${consent_prompt}"
    gum confirm 'Proceed?' || { just log info "Aborted — nothing changed"; exit 0; }
    if [ -n "${create_group}" ]; then
      just kanidm group-create "${group}"
      just -q kanidm entity-exists group "${group}" || { just log error "Group creation failed — see the error above"; exit 1; }
      if [ -n "${members}" ]; then just kanidm group-add-members "${group}" ${members}; fi
    fi
    if [ -z "${exists}" ]; then
      if [ "${type}" = 'confidential' ]; then
        just kanidm oauth2-create "${name}" "${displayname}" "${origin}"
      else
        just kanidm oauth2-create-public "${name}" "${displayname}" "${origin}"
      fi
      just -q kanidm entity-exists oauth2 "${name}" || { just log error "Client creation failed — see the error above"; exit 1; }
    fi
    if [ "${#redirects[@]}" -gt 0 ]; then
      for url in "${redirects[@]}"; do just kanidm oauth2-add-redirect-url "${name}" "${url}"; done
    fi
    just kanidm oauth2-update-scope-map "${name}" "${group}" ${scopes}
    if [ "${short_username}" = 'yes' ]; then just kanidm oauth2-prefer-short-username "${name}"; fi
    if [ "${consent_prompt}" = 'disabled' ]; then just kanidm oauth2-disable-consent-prompt "${name}"; fi
    if [ "${type}" = 'confidential' ]; then
      just log info "Basic secret below — store it in 1Password for the app ExternalSecret, never in git"
      just kanidm oauth2-show-secret "${name}"
    fi
