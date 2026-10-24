#!/bin/sh
# Creates a self-signed code-signing certificate, "Dante Journal Developer",
# in the login keychain and trusts it for code signing, so builds of the app
# keep one code identity and macOS remembers its permissions (microphone,
# Input Monitoring) across rebuilds. Ad hoc signatures change every build.
#
# macOS may ask for your login password when the trust setting is added and
# when codesign first uses the key (choose "Always Allow").
set -eu
name="Dante Journal Developer"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$keychain" | grep -q "$name"; then
  echo "already present: $name"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/ext.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $name
[v3]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$work/key.pem" -out "$work/cert.pem" -config "$work/ext.cnf" 2>/dev/null
openssl pkcs12 -export -out "$work/identity.p12" -inkey "$work/key.pem" -in "$work/cert.pem" \
  -name "$name" -passout pass:dante-journal \
  -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES
security import "$work/identity.p12" -k "$keychain" -P dante-journal \
  -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild >/dev/null
security add-trusted-cert -p codeSign -k "$keychain" "$work/cert.pem"
security find-identity -v -p codesigning "$keychain" | grep "$name"
