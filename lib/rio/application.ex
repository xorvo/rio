defmodule Rio.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ensure_db_dir()

    children =
      [
        RioWeb.Telemetry,
        Rio.Repo,
        {Phoenix.PubSub, name: Rio.PubSub},
        # Auto-archive completed todos after X days
        Rio.AutoArchiver,
        # Expire stale inbox items
        Rio.Inbox.InboxExpirer,
        # Start to serve requests, typically the last entry
        RioWeb.Endpoint
      ] ++ sync_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Rio.Supervisor]
    result = Supervisor.start_link(children, opts)

    run_migrations()

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RioWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Ensure the SQLite database directory exists
  defp ensure_db_dir do
    db_path = Application.get_env(:rio, Rio.Repo)[:database]

    if db_path do
      db_path |> Path.dirname() |> File.mkdir_p!()
    end
  end

  defp sync_children do
    sync_dir = Application.get_env(:rio, :sync_dir)

    if sync_dir do
      [{Rio.Sync.Worker, sync_dir: sync_dir}]
    else
      [{Rio.Sync.Worker, []}]
    end
  end

  # Auto-run migrations on startup
  defp run_migrations do
    migrations_path = Application.app_dir(:rio, "priv/repo/migrations")

    if File.dir?(migrations_path) do
      Ecto.Migrator.run(Rio.Repo, migrations_path, :up, all: true, log: false)
    end
  end
end
