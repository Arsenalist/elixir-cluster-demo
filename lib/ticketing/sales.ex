defmodule Ticketing.Sales do
  @moduledoc """
  Per-node sales numbers, used to show `:erpc.multicall/4` fanning out.

  **These numbers are simulated.** There is no database in this demo; each node
  returns a fixed number based on its region so the output is reproducible.
  """

  @last_minute %{"tor1" => 132, "fra1" => 97, "sfo1" => 141, "lhr1" => 88, "sin1" => 120}

  @doc "Tickets this node sold in the last minute (simulated)."
  def last_minute, do: Map.get(@last_minute, Ticketing.region(), 0)
end
