import Config

if config_env() == :prod do
  if ollama_base_url = System.get_env("ARCHIVIST_OLLAMA_BASE_URL") do
    config :archivist, :ollama, base_url: ollama_base_url
  end

  if ollama_timeout_string = System.get_env("ARCHIVIST_OLLAMA_TIMEOUT_SECONDS") do
    ollama_timeout_seconds = String.to_integer(ollama_timeout_string)
    config :archivist, :ollama, receive_timeout: to_timeout(second: ollama_timeout_seconds)
  end

  check_interval = String.to_integer(System.get_env("ARCHIVIST_CHECK_INTERVAL_SECONDS", "60"))

  config :archivist, :worker,
    archive: System.fetch_env!("ARCHIVIST_ARCHIVE_DIR"),
    check_interval: to_timeout(second: check_interval),
    inbox: System.fetch_env!("ARCHIVIST_INBOX_DIR")
end
