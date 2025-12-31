#!/bin/bash
# Rauthy 1Password secrets setup script
# This script generates and stores required secrets for Rauthy in 1Password
#
# Prerequisites:
# - 1Password CLI (op) installed and configured
# - Logged in to 1Password: eval $(op signin)
# - "rauthy" item already exists in HomeOps vault

set -eu

VAULT="HomeOps"
ITEM="rauthy"

echo "🔐 Generating Rauthy secrets..."

# Generate cluster secrets (48 char alphanumeric)
CLUSTER_SECRET_RAFT=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c48 || true)
CLUSTER_SECRET_API=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c48 || true)

# Generate encryption key (format: id/base64key)
ENC_KEY_ID=$(openssl rand -hex 4)
ENC_KEY_VALUE=$(openssl rand -base64 32)
ENC_KEYS="${ENC_KEY_ID}/${ENC_KEY_VALUE}"

echo "📝 Generated values:"
echo "  ENC_KEY_ACTIVE: ${ENC_KEY_ID}"
echo "  (Other values are sensitive and not displayed)"

# Prompt for email addresses
echo ""
read -p "Enter Bootstrap Admin Email: " BOOTSTRAP_ADMIN_EMAIL
read -p "Enter Event Notification Email: " EVENT_EMAIL

echo ""
echo "🔄 Updating 1Password item '${ITEM}' in vault '${VAULT}'..."

# Update 1Password item with all fields
op item edit "${ITEM}" --vault="${VAULT}" \
  "CLUSTER_SECRET_RAFT=${CLUSTER_SECRET_RAFT}" \
  "CLUSTER_SECRET_API=${CLUSTER_SECRET_API}" \
  "ENC_KEYS=${ENC_KEYS}" \
  "ENC_KEY_ACTIVE=${ENC_KEY_ID}" \
  "BOOTSTRAP_ADMIN_EMAIL=${BOOTSTRAP_ADMIN_EMAIL}" \
  "EVENT_EMAIL=${EVENT_EMAIL}"

echo ""
echo "✅ Rauthy secrets successfully stored in 1Password!"
echo ""
echo "📋 Summary of created fields:"
echo "  - CLUSTER_SECRET_RAFT (48 char random)"
echo "  - CLUSTER_SECRET_API (48 char random)"
echo "  - ENC_KEYS (encryption key with ID)"
echo "  - ENC_KEY_ACTIVE (encryption key ID)"
echo "  - BOOTSTRAP_ADMIN_EMAIL"
echo "  - EVENT_EMAIL"
