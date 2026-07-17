defmodule YscWeb.LegacyRedirectController do
  @moduledoc """
  Permanent redirects for legacy WordPress URLs.
  """
  use YscWeb, :controller

  def register(conn, _params) do
    conn
    |> put_status(301)
    |> redirect(to: with_query_string(~p"/users/register", conn.query_string))
  end

  defp with_query_string(path, ""), do: path
  defp with_query_string(path, query_string), do: path <> "?" <> query_string
end
