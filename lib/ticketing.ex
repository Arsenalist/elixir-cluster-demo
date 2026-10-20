defmodule Ticketing do
  @moduledoc """
  A tiny box office spread across five "regions" (tor1, fra1, sfo1, lhr1, sin1).

  Every node runs the same release. The only thing that differs between them is
  the `REGION` environment variable, which is what you see in the logs and in
  the IEx prompt (`tor1>`).
  """

  # We define our own `node/1` (region -> node name), so stop importing
  # `Kernel.node/1` (pid -> node name) to avoid the clash.
  import Kernel, except: [node: 1]

  @doc "The region this node runs in, e.g. `\"tor1\"`."
  def region, do: System.get_env("REGION", "local")

  @doc """
  The node name for a region, or `nil` if no connected node is in that region.

      tor1> Ticketing.node(:fra1)
      :"ticketing@10.0.1.12"
  """
  def node(region) do
    region = to_string(region)
    Enum.find([node() | Node.list()], &(Ticketing.Cluster.region_of(&1) == region))
  end
end
