defmodule MindMapperPoc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MindMapperPocWeb.Telemetry,
      MindMapperPoc.Repo,
      {DNSCluster, query: Application.get_env(:mind_mapper_poc, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MindMapperPoc.PubSub},
      # Start a worker by calling: MindMapperPoc.Worker.start_link(arg)
      # {MindMapperPoc.Worker, arg},
      # Start to serve requests, typically the last entry
      MindMapperPocWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MindMapperPoc.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MindMapperPocWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
