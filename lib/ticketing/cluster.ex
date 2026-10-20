defmodule Ticketing.Cluster do
  @moduledoc """
  Watches the cluster and logs every node that joins or leaves:

      node ticketing@10.0.1.12 (fra1) joined
      node ticketing@10.0.1.12 (fra1) down

  DNSCluster does the connecting. This process only listens, using
  `:net_kernel.monitor_nodes/1`, and remembers which region each node is in so
  we can still name the region after the node has gone away.
  """
  use GenServer
  require Logger

  # Fallback for nodes we never managed to ask (they died before we could).
  # Matches the static IPs in docker-compose.yml.
  @static_regions %{
    "10.0.1.11" => "tor1",
    "10.0.1.12" => "fra1",
    "10.0.1.13" => "sfo1",
    "10.0.1.14" => "lhr1",
    "10.0.1.15" => "sin1"
  }

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "The region a node runs in (\"fra1\"), or \"?\" if we can't tell."
  def region_of(node) when node == node(), do: Ticketing.region()
  def region_of(node), do: GenServer.call(__MODULE__, {:region_of, node})

  @impl true
  def init(:ok) do
    # Ask the runtime to send us {:nodeup, node} / {:nodedown, node} messages.
    :ok = :net_kernel.monitor_nodes(true)
    regions = Map.new(Node.list(), &{&1, ask_region(&1)})
    {:ok, regions}
  end

  @impl true
  def handle_info({:nodeup, node}, regions) do
    region = ask_region(node)
    Logger.info("node #{node} (#{region}) joined")
    {:noreply, Map.put(regions, node, region)}
  end

  def handle_info({:nodedown, node}, regions) do
    Logger.info("node #{node} (#{Map.get(regions, node, static_region(node))}) down")
    {:noreply, regions}
  end

  @impl true
  def handle_call({:region_of, node}, _from, regions) do
    region =
      case regions do
        %{^node => region} -> region
        _ -> if node in Node.list(), do: ask_region(node), else: static_region(node)
      end

    {:reply, region, Map.put(regions, node, region)}
  end

  # Ask the remote node directly. If that fails for any reason, fall back to
  # the static IP map so logging never crashes this process.
  defp ask_region(node) do
    :erpc.call(node, Ticketing, :region, [], 2_000)
  catch
    _, _ -> static_region(node)
  end

  defp static_region(node) do
    [_name, host] = node |> Atom.to_string() |> String.split("@", parts: 2)
    Map.get(@static_regions, host, "?")
  end
end
