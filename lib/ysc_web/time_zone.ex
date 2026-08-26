defmodule YscWeb.TimeZone do
  @moduledoc """
  Browser timezone resolution for LiveViews.

  LiveSocket sends the IANA name via connect params (`timezone`). Invalid or
  missing values fall back to Pacific time (`America/Los_Angeles`).
  """

  @default "America/Los_Angeles"

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
end
