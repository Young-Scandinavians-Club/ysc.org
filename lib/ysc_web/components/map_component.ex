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
      id="mapComponent"
    >
      <div class="w-full h-80" id="map" phx-hook="RadarMap"></div>
    </div>
    """
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:latitude, assigns[:latitude])
     |> assign(:longitude, assigns[:longitude])
     |> Phoenix.LiveView.push_event("add-marker", %{
       lat: assigns[:latitude],
       lon: assigns[:longitude],
       locked: assigns[:locked]
     })
     |> Phoenix.LiveView.push_event("position", %{})}
  end
end
