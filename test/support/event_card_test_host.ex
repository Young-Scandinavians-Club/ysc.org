defmodule YscWeb.EventCardTestHost do
  @moduledoc false
  use YscWeb, :live_component

  import YscWeb.CoreComponents

  @impl true
  def render(assigns) do
    ~H"""
    <div id="event-card-test-host">
      <.event_card event={@event} sold_out={@sold_out} selling_fast={@selling_fast} />
    </div>
    """
  end
end
