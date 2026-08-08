defmodule Ysc.QueryConsole do
  @moduledoc """
  Outbound link helpers for the standalone Query Console app.
  """

  @doc """
  Public base URL of the Query Console app, or `nil` when unset.

  Configured via `:ysc, :query_console_url` / `QUERY_CONSOLE_URL`.
  """
  @spec url() :: String.t() | nil
  def url do
    case Application.get_env(:ysc, :query_console_url) do
      url when is_binary(url) and url != "" -> String.trim_trailing(url, "/")
      _ -> nil
    end
  end

  @doc """
  Hostname for UI copy (e.g. tooltips), or `nil` when unset.
  """
  @spec host() :: String.t() | nil
  def host do
    case url() do
      nil -> nil
      url -> URI.parse(url).host
    end
  end
end
