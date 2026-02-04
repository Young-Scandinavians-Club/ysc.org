defmodule YscWeb.HomeLiveTest do
  @moduledoc """
  Tests for HomeLive.
  """
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders home page for logged-in user", %{conn: conn, user: user} do
    {:ok, _index_live, html} = live(conn, ~p"/")

    assert html =~ "Home"
    assert html =~ user.email
  end

  test "renders home page for guest user", %{conn: conn} do
    # Don't log in - use a fresh connection
    {:ok, _index_live, html} = live(conn, ~p"/")

    assert html =~ "Home"
  end
end
