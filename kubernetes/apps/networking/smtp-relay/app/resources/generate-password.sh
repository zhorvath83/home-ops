#!/bin/sh
set -e

echo "Starting password file generation..."
echo "Username: $SMTP_RELAY_USERNAME"

if [ -z "$SMTP_RELAY_USERNAME" ]; then
    echo "ERROR: SMTP_RELAY_USERNAME is empty!"
    exit 1
fi

if [ -z "$SMTP_RELAY_PASSWORD" ]; then
    echo "ERROR: SMTP_RELAY_PASSWORD is empty!"
    exit 1  
fi

# Generate hash using printf for consistency
# The maddy hash command outputs: bcrypt:$2a$10$...
HASHED_PASSWORD=$(printf "%s" "$SMTP_RELAY_PASSWORD" | maddy hash --password -)
echo "Hash generated: $HASHED_PASSWORD"

# Create password file in the format: username:hash
# The hash already includes the algorithm prefix (bcrypt:)
echo "$SMTP_RELAY_USERNAME:$HASHED_PASSWORD" > /auth/smtp_passwd
chmod 600 /auth/smtp_passwd

echo "Password file created successfully"
echo "File contents:"
cat /auth/smtp_passwd
