defmodule YscWeb.Api.EventsController do
  @moduledoc """
  REST API controller for upcoming events.

  Returns paginated upcoming events with pricing, ticket tier,
  and cover image information.
  """
  use YscWeb, :controller

  alias Ysc.Events

  action_fallback YscWeb.Api.FallbackController

  @doc """
  List upcoming events with pagination.

  Query params:
    - page:      1-based page number (default 1)
    - page_size: results per page (default 20, max 100)
  """
  def index(conn, params) do
    {events, meta} = Events.list_upcoming_events_paginated(params)
    render(conn, :index, events: events, meta: meta)
  end
end
