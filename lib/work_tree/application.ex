defmodule WorkTree.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ensure_db_dir()

    children =
      [
        WorkTreeWeb.Telemetry,
        WorkTree.Repo,
        {Phoenix.PubSub, name: WorkTree.PubSub},
        # Auto-archive completed todos after X days
        WorkTree.AutoArchiver,
        # Start to serve requests, typically the last entry
        WorkTreeWeb.Endpoint
      ] ++ sync_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WorkTree.Supervisor]
    result = Supervisor.start_link(children, opts)

    run_migrations()

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WorkTreeWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Ensure the SQLite database directory exists
  defp ensure_db_dir do
    db_path = Application.get_env(:work_tree, WorkTree.Repo)[:database]

    if db_path do
      db_path |> Path.dirname() |> File.mkdir_p!()
    end
  end

  defp sync_children do
    sync_dir = Application.get_env(:work_tree, :sync_dir)

    if sync_dir do
      [{WorkTree.Sync.Worker, sync_dir: sync_dir}]
    else
      [{WorkTree.Sync.Worker, []}]
    end
  end

  # Auto-run migrations on startup
  defp run_migrations do
    migrations_path = Application.app_dir(:work_tree, "priv/repo/migrations")

    if File.dir?(migrations_path) do
      Ecto.Migrator.run(WorkTree.Repo, migrations_path, :up, all: true, log: false)
    end
  end
end
