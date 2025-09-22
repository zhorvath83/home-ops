#!/bin/sh
set -e

echo "Starting password file generation..."
echo "Username: $SMTP_RELAY_USERNAME"
echo "Password length: ${#SMTP_RELAY_PASSWORD}"
echo "Password first 3 chars: $(echo "$SMTP_RELAY_PASSWORD" | cut -c1-3)..."

if [ -z "$SMTP_RELAY_USERNAME" ]; then
    echo "ERROR: SMTP_RELAY_USERNAME is empty!"
    exit 1
fi

if [ -z "$SMTP_RELAY_PASSWORD" ]; then
    echo "ERROR: SMTP_RELAY_PASSWORD is empty!"
    exit 1
fi

# Generate hash using printf for consistency
FULL_HASH=$(printf "%s" "$SMTP_RELAY_PASSWORD" | maddy hash --password -)
echo "Full hash from maddy: $FULL_HASH"

# The maddy hash command returns "bcrypt:$2a$10$..." but table.file might expect just the hash
# Let's try removing the "bcrypt:" prefix
HASH_WITHOUT_PREFIX=$(echo "$FULL_HASH" | sed 's/^bcrypt://')
echo "Hash without prefix: $HASH_WITHOUT_PREFIX"

# Try with full format first
echo "$SMTP_RELAY_USERNAME:$FULL_HASH" > /auth/smtp_passwd
chmod 600 /auth/smtp_passwd

echo "Password file created with full format:"
cat /auth/smtp_passwd
echo ""

# Also create a version without the bcrypt: prefix for testing
echo "$SMTP_RELAY_USERNAME:$HASH_WITHOUT_PREFIX" > /auth/smtp_passwd_no_prefix
chmod 600 /auth/smtp_passwd_no_prefix
echo "Alternative file without prefix:"
cat /auth/smtp_passwd_no_prefix
echo ""

echo "File permissions:"
ls -la /auth/
