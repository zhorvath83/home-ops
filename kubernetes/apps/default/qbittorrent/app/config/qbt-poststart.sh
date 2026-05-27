#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

QBT_URL="http://127.0.0.1:8080"
CONFIG_FILE="/scripts/qbt-config.json"
RETRY_INTERVAL=2
MAX_RETRIES=60

# Wait for qBittorrent API
echo "Waiting for qBittorrent API at ${QBT_URL}..."
for i in $(seq 1 "${MAX_RETRIES}"); do
  if curl --silent --fail "${QBT_URL}/api/v2/app/version" > /dev/null 2>&1; then
    echo "qBittorrent API is ready (attempt ${i})."
    break
  fi
  if [[ "${i}" -eq "${MAX_RETRIES}" ]]; then
    echo "ERROR: qBittorrent API did not become ready within $((MAX_RETRIES * RETRY_INTERVAL)) seconds."
    exit 1
  fi
  sleep "${RETRY_INTERVAL}"
done

# Apply API calls from config
CALL_COUNT=$(jq 'length' "${CONFIG_FILE}")
echo "Processing ${CALL_COUNT} API calls..."

for ((i=0; i<CALL_COUNT; i++)); do
  endpoint=$(jq -r ".[${i}].endpoint" "${CONFIG_FILE}")
  method=$(jq -r ".[${i}].method" "${CONFIG_FILE}")

  if [[ "${method}" == "json" ]]; then
    payload=$(jq -c ".[${i}].payload" "${CONFIG_FILE}")
    echo "Calling ${endpoint} (json)..."
    http_code=$(curl --silent --output /dev/null --write-out '%{http_code}' \
      --request POST \
      --header "Referer: ${QBT_URL}" \
      --data-urlencode "json=${payload}" \
      "${QBT_URL}${endpoint}")
  else
    echo "Calling ${endpoint} (form)..."
    curl_args=()
    while IFS=$'\t' read -r key value; do
      curl_args+=("--data-urlencode" "${key}=${value}")
    done < <(jq -r ".[${i}].payload | to_entries[] | [.key, .value] | @tsv" "${CONFIG_FILE}")
    http_code=$(curl --silent --output /dev/null --write-out '%{http_code}' \
      --request POST \
      --header "Referer: ${QBT_URL}" \
      "${curl_args[@]}" \
      "${QBT_URL}${endpoint}")
  fi

  # Accept 2xx-3xx and 409 (Conflict = idempotent success); reject 000, 4xx (except 409), 5xx
  if [[ "${http_code}" -lt 200 || ("${http_code}" -ge 400 && "${http_code}" -ne 409) ]]; then
    echo "ERROR: ${endpoint} returned HTTP ${http_code}"
    exit 1
  fi
  echo "  ${endpoint} -> HTTP ${http_code}"
done

echo "PostStart configuration complete."
