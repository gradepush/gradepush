#!/bin/sh
set -eu

/app/bin/gradepush eval 'GradePush.Release.migrate()'
exec "$@"
