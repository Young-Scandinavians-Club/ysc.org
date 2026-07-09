defmodule YscWeb.Components.MapComponent do
  @moduledoc """
  LiveView component for displaying maps.

  Provides an interactive map display component for showing event locations.
  """
  use YscWeb, :live_component

  def render(assigns) do
    ~H"""
    <div
      style="overflow: hidden"
      class="border border-zinc-300 rounded w-full h-80"
      phx-update="ignore"
      id={"#{@id}-container"}
    >
      <div
        class="w-full h-80"
        id={@id}
        phx-hook="RadarMap"
        data-cooperative-gestures={to_string(@cooperative_gestures)}
      >
      </div>
    </div>
    """
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:id, assigns.id)
     |> assign(:latitude, assigns[:latitude])
     |> assign(:longitude, assigns[:longitude])
     |> assign(
       :cooperative_gestures,
       Map.get(assigns, :cooperative_gestures, true)
     )
     |> Phoenix.LiveView.push_event("add-marker", %{
       lat: assigns[:latitude],
       lon: assigns[:longitude],
       locked: assigns[:locked]
     })
     |> Phoenix.LiveView.push_event("position", %{})}
  end
end
