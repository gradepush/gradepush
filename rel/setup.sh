#!/bin/sh
set -eu

exec /app/bin/gradepush rpc 'GradePush.Release.setup_link()'
