ARG ELIXIR_VERSION=1.18.2
ARG OTP_VERSION=27.2.1
ARG DEBIAN_VERSION=bookworm-20250113-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS devcontainer

RUN apt-get update && apt-get install -y \
  curl \
  git \
  gnupg2 \
  ocrmypdf \
  poppler-utils \
  sudo \
  zsh

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Add vscode user
RUN groupadd --gid $USER_GID $USERNAME \
  && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
  && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
  && chmod 0440 /etc/sudoers.d/$USERNAME

USER $USERNAME

# Let the BEAM change its clock when the system time changes.
ENV ERL_FLAGS="+C multi_time_warp"

# Enable history in IEX.
ENV ERL_AFLAGS="-kernel shell_history enabled"

# Install Oh My Zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Co-locate the zsh history with IEx shell history for convenience
RUN mkdir -p /home/${USERNAME}/.cache/erlang-history \
  && SNIPPET="export HISTFILE=/home/${USERNAME}/.cache/erlang-history/.zsh_history" \
  && echo "$SNIPPET" >> "/home/${USERNAME}/.zshrc"

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /workspace


FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies to ensure any relevant config
# change will trigger the dependencies to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY lib ./lib

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

RUN mix release


FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y && apt-get install -y \
  ca-certificates \
  libncurses5 \
  libstdc++6 \
  locales \
  ocrmypdf \
  openssl \
  poppler-utils \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/archivist ./

USER nobody

CMD ["/app/bin/archivist", "start"]
