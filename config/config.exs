import Config

config :archivist, ecto_repos: [Archivist.Repo]

config :archivist, Archivist.Repo, database: "archivist_repo.db"
