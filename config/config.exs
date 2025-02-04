import Config

ollama_timeout_seconds =
  String.to_integer(System.get_env("ARCHIVIST_OLLAMA_TIMEOUT_SECONDS", "60"))

config :archivist, :ollama,
  base_url: System.get_env("ARCHIVIST_OLLAMA_BASE_URL", "http://localhost:11434/api"),
  receive_timeout: to_timeout(second: ollama_timeout_seconds)

# Import environment specific config.  This must remain at the bottom of this file so it overrides
# the configuration defined above.
import_config "#{config_env()}.exs"
