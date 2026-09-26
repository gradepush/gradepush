#!/bin/sh
set -eu

data_dir="${GRADEPUSH_DATA_DIR:-/var/lib/gradepush}"

if [ -z "${SECRET_KEY_BASE:-}" ]; then
  secret_file="$data_dir/secret_key_base"
  mkdir -p "$data_dir"

  if [ ! -s "$secret_file" ]; then
    temporary_file="$secret_file.tmp.$$"
    trap 'rm -f "$temporary_file"' EXIT HUP INT TERM
    (
      umask 077
      head -c 64 /dev/urandom | base64 | tr -d '\n' > "$temporary_file"
    )
    test -s "$temporary_file"
    if ! ln "$temporary_file" "$secret_file" 2>/dev/null && [ ! -s "$secret_file" ]; then
      echo "Could not persist the generated SECRET_KEY_BASE." >&2
      exit 1
    fi
    rm -f "$temporary_file"
    trap - EXIT HUP INT TERM
  fi

  SECRET_KEY_BASE="$(cat "$secret_file")"
  export SECRET_KEY_BASE
fi

/app/bin/gradepush eval 'GradePush.Release.migrate()'
exec "$@"
