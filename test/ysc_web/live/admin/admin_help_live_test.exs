defmodule YscWeb.AdminHelpLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture(%{role: "volunteer"})
    %{conn: log_in_user(conn, user), volunteer: user}
  end

  test "volunteer can open help index", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/help")

    assert has_element?(view, "h1", "Help")
    assert has_element?(view, "#admin-help-card-posts-publish")
    assert has_element?(view, "#admin-help-card-getting-started-roles")
    assert has_element?(view, "a[href='/admin/help/getting-started']")
    assert has_element?(view, "#admin-help-print-index-document")
    refute has_element?(view, "#admin-help-print-index-button")
  end

  test "help index has no plain filter box, only the assistant finder", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/help")

    refute has_element?(view, "#admin-help-search-form")
    assert has_element?(view, "#admin-help-card-day-of-scanner")
  end

  test "finder result deep-links to the matched step with highlight", %{
    conn: conn
  } do
    prev_open_router = Application.get_env(:ysc, :open_router)
    prev_client = Application.get_env(:ysc, :open_router_client)

    Application.put_env(:ysc, :open_router,
      api_key: "test-key",
      model: "test-model"
    )

    Application.put_env(:ysc, :open_router_client, Ysc.OpenRouter.Mock)

    on_exit(fn ->
      if prev_open_router do
        Application.put_env(:ysc, :open_router, prev_open_router)
      else
        Application.delete_env(:ysc, :open_router)
      end

      if prev_client do
        Application.put_env(:ysc, :open_router_client, prev_client)
      else
        Application.delete_env(:ysc, :open_router_client)
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/help")

    view
    |> form("#admin-help-finder-form", %{
      finder: %{query: "how do I test the email?"}
    })
    |> render_submit()

    # The handle_info round-trip with the mock completes before this render.
    assert has_element?(
             view,
             "#admin-help-finder-open-guide",
             "Open guide at step 2"
           )

    open_guide_html =
      view |> element("#admin-help-finder-open-guide") |> render()

    # The splat-route slug is URL-encoded in hrefs (decoded back by the router).
    assert open_guide_html =~ "/admin/help/newsletters%2Fsend?"
    assert open_guide_html =~ "step=2"
    assert open_guide_html =~ "highlight="

    # Following the link lands on the right guide, step, and highlight.
    {:ok, guide_view, _guide_html} =
      view
      |> element("#admin-help-finder-open-guide")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(guide_view, "h1", "Send or schedule a newsletter")
    assert has_element?(guide_view, "#admin-help-step-1", "Step 2 of")
    assert has_element?(guide_view, "mark.admin-help-highlight")
  end
end
