defmodule YscWeb.Api.AppMembersController do
  @moduledoc """
  Member lookup for the admin/volunteer mobile app — lets an admin find which
  member they're taking a payment for (event ticket or membership) by name
  or email, since the app only ever receives a raw member_id otherwise.
  """
  use YscWeb, :controller

  alias Ysc.Accounts

  action_fallback YscWeb.Api.FallbackController

  @min_query_length 2

  def search(conn, %{"q" => query})
      when is_binary(query) and byte_size(query) >= @min_query_length do
    users = Accounts.search_users(query, limit: 10)
    render(conn, :search, users: users)
  end

  def search(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "q (at least #{@min_query_length} characters) is required"
    })
  end
end
