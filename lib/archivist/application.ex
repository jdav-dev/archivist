defmodule Archivist.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children =
      case Application.get_env(:archivist, :worker) do
        worker_opts when is_list(worker_opts) -> [{Archivist.Worker, worker_opts}]
        nil -> []
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Archivist.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
