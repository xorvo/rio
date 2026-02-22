import Config

# Desktop mode: SQLite backend, localhost only, no external services

config :work_tree,
  storage_backend: :sqlite

db_dir =
  System.get_env("WORK_TREE_DATA_DIR") ||
    Path.expand("~/.local/share/work_tree")

config :work_tree, WorkTree.Repo,
  database: Path.join(db_dir, "work_tree.db"),
  pool_size: 1,
  journal_mode: :wal,
  # Use SQLite-specific migrations
  priv: "priv/repo_sqlite",
  # Override any Postgres-specific settings from dev.exs
  username: nil,
  password: nil,
  hostname: nil

config :work_tree, WorkTreeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  secret_key_base: "desktop-dev-only-key-not-for-production-use-replace-in-release-00",
  server: true

# Disable mailer in desktop mode
config :work_tree, WorkTree.Mailer, adapter: Swoosh.Adapters.Local

config :swoosh, :api_client, false

# Less verbose logging
config :logger, level: :info
