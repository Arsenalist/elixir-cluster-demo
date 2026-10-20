defmodule Ticketing.SingletonManager do
  @moduledoc """
  Keeps one `Ticketing.Reminders` alive somewhere in the cluster.

  Every node runs one of these managers. Each one tries to start the singleton
  under its global name:

    * if it wins, the singleton runs on this node (under a local supervisor);
    * if another node already has it, we get `{:already_started, pid}` back.

  Either way the manager **monitors** the singleton's pid. It doesn't link to
  it: a link would take the manager down with it (and, across nodes, a dead
  node would kill managers everywhere). When the monitor fires with anything
  other than `:normal` (a crash, `:noconnection` because the node vanished, or
  `:killed` because `:global` resolved a name clash), every surviving manager
  races to start it again. `:global` makes sure exactly one wins; the rest get
  `{:already_started, pid}` and monitor the winner.

  Pattern from Johanna Larsson, "Cluster singleton pattern":
  https://jola.dev/posts/cluster-singleton-pattern
  (written out here from scratch; differences from her snippet are ours.)
  """
  use GenServer
  require Logger

  alias Ticketing.Reminders

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    # Demo-only: on a cold start every node boots before DNSCluster has joined
    # them, so each would happily start its own copy and :global would pick a
    # random survivor when they meet. To make the demo begin with the singleton
    # on fra1, fra1 tries right away (delay 0 in docker-compose.yml) and the
    # others wait until they've joined the cluster and can see fra1's copy.
    delay = String.to_integer(System.get_env("SINGLETON_START_DELAY_MS", "5000"))
    Process.send_after(self(), :start_or_monitor, delay)
    {:ok, nil}
  end

  @impl true
  def handle_info(:start_or_monitor, _ref) do
    pid =
      case DynamicSupervisor.start_child(Ticketing.SingletonSupervisor, Reminders) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    # If pid is already dead (we raced a node going down), the monitor fires
    # immediately with :noproc / :noconnection and we simply try again.
    {:noreply, Process.monitor(pid)}
  end

  # The singleton was stopped on purpose. Leave it stopped.
  def handle_info({:DOWN, ref, :process, _pid, :normal}, ref), do: {:noreply, nil}

  # It crashed, or its node went away. Try to take over.
  def handle_info({:DOWN, ref, :process, pid, reason}, ref) do
    Logger.debug("Reminders #{inspect(pid)} down (#{inspect(reason)}), re-electing")
    send(self(), :start_or_monitor)
    {:noreply, nil}
  end
end
