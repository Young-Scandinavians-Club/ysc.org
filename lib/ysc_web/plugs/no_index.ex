defmodule YscWeb.Plugs.NoIndex do
  @moduledoc """
  Sets the `X-Robots-Tag: noindex, nofollow` response header to prevent search
  engines from indexing the response.

  Used in the admin pipeline so that admin pages are never indexed.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    put_resp_header(conn, "x-robots-tag", "noindex, nofollow")
  end
end
