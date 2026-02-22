defmodule WorkTree.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    maybe_ensure_sqlite_dir()

    children =
      [
        WorkTreeWeb.Telemetry,
        WorkTree.Repo,
        unless(desktop_mode?(),
          do: {DNSCluster, query: Application.get_env(:work_tree, :dns_cluster_query) || :ignore}
        ),
        {Phoenix.PubSub, name: WorkTree.PubSub},
        # Auto-archive completed todos after X days
        WorkTree.AutoArchiver,
        # Start to serve requests, typically the last entry
        WorkTreeWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WorkTree.Supervisor]
    result = Supervisor.start_link(children, opts)

    maybe_run_sqlite_migrations()

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WorkTreeWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @doc """
  Returns true if running in desktop mode (SQLite backend).
  """
  def desktop_mode? do
    Application.get_env(:work_tree, :storage_backend) == :sqlite
  end

  # Ensure the SQLite database directory exists
  defp maybe_ensure_sqlite_dir do
    if desktop_mode?() do
      db_path = Application.get_env(:work_tree, WorkTree.Repo)[:database]

      if db_path do
        db_path |> Path.dirname() |> File.mkdir_p!()
      end
    end
  end

  # Auto-run migrations for SQLite in desktop mode
  defp maybe_run_sqlite_migrations do
    if desktop_mode?() do
      migrations_path = Application.app_dir(:work_tree, "priv/repo_sqlite/migrations")

      if File.dir?(migrations_path) do
        Ecto.Migrator.run(WorkTree.Repo, migrations_path, :up, all: true, log: false)
      end
    end
  end
end
