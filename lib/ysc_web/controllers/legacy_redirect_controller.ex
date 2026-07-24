defmodule YscWeb.LegacyRedirectController do
  @moduledoc """
  Permanent redirects for legacy WordPress URLs.
  """
  use YscWeb, :controller

  def tahoe_booking(conn, _params) do
    permanent_redirect(conn, ~p"/bookings/tahoe")
  end

  def clear_lake_booking(conn, _params) do
    permanent_redirect(conn, ~p"/bookings/clear-lake")
  end

  def login(conn, _params) do
    permanent_redirect(conn, ~p"/users/log-in")
  end

  def register(conn, _params) do
    permanent_redirect(conn, ~p"/users/register")
  end

  defp permanent_redirect(conn, path) do
    conn
    |> put_status(301)
    |> redirect(to: with_query_string(path, conn.query_string))
  end

  defp with_query_string(path, ""), do: path
  defp with_query_string(path, query_string), do: path <> "?" <> query_string
end
