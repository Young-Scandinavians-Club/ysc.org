defmodule YscWeb.AdminHelpGuideLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture(%{role: "volunteer"})
    %{conn: log_in_user(conn, user)}
  end

  test "volunteer can open roles and permissions guide", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/help/getting-started/roles")

    assert has_element?(view, "h1", "Volunteer vs admin permissions")
    assert has_element?(view, "#admin-help-next")
  end

  test "shows wizard steps for a guide", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/help/posts/publish")

    assert has_element?(view, "h1", "Publish a news article")
    assert has_element?(view, "#admin-help-step-0", "Step 1 of")
    assert has_element?(view, "#admin-help-next")
    assert has_element?(view, "#admin-help-print-guide")
    assert has_element?(view, "#admin-help-print-document")

    view |> element("#admin-help-next") |> render_click()
    assert_patch(view, "/admin/help/posts%2Fpublish?step=2")
    assert has_element?(view, "#admin-help-step-1", "Step 2 of")
  end

  test "unknown guide redirects to index", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/help"}}} =
             live(conn, ~p"/admin/help/not/a/guide")
  end

  test "stepper jumps to step", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/help/posts/publish")

    assert has_element?(view, "#admin-help-stepper [aria-current='step']")

    view
    |> element("#admin-help-stepper button[phx-value-step='2']")
    |> render_click()

    assert_patch(view, "/admin/help/posts%2Fpublish?step=3")

    assert has_element?(
             view,
             "#admin-help-stepper button[phx-value-step='2'][aria-current='step']"
           )
  end

  test "step and highlight params deep-link into the guide", %{conn: conn} do
    highlight = "A real copy of the email goes to your own address"

    {:ok, view, _html} =
      live(
        conn,
        ~p"/admin/help/newsletters/send?step=2&highlight=#{highlight}"
      )

    assert has_element?(view, "#admin-help-step-1", "Step 2 of")
    assert has_element?(view, "mark.admin-help-highlight", "A real copy")

    # Highlight clears when navigating to another step.
    view |> element("#admin-help-next") |> render_click()
    assert_patch(view, "/admin/help/newsletters%2Fsend?step=3")
    refute has_element?(view, "mark.admin-help-highlight")
  end

  test "reload restores the step from the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/help/posts/publish?step=4")

    assert has_element?(view, "#admin-help-step-3", "Step 4 of")

    {:ok, view, _html} = live(conn, ~p"/admin/help/posts/publish?step=4")

    assert has_element?(view, "#admin-help-step-3", "Step 4 of")
  end

  test "out-of-range step param is clamped", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/help/newsletters/send?step=99")

    assert has_element?(view, "#admin-help-step-4", "Step 5 of 5")
  end

  test "publish step shows member-facing preview below admin screenshot", %{
    conn: conn
  } do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/posts/publish?step=6")

    assert has_element?(view, "#admin-help-step-5", "Step 6 of")
    assert has_element?(view, "#admin-help-step-5-public")
    assert has_element?(view, "[data-ghost-slug='public-news-list']")

    assert has_element?(
             view,
             "#admin-help-step-5",
             "What members see on the website"
           )
  end

  test "FAQ and troubleshooting live on a separate help tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/help/posts/publish")

    assert has_element?(view, "#admin-help-guide-tabs")
    refute has_element?(view, "#admin-help-appendix-faq")

    view |> element("#admin-help-guide-tabs-help") |> render_click()
    assert_patch(view, "/admin/help/posts%2Fpublish?step=1&view=help")

    assert has_element?(view, "#admin-help-appendix-faq", "featured image")

    assert has_element?(
             view,
             "#admin-help-appendix-troubleshooting",
             "settings modal"
           )

    refute has_element?(view, "#admin-help-step-0")

    view |> element("#admin-help-guide-tabs-steps") |> render_click()
    assert_patch(view, "/admin/help/posts%2Fpublish?step=1")
    assert has_element?(view, "#admin-help-step-0")
    refute has_element?(view, "#admin-help-appendix-faq")
  end

  test "help tab deep-links from the URL", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, ~p"/admin/help/posts/publish?view=help&step=3")

    assert has_element?(view, "#admin-help-appendix-faq")

    assert has_element?(
             view,
             "#admin-help-guide-tabs-help[aria-current='page']"
           )

    refute has_element?(view, "#admin-help-step-2")
  end

  test "print button triggers print-page event", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/help/posts/publish")

    assert render_click(view, "print-help") =~ "Publish a news article"

    assert_push_event(view, "print-page", %{
      title: "YSC Admin Guide — Publish a news article"
    })
  end
end
