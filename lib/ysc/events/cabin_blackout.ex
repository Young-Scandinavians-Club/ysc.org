defmodule Ysc.Events.CabinBlackout do
  @moduledoc """
  Bridges events held at a YSC cabin to the booking calendar.

  When an event's location is the Lake Tahoe or Clear Lake cabin, the admin
  editor offers to add a booking `Ysc.Bookings.Blackout` spanning the event
  dates so members cannot reserve the cabin while the event is happening.

  Detection is best-effort and based on the event's `location_name` / `address`
  (the event schema has no explicit property field). Matching is intentionally
  narrow so only the actual cabins trigger the prompt.
  """

  # Substrings (case-insensitive) that identify each cabin from an event's
  # location_name or address. Addresses mirror `Ysc.Bookings.PropertyDisplay`.
  @cabin_markers %{
    clear_lake: ["clear lake", "bass road", "kelseyville"],
    tahoe: ["lake tahoe", "tahoe cabin", "cedar lane", "homewood"]
  }

  @doc """
  Returns the booking property (`:tahoe` or `:clear_lake`) an event is held at,
  or `nil` when the event is not at a cabin.
  """
  @spec property_for_event(map()) :: :tahoe | :clear_lake | nil
  def property_for_event(%{} = event) do
    haystack =
      [Map.get(event, :location_name), Map.get(event, :address)]
      |> Enum.map_join(" ", &normalize/1)

    cond do
      matches?(haystack, @cabin_markers.clear_lake) -> :clear_lake
      matches?(haystack, @cabin_markers.tahoe) -> :tahoe
      true -> nil
    end
  end

  def property_for_event(_), do: nil

  @doc """
  Returns `{start_date, end_date}` (California `Date`s) the blackout should cover
  for an event, or `nil` when the event has no start date.

  Single-day events (no `end_date`) return `{date, date}`.
  """
  @spec blackout_range(map()) :: {Date.t(), Date.t()} | nil
  def blackout_range(%{start_date: start_date} = event)
      when not is_nil(start_date) do
    start = to_date(start_date)
    finish = to_date(Map.get(event, :end_date)) || start

    if Date.compare(finish, start) == :lt do
      {start, start}
    else
      {start, finish}
    end
  end

  def blackout_range(_), do: nil

  @doc """
  Builds `Ysc.Bookings.create_blackout/1` attrs (string keys) for an event held
  at a cabin, or `:error` when the event is not at a cabin or has no start date.
  """
  @spec blackout_attrs(map()) :: {:ok, map()} | :error
  def blackout_attrs(%{} = event) do
    with property when not is_nil(property) <- property_for_event(event),
         {start_date, end_date} <- blackout_range(event) do
      {:ok,
       %{
         "property" => property,
         "reason" => reason(event),
         "start_date" => start_date,
         "end_date" => end_date
       }}
    else
      _ -> :error
    end
  end

  def blackout_attrs(_), do: :error

  defp reason(event) do
    title = event |> Map.get(:title) |> to_string() |> String.trim()
    reference_id = Map.get(event, :reference_id)

    base = if title == "", do: "Club event", else: "Event: #{title}"
    suffix = if reference_id in [nil, ""], do: "", else: " (#{reference_id})"

    String.slice(base <> suffix, 0, 500)
  end

  defp matches?(haystack, markers),
    do: Enum.any?(markers, &String.contains?(haystack, &1))

  defp normalize(value) when is_binary(value),
    do: value |> String.downcase() |> String.trim()

  defp normalize(_), do: ""

  defp to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)
  defp to_date(%Date{} = date), do: date
  defp to_date(_), do: nil
end
