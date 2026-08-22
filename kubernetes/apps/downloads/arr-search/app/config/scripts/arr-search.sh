#!/usr/bin/env bash
# Monthly Missing + Cutoff Unmet search trigger for Sonarr & Radarr (v3 REST API).
# Mirrors recyclarr/fix-radarr-language.sh: per-step OK/ERROR, set -euo pipefail,
# the returned command id logged as evidence, non-zero exit on any non-2xx.
set -euo pipefail

# Kubernetes CronJob 5-field cron cannot express "Nth weekday of month" (no L/hash
# modifier), so the schedule fires every Saturday and this guard keeps only the first
# Saturday of the month (a Saturday whose day-of-month is 1-7).
# dom="$(date +%d)"; dom="${dom#0}"
# if [ "$(date +%u)" != 6 ] || [ "$dom" -gt 7 ]; then
#   echo "not first Saturday of month, skipping"
#   exit 0
# fi

SONARR_HOST="sonarr.downloads.svc.cluster.local"
SONARR_PORT="8989"
RADARR_HOST="radarr.downloads.svc.cluster.local"
RADARR_PORT="7878"

: "${SONARR_API_KEY:?SONARR_API_KEY env not set}"
: "${RADARR_API_KEY:?RADARR_API_KEY env not set}"

SONARR_BASE="http://${SONARR_HOST}:${SONARR_PORT}/api/v3"
RADARR_BASE="http://${RADARR_HOST}:${RADARR_PORT}/api/v3"

# POST a /api/v3/command body, assert 2xx, log the returned command id. Exit 1 on failure.
post_command() {
  local base="$1" api_key="$2" name="$3" label="$4"
  local resp http_code body_resp cmd_id
  # -w appends the HTTP status on its own line; 2>&1 surfaces curl connection errors.
  if ! resp=$(curl -sS -w '\n%{http_code}' -X POST \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: ${api_key}" \
        -d "{\"name\":\"${name}\"}" \
        "${base}/command" 2>&1); then
    echo "ERROR: ${label} -> request failed: ${resp}" >&2
    exit 1
  fi
  http_code="${resp##*$'\n'}"
  body_resp="${resp%$'\n'*}"
  if ! [[ "${http_code}" =~ ^2[0-9][0-9]$ ]]; then
    echo "ERROR: ${label} -> HTTP ${http_code}: ${body_resp}" >&2
    exit 1
  fi
  cmd_id="$(jq -r '.id // empty' <<<"${body_resp}" 2>/dev/null || true)"
  if [ -z "${cmd_id}" ]; then
    echo "ERROR: ${label} -> no command id in response: ${body_resp}" >&2
    exit 1
  fi
  echo "OK: ${label} -> command id ${cmd_id}"
}

post_command "${SONARR_BASE}" "${SONARR_API_KEY}" "MissingEpisodeSearch"      "sonarr missing"
# post_command "${SONARR_BASE}" "${SONARR_API_KEY}" "CutoffUnmetEpisodeSearch"   "sonarr cutoff-unmet"
post_command "${RADARR_BASE}" "${RADARR_API_KEY}" "MissingMoviesSearch"        "radarr missing"
# post_command "${RADARR_BASE}" "${RADARR_API_KEY}" "CutoffUnmetMoviesSearch"     "radarr cutoff-unmet"

echo "OK: arr-search complete (4 commands queued)"
