defmodule Archivist.Repo do
  use Ecto.Repo,
    otp_app: :archivist,
    adapter: Ecto.Adapters.SQLite3
end
