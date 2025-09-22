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

# Generate hash
HASHED_PASSWORD=$(echo -n "$SMTP_RELAY_PASSWORD" | maddy hash --password -)
echo "Hash generated successfully"

# Create password file
echo "$SMTP_RELAY_USERNAME:$HASHED_PASSWORD" > /auth/smtp_passwd
chmod 600 /auth/smtp_passwd

echo "Password file created successfully"
echo "Content (first 50 chars): $(head -c 50 /auth/smtp_passwd)..."
