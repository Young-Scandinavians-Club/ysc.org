# Find eligible builder and runner images on Docker Hub. We use Elixir + OTP alpine.
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=27.3.4.15
ARG ALPINE_VERSION=3.22.5

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="alpine:${ALPINE_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apk add --no-cache build-base git npm curl

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN cd assets && npm install --prefer-offline --no-audit --progress=false
# Colocated hooks resolve from _build via NODE_PATH; compile before bundling.
RUN mix compile
RUN mix assets.deploy

COPY config/runtime.exs config/
COPY rel rel

RUN mix release

FROM ${RUNNER_IMAGE}

RUN apk add --no-cache libstdc++ openssl ncurses-libs bash

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV=prod
ENV LANG=C.UTF-8

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/query_console ./

USER nobody

CMD ["/app/bin/server"]
