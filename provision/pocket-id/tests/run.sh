#!/usr/bin/env bash
# Fixture tests for lint.sh (L1) and lint-rendered.sh (L2): each case mutates a copy of
# fixtures/base and asserts the exit code plus the rule tag in the output.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base="${here}/fixtures/base"
lint="${here}/../lint.sh"
lint_rendered="${here}/../lint-rendered.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/pocket-id-tests.XXXXXX")"
trap 'rm -rf "${scratch}"' EXIT

passed=0
failed=0

# check <name> <layer: l1|l2> <expected exit> <expected output regex> <mutation script>
check() {
    local name="$1" layer="$2" want_rc="$3" want_re="$4" mutation="$5"
    local dir="${scratch}/${name}" out rc
    cp -R "${base}" "${dir}"
    (cd "${dir}" && eval "${mutation}")
    set +e
    if [ "${layer}" = l1 ]; then
        out="$(REPO_ROOT="${dir}" REGISTRY="${dir}/clients.yaml" "${lint}" 2>&1)"
    else
        out="$(REPO_ROOT="${dir}" REGISTRY="${dir}/clients.yaml" "${lint_rendered}" "${dir}/rendered.json" 2>&1)"
    fi
    rc=$?
    set -e
    if [ "${rc}" -eq "${want_rc}" ] && grep -qE -- "${want_re}" <<<"${out}"; then
        passed=$((passed + 1))
        printf '  ok   %s\n' "${name}"
    else
        failed=$((failed + 1))
        printf '  FAIL %s (rc=%s, want %s, pattern %s)\n%s\n' "${name}" "${rc}" "${want_rc}" "${want_re}" "${out}" | sed 's/^/       /'
    fi
}

gated_hr=kubernetes/apps/web/gated/app/helmrelease.yaml
gated_ks=kubernetes/apps/web/gated/ks.yaml
native_ks=kubernetes/apps/web/native/ks.yaml
native_rt=kubernetes/apps/web/native/app/httproute.yaml
hook_rt=kubernetes/apps/net/hook/app/httproute.yaml
redirect_rt=kubernetes/apps/net/redirect/app/redirect.yaml

new_route() { # file host section
    cat >"$1" <<EOF
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: extra
spec:
  hostnames:
    - "$2"
  parentRefs:
    - name: envoy-internal
      sectionName: $3
  rules:
    - backendRefs:
        - name: extra
          port: 80
EOF
}
export -f new_route

