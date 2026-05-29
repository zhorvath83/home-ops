#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

IPFILTER_FILE="/ipfilter/ipfilter.dat"
IPFILTER_URL="https://github.com/DavidMoore/ipfilter/releases/download/lists/ipfilter.dat.gz"
# --- Download ipfilter ---
echo "Downloading ipfilter.dat..."
if curl --silent --location --fail "${IPFILTER_URL}" | gunzip > "${IPFILTER_FILE}" 2>/dev/null; then
  LINE_COUNT=$(wc -l < "${IPFILTER_FILE}")
  echo "ipfilter.dat downloaded (${LINE_COUNT} lines)."
else
  echo "WARNING: Failed to download ipfilter.dat. qBittorrent will start without IP filtering."
  rm -f "${IPFILTER_FILE}"
fi
