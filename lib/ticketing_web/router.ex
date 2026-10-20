defmodule TicketingWeb.Router do
  use TicketingWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", TicketingWeb do
    pipe_through :api
  end
end
