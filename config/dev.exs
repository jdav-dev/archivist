import Config

config :archivist,
  worker: [
    archive: "/archive",
    check_interval: to_timeout(minute: 1),
    inbox: "/inbox",
    llm_timeout: to_timeout(minute: 5)
  ]
