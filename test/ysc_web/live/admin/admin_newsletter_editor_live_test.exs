defmodule YscWeb.AdminNewsletterEditorLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
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
        Map.merge(
          %{"title" => "My Newsletter", "subject" => "Weekly news"},
          attrs
        ),
        created_by_id: user.id
      )

    edition
  end

  defp live_editing_edition(conn, edition) do
    {:ok, view, _html} = live(conn, ~p"/admin/newsletters/#{edition.id}/edit")
    render_async(view)
    view
  end

  # ---------------------------------------------------------------------------
  # Access control
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "redirects unauthenticated visitors to login", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} =
        live(conn, ~p"/admin/newsletters/new")

      assert path =~ "/log-in"
    end

    test "redirects non-admin users", %{conn: conn} do
      member = user_fixture(%{role: "member"})
      conn = log_in_user(conn, member)
      {:error, {:redirect, _}} = live(conn, ~p"/admin/newsletters/new")
    end
  end

  # ---------------------------------------------------------------------------
  # New edition page (:new)
  # ---------------------------------------------------------------------------

  describe "new edition page" do
    setup [:create_admin]

    test "renders the editor with empty form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/newsletters/new")

      assert html =~ "Newsletter"
      assert has_element?(view, "#newsletter-editor-form")
    end

    test "shows title and subject fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/new")

      assert has_element?(view, "input[name='edition[title]']")
      assert has_element?(view, "input[name='edition[subject]']")
    end

    test "shows Schedule and Send now buttons", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/new")

      assert has_element?(view, "[phx-click='open-schedule-modal']")
      assert has_element?(view, "[phx-click='open-send-modal']")
    end

    test "does not show Send test button before edition is saved", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/new")

      refute has_element?(view, "[phx-click='send-test-email']")
    end

    test "save-draft with valid data persists the edition in the database", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/new")

      view
      |> form("#newsletter-editor-form", %{
        "edition" => %{"title" => "New Title", "subject" => "New Subject"}
      })
      |> render_submit()

      assert Newsletter.list_editions() |> Enum.any?(&(&1.title == "New Title"))
    end
  end

  # ---------------------------------------------------------------------------
  # Edit edition page (:edit)
  # ---------------------------------------------------------------------------

  describe "edit edition page" do
    setup [:create_admin]

    test "renders the editor with existing edition data", %{
      conn: conn,
      admin: admin
    } do
      edition =
        edition_fixture(admin, %{"title" => "Existing Ed", "subject" => "Subj"})

      view = live_editing_edition(conn, edition)

      assert has_element?(view, "#newsletter-editor-form")
      html = render(view)
      assert html =~ "Existing Ed"
      assert html =~ "Subj"
    end

    test "shows the Send test button for an existing edition", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)

      view = live_editing_edition(conn, edition)

      assert has_element?(view, "[phx-click='send-test-email']")
    end

    test "shows draft status badge", %{conn: conn, admin: admin} do
      edition = edition_fixture(admin)

      view = live_editing_edition(conn, edition)
      html = render(view)

      assert html =~ "Draft"
    end

    test "save-draft updates the edition in the database", %{
      conn: conn,
      admin: admin
    } do
      edition =
        edition_fixture(admin, %{
          "title" => "Old Title",
          "subject" => "Old Subj"
        })

      view = live_editing_edition(conn, edition)

      view
      |> form("#newsletter-editor-form", %{
        "edition" => %{"title" => "Updated Title", "subject" => "Updated Subj"}
      })
      |> render_submit()

      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.title == "Updated Title"
      assert reloaded.subject == "Updated Subj"
    end

    test "save-draft with blank title does not persist the change to the database",
         %{
           conn: conn,
           admin: admin
         } do
      edition = edition_fixture(admin, %{"title" => "Original Title"})

      view = live_editing_edition(conn, edition)

      view
      |> form("#newsletter-editor-form", %{
        "edition" => %{"title" => "", "subject" => "ok"}
      })
      |> render_submit()

      # DB should be unchanged because the changeset was invalid
      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.title == "Original Title"
    end

    test "save-draft ignores forged sent status in edition params", %{
      conn: conn,
      admin: admin
    } do
      edition =
        edition_fixture(admin, %{"title" => "Draft", "subject" => "Subj"})

      view = live_editing_edition(conn, edition)

      render_submit(view, "save-draft", %{
        "edition" => %{
          "title" => "Draft",
          "subject" => "Subj",
          "status" => "sent",
          "sent_count" => "9999"
        }
      })

      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :draft
      assert reloaded.sent_count == 0
    end
  end

  # ---------------------------------------------------------------------------
  # Send now modal
  # ---------------------------------------------------------------------------

  describe "send now modal" do
    setup [:create_admin]

    test "opens send confirmation modal on button click", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)

      view = live_editing_edition(conn, edition)

      refute has_element?(view, "#send-newsletter-modal")

      view |> element("[phx-click='open-send-modal']") |> render_click()

      assert has_element?(view, "#send-newsletter-modal")
    end

    test "closes modal on cancel", %{conn: conn, admin: admin} do
      edition = edition_fixture(admin)

      view = live_editing_edition(conn, edition)

      view |> element("[phx-click='open-send-modal']") |> render_click()
      assert has_element?(view, "#send-newsletter-modal")

      view |> element("[phx-click='close-send-modal']") |> render_click()

      refute has_element?(view, "#send-newsletter-modal")
    end

    test "confirm-send triggers sending and marks edition as sent", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)

      view = live_editing_edition(conn, edition)

      view |> element("[phx-click='open-send-modal']") |> render_click()

      view
      |> element("[phx-click='confirm-send']")
      |> render_click()

      # In inline Oban mode the sender fires synchronously
      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :sent
    end
  end

  # ---------------------------------------------------------------------------
  # Schedule modal
  # ---------------------------------------------------------------------------

  describe "schedule modal" do
    setup [:create_admin]

    test "opens schedule modal on button click", %{conn: conn, admin: admin} do
      edition = edition_fixture(admin)

      view = live_editing_edition(conn, edition)

      refute has_element?(view, "#schedule-newsletter-modal")

      view |> element("[phx-click='open-schedule-modal']") |> render_click()

      assert has_element?(view, "#schedule-newsletter-modal")
    end

    test "schedule modal contains a datetime-local input and timezone field", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)

      view = live_editing_edition(conn, edition)

      view |> element("[phx-click='open-schedule-modal']") |> render_click()

      assert has_element?(
               view,
               "input[name='scheduled_at'][type='datetime-local']"
             )

      assert has_element?(view, "input[name='timezone']")
    end

    test "closes schedule modal on cancel", %{conn: conn, admin: admin} do
      edition = edition_fixture(admin)

      view = live_editing_edition(conn, edition)

      view |> element("[phx-click='open-schedule-modal']") |> render_click()
      view |> element("[phx-click='close-schedule-modal']") |> render_click()

      refute has_element?(view, "#schedule-newsletter-modal")
    end

    test "confirm-schedule stores scheduled_at and transitions edition from draft",
         %{
           conn: conn,
           admin: admin
         } do
      edition = edition_fixture(admin)

      view = live_editing_edition(conn, edition)

      view |> element("[phx-click='open-schedule-modal']") |> render_click()

      future = DateTime.utc_now() |> DateTime.add(3600, :second)

      pad = fn n -> String.pad_leading(to_string(n), 2, "0") end

      local_str =
        "#{future.year}-#{pad.(future.month)}-#{pad.(future.day)}T#{pad.(future.hour)}:#{pad.(future.minute)}"

      view
      |> form("#schedule-form", %{
        "scheduled_at" => local_str,
        "timezone" => "Etc/UTC"
      })
      |> render_submit()

      reloaded = Newsletter.get_edition!(edition.id)
      # scheduled_at is persisted; in inline Oban mode the sender fires
      # immediately so status may be :sent rather than :scheduled.
      assert reloaded.scheduled_at != nil
      refute reloaded.status == :draft
    end

    test "confirm-schedule shows error for empty datetime", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)

      view = live_editing_edition(conn, edition)

      view |> element("[phx-click='open-schedule-modal']") |> render_click()

      view
      |> form("#schedule-form", %{"scheduled_at" => "", "timezone" => "Etc/UTC"})
      |> render_submit()

      # Edition should remain as draft (schedule failed)
      reloaded = Newsletter.get_edition!(edition.id)
      assert reloaded.status == :draft
    end
  end

  # ---------------------------------------------------------------------------
  # Send test email
  # ---------------------------------------------------------------------------

  describe "send test email" do
    setup [:create_admin]

    test "delivers a test email to the current admin user", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin, %{"subject" => "My Subject"})

      view = live_editing_edition(conn, edition)

      view |> element("[phx-click='send-test-email']") |> render_click()

      assert_email_sent(fn email ->
        assert email.subject == "[YSC] [TEST] My Subject"
        assert Enum.any?(email.to, fn {_, addr} -> addr == admin.email end)
      end)
    end
  end
end
