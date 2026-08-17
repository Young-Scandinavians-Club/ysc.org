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

    test "shows live sending progress", %{conn: conn, admin: admin} do
      edition = edition_fixture(admin)

      {:ok, sending_edition} =
        Newsletter.update_edition(edition, %{
          "status" => :sending,
          "sent_count" => 0,
          "recipient_count" => 20
        })

      view = live_editing_edition(conn, sending_edition)

      {:ok, progress_edition} =
        Newsletter.update_edition(sending_edition, %{"sent_count" => 12})

      Newsletter.broadcast_edition_delivery_progress(progress_edition)

      assert has_element?(
               view,
               "#newsletter-sending-progress",
               "Sending… 12 / 20"
             )

      assert has_element?(view, "#duplicate-edition-btn")
      refute has_element?(view, "[phx-click='open-send-modal']")
    end

    test "shows the Send test button for an existing edition", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)

      view = live_editing_edition(conn, edition)

      assert has_element?(view, "[phx-click='send-test-email']")
    end

    test "renders a sent edition preview directly in the iframe srcdoc",
         %{
           conn: conn,
           admin: admin
         } do
      edition = edition_fixture(admin, %{"title" => "Already Sent"})

      {:ok, edition} =
        Newsletter.update_edition(edition, %{
          status: :sent,
          sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      view = live_editing_edition(conn, edition)

      assert has_element?(
               view,
               "#newsletter-email-preview-iframe[srcdoc*='Already Sent']"
             )

      assert has_element?(
               view,
               "#preview-scroll-container[phx-update='ignore']"
             )
    end

    test "pushes later preview changes without patching the iframe", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)
      view = live_editing_edition(conn, edition)

      view
      |> form("#newsletter-editor-form", %{
        "edition" => %{"title" => "Updated Preview", "subject" => "Subject"}
      })
      |> render_change()

      assert_push_event(view, "preview-html", %{html: updated_html})
      assert updated_html =~ "Updated Preview"
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

  describe "insert saved notice" do
    setup [:create_admin]

    test "opens picker from toolbar trigger and inserts notice HTML", %{
      conn: conn,
      admin: admin
    } do
      {:ok, notice} =
        Newsletter.create_notice(
          %{"name" => "Office hours", "body" => "<p>Open Tue–Thu</p>"},
          created_by_id: admin.id
        )

      edition = edition_fixture(admin)
      view = live_editing_edition(conn, edition)

      assert has_element?(view, "#open-notice-picker-btn")

      assert has_element?(
               view,
               "#edition_intro_text[data-newsletter-notices='true']"
             )

      view |> element("#open-notice-picker-btn") |> render_click()
      assert has_element?(view, "#insert-notice-picker-modal")
      assert has_element?(view, "#insert-notice-#{notice.id}")

      view |> element("#insert-notice-#{notice.id}") |> render_click()

      assert_push_event(view, "insert-trix-html", %{
        html: html,
        target_input_id: "edition_intro_text"
      })

      assert html =~ "Open Tue"
      refute has_element?(view, "#insert-notice-picker-modal")
    end

    test "can create a new notice from the picker and insert it", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)
      view = live_editing_edition(conn, edition)

      view |> element("#open-notice-picker-btn") |> render_click()
      assert has_element?(view, "#notice-picker-new-btn")

      view |> element("#notice-picker-new-btn") |> render_click()
      assert has_element?(view, "#new-notice-from-picker-form")

      view
      |> form("#new-notice-from-picker-form", %{
        "new_notice" => %{
          "name" => "Volunteer call",
          "body" => "Join us Saturday at 10am"
        }
      })
      |> render_submit()

      refute has_element?(view, "#insert-notice-picker-modal")

      assert_push_event(view, "insert-trix-html", %{
        html: html,
        target_input_id: "edition_intro_text"
      })

      assert html =~ "Join us Saturday"

      assert Enum.any?(
               Newsletter.list_notices(),
               &(&1.name == "Volunteer call")
             )
    end
  end

  describe "save selection as notice" do
    setup [:create_admin]

    test "opens save modal from selection event and creates a notice", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)
      view = live_editing_edition(conn, edition)

      render_hook(view, "save-selection-as-notice", %{
        "html" => "<p>Park in lot B please</p>"
      })

      assert has_element?(view, "#save-notice-modal")
      assert has_element?(view, "#save-notice-form")
      assert render(view) =~ "Park in lot B"

      view
      |> form("#save-notice-form", %{
        "save_notice" => %{"name" => "Parking reminder"}
      })
      |> render_submit()

      refute has_element?(view, "#save-notice-modal")

      assert [%{name: "Parking reminder"} | _] =
               Newsletter.list_notices()
               |> Enum.filter(&(&1.name == "Parking reminder"))

      # Picker should list the new notice
      view |> element("#open-notice-picker-btn") |> render_click()
      assert render(view) =~ "Parking reminder"
    end

    test "shows error when selection html is empty", %{conn: conn, admin: admin} do
      edition = edition_fixture(admin)
      view = live_editing_edition(conn, edition)

      render_hook(view, "save-selection-as-notice", %{"html" => "   "})

      refute has_element?(view, "#save-notice-modal")
      assert render(view) =~ "Select some text first"
    end
  end

  describe "duplicate from editor" do
    setup [:create_admin]

    test "shows duplicate on sent editions and navigates to new draft", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin, %{"title" => "Sent One"})

      {:ok, _} =
        Newsletter.update_edition(edition, %{
          status: :sent,
          sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      view = live_editing_edition(conn, edition)
      assert has_element?(view, "#duplicate-edition-btn")

      {:ok, new_view, _html} =
        view
        |> element("#duplicate-edition-btn")
        |> render_click()
        |> follow_redirect(conn)

      render_async(new_view, 5000)

      assert new_view
             |> element("input[name='edition[title]']")
             |> render() =~ "Sent One (copy)"
    end
  end

  describe "editing presence" do
    setup [:create_admin]

    test "shows an avatar for another admin currently editing", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)
      other_admin = user_fixture(%{role: "admin", first_name: "Jamie"})

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: "other-tab-#{System.unique_integer([:positive])}"},
          :newsletter,
          edition.id,
          other_admin
        )

      view = live_editing_edition(conn, edition)
      html = render(view)

      assert html =~ "Jamie"
      assert html =~ "is editing"
    end

    test "does not show the current admin's own presence", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: "self-tab-#{System.unique_integer([:positive])}"},
          :newsletter,
          edition.id,
          admin
        )

      view = live_editing_edition(conn, edition)
      refute render(view) =~ "is editing"
    end

    test "shows no avatars for a brand new (unsaved) newsletter", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/new")
      render_async(view)

      refute render(view) =~ "is editing"
    end

    test "updates avatars live when another admin starts editing", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)
      view = live_editing_edition(conn, edition)
      refute render(view) =~ "is editing"

      other_admin = user_fixture(%{role: "admin", first_name: "Taylor"})

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: "live-tab-#{System.unique_integer([:positive])}"},
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

    test "an unrelated presence_diff broadcast does not crash the editor", %{
      conn: conn,
      admin: admin
    } do
      edition = edition_fixture(admin)
      view = live_editing_edition(conn, edition)

      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: YscWeb.Admin.EditingPresence.topic(:newsletter),
        event: "presence_diff",
        payload: %{joins: %{}, leaves: %{}}
      })

      assert render(view) =~ edition.title
    end
  end

  describe "last edited by" do
    setup [:create_admin]

    test "shows who last edited the newsletter", %{conn: conn, admin: admin} do
      editor = user_fixture(%{role: "admin", first_name: "Morgan"})
      edition = edition_fixture(admin)

      {:ok, _edition} =
        Newsletter.update_edition_draft(edition, %{"title" => "Edited"},
          updated_by_id: editor.id
        )

      view = live_editing_edition(conn, edition)
      html = render(view)

      assert html =~ "Last edited by"
      assert html =~ "Morgan"
    end
  end
end
