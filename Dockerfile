ARG ELIXIR_IMAGE=hexpm/elixir:1.20.4-erlang-29.1.1-debian-bookworm-20260918-slim@sha256:037687742ae12c329b59a681a230d62ef3ddd555c0275e577ce41c61539e5248
ARG RUNTIME_IMAGE=debian:bookworm-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251

FROM ${ELIXIR_IMAGE} AS build

ENV MIX_ENV=prod
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only prod && mix deps.compile

COPY lib lib
COPY priv priv
COPY assets assets
COPY LICENSE THIRD_PARTY_NOTICES.md ./

RUN mix compile --warnings-as-errors \
    && mix assets.deploy \
    && mix release

FROM ${RUNTIME_IMAGE} AS app

ENV HOME=/app \
    LANG=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl libncurses6 libssl3 libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
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
