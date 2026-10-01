ARG ELIXIR_IMAGE=hexpm/elixir:1.20.4-erlang-29.1.1-alpine-3.24.2@sha256:ad851f40ce103dcb4ad56f23877d99473ef5c013e09b9e57921ffe877ac6d6a9
ARG RUNTIME_IMAGE=alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
ARG NODE_IMAGE=node:26.8.1-alpine3.24@sha256:2d984a15c9b54fd0aeb608b8e0d0d83529eb34d2966db27a1fb4f1edc3d298a3

FROM ${NODE_IMAGE} AS test-runtime

FROM ${RUNTIME_IMAGE} AS local-https

RUN apk add --no-cache openssl
COPY --chmod=755 deploy/local-https.sh /usr/local/bin/local-https
ENTRYPOINT ["/usr/local/bin/local-https"]

FROM ${ELIXIR_IMAGE} AS development

ENV HOME=/opt/gradepush
WORKDIR /app

RUN apk add --no-cache bash build-base ca-certificates coreutils curl diffutils git inotify-tools openssl python3=3.14.8-r0 su-exec \
    && mkdir -p /opt/gradepush /app/deps /app/_build \
    && chown -R 1000:1000 /opt/gradepush /app

COPY --from=test-runtime /usr/local/bin/node /usr/local/bin/node

USER 1000:1000
RUN mix local.hex --force && mix local.rebar --force

COPY --chown=1000:1000 . .
USER root
COPY --chmod=755 deploy/development-entrypoint.sh /usr/local/bin/gradepush-development
ENTRYPOINT ["/usr/local/bin/gradepush-development"]
CMD ["sh", "-c", "mix setup && exec mix phx.server"]

FROM ${ELIXIR_IMAGE} AS build

ENV MIX_ENV=prod
WORKDIR /app

RUN apk add --no-cache build-base ca-certificates git

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only prod --check-locked && mix deps.compile

COPY lib lib
COPY priv priv
COPY assets assets
COPY rel rel
COPY LICENSE THIRD_PARTY_NOTICES.md ./

RUN mix compile --warnings-as-errors \
    && mix assets.deploy \
    && mix release \
    && rm _build/prod/rel/gradepush/releases/COOKIE

FROM ${RUNTIME_IMAGE} AS app

ENV HOME=/app \
    LANG=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true \
    GRADEPUSH_DATA_DIR=/var/lib/gradepush \
    RELEASE_TMP=/tmp/gradepush \
    ERL_CRASH_DUMP=/tmp/erl_crash.dump \
    PORT=4000

RUN apk add --no-cache ca-certificates curl libstdc++ lksctp-tools ncurses-libs openssl \
    && addgroup -S -g 10001 gradepush \
    && adduser -S -D -H -u 10001 -G gradepush gradepush \
    && mkdir -p /app /var/lib/gradepush \
    && chown 10001:10001 /app /var/lib/gradepush

WORKDIR /app

COPY --from=build --chown=10001:10001 /app/_build/prod/rel/gradepush ./
COPY --chown=root:root --chmod=755 rel/entrypoint.sh /usr/local/bin/gradepush-entrypoint
COPY --chown=root:root --chmod=755 rel/setup.sh /usr/local/bin/gradepush-setup

USER 10001:10001

EXPOSE 4000
VOLUME ["/var/lib/gradepush"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD curl --fail --silent "http://127.0.0.1:$PORT/health/ready" > /dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/gradepush-entrypoint"]
CMD ["/app/bin/gradepush", "start"]