echo "L1 - static"
check clean l1 0 'agree' ':'
check unclaimed-host l1 1 '\[R2\].*foo' "new_route kubernetes/apps/web/native/app/extra.yaml 'foo.\${PUBLIC_DOMAIN}' https"
check nested-path-unclaimed l1 1 '\[R2\].*vlogs' "yq -i 'del(.clients.nested)' clients.yaml"
check claimed-twice l1 1 '\[REG\].*gate' "yq -i '.exempt.gate = {\"reason\": \"x\", \"control\": \"y\", \"gateways\": [\"envoy-internal\"]}' clients.yaml"
check unresolved-var l1 1 '\[R1\]' "yq -i '.spec.hostnames[0] = \"\${NOPE}.\${PUBLIC_DOMAIN}\"' ${native_rt}"
check foreign-domain l1 1 '\[R1\].*other\.org' "yq -i '.spec.hostnames[0] = \"hook.other.org\"' ${hook_rt}"
check bare-host l1 1 '\[R1\]' "yq -i '.spec.hostnames[0] = \"hook\"' ${hook_rt}"
check no-owner-ks l1 1 '\[OWN\]' "mkdir -p kubernetes/stray && new_route kubernetes/stray/r.yaml 'native.\${PUBLIC_DOMAIN}' https"
check envoy-without-component l1 1 '\[R3\].*gate' "yq -i 'del(.spec.components)' ${gated_ks}"
check envoy-subdomain-mismatch l1 1 '\[R3\].*gate' "yq -i '.spec.values.route.app.hostnames[0] = \"gate.\${PUBLIC_DOMAIN}\" | .' ${gated_hr} && yq -i '.spec.postBuild.substitute.APP_SUBDOMAIN = \"other\"' ${gated_ks}"
check envoy-app-mismatch l1 1 '\[R3\].*gate' "yq -i '.spec.postBuild.substitute.APP = \"wrong\"' ${gated_ks}"
check envoy-two-hostnames l1 1 '\[R3\].*one hostname' "yq -i '.spec.values.route.app.hostnames += [\"native.\${PUBLIC_DOMAIN}\"]' ${gated_hr}"
check envoy-two-routes l1 1 '\[R3\].*more than one route' "new_route kubernetes/apps/web/gated/app/extra.yaml '\${APP_SUBDOMAIN}.\${PUBLIC_DOMAIN}' https"
check native-with-component l1 1 '\[R4\].*native' "yq -i '.spec.components = [\"../../../../components/gateway-oidc\"]' ${native_ks}"
check exempt-wrong-gateway l1 1 '\[R5\].*hook.*envoy-internal' "yq -i '.spec.parentRefs += [{\"name\": \"envoy-internal\", \"sectionName\": \"https\"}]' ${hook_rt}"
check exempt-no-reason l1 1 '\[REG\].*hook.*reason' "yq -i 'del(.exempt.hook.reason)' clients.yaml"
check exempt-no-control l1 1 '\[REG\].*hook.*control' "yq -i '.exempt.hook.control = \"\"' clients.yaml"
check exempt-no-gateways l1 1 '\[REG\].*hook.*gateways' "yq -i '.exempt.hook.gateways = []' clients.yaml"
check temporary-no-tracking l1 1 '\[REG\].*hook.*tracking' "yq -i '.exempt.hook.temporary = true' clients.yaml"
check temporary-warns l1 0 '\[TEMP\].*hook' "yq -i '.exempt.hook.temporary = true | .exempt.hook.tracking = \"docs/roadmap/x\"' clients.yaml"
check redirect-with-backend l1 1 '\[R5\].*backend' "yq -i '.spec.rules[0].backendRefs = [{\"name\": \"x\", \"port\": 80}]' ${redirect_rt}"
check redirect-on-https l1 1 '\[R5\].*http' "yq -i '.spec.parentRefs[0].sectionName = \"https\"' ${redirect_rt}"
check stale-client l1 1 '\[R6\].*ghost' "yq -i '.clients.ghost = {\"gate\": \"native\", \"subdomain\": \"ghost\", \"callback_path\": \"/\", \"groups\": [\"g1\"]}' clients.yaml"
check stale-exempt l1 1 '\[R6\].*ghost' "yq -i '.exempt.ghost = {\"reason\": \"x\", \"control\": \"y\", \"gateways\": [\"envoy-internal\"]}' clients.yaml"
check catch-all-on-https l1 1 '\[R7\]' "yq -i 'del(.spec.hostnames) | .spec.parentRefs[0].sectionName = \"https\"' ${redirect_rt}"
check empty-groups l1 1 '\[REG\].*native.*group' "yq -i '.clients.native.groups = []' clients.yaml"
check undefined-group l1 1 '\[REG\].*undefined group' "yq -i '.clients.native.groups += [\"nope\"]' clients.yaml"
check top-level-list-doc l1 0 'agree' "printf -- '---\\n- op: add\\n  path: /x\\n' > kubernetes/apps/web/native/app/patch.yaml"
check parse-error l1 1 '\[PARSE\]' "printf 'a: [\\n' > kubernetes/apps/web/native/app/broken.yaml"

echo "L2 - rendered"
check rendered-clean l2 0 'rendered' ':'
check rendered-empty l2 1 '\[L2\.1\]' "echo '[]' > rendered.json"
check rendered-unsubstituted l2 1 '\[L2\.1\]' "jq '(.[] | select(.metadata.name == \"hook\") | .spec.hostnames[0]) = \"\${X}.example.com\"' rendered.json > r && mv r rendered.json"
check rendered-extra-host l2 1 '\[L2\.2\].*extra' "jq '. + [(.[] | select(.metadata.name == \"hook\") | .metadata.name = \"extra\" | .spec.hostnames = [\"extra.example.com\"])]' rendered.json > r && mv r rendered.json"
check rendered-missing-host l2 1 '\[L2\.2\].*hook' "jq 'map(select(.metadata.name != \"hook\"))' rendered.json > r && mv r rendered.json"
check rendered-wrong-target l2 1 '\[L2\.3\].*gate' "jq '(.[] | select(.kind == \"SecurityPolicy\") | .spec.targetRefs[0].name) = \"other\"' rendered.json > r && mv r rendered.json"
check rendered-no-mergetype l2 1 '\[L2\.3\].*gate' "jq '(.[] | select(.kind == \"SecurityPolicy\") | .spec) |= del(.mergeType)' rendered.json > r && mv r rendered.json"
check rendered-wrong-redirect l2 1 '\[L2\.3\].*gate' "jq '(.[] | select(.kind == \"SecurityPolicy\") | .spec.oidc.redirectURL) = \"https://evil.example.com/oauth2/callback\"' rendered.json > r && mv r rendered.json"
check rendered-native-with-oidc l2 1 '\[L2\.4\].*native' "jq '. + [(.[] | select(.kind == \"SecurityPolicy\") | .metadata.name = \"native-oidc\" | .spec.targetRefs[0].name = \"native\" | .spec.oidc.redirectURL = \"https://native.example.com/oauth2/callback\")]' rendered.json > r && mv r rendered.json"

printf '\n%s passed, %s failed\n' "${passed}" "${failed}"
[ "${failed}" -eq 0 ]
