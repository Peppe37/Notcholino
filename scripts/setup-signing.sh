#!/bin/bash
# One-time setup: creates a self-signed code signing certificate and stores it as GitHub secrets,
# so every release is signed with the SAME identity.
#
# Why: with the default ad-hoc signature, macOS sees every new build as a different app and asks again
# for the Keychain password (Spotify), Calendar, Automation and Accessibility permissions after each update.
# With a fixed certificate the app keeps its identity across updates, so these are asked only once.
#
# Run it yourself, once:   scripts/setup-signing.sh
# It needs: openssl, and the `gh` CLI logged in with access to this repository.
# Keep ~/.notcholino/signing safe: whoever has the key can sign apps that macOS treats as Notcholino.
set -euo pipefail

REPO="${REPO:-Peppe37/Notcholino}"
DIR="$HOME/.notcholino/signing"
NAME="Notcholino Self-Signed"
mkdir -p "$DIR" && chmod 700 "$HOME/.notcholino" "$DIR"

if [ ! -f "$DIR/$NAME.p12" ]; then
  echo "Creating the certificate..."
  cat > "$DIR/cs.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
O = Notcholino
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$DIR/key.pem" -out "$DIR/certificate.pem" -days 7300 -config "$DIR/cs.cnf" 2>/dev/null
  openssl rand -hex 16 > "$DIR/password.txt"
  # Legacy algorithms: the macOS `security` tool can't read the OpenSSL 3 defaults
  openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/certificate.pem" -out "$DIR/$NAME.p12" \
    -passout "pass:$(cat "$DIR/password.txt")" -name "$NAME" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
  rm -f "$DIR/key.pem" "$DIR/cs.cnf"
  chmod 600 "$DIR"/*
else
  echo "Reusing the certificate in $DIR"
fi

echo "Saving the secrets in ${REPO}..."
base64 < "$DIR/$NAME.p12" | tr -d '\n' | gh secret set SIGNING_P12 --repo "$REPO"
gh secret set SIGNING_P12_PASSWORD --repo "$REPO" < "$DIR/password.txt"

echo
echo "Done. Releases from now on are signed with this identity."
echo "Back up $DIR somewhere safe: if you lose it, the next certificate makes macOS ask for permissions once more."
