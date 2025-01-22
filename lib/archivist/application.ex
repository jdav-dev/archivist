defmodule Archivist.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Archivist.Repo,
      {Archivist.Worker,
       dir: System.fetch_env!("ARCHIVIST_INBOX"),
       interval_seconds: 1}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Archivist.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
