# One image, five nodes. Build stage compiles a release, run stage just runs it.
ARG ELIXIR_VERSION=1.20.0
ARG OTP_VERSION=28.5.0.2
ARG DEBIAN_VERSION=trixie-20260610-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# --- build -------------------------------------------------------------------
FROM ${BUILDER_IMAGE} AS build

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY lib lib
COPY rel rel
COPY config/runtime.exs config/
RUN mix compile && mix release

# --- run ---------------------------------------------------------------------
FROM ${RUNNER_IMAGE}

# dnsutils for `dig`, iproute2/procps for poking around inside a container.
RUN apt-get update -y \
    && apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates dnsutils iproute2 procps \
    && apt-get clean && rm -f /var/lib/apt/lists/*_* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 MIX_ENV=prod

WORKDIR /app
RUN chown nobody /app
COPY --from=build --chown=nobody:root /app/_build/prod/rel/ticketing ./
# Region-aware IEx prompt for `bin/ticketing remote` (IEx reads ./.iex.exs).
COPY --chown=nobody:root .iex.exs ./

USER nobody
CMD ["/app/bin/ticketing", "start"]
