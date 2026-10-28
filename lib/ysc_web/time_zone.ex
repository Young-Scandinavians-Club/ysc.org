defmodule YscWeb.TimeZone do
  @moduledoc """
  Browser timezone resolution for LiveViews, plus helpers for HTML
  `datetime-local` inputs and Pacific wall-clock instants.

  LiveSocket sends the IANA name via connect params (`timezone`). Invalid or
  missing values fall back to Pacific time (`America/Los_Angeles`).

  Use `at/2` and `at_utc/2` to turn a calendar date plus wall-clock time into
  a zoned `DateTime` (or UTC) without repeating `DateTime.new!/3` +
  `shift_zone!/2` at each call site.
  """

  @default "America/Los_Angeles"
  @datetime_local_format "%Y-%m-%dT%H:%M"

  @doc """
  Returns the configured default timezone (`America/Los_Angeles` unless overridden).
  """
  def default do
    Application.get_env(:ysc, :default_timezone, @default)
  end

  @doc """
  Reads the browser timezone from LiveView connect params.

  Falls back to `default/0` on the disconnected render (no connect params),
  blank values, and unknown IANA names.
  """
  def from_connect_params(socket) do
    params = Phoenix.LiveView.get_connect_params(socket) || %{}
    from_name(Map.get(params, "timezone"))
  end

  @doc """
  Returns `name` when it is a valid IANA timezone, otherwise `default/0`.
  """
  def from_name(name) when is_binary(name) and name != "" do
    case DateTime.now(name) do
      {:ok, _} -> name
      _ -> default()
    end
  end

  def from_name(_), do: default()

  @doc """
  Current `DateTime` in `timezone`, falling back to Pacific time.
  """
  def now(timezone \\ default()) do
    DateTime.now!(from_name(timezone))
  end

  @doc """
  Current calendar date in `timezone`, falling back to Pacific time.
  """
  def today(timezone \\ default()) do
    timezone |> now() |> DateTime.to_date()
  end

  @doc """
  Shifts a UTC instant into `timezone`, falling back to Pacific time.
  """
  def shift(%DateTime{} = datetime, timezone) do
    DateTime.shift_zone!(datetime, from_name(timezone))
  end

  @doc """
  Wall-clock instant for `date` at `time` in `timezone` (Pacific by default).

      TimeZone.at(~D[2024-06-15], ~T[13:00:00]).time_zone
      #=> "America/Los_Angeles"
  """
  def at(%Date{} = date, %Time{} = time, timezone \\ default()) do
    DateTime.new!(date, time, from_name(timezone))
  end

  @doc """
  UTC instant for `date` at `time` in `timezone` (Pacific by default).

  Use this to schedule Oban jobs and compare against `DateTime.utc_now/0`.

      TimeZone.at_utc(~D[2024-06-15], ~T[13:00:00])
      #=> ~U[2024-06-15 20:00:00Z]
  """
  def at_utc(%Date{} = date, %Time{} = time, timezone \\ default()) do
    date
    |> at(time, timezone)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  @doc """
  Formats a UTC datetime for an HTML `datetime-local` input in `timezone`.

  `datetime-local` values are naive local timestamps (`YYYY-MM-DDTHH:MM`).
  Defaults to Pacific time. Returns `""` for nil and passes through binaries
  that are already formatted.

      TimeZone.format_datetime_local(~U[2024-06-15 20:00:00Z])
      #=> "2024-06-15T13:00"
  """
  def format_datetime_local(datetime, timezone \\ default())

  def format_datetime_local(%DateTime{} = datetime, timezone) do
    datetime
    |> shift(timezone)
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime(@datetime_local_format)
  end

  def format_datetime_local(nil, _timezone), do: ""

  def format_datetime_local(datetime, _timezone) when is_binary(datetime),
    do: datetime

  @doc """
  Parses an HTML `datetime-local` value (`YYYY-MM-DDTHH:MM`) in `timezone`
  and returns UTC.

  Defaults to Pacific time. Returns `{:ok, datetime}` or `{:error, reason}`.

      TimeZone.parse_datetime_local("2024-06-15T13:00")
      #=> {:ok, ~U[2024-06-15 20:00:00Z]}
  """
  def parse_datetime_local(value, timezone \\ default())

  def parse_datetime_local(value, timezone) when is_binary(value) do
    case NaiveDateTime.from_iso8601("#{value}:00") do
      {:ok, naive_dt} ->
        local_dt = DateTime.from_naive!(naive_dt, from_name(timezone))
        {:ok, DateTime.shift_zone!(local_dt, "Etc/UTC")}

      {:error, _} = error ->
        error
    end
  end

  def parse_datetime_local(_, _), do: {:error, :invalid_format}
end
