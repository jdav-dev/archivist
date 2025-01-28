FROM hexpm/elixir:1.18.2-erlang-27.2.1-debian-bookworm-20250113-slim

RUN apt-get update && apt-get install -y curl git zsh

# Install Oh My Zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Co-locate the zsh history with IEx shell history for convenience
RUN SNIPPET="export HISTFILE=/root/.cache/erlang-history/.zsh_history" \
  && echo "$SNIPPET" >> "/root/.zshrc"

# Let the BEAM change its clock when the system time changes.
ENV ERL_FLAGS="+C multi_time_warp"

# Enable history in IEX.
ENV ERL_AFLAGS="-kernel shell_history enabled"

RUN mix local.hex --force && mix local.rebar --force
