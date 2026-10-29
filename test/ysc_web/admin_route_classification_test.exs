defmodule YscWeb.AdminRouteClassificationTest do
  @moduledoc """
  Every `/admin` route must be classified as staff (admin and volunteer) or
  full-admin only.

  Volunteers can enter the whole `/admin` live session, and a LiveView is
  only closed to them when it carries `on_mount {UserAuth, :ensure_full_admin}`
  (or sits behind the `full_admin_only` pipeline for controllers). A new admin
  page that forgets the hook would therefore be open to volunteers, so this
  test fails until each new route is placed in one of the lists below on
  purpose. Full-admin routes are also exercised as a signed-in volunteer to
  confirm they really refuse.
  """
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  # Pages volunteers may open.
  @staff_liveviews [
    YscWeb.AdminDashboardLive,
    YscWeb.AdminEventCheckInLive,
    YscWeb.AdminEventsLive,
    YscWeb.AdminEventsNewLive,
    YscWeb.AdminHelpGhostLive,
    YscWeb.AdminHelpGuideLive,
    YscWeb.AdminHelpLive,
    YscWeb.AdminMediaLive,
    YscWeb.AdminMembershipCheckInLive,
    YscWeb.AdminNewsletterEditorLive,
    YscWeb.AdminNewslettersLive,
    YscWeb.AdminPostEditorLive,
    YscWeb.AdminPostsLive,
    YscWeb.AdminScannerLive
  ]

  # Pages closed to volunteers by `on_mount {UserAuth, :ensure_full_admin}`.
  @full_admin_liveviews [
    YscWeb.AdminBookingEntitlementsLive,
    YscWeb.AdminBookingsLive,
    YscWeb.AdminMembershipReportLive,
    YscWeb.AdminMembershipsLive,
    YscWeb.AdminMerchLive,
    YscWeb.AdminMerchOrderNewLive,
    YscWeb.AdminMerchOrdersLive,
    YscWeb.AdminMoneyLive,
    YscWeb.AdminSettingsLive,
    YscWeb.AdminUserDetailsLive,
    YscWeb.AdminUsersLive
  ]

  # Closed to volunteers by the router's `full_admin_only` pipeline instead of
  # a mount hook (`live_dashboard`).
  @full_admin_pipeline_liveviews [Phoenix.LiveDashboard.PageLive]

  # Controller routes volunteers may use.
  @staff_http [
    {:get, "/admin/events/:id/tv-poster"},
    {:get, "/admin/events/:id/tv-poster/image"},
    {:get, "/admin/exports/:filename"},
    {:post, "/admin/trix-uploads"}
  ]

  # Controller routes behind the `full_admin_only` pipeline.
  @full_admin_http [
    {:delete, "/admin/integrations/google-photos"},
    {:get, "/admin/dashboard/css-:md5"},
    {:get, "/admin/dashboard/js-:md5"},
    {:get, "/admin/integrations/google-photos/callback"},
    {:get, "/admin/integrations/google-photos/connect"},
    {:post, "/admin/impersonate/:user_id"},
    {:post, "/admin/stop-impersonation"}
  ]

  @ensure_full_admin {YscWeb.UserAuth, :ensure_full_admin}

  describe "classification" do
    test "every admin LiveView is classified" do
      classified =
        @staff_liveviews ++
          @full_admin_liveviews ++ @full_admin_pipeline_liveviews

      assert Enum.sort(liveview_modules()) == Enum.sort(classified),
             "Admin LiveViews not in sync with the classification lists. " <>
               "Unclassified: #{inspect(liveview_modules() -- classified)}. " <>
               "Stale: #{inspect(classified -- liveview_modules())}. " <>
               "Add new pages to @staff_liveviews or, if volunteers must not " <>
               "see them, to @full_admin_liveviews with ensure_full_admin."
    end

    test "every admin controller route is classified" do
      classified = @staff_http ++ @full_admin_http

      assert Enum.sort(http_routes()) == Enum.sort(classified),
             "Unclassified: #{inspect(http_routes() -- classified)}. " <>
               "Stale: #{inspect(classified -- http_routes())}."
    end

    test "full-admin LiveViews carry the ensure_full_admin mount hook" do
      missing =
        Enum.reject(@full_admin_liveviews, &has_full_admin_hook?/1)

      assert missing == [],
             "Add `on_mount #{inspect(@ensure_full_admin)}` to: #{inspect(missing)}"
    end

    test "staff LiveViews do not carry the ensure_full_admin mount hook" do
      assert Enum.filter(@staff_liveviews, &has_full_admin_hook?/1) == [],
             "These are listed as staff pages but close to volunteers."
    end
  end

  describe "as a volunteer" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, user_fixture(%{role: :volunteer}))}
    end

    test "every full-admin LiveView redirects to /admin", %{conn: conn} do
      for {path, module} <- liveview_routes(),
          module in @full_admin_liveviews do
        assert {:error, {kind, %{to: "/admin"}}} = live(conn, path),
               "#{inspect(module)} at #{path} let a volunteer in"

        assert kind in [:redirect, :live_redirect]
      end
    end

    test "every full-admin controller route and the dashboard redirect to /admin",
         %{conn: conn} do
      paths =
        for {verb, path} <- @full_admin_http, do: {verb, fill_params(path)}

      for {verb, path} <- [{:get, "/admin/dashboard"} | paths] do
        conn = Phoenix.ConnTest.dispatch(conn, @endpoint, verb, path, %{})

        assert redirected_to(conn) == "/admin",
               "#{verb} #{path} let a volunteer in"
      end
    end

    test "volunteers are admitted to the admin area itself", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, ~p"/admin")
    end
  end

  defp admin_routes do
    Enum.filter(
      YscWeb.Router.__routes__(),
      &String.starts_with?(&1.path, "/admin")
    )
  end

  defp liveview_routes do
    for %{path: path, metadata: %{phoenix_live_view: {module, _, _, _}}} <-
          admin_routes() do
      {fill_params(path), module}
    end
  end

  defp liveview_modules do
    for %{metadata: %{phoenix_live_view: {module, _, _, _}}} <- admin_routes(),
        uniq: true,
        do: module
  end

  defp http_routes do
    for %{verb: verb, path: path, metadata: metadata} <- admin_routes(),
        not Map.has_key?(metadata, :phoenix_live_view),
        do: {verb, path}
  end

  defp has_full_admin_hook?(module) do
    module.__live__().lifecycle.mount
    |> Enum.any?(&(&1.id == @ensure_full_admin))
  end

  # Fills `:param` and `*glob` segments with throwaway values. The guards under
  # test run before the page loads anything.
  defp fill_params(path) do
    path
    |> String.replace(~r/:[a-z_]+/, "01ARZ3NDEKTSV4RRFFQ69G5FAV")
    |> String.replace(~r/\*[a-z_]+/, "x")
  end
end
