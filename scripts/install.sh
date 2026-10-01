#!/bin/sh
set -eu
umask 077

compose_ref=cd53a9c9d146d9578117b2080e937cdcd52a709a
compose_sha256=9d999b6396852f60b2884c41343a50deaa8ba5232cfb73797e8fe7975bc173b8
domain=
directory=gradepush
compose_file=

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --domain|--directory|--compose-file)
      [ "$#" -ge 2 ] || fail "Missing value for $1."
      case "$1" in
        --domain) domain=$2 ;;
        --directory) directory=$2 ;;
        --compose-file) compose_file=$2 ;;
      esac
      shift 2
      ;;
    --help|-h)
      printf '%s\n' 'Usage: sh install.sh [--domain grades.example.org] [--directory gradepush] [--compose-file path]' \
        'Prepares a new Docker Compose installation. Does not start services.' \
        'Use --compose-file only for a local configuration you have reviewed.'
      exit 0
      ;;
    *) fail "Unknown option: $1" ;;
  esac
done

for tool in docker curl openssl awk mktemp; do
  command -v "$tool" >/dev/null 2>&1 || fail "Install $tool before continuing."
done

compose_version=$(docker compose version --short) || fail 'Install Docker Compose 2.32 or newer.'
printf '%s\n' "$compose_version" | awk -F. '
  { sub(/^v/, "", $1); exit !(($1 + 0 > 2) || ($1 + 0 == 2 && $2 + 0 >= 32)) }
' || fail 'Docker Compose 2.32 or newer is required.'

if [ -z "$domain" ]; then
  printf 'Public domain (for example grades.example.org): '
  if [ -t 0 ]; then
    IFS= read -r domain || fail 'No domain provided.'
  elif (test -r /dev/tty && : </dev/tty) 2>/dev/null; then
    IFS= read -r domain </dev/tty || fail 'No domain provided.'
  else
    fail 'Use --domain grades.example.org when no terminal is available.'
  fi
fi

printf '%s\n' "$domain" | LC_ALL=C awk -F. '
  NR != 1 { invalid = 1 }
  {
    if (length($0) > 253 || NF < 2 || $NF !~ /^[A-Za-z][A-Za-z]+$/) invalid = 1
    for (i = 1; i <= NF; i++)
      if (length($i) > 63 || $i !~ /^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/) invalid = 1
  }
  END { exit invalid }
' || fail 'Enter a domain only, without https://, a port, or a path.'

[ -n "$directory" ] || fail 'Choose a new installation directory.'
case "$directory" in
  /*|./*|../*) ;;
  *) directory=./$directory ;;
esac
[ ! -e "$directory" ] && [ ! -L "$directory" ] || fail 'The installation directory already exists. Nothing was changed.'
parent=$(dirname "$directory")
[ -d "$parent" ] || fail 'The parent directory does not exist.'
scratch=$(mktemp -d "$parent/.gradepush-install.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
trap 'exit 1' HUP INT TERM

if [ -n "$compose_file" ]; then
  [ -f "$compose_file" ] || fail 'The local Compose file does not exist.'
  cp -- "$compose_file" "$scratch/compose.yaml" || fail 'Could not read the local Compose file.'
else
  printf 'Downloading the installation configuration...\n'
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 15 --max-time 120 \
    "https://raw.githubusercontent.com/gradepush/gradepush/$compose_ref/compose.self-host.yaml" \
    -o "$scratch/compose.yaml" || fail 'Download failed. Run the installer again.'
  actual_sha256=$(openssl dgst -sha256 "$scratch/compose.yaml" | awk '{print $NF}')
  [ "$actual_sha256" = "$compose_sha256" ] || fail 'The downloaded configuration failed verification. Nothing was installed.'
fi

db_password=$(openssl rand -hex 32)
setup_token=$(openssl rand -hex 32)
printf 'PHX_HOST=%s\nDB_PASSWORD=%s\nSETUP_TOKEN=%s\n' \
  "$domain" "$db_password" "$setup_token" > "$scratch/.env"
docker compose --env-file "$scratch/.env" -f "$scratch/compose.yaml" config --quiet \
  || fail 'Docker Compose could not validate the configuration.'

mkdir "$directory" || fail 'Could not create the installation directory. Nothing was overwritten.'
mv "$scratch/compose.yaml" "$scratch/.env" "$directory/"

printf '\nFiles saved in: %s\n\n' "$directory"
printf '%s\n' 'From that directory, start GradePush:' '' \
  '  docker compose pull' '  docker compose up -d --wait' ''
printf '%s\n' 'Your domain must point to this server, with ports 80 and 443 open.' \
  'Caddy configures HTTPS automatically.' ''
printf 'Once GradePush is running, open this private setup link:\n\n  https://%s/setup#setup_token=%s\n\n' \
  "$domain" "$setup_token"
printf 'Setup token: %s\nKeep this token and the .env file private.\n' "$setup_token"
