#!/bin/sh
set -eu

cd "${GRADEPUSH_CERT_DIR:-/certs}"
umask 077

valid_pair() {
  openssl x509 -in "$1" -checkend 2592000 -noout >/dev/null 2>&1 || return 1
  certificate_key=$(openssl x509 -in "$1" -pubkey -noout) || return 1
  private_key=$(openssl pkey -in "$2" -pubout 2>/dev/null) || return 1
  [ "$certificate_key" = "$private_key" ]
}

if ! valid_pair ca.pem ca-key.pem; then
  openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
    -subj '/CN=GradePush Local Development CA' \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign' \
    -keyout ca-key.pem -out ca.pem 2>/dev/null
fi

if ! valid_pair localhost.pem localhost-key.pem || \
   ! openssl verify -CAfile ca.pem localhost.pem >/dev/null 2>&1; then
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT HUP INT TERM
  openssl req -new -newkey rsa:2048 -nodes -sha256 \
    -subj '/CN=localhost' -keyout "$work/key.pem" -out "$work/request.pem" 2>/dev/null
  cat > "$work/extensions" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1
EOF
  openssl x509 -req -in "$work/request.pem" -CA ca.pem -CAkey ca-key.pem \
    -CAcreateserial -days 365 -sha256 -extfile "$work/extensions" \
    -out "$work/cert.pem" 2>/dev/null
  mv "$work/key.pem" localhost-key.pem
  mv "$work/cert.pem" localhost.pem
fi

chmod 644 ca.pem localhost.pem localhost-key.pem
echo 'Local HTTPS certificates are ready.'
