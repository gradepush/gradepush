#!/bin/sh
set -eu

for directory in /opt/gradepush /app/deps /app/_build; do
  if [ "$(stat -c %u:%g "$directory")" != "1000:1000" ]; then
    chown -R 1000:1000 "$directory"
  fi
done

exec su-exec 1000:1000 env HOME=/opt/gradepush "$@"
