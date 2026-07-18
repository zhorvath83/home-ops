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
