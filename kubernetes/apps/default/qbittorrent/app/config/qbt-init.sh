#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

CONFIG_DIR="/config/qBittorrent"
CONFIG_FILE="${CONFIG_DIR}/qBittorrent.conf"
DEFAULT_CONFIG="/defaults/qBittorrent.conf"
IPFILTER_FILE="/ipfilter/ipfilter.dat"
IPFILTER_URL="https://github.com/DavidMoore/ipfilter/releases/download/lists/ipfilter.dat.gz"

# --- Overwrite config with image default ---
mkdir -p "${CONFIG_DIR}"

if [[ -f "${DEFAULT_CONFIG}" ]]; then
  echo "Overwriting config with image default..."
  cp "${DEFAULT_CONFIG}" "${CONFIG_FILE}"
else
  echo "WARNING: Default config not found at ${DEFAULT_CONFIG}."
fi

# --- Remove stale config files now managed via API ---
rm -f "${CONFIG_DIR}/categories.json" "${CONFIG_DIR}/watched_folders.json"

# --- Ensure per-category watchdir directories exist ---
for dir in misc movies shows documentaries ebooks; do
  mkdir -p "/media/downloads/watchdir/${dir}"
done

# --- Download ipfilter ---
echo "Downloading ipfilter.dat..."
if curl --silent --location --fail "${IPFILTER_URL}" | gunzip > "${IPFILTER_FILE}" 2>/dev/null; then
  LINE_COUNT=$(wc -l < "${IPFILTER_FILE}")
  echo "ipfilter.dat downloaded (${LINE_COUNT} lines)."
else
  echo "WARNING: Failed to download ipfilter.dat. qBittorrent will start without IP filtering."
  rm -f "${IPFILTER_FILE}"
fi
