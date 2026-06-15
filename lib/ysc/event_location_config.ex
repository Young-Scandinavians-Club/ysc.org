defmodule Ysc.EventLocationConfig do
  @moduledoc """
  Configurable event venue presets for the admin event editor.

  Presets are defined in `config :ysc, :event_location_presets` and surfaced
  as quick-pick pills when setting an event location.
  """

  @doc """
  Returns all configured event location presets.
  """
  def presets do
    Application.get_env(:ysc, :event_location_presets, [])
  end

  @doc """
  Looks up a preset by its string `id`.

  Returns `{:ok, preset}` or `:error`.
  """
  def get(id) when is_binary(id) do
    case Enum.find(presets(), &(&1.id == id)) do
      nil -> :error
      preset -> {:ok, preset}
    end
  end

  def get(_), do: :error

  @doc """
  Returns presets formatted for the location search hook (`data-presets`).
  """
  def presets_for_search do
    Enum.map(presets(), fn preset ->
      %{
        id: preset.id,
        label: preset.label,
        location_name: preset.location_name,
        address: preset.address,
        latitude: preset.latitude,
        longitude: preset.longitude
      }
    end)
  end
end
