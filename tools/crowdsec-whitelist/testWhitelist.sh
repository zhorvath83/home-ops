#!/usr/bin/env bash
# Replays fixtures.txt through `cscli explain` in the crowdsec agent pod and checks each line's whitelist verdict.
# Usage: testWhitelist.sh [candidate|live]
#   candidate (default): stages the s02-enrich whitelists from the HelmRelease into a scratch config under /tmp in the pod
#   live: uses the agent's deployed /etc/crowdsec
set -euo pipefail

MODE="${1:-candidate}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
HELMRELEASE="$REPO_ROOT/kubernetes/apps/crowdsec/crowdsec/app/helmrelease.yaml"
FIXTURES="$HERE/fixtures.txt"
NAMESPACE=crowdsec
SCRATCH=/tmp/crowdsec-whitelist-test

case "$MODE" in
  candidate | live) ;;
  *) echo "unknown mode: $MODE (expected candidate or live)" >&2; exit 2 ;;
esac

pod="$(kubectl -n "$NAMESPACE" get pods -l k8s-app=crowdsec,type=agent -o jsonpath='{.items[0].metadata.name}')"
[ -n "$pod" ] || { echo "no crowdsec agent pod found in namespace $NAMESPACE" >&2; exit 1; }
podExec() { kubectl -n "$NAMESPACE" exec -i "$pod" -c crowdsec-agent -- "$@"; }

configArgs=()
if [ "$MODE" = candidate ]; then
  trap 'podExec rm -rf "$SCRATCH" || echo "cleanup of $SCRATCH in $pod failed" >&2' EXIT
  # No credentials are copied: explain runs crowdsec without the API.
  podExec sh -ec "rm -rf $SCRATCH && mkdir -p $SCRATCH
    cd /etc/crowdsec && cp -a config.yaml simulation.yaml parsers postoverflows scenarios collections patterns contexts $SCRATCH/
    ln -s /etc/crowdsec/hub $SCRATCH/hub
    sed -i 's#config_dir: /etc/crowdsec/#config_dir: $SCRATCH/#; s#simulation_path: /etc/crowdsec/#simulation_path: $SCRATCH/#' $SCRATCH/config.yaml"
  staged=0
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    yq -r ".spec.values.config.parsers.\"s02-enrich\".\"$file\"" "$HELMRELEASE" | podExec sh -c "cat > $SCRATCH/parsers/s02-enrich/$file"
    staged=$((staged + 1))
  done < <(yq -r '.spec.values.config.parsers."s02-enrich" // {} | keys | .[]' "$HELMRELEASE")
  echo "staged $staged s02-enrich file(s) from the HelmRelease into $pod:$SCRATCH"
  configArgs=(-c "$SCRATCH/config.yaml")
fi

failures=0
total=0
while IFS='|' read -r expect name line; do
  case "$expect" in '' | \#*) continue ;; esac
  total=$((total + 1))
  output="$(podExec cscli "${configArgs[@]}" explain --log "$line" --type containerd --labels program:envoy --color no 2>&1 </dev/null)" || true
  verdict=keep
  grep -q 'whitelisted' <<<"$output" && verdict=wl
  if grep -qiE 'runtime error|level=(error|fatal)' <<<"$output"; then
    verdict=error
  fi
  if [ "$verdict" = "$expect" ]; then
    printf 'ok    %-32s %s\n' "$name" "$verdict"
  else
    printf 'FAIL  %-32s expected %s, got %s\n' "$name" "$expect" "$verdict"
    printf '      | %s\n' "${output//$'\n'/$'\n'      | }"
    failures=$((failures + 1))
  fi
done <"$FIXTURES"

echo "$((total - failures))/$total passed ($MODE)"
[ "$failures" -eq 0 ]
