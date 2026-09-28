ARG ELIXIR_IMAGE=hexpm/elixir:1.20.4-erlang-29.1.1-alpine-3.24.2@sha256:ad851f40ce103dcb4ad56f23877d99473ef5c013e09b9e57921ffe877ac6d6a9
ARG RUNTIME_IMAGE=alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

FROM ${ELIXIR_IMAGE} AS development

ARG LOCAL_UID=1000
ARG LOCAL_GID=1000

ENV HOME=/opt/gradepush
WORKDIR /app

RUN apk add --no-cache bash build-base ca-certificates coreutils curl diffutils git inotify-tools openssl \
    && mkdir -p /opt/gradepush /app/deps /app/_build \
    && chown -R ${LOCAL_UID}:${LOCAL_GID} /opt/gradepush /app

USER ${LOCAL_UID}:${LOCAL_GID}
RUN mix local.hex --force && mix local.rebar --force

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
