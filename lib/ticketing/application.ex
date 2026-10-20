defmodule Ticketing.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TicketingWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:ticketing, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ticketing.PubSub},
      # Logs nodes joining and leaving.
      Ticketing.Cluster,
      # One box office per node, registered locally as `BoxOffice`.
      Ticketing.BoxOffice,
      # Per-show processes, started lazily on the node that owns the show.
      {Registry, keys: :unique, name: Ticketing.ShowRegistry},
      {DynamicSupervisor, name: Ticketing.ShowSupervisor},
      # Cluster-wide singleton: a local supervisor to run it under if this
      # node wins, and a manager that starts it or watches whoever has it.
      {DynamicSupervisor, name: Ticketing.SingletonSupervisor},
      Ticketing.SingletonManager,
      # Start to serve requests, typically the last entry
      TicketingWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ticketing.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TicketingWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
