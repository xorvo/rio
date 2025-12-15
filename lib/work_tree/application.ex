defmodule WorkTree.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WorkTreeWeb.Telemetry,
      WorkTree.Repo,
      {DNSCluster, query: Application.get_env(:work_tree, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WorkTree.PubSub},
      # Start a worker by calling: WorkTree.Worker.start_link(arg)
      # {WorkTree.Worker, arg},
      # Start to serve requests, typically the last entry
      WorkTreeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WorkTree.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WorkTreeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
