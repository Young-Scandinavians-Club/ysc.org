defmodule YscWeb.AdminHelpGuideLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture(%{role: "volunteer"})
    %{conn: log_in_user(conn, user)}
  end

  test "volunteer can open roles and permissions guide", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin/help/getting-started/roles")

    assert html =~ "Volunteer vs admin permissions"
    assert has_element?(view, "#admin-help-next")
  end

  test "shows wizard steps for a guide", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin/help/posts/publish")

    assert html =~ "Publish a news article"
    assert html =~ "Step 1 of"
    assert has_element?(view, "#admin-help-next")
    assert has_element?(view, "#admin-help-print-guide")
    assert has_element?(view, "#admin-help-print-document")

    html = view |> element("#admin-help-next") |> render_click()
    assert html =~ "Step 2 of"
  end

  test "unknown guide redirects to index", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/help"}}} =
             live(conn, ~p"/admin/help/not/a/guide")
  end

  test "stepper jumps to step", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/help/posts/publish")

    assert has_element?(view, "#admin-help-stepper [aria-current='step']")

    html =
      view
      |> element("#admin-help-stepper button[phx-value-step='2']")
      |> render_click()

    assert html =~ "Step 3 of"

    assert has_element?(
             view,
             "#admin-help-stepper button[phx-value-step='2'][aria-current='step']"
           )
  end

  test "step and highlight params deep-link into the guide", %{conn: conn} do
    highlight = "A real copy of the email goes to your own address"

    {:ok, view, html} =
      live(
        conn,
        ~p"/admin/help/newsletters/send?step=2&highlight=#{highlight}"
      )

    assert html =~ "Step 2 of"
    assert has_element?(view, "mark.admin-help-highlight", "A real copy")

    # Highlight clears when navigating to another step.
    html = view |> element("#admin-help-next") |> render_click()
    assert html =~ "Step 3 of"
    refute has_element?(view, "mark.admin-help-highlight")
  end

  test "out-of-range step param is clamped", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/help/newsletters/send?step=99")

    assert html =~ "Step 5 of 5"
  end

  test "publish step shows member-facing preview below admin screenshot", %{
    conn: conn
  } do
    {:ok, view, html} =
      live(conn, ~p"/admin/help/posts/publish?step=6")

    assert html =~ "Step 6 of"
    assert has_element?(view, "#admin-help-step-5-public")
    assert has_element?(view, "[data-ghost-slug='public-news-list']")
    assert render(view) =~ "What members see on the website"
  end

  test "print button triggers print-page event", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/help/posts/publish")

    assert render_click(view, "print-help") =~ "Publish a news article"

    assert_push_event(view, "print-page", %{
      title: "YSC Admin Guide — Publish a news article"
    })
  end
end
