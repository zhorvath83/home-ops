#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

QBT_URL="http://127.0.0.1:8080"
CONFIG_FILE="/scripts/qbt-config.json"
RETRY_INTERVAL=2
MAX_RETRIES=60

log() {
  local level="$1"; shift
  local ts
  ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  if [[ "${level}" == "INFO" ]]; then
    printf '%s %s %s\n' "${ts}" "${level}" "$*"
  else
    printf '%s %s %s\n' "${ts}" "${level}" "$*" >&2
  fi
}

log INFO "waiting for API at ${QBT_URL}"
for attempt in $(seq 1 "${MAX_RETRIES}"); do
  if curl --silent --fail "${QBT_URL}/api/v2/app/version" >/dev/null 2>&1; then
    log INFO "API ready (attempt ${attempt}/${MAX_RETRIES})"
    break
  fi
  if [[ "${attempt}" -eq "${MAX_RETRIES}" ]]; then
    log ERROR "API not ready after $((MAX_RETRIES * RETRY_INTERVAL))s"
    exit 1
  fi
  sleep "${RETRY_INTERVAL}"
done

# Accepts 2xx and 409 (idempotent "already exists").
qbt_call() {
  local label="$1"; shift
  local endpoint="$1"; shift
  local http_code
  http_code="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --request POST \
    --header "Referer: ${QBT_URL}" \
    "$@" \
    "${QBT_URL}${endpoint}")"

  if (( http_code < 200 )) || (( http_code >= 400 && http_code != 409 )); then
    log ERROR "${label} http=${http_code}"
    return 1
  fi
  if (( http_code == 409 )); then
    log WARN "${label} http=${http_code} exists"
  else
    log INFO "${label} http=${http_code}"
  fi
}

[[ -z "${QBT_WEBUI_USERNAME:-}" ]] && log WARN "QBT_WEBUI_USERNAME unset, web_ui_username will not be set"
[[ -z "${QBT_WEBUI_PASSWORD:-}" ]] && log WARN "QBT_WEBUI_PASSWORD unset, web_ui_password will not be set"

preferences="$(jq -c \
  --arg user "${QBT_WEBUI_USERNAME:-}" \
  --arg pass "${QBT_WEBUI_PASSWORD:-}" \
  '.preferences
   + (if $user != "" then {web_ui_username: $user} else {} end)
   + (if $pass != "" then {web_ui_password: $pass} else {} end)' \
  "${CONFIG_FILE}")"

log INFO "applying preferences"
qbt_call "setPreferences" "/api/v2/app/setPreferences" \
  --data-urlencode "json=${preferences}"

save_path="$(jq -r '.preferences.save_path' "${CONFIG_FILE}")"
save_path="${save_path%/}"
mapfile -t categories < <(jq -r '.categories[]' "${CONFIG_FILE}")

log INFO "creating ${#categories[@]} categories under ${save_path}"
for category in "${categories[@]}"; do
  qbt_call "createCategory/${category}" "/api/v2/torrents/createCategory" \
    --data-urlencode "category=${category}" \
    --data-urlencode "savePath=${save_path}/${category}"
done

log INFO "done"
