defmodule Ticketing.BoxOffice do
  @moduledoc """
  The simplest possible box office: one process per node holding a seat count.

  It is registered locally under the name `BoxOffice` on every node, which is
  what makes `{BoxOffice, node}` addressing work from anywhere in the cluster:

      # fire and forget, the reply comes back as a message
      send({BoxOffice, fra1}, {:hold, 2, self()})

      # request/response
      GenServer.call({BoxOffice, fra1}, {:hold, 2})
      #=> {:ok, %{held: 2, seats_left: 46}}
  """
  use GenServer

  @seats 50

  def start_link(_opts), do: GenServer.start_link(__MODULE__, @seats, name: BoxOffice)

  @impl true
  def init(seats), do: {:ok, seats}

  # A plain message. Whoever sent it told us where to reply.
  @impl true
  def handle_info({:hold, n, reply_to}, seats_left) do
    seats_left = seats_left - n
    send(reply_to, {:held, n, seats_left: seats_left})
    {:noreply, seats_left}
  end

  # The same thing as a call: GenServer handles the reply, the timeout and the
  # monitor for us.
  @impl true
  def handle_call({:hold, n}, _from, seats_left) do
    seats_left = seats_left - n
    {:reply, {:ok, %{held: n, seats_left: seats_left}}, seats_left}
  end
end
