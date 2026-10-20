defmodule Ticketing.Reminders do
  @moduledoc """
  A cluster-wide singleton: exactly one of these runs in the whole cluster,
  registered globally as `{:global, Ticketing.Reminders}`.

  Think "send the 'your show starts in an hour' emails". You want that done
  once, not once per node. It doesn't actually send anything here.

  Nobody starts this directly. `Ticketing.SingletonManager` (one per node)
  starts it if nobody else has, and starts it again if it dies.
  """
  use GenServer, restart: :temporary
  require Logger

  @name {:global, __MODULE__}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: @name)

  @impl true
  def init(:ok) do
    Logger.info("Reminders started under #{inspect(@name)}")
    {:ok, %{}}
  end
end
