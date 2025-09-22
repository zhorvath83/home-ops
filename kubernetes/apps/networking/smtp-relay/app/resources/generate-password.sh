#!/bin/sh
set -e

echo "Starting password file generation..."
echo "Username: $SMTP_RELAY_USERNAME"
echo "Password length: ${#SMTP_RELAY_PASSWORD}"
echo "Password first 3 chars: $(echo "$SMTP_RELAY_PASSWORD" | cut -c1-3)..."
echo "Password last 3 chars: ...$(echo "$SMTP_RELAY_PASSWORD" | tail -c 4)"

if [ -z "$SMTP_RELAY_USERNAME" ]; then
    echo "ERROR: SMTP_RELAY_USERNAME is empty!"
    exit 1
fi

if [ -z "$SMTP_RELAY_PASSWORD" ]; then
    echo "ERROR: SMTP_RELAY_PASSWORD is empty!"
    exit 1
fi

# Test with printf instead of echo -n  
# printf is more reliable across different shells
HASHED_PASSWORD=$(printf "%s" "$SMTP_RELAY_PASSWORD" | maddy hash --password -)
echo "Hash generated successfully"
echo "Full hash: $HASHED_PASSWORD"

# Create password file
echo "$SMTP_RELAY_USERNAME:$HASHED_PASSWORD" > /auth/smtp_passwd
chmod 600 /auth/smtp_passwd

echo "Password file created successfully"
echo "File contents:"
cat /auth/smtp_passwd
echo ""
echo "File permissions:"
ls -la /auth/smtp_passwd

# Double check - try to verify the password
echo ""
echo "Testing hash verification:"
printf "%s" "$SMTP_RELAY_PASSWORD" | maddy hash --password - > /tmp/test_hash 2>&1 || true
echo "Test hash result: $(cat /tmp/test_hash 2>/dev/null || echo 'Could not generate test hash')"
