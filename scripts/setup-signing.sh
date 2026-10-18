#!/bin/bash
# Run --prepare first; --install changes the user's login keychain and requires consent.
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
signing_dir="$PWD/.build/local-signing"
certificate="$signing_dir/certificate.pem"
mode="${1:---prepare}"
if [ "$mode" = "--prepare" ]; then
  umask 077
  mkdir -p "$signing_dir"
  if [ ! -f "$certificate" ]; then
    cat > "$signing_dir/certificate.cnf" <<'CONFIG'
[req]
prompt = no
distinguished_name = name
x509_extensions = codesign
[name]
CN = Tangerine Local Development
[codesign]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
CONFIG
    openssl req -new -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 -config "$signing_dir/certificate.cnf" -keyout "$signing_dir/private-key.pem" -out "$certificate" 2> "$signing_dir/generation.log"
  fi
  openssl x509 -in "$certificate" -noout -subject -dates -fingerprint -sha256
  printf '\nPrepared only. No keychain entries or trust settings were changed.\n'
elif [ "$mode" = "--install" ]; then
  test -f "$certificate"
  fingerprint="$(openssl x509 -in "$certificate" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
  if ! security find-identity -p codesigning "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null | /usr/bin/grep -Fq "$fingerprint"; then
    test -f "$signing_dir/private-key.pem"
    openssl rsa -traditional -in "$signing_dir/private-key.pem" -out "$signing_dir/private-key-rsa.pem" 2>/dev/null
    security import "$signing_dir/private-key-rsa.pem" -k "$HOME/Library/Keychains/login.keychain-db" -f openssl -t priv -x -T /usr/bin/codesign
    security import "$certificate" -k "$HOME/Library/Keychains/login.keychain-db" -t cert
  fi
  # Trust only this self-signed certificate for code-signing policy in the user domain.
  # This does not install system-wide, TLS, email, or general-purpose CA trust.
  security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$certificate"
  # Store a public certificate fingerprint, never a private key or password.
  printf '%s\n' "$fingerprint" > .signing-identity
  chmod 600 .signing-identity
  rm -f "$signing_dir/private-key.pem" "$signing_dir/private-key.der" "$signing_dir/private-key-rsa.pem" "$signing_dir/identity.p12"
  printf 'Local signing identity installed. Rebuild with scripts/build-app.sh.\n'
else
  printf 'Usage: %s --prepare | --install\n' "$0" >&2
  exit 2
fi
