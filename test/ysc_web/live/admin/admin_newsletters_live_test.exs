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

      # Re-render after send-now: stream updates must not crash when :creator is NotLoaded.
      html = render(view)
      assert html =~ "Sent"

      # In inline Oban mode the sender fires synchronously; edition is :sent
      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :sent
    end

    test "renders edition when edition_sent delivers edition without preloaded creator",
         %{
           conn: conn,
           admin: admin
         } do
      edition = edition_fixture(admin, %{"title" => "Raw Sent Edition"})
      edition = Newsletter.get_edition!(edition.id)

      {view, _html} = live_newsletters(conn)

      send(view.pid, {:edition_sent, edition})

      html = render(view)
      assert html =~ "Raw Sent Edition"
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

    test "paginating subscribers patches to the next page", %{conn: conn} do
      # default_limit is 20; need a second page of results
      for i <- 1..21 do
        Newsletter.subscribe(
          "page-sub-#{i}-#{System.unique_integer()}@example.com",
          source: "test"
        )
      end

      {:ok, view, _html} =
        live(conn, ~p"/admin/newsletters?tab=subscribers&page=1")

      render_async(view, 5000)

      # Regression: path must not keep page=1 when linking to page=2
      assert has_element?(
               view,
               ".hidden.md\\:block a[rel='next'][href*='page=2']"
             )

      refute has_element?(
               view,
               ".hidden.md\\:block a[rel='next'][href*='page=1']"
             )

      view
      |> element(".hidden.md\\:block a[rel='next']")
      |> render_click()

      assert_patch(view, ~p"/admin/newsletters?page=2&tab=subscribers")
      render_async(view, 5000)

      assert has_element?(
               view,
               ".hidden.md\\:block a[aria-current='page']",
               "2"
             )
    end
  end

  describe "saved notices tab" do
    setup [:create_admin]

    test "lists saved notices and opens create modal", %{
      conn: conn,
      admin: admin
    } do
      admin =
        admin
        |> Ecto.Changeset.change(%{first_name: "Ada", last_name: "Admin"})
        |> Ysc.Repo.update!()

      {:ok, _notice} =
        Newsletter.create_notice(
          %{"name" => "Parking reminder", "body" => "<p>Lot B</p>"},
          created_by_id: admin.id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/newsletters?tab=notices")
      html = render_async(view, 5000)

      assert html =~ "Saved notices"
      assert html =~ "Parking reminder"
      assert html =~ "Ada Admin"
      assert has_element?(view, "#new-notice-btn")

      view |> element("#new-notice-btn") |> render_click()
      assert has_element?(view, "#notice-form")
      assert has_element?(view, "#notice-name")
    end

    test "deletes a notice", %{conn: conn, admin: admin} do
      {:ok, notice} =
        Newsletter.create_notice(
          %{"name" => "Delete me", "body" => "<p>bye</p>"},
          created_by_id: admin.id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/newsletters?tab=notices")
      render_async(view, 5000)

      view
      |> element("#notice-actions-dt-#{notice.id}-delete")
      |> render_click()

      refute has_element?(view, "#notice-#{notice.id}")
    end

    test "clicking a table row opens the edit modal", %{
      conn: conn,
      admin: admin
    } do
      {:ok, notice} =
        Newsletter.create_notice(
          %{"name" => "Row click notice", "body" => "<p>Hello</p>"},
          created_by_id: admin.id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/newsletters?tab=notices")
      render_async(view, 5000)

      view |> element("#notice-#{notice.id}") |> render_click()

      assert has_element?(view, "#notice-modal")
      assert has_element?(view, "#notice-form")
      assert render(view) =~ "Edit notice"
      assert has_element?(view, "#notice-name[value='Row click notice']")
    end
  end

  describe "duplicate edition" do
    setup [:create_admin]

    test "duplicates from the list and navigates to the new draft", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin, %{"title" => "Original Edition"})
      {view, _html} = live_newsletters(conn)

      {:ok, editor_view, _html} =
        view
        |> element("#newsletter-actions-dt-#{edition.id}-duplicate")
        |> render_click()
        |> follow_redirect(conn)

      render_async(editor_view, 5000)

      assert editor_view
             |> element("input[name='edition[title]']")
             |> render() =~ "Original Edition (copy)"

      copy =
        Newsletter.list_editions()
        |> Enum.find(&(&1.title == "Original Edition (copy)"))

      assert copy
      assert copy.status == :draft
      assert copy.id != edition.id
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

    test "renders edition when delivery progress is broadcast without preloaded creator",
         %{
           conn: conn,
           admin: admin
         } do
      edition = edition_fixture(admin, %{"title" => "Progress Edition"})

      {view, _html} = live_newsletters(conn)

      {:ok, progress_edition} =
        Newsletter.update_edition(edition, %{
          "status" => :sending,
          "sent_count" => 1
        })

      :ok = Newsletter.broadcast_edition_delivery_progress(progress_edition)

      html = render(view)
      assert html =~ "Progress Edition"
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

  describe "editing presence" do
    setup [:create_admin]

    test "shows an avatar on the row of an edition currently being edited", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin, %{"title" => "Being edited"})
      other_admin = user_fixture(%{role: "admin", first_name: "Jamie"})

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: "row-tab-#{System.unique_integer([:positive])}"},
          :newsletter,
          edition.id,
          other_admin
        )

      {_view, html} = live_newsletters(conn)

      assert html =~ "Jamie"
      assert html =~ "is editing"
    end

    test "does not show the current admin's own presence", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin, %{"title" => "Own tab open"})

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: "self-row-tab-#{System.unique_integer([:positive])}"},
          :newsletter,
          edition.id,
          admin
        )

      {_view, html} = live_newsletters(conn)

      refute html =~ "is editing"
    end

    test "updates row avatars live when another admin starts editing", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin, %{"title" => "Live update row"})

      {view, html} = live_newsletters(conn)
      refute html =~ "is editing"

      other_admin = user_fixture(%{role: "admin", first_name: "Taylor"})

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: "live-row-tab-#{System.unique_integer([:positive])}"},
          :newsletter,
          edition.id,
          other_admin
        )

      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: YscWeb.Admin.EditingPresence.topic(:newsletter),
        event: "presence_diff",
        payload: %{}
      })

      html = render(view)
      assert html =~ "Taylor"
      assert html =~ "is editing"
    end
  end

  describe "last edited by" do
    setup [:create_admin]

    test "is not shown on the listing page", %{conn: conn, admin: admin} do
      edition_fixture(admin, %{"title" => "Not on listing"})

      {_view, html} = live_newsletters(conn)

      refute html =~ "Last edited by"
    end
  end
end
