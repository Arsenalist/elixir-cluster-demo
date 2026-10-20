defmodule Ticketing.ShowsTest do
  use ExUnit.Case, async: true

  alias Ticketing.Shows

  test "a single node owns every show" do
    assert Shows.owner(26) == node()
  end

  test "the last seat goes to exactly one caller" do
    show = System.unique_integer([:positive])
    assert {:ok, seats_left: 1} = Shows.open(show, ["F12"])

    results =
      1..2
      |> Enum.map(fn _ -> Task.async(fn -> Shows.hold(show, 1) end) end)
      |> Task.await_many()

    assert Enum.sort(results) == [{:error, :sold_out}, {:ok, seat: "F12"}]
  end

  test "box office replies to plain messages and calls" do
    send(BoxOffice, {:hold, 0, self()})
    assert_receive {:held, 0, seats_left: _}
    assert {:ok, %{held: 0}} = GenServer.call(BoxOffice, {:hold, 0})
  end
end
