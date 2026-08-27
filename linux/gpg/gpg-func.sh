# Encrypt clipboard/stdin to a recipient, armored
gpgenc() {
    gpg --armor --encrypt --recipient "$1"
}
# usage: echo "secret" | gpgenc you@example.com
# or:    gpgenc you@example.com < file.txt

# Decrypt stdin (uses loopback since you have no pinentry)
gpgdec() {
    gpg --batch --pinentry-mode loopback --decrypt
}
# usage: gpgdec < message.asc
# or paste into terminal, then Ctrl-D

# Sign stdin (clear-sign, human-readable output)
gpgsign() {
    gpg --batch --pinentry-mode loopback --clearsign
}

# Detached-sign stdin, output just the signature block
gpgsigndetach() {
    gpg --batch --pinentry-mode loopback --armor --detach-sign
}

# Verify stdin (clearsigned or normal signed message)
gpgverify() {
    gpg --verify
}

# Import a key from stdin
gpgimport() {
    gpg --import
}

# Symmetric encrypt (password-based, no recipient key needed)
gpgencsym() {
    gpg --batch --pinentry-mode loopback --symmetric --armor --cipher-algo AES256
}

gpgauto() {
    local input
    input=$(cat)
    if echo "$input" | grep -q "BEGIN PGP MESSAGE"; then
        echo "$input" | gpg --batch --pinentry-mode loopback --decrypt
    elif echo "$input" | grep -q "BEGIN PGP SIGNED MESSAGE"; then
        echo "$input" | gpg --verify
    elif echo "$input" | grep -q "BEGIN PGP PUBLIC KEY BLOCK"; then
        echo "$input" | gpg --import
    elif echo "$input" | grep -q "BEGIN PGP SIGNATURE"; then
        echo "$input" | gpg --verify
    else
        echo "No recognizable PGP block found." >&2
        return 1
    fi
}
