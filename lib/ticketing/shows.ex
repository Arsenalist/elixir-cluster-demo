defmodule Ticketing.Shows do
  @moduledoc """
  Every show is owned by exactly one node, and every hold for that show runs
  there, inside one process. One process handles one message at a time, so two
  people grabbing the last seat at the same moment can't both get it.

  Which node owns a show? Rendezvous hashing (highest random weight): hash the
  show id together with each node name and pick the node with the highest
  score. Every node computes the same answer from the same member list, with
  no coordination, and when a node leaves only its shows move.

      tor1> Ticketing.Shows.owner(42)
      :"ticketing@10.0.1.13"

  See Johanna Larsson's https://jola.dev/posts/distributed-ratelimiter-with-hrw
  """

  import Kernel, except: [node: 1]

  alias Ticketing.Show

  @doc "The node that owns `show_id`."
  def owner(show_id) do
    [node() | Node.list()]
    |> Enum.sort()
    |> Enum.max_by(&:erlang.phash2({show_id, &1}))
  end

  @doc """
  Hold `n` seats for a show. Runs on the owner, wherever we call it from.

      {:ok, seat: "F12"}          # one seat
      {:ok, seats: ["A1", "A2"]}  # several
      {:error, :sold_out}
  """
  def hold(show_id, n \\ 1) do
    :erpc.call(owner(show_id), __MODULE__, :local_hold, [show_id, n])
  end

  @doc """
  (Re)open a show on its owner with exactly these seats left. For the demo:

      Ticketing.Shows.open(42, ["F12"])   # one seat left
  """
  def open(show_id, seats) do
    :erpc.call(owner(show_id), __MODULE__, :local_open, [show_id, seats])
  end

  @doc false
  # Runs on the owning node. Start the show's process on first use.
  def local_hold(show_id, n), do: show_id |> local_show() |> Show.hold(n)

  @doc false
  def local_open(show_id, seats), do: show_id |> local_show() |> Show.reset(seats)

  defp local_show(show_id) do
    case DynamicSupervisor.start_child(Ticketing.ShowSupervisor, {Show, show_id}) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end
end

defmodule Ticketing.Show do
  @moduledoc """
  One process per show, registered by show id in the node-local
  `Ticketing.ShowRegistry`. It holds the list of seats still for sale.
  """
  use GenServer, restart: :temporary

  # 50 seats: rows A-E, seats 1-10.
  @all_seats for row <- ~w(A B C D E), n <- 1..10, do: "#{row}#{n}"

  def start_link(show_id) do
    GenServer.start_link(__MODULE__, @all_seats, name: via(show_id))
  end

  def hold(pid, n), do: GenServer.call(pid, {:hold, n})
  def reset(pid, seats), do: GenServer.call(pid, {:reset, seats})

  defp via(show_id), do: {:via, Registry, {Ticketing.ShowRegistry, show_id}}

  @impl true
  def init(seats), do: {:ok, seats}

  @impl true
  def handle_call({:hold, n}, _from, seats) when length(seats) < n do
    {:reply, {:error, :sold_out}, seats}
  end

  def handle_call({:hold, 1}, _from, [seat | rest]), do: {:reply, {:ok, seat: seat}, rest}

  def handle_call({:hold, n}, _from, seats) do
    {held, rest} = Enum.split(seats, n)
    {:reply, {:ok, seats: held}, rest}
  end

  def handle_call({:reset, seats}, _from, _seats),
    do: {:reply, {:ok, seats_left: length(seats)}, seats}
end
