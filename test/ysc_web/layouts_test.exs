defmodule YscWeb.LayoutsTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias YscWeb.Layouts

  describe "error_page_title/1" do
    test "prefers explicit page_title assign" do
      assert Layouts.error_page_title(%{page_title: "Custom"}) == "Custom"
    end

    test "maps status codes to titles" do
      assert Layouts.error_page_title(%{status: 400}) == "Bad request"
      assert Layouts.error_page_title(%{status: 403}) == "Access denied"
      assert Layouts.error_page_title(%{status: 404}) == "Page not found"
      assert Layouts.error_page_title(%{status: 500}) == "Something went wrong"
    end

    test "derives title from conn.status when status assign is absent" do
      assert Layouts.error_page_title(%{conn: %Plug.Conn{status: 403}}) ==
               "Access denied"

      assert Layouts.error_page_title(%{conn: %Plug.Conn{status: 400}}) ==
               "Bad request"
    end

    test "falls back to Error when status cannot be derived" do
      assert Layouts.error_page_title(%{}) == "Error"

      assert Layouts.error_page_title(%{conn: %Plug.Conn{status: nil}}) ==
               "Error"

      assert Layouts.error_page_title(%{status: 418}) == "Error"
    end
  end

  describe "toasts_sync_with_flash/1" do
    test "promotes Welcome back info into a dedicated toast and keeps info flash for LiveToast" do
      msg = "Welcome back, friend"

      assert {toasts, flash} =
               Layouts.toasts_sync_with_flash(%{
                 toasts_sync: [],
                 flash: %{"info" => msg}
               })

      assert [%LiveToast{title: "Welcome back!", msg: ^msg}] = toasts
      assert flash["info"] == msg
    end

    test "promotes Good to see you again info into the welcome toast" do
      msg = "Good to see you again."

      assert {toasts, flash} =
               Layouts.toasts_sync_with_flash(%{
                 toasts_sync: [],
                 flash: %{"info" => msg}
               })

      assert [%LiveToast{title: "Welcome back!", msg: ^msg}] = toasts
      assert flash["info"] == msg
    end

    test "promotes flash with title for info, error, and warning" do
      assert {toasts, flash} =
               Layouts.toasts_sync_with_flash(%{
                 toasts_sync: [],
                 flash: %{
                   "info" => "i",
                   "info_toast_title" => "It",
                   "error" => "e",
                   "error_toast_title" => "Et",
                   "warning" => "w",
                   "warning_toast_title" => "Wt"
                 }
               })

      assert length(toasts) == 3
      assert flash["info"] == "i"
      assert flash["error"] == "e"
      assert flash["warning"] == "w"
      assert flash["info_toast_title"] == "It"
      assert flash["error_toast_title"] == "Et"
      assert flash["warning_toast_title"] == "Wt"
    end

    test "normalizes atom flash keys when promoting" do
      assert {_toasts, flash} =
               Layouts.toasts_sync_with_flash(%{
                 flash: %{info: "hello", info_toast_title: "T"}
               })

      assert flash["info"] == "hello"
      assert flash["info_toast_title"] == "T"
    end

    test "prepends promoted toasts to existing toasts_sync" do
      existing = [%LiveToast{kind: :info, msg: "x", title: "t", uuid: "u"}]

      assert {toasts, _} =
               Layouts.toasts_sync_with_flash(%{
                 toasts_sync: existing,
                 flash: %{
                   "error" => "e",
                   "error_toast_title" => "E"
                 }
               })

      assert length(toasts) == 2
      assert match?(%LiveToast{kind: :error}, hd(toasts))
      assert Enum.at(toasts, 1).uuid == "u"
    end
  end

  describe "toast_group_class_fn/1" do
    test "returns positioning classes for each corner" do
      corners = [
        :bottom_left,
        :bottom_center,
        :bottom_right,
        :top_left,
        :top_center,
        :top_right
      ]

      for corner <- corners do
        classes = Layouts.toast_group_class_fn(%{corner: corner})
        assert is_list(classes)
        assert [base | _] = classes
        assert is_binary(base)
        assert Enum.any?(classes, &is_binary/1)
      end
    end
  end

  describe "fullscreen?/1" do
    test "matches auth and onboarding paths" do
      assert Layouts.fullscreen?("/users/log-in")
      assert Layouts.fullscreen?("/users/register")
      assert Layouts.fullscreen?("/users/reset-password")
      assert Layouts.fullscreen?("/users/settings/confirm-email")
      assert Layouts.fullscreen?("/users/log-in/auto")
      assert Layouts.fullscreen?("/account/setup")
      assert Layouts.fullscreen?("/onboarding")
      assert Layouts.fullscreen?("/report-conduct-violation")
    end

    test "returns false for other paths and non-matching types" do
      refute Layouts.fullscreen?("/")
      refute Layouts.fullscreen?("/other")
      refute Layouts.fullscreen?(:not_a_conn)
    end

    test "uses request path from a conn" do
      conn = conn(:get, "/users/log-in")
      assert Layouts.fullscreen?(conn)
    end
  end

  describe "hero_mode?/2" do
    test "home is hero when no user" do
      assert Layouts.hero_mode?("/", nil)
    end

    test "home is not hero when user present" do
      refute Layouts.hero_mode?("/", %{})
    end

    test "booking tahoe and clear-lake paths" do
      assert Layouts.hero_mode?("/bookings/tahoe/x", nil)
      assert Layouts.hero_mode?("/bookings/clear-lake", %{})
    end

    test "returns false for other paths and fallback clauses" do
      refute Layouts.hero_mode?("/about", nil)
      refute Layouts.hero_mode?(:bad, nil)
    end

    test "uses path from conn" do
      conn = conn(:get, "/bookings/tahoe")
      assert Layouts.hero_mode?(conn, nil)
    end
  end
end
