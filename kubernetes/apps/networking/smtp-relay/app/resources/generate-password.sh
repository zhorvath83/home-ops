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

# Hash jelszó bcrypt-tel
HASHED_PASSWORD=$(maddy hash --hash "bcrypt" --password "$SMTP_RELAY_PASSWORD")
echo "Hash generated: $HASHED_PASSWORD"

# Jelszófájl létrehozása
echo "$SMTP_RELAY_USERNAME:$HASHED_PASSWORD" > /auth/smtp_passwd
chown maddy:maddy /auth/smtp_passwd || true
chmod 640 /auth/smtp_passwd

echo "Password file created successfully"
cat /auth/smtp_passwd
