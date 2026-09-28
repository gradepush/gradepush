#!/bin/sh
set -eu

case "$POSTGRES_USER" in
  gradepush_operator|gradepush_initializer)
    echo "DB_USER cannot use a reserved GradePush operator role." >&2
    exit 1
    ;;
esac

psql --no-psqlrc --set=ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
CREATE ROLE gradepush_initializer WITH LOGIN SUPERUSER PASSWORD NULL;
SQL

# PostgreSQL's bootstrap role must remain a superuser; retain it for local administration.
psql --no-psqlrc --set=ON_ERROR_STOP=1 \
  --username gradepush_initializer --dbname "$POSTGRES_DB" \
  --set=app_user="$POSTGRES_USER" --set=app_database="$POSTGRES_DB" \
  --set=can_create_db="${POSTGRES_APP_CREATEDB:-false}" <<'SQL'
\getenv app_password POSTGRES_PASSWORD
ALTER ROLE :"app_user" RENAME TO gradepush_operator;
ALTER ROLE gradepush_operator PASSWORD NULL;
CREATE ROLE :"app_user" WITH LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER DATABASE :"app_database" OWNER TO :"app_user";
\if :can_create_db
ALTER ROLE :"app_user" CREATEDB;
\endif
SQL

psql --no-psqlrc --set=ON_ERROR_STOP=1 \
  --username gradepush_operator --dbname "$POSTGRES_DB" <<'SQL'
DROP ROLE gradepush_initializer;
SQL
