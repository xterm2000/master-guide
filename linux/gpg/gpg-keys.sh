#!/bin/bash
PASS="password"
NAME="user"
EMAIL="user@example.com"

gpg --batch --passphrase "$PASS" --pinentry-mode loopback \
    --quick-generate-key "$NAME <$EMAIL>" ed25519 cert 1y

FPR=$(gpg --list-secret-keys --with-colons "$EMAIL" | awk -F: '/^fpr:/{print $10; exit}')

gpg --batch --passphrase "$PASS" --pinentry-mode loopback --quick-add-key "$FPR" ed25519 sign 1y
gpg --batch --passphrase "$PASS" --pinentry-mode loopback --quick-add-key "$FPR" cv25519 encrypt 1y
gpg --batch --passphrase "$PASS" --pinentry-mode loopback --quick-add-key "$FPR" ed25519 auth 1y
