#!/bin/sh
set -eu

data_dir="${GRADEPUSH_DATA_DIR:-/var/lib/gradepush}"

persisted_secret() {
  secret_file="$data_dir/$1"
  mkdir -p "$data_dir"

  if [ ! -s "$secret_file" ]; then
    temporary_file="$secret_file.tmp.$$"
    trap 'rm -f "$temporary_file"' EXIT HUP INT TERM
    (
      umask 077
      head -c "$2" /dev/urandom | base64 | tr -d '\n' > "$temporary_file"
    )
    test -s "$temporary_file"
    if ! ln "$temporary_file" "$secret_file" 2>/dev/null && [ ! -s "$secret_file" ]; then
      echo "Could not persist $1." >&2
      exit 1
    fi
    rm -f "$temporary_file"
    trap - EXIT HUP INT TERM
  fi

  cat "$secret_file"
}

if [ -z "${SECRET_KEY_BASE:-}" ]; then
  SECRET_KEY_BASE="$(persisted_secret secret_key_base 64)"
  export SECRET_KEY_BASE
fi

if [ -z "${CREDENTIAL_ENCRYPTION_KEY:-}" ]; then
  CREDENTIAL_ENCRYPTION_KEY="$(persisted_secret credential_encryption_key 32)"
  export CREDENTIAL_ENCRYPTION_KEY
fi

/app/bin/gradepush eval 'GradePush.Release.migrate()'
exec "$@"
