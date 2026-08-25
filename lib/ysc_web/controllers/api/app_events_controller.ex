defmodule YscWeb.Api.AppEventsController do
  @moduledoc """
  Upcoming events for the admin/volunteer mobile app.

  Unlike the kiosk-facing `EventsController` (which lists everything so
  guests can browse), this only includes events with at least one `:paid`
  or `:donation` ticket tier — the app is for taking payments, so an event
  with no payable tier (not yet priced, or free-only) isn't actionable here.
  """
  use YscWeb, :controller

  alias Ysc.Events

  action_fallback YscWeb.Api.FallbackController

  @doc """
  List upcoming payable events with pagination.

  Query params:
    - page:      1-based page number (default 1)
    - page_size: results per page (default 20, max 100)
  """
  def index(conn, params) do
    {events, meta} =
      Events.list_upcoming_events_paginated(params, require_payable_tier: true)

    render(conn, :index, events: events, meta: meta)
  end
end
