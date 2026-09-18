defmodule Indivisual.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      IndivisualWeb.Telemetry,
      Indivisual.Repo,
      {DNSCluster, query: Application.get_env(:indivisual, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Indivisual.PubSub},
      {Task.Supervisor, name: Indivisual.TaskSupervisor},
      # Background jobs (embedding generation for the topo semantic axes).
      {Oban, Application.fetch_env!(:indivisual, Oban)},
      # In-memory Atlas event feed: loads source adapters, broadcasts appends.
      Indivisual.Atlas.Feed,
      # Start to serve requests, typically the last entry
      IndivisualWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Indivisual.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    IndivisualWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
