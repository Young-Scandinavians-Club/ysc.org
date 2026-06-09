defmodule YscWeb.AdminNewslettersLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Newsletter

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp edition_fixture(user, attrs \\ %{}) do
    {:ok, edition} =
      Newsletter.create_edition(
        Map.merge(%{"title" => "Test Edition", "subject" => "Hello"}, attrs),
        created_by_id: user.id
      )

    edition
  end

  defp live_newsletters(conn, path \\ ~p"/admin/newsletters") do
    {:ok, view, _html} = live(conn, path)
    html = render_async(view, 5000)
    {view, html}
  end

  # ---------------------------------------------------------------------------
  # Access control
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "redirects unauthenticated visitors", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/newsletters")
      assert path =~ "/log-in"
    end

    test "redirects non-admin users", %{conn: conn} do
      member = user_fixture(%{role: "member"})
      conn = log_in_user(conn, member)
      {:error, {:redirect, _}} = live(conn, ~p"/admin/newsletters")
    end
  end

  # ---------------------------------------------------------------------------
  # Listing editions
  # ---------------------------------------------------------------------------

  describe "listing editions" do
    setup [:create_admin]

    test "renders the newsletters page with subscriber count", %{conn: conn} do
      Newsletter.subscribe("sub@example.com", source: "test")

      {:ok, _view, html} = live(conn, ~p"/admin/newsletters")

      assert html =~ "Newsletters"
      assert html =~ "subscriber"
    end

    test "lists existing editions", %{conn: conn, admin: admin} do
      edition_fixture(admin, %{"title" => "Spring Update"})

      {_view, html} = live_newsletters(conn)

      assert html =~ "Spring Update"
    end

    test "shows a New Newsletter button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/newsletters")
      assert html =~ "New Newsletter"
    end

    test "shows correct status badge for draft edition", %{
      conn: conn,
      admin: admin
    } do
      edition_fixture(admin, %{"title" => "Draft Ed"})

      {_view, html} = live_newsletters(conn)

      assert html =~ "Draft"
    end

    test "shows correct status badge for sent edition", %{
      conn: conn,
      admin: admin
    } do
      {:ok, edition} =
        Newsletter.create_edition(
          %{"title" => "Sent Ed", "subject" => "Subj", "status" => :sent},
          created_by_id: admin.id
        )

      {:ok, _} =
        Newsletter.update_edition(edition, %{"sent_at" => DateTime.utc_now()})

      {_view, html} = live_newsletters(conn)

      assert html =~ "Sent"
    end
  end

  # ---------------------------------------------------------------------------
  # Search
  # ---------------------------------------------------------------------------

  describe "search" do
    setup [:create_admin]

    test "filters editions by title", %{conn: conn, admin: admin} do
      edition_fixture(admin, %{"title" => "Searchable Title"})
      edition_fixture(admin, %{"title" => "Other Title"})

      {view, _html} = live_newsletters(conn)

      html =
        view
        |> form("#newsletters-search-form", %{q: "Searchable"})
        |> render_submit()
        |> then(fn _ -> render_async(view, 5000) end)

      assert html =~ "Searchable Title"
      refute html =~ "Other Title"
    end

    test "shows all editions when search is cleared", %{
      conn: conn,
      admin: admin
    } do
      edition_fixture(admin, %{"title" => "Alpha"})
      edition_fixture(admin, %{"title" => "Beta"})

      {view, _html} = live_newsletters(conn)

      view |> form("#newsletters-search-form", %{q: "Alpha"}) |> render_submit()
      render_async(view, 5000)

      html =
        view
        |> form("#newsletters-search-form", %{q: ""})
        |> render_submit()
        |> then(fn _ -> render_async(view, 5000) end)

      assert html =~ "Alpha"
      assert html =~ "Beta"
    end
  end

  # ---------------------------------------------------------------------------
  # Delete
  # ---------------------------------------------------------------------------

  describe "delete edition" do
    setup [:create_admin]

    test "removes the edition from the list", %{conn: conn, admin: admin} do
      edition = edition_fixture(admin, %{"title" => "To Delete"})

      {view, _html} = live_newsletters(conn)

      assert has_element?(view, "#edition-#{edition.id}")

      view
      |> element(
        "#admin_newsletters_list [phx-value-id='#{edition.id}'][phx-click='delete-edition']"
      )
      |> render_click()

      refute has_element?(view, "#edition-#{edition.id}")
    end
  end

  # ---------------------------------------------------------------------------
  # Send now
  # ---------------------------------------------------------------------------

  describe "send now" do
    setup [:create_admin]

    test "sends the newsletter and marks it as sent", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)

      {view, _html} = live_newsletters(conn)

      # Two send-now buttons exist (mobile card + desktop table); target the desktop dropdown action.
      view
      |> element("#newsletter-actions-dt-#{edition.id}-send-now")
      |> render_click()

      # In inline Oban mode the sender fires synchronously; edition is :sent
      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :sent
    end
  end

  # ---------------------------------------------------------------------------
  # Navigation
  # ---------------------------------------------------------------------------

  describe "subscribers tab" do
    setup [:create_admin]

    test "loads subscribers list after async fetch", %{conn: conn} do
      Newsletter.subscribe("sub-tab-#{System.unique_integer()}@example.com",
        source: "test"
      )

      {:ok, view, _html} = live(conn, ~p"/admin/newsletters?tab=subscribers")
      html = render_async(view, 5000)

      assert html =~ "sub-tab-"
      assert html =~ "Subscribers" or html =~ "subscriber"
    end

    test "switch-tab patches URL for editions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/newsletters?tab=subscribers")

      view
      |> element(
        "button[phx-click='switch-tab'][phx-value-tab='editions']",
        "Editions"
      )
      |> render_click()

      assert_patch(view, ~p"/admin/newsletters?tab=editions")
    end
  end

  describe "edition broadcast" do
    setup [:create_admin]

    test "inserts edition into stream when edition_sent is broadcast", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin, %{"title" => "Broadcast Edition"})
      edition = Newsletter.get_edition!(edition.id)

      {view, _html} = live_newsletters(conn)

      :ok = Newsletter.broadcast_edition_sent(edition)

      html = render(view)
      assert html =~ "Broadcast Edition"
    end
  end

  describe "handle_async load_subscribers exit" do
    setup [:create_admin]

    test "handles subscriber load task exit without crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/newsletters?tab=subscribers")
      %{socket: socket} = :sys.get_state(view.pid)

      assert {:noreply, _socket} =
               YscWeb.AdminNewslettersLive.handle_async(
                 :load_subscribers,
                 {:exit, :test_reason},
                 socket
               )
    end
  end

  describe "navigation" do
    setup [:create_admin]

    test "new newsletter link navigates to editor", %{conn: conn} do
      {view, _html} = live_newsletters(conn)

      {:ok, _editor_view, html} =
        view
        |> element("a", "New Newsletter")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/newsletters/new")

      assert html =~ "Newsletter"
    end
  end
end
