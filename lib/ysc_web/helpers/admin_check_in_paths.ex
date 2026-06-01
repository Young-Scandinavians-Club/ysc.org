defmodule YscWeb.AdminCheckInPaths do
  @moduledoc false

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.Scanning

  @doc """
  Returns the admin check-in URL for an event.

  When an open scan session exists, links to the membership desk for
  `:event_membership` sessions; otherwise the ticket event check-in desk.

  Pass a preloaded `open_sessions_by_event_id` map from
  `Scanning.get_open_check_in_sessions_by_event_id/1` to avoid a query.
  """
  def path_for_event(event_id, open_sessions_by_event_id \\ nil) do
    session =
      case open_sessions_by_event_id do
        %{} = by_id -> Map.get(by_id, event_id)
        nil -> Scanning.get_open_session_for_event(event_id)
      end

    case session do
      %{type: :event_membership, id: session_id} ->
        ~p"/admin/membership-check-in/#{session_id}"

      _ ->
        ~p"/admin/events/#{event_id}/check-in"
    end
  end
end
