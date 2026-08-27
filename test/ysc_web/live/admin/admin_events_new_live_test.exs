defmodule YscWeb.AdminEventsNewLiveTest do
  use YscWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.ScanningFixtures

  alias Ysc.Agendas
  alias Ysc.EventPhotos
  alias Ysc.Events
  alias Ysc.Events.Event
  alias Ysc.MessagePassingEvents
  alias Ysc.Repo

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  # Opening the calendar focuses the visible month on the event's existing
  # start_date, not on today - so any date button computed relative to
  # `Date.utc_today()` may fall outside that view whenever the event's start
  # date and "today" land in different calendar months (which depends on
  # what day of the month the suite happens to run on). Jump to the current
  # month via the picker's own "Today" button before looking for such a
  # button, mirroring how a real user would navigate there. The button is
  # disabled (a no-op click) when already showing the current month.
  defp go_to_today(view, id \\ "event_date") do
    if has_element?(view, ~s|##{id}-go-to-today:not([disabled])|) do
      view |> element(~s|##{id}-go-to-today|) |> render_click()
    end

    view
  end

  describe "mount" do
    setup [:create_admin]

    test "static HTML shows loading shell before websocket connects", %{
      conn: conn,
      admin: admin
    } do
      event =
        event_fixture(%{organizer_id: admin.id, title: "Deferred Load Event"})

      conn = get(conn, ~p"/admin/events/#{event.id}/edit")
      html = html_response(conn, 200)

      assert html =~ ~s|id="admin-event-loading"|
      refute html =~ "Deferred Load Event"
      refute html =~ ~s|id="event-header-bar"|
    end
  end

  describe "check-in navigation" do
    setup [:create_admin]

    test "check-in button joins open membership session", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})
      session = event_membership_session_fixture(event, admin)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(
               view,
               "a[href='/admin/membership-check-in/#{session.id}']"
             )

      refute has_element?(
               view,
               "a[href='/admin/events/#{event.id}/check-in']"
             )
    end
  end

  describe "hosts - create_event defaults" do
    setup [:create_admin]

    test "newly created event has organizer as default host", %{admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      hosts = Events.list_event_hosts(event)

      assert length(hosts) == 1
      assert hd(hosts).id == admin.id
    end
  end

  describe "new event mount" do
    setup [:create_admin]

    test "disconnected render does not insert a draft event", %{conn: conn} do
      count_before = Repo.aggregate(Event, :count)

      html =
        conn
        |> get(~p"/admin/events/new")
        |> html_response(200)

      assert html =~ "admin-event-loading"
      assert Repo.aggregate(Event, :count) == count_before
    end

    test "connected mount inserts one draft and redirects to edit", %{
      conn: conn
    } do
      count_before = Repo.aggregate(Event, :count)

      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, ~p"/admin/events/new")

      assert path =~ ~r{/admin/events/.+/edit}
      assert Repo.aggregate(Event, :count) == count_before + 1
    end
  end

  describe "editor date picker" do
    setup [:create_admin]

    test "picking a date and closing the calendar persists start/end dates", %{
      conn: conn,
      admin: admin
    } do
      old_start =
        DateTime.utc_now()
        |> DateTime.add(10, :day)
        |> DateTime.to_date()
        |> then(&DateTime.new!(&1, ~T[00:00:00], "Etc/UTC"))

      old_end = DateTime.add(old_start, 1, :day)

      event =
        event_fixture(%{
          organizer_id: admin.id,
          title: "Date Edit Event",
          start_date: old_start,
          end_date: old_end,
          start_time: ~T[18:00:00],
          end_time: ~T[20:00:00]
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      new_date = Date.add(Date.utc_today(), 3)
      new_iso = "#{Date.to_iso8601(new_date)}T00:00:00Z"

      view
      |> element("#event_date [phx-click=open-calendar]")
      |> render_click()

      assert has_element?(view, "#event_date_calendar")

      go_to_today(view)

      view
      |> element(~s|#event_date_calendar button[phx-value-date="#{new_iso}"]|)
      |> render_click()

      view
      |> element(~s|#event_date_calendar button[phx-click="close-calendar"]|)
      |> render_click()

      _ = render(view)

      reloaded = Events.get_event!(event.id)

      assert DateTime.to_date(reloaded.start_date) == new_date
      assert DateTime.to_date(reloaded.end_date) == new_date
    end

    test "date change after validate auto-save still persists", %{
      conn: conn,
      admin: admin
    } do
      old_start =
        DateTime.utc_now()
        |> DateTime.add(10, :day)
        |> DateTime.to_date()
        |> then(&DateTime.new!(&1, ~T[00:00:00], "Etc/UTC"))

      event =
        event_fixture(%{
          organizer_id: admin.id,
          title: "Date After Validate",
          description: "Summary text",
          start_date: old_start,
          end_date: DateTime.add(old_start, 1, :day),
          start_time: ~T[18:00:00],
          end_time: ~T[20:00:00]
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      view
      |> element("#new_event_form")
      |> render_change(%{
        "event" => %{
          "title" => "Date After Validate Updated",
          "description" => "Summary text",
          "start_date" => DateTime.to_iso8601(old_start),
          "end_date" => DateTime.to_iso8601(DateTime.add(old_start, 1, :day)),
          "start_time" => "18:00:00",
          "end_time" => "20:00:00"
        }
      })

      new_date = Date.add(Date.utc_today(), 4)
      new_iso = "#{Date.to_iso8601(new_date)}T00:00:00Z"

      view
      |> element("#event_date [phx-click=open-calendar]")
      |> render_click()

      go_to_today(view)

      view
      |> element(~s|#event_date_calendar button[phx-value-date="#{new_iso}"]|)
      |> render_click()

      view
      |> element(~s|#event_date_calendar button[phx-click="close-calendar"]|)
      |> render_click()

      _ = render(view)

      reloaded = Events.get_event!(event.id)
      assert DateTime.to_date(reloaded.start_date) == new_date
      assert DateTime.to_date(reloaded.end_date) == new_date
    end

    test "in-progress date pick survives a concurrent form validate", %{
      conn: conn,
      admin: admin
    } do
      old_start =
        DateTime.utc_now()
        |> DateTime.add(20, :day)
        |> DateTime.to_date()
        |> then(&DateTime.new!(&1, ~T[00:00:00], "Etc/UTC"))

      event =
        event_fixture(%{
          organizer_id: admin.id,
          title: "Concurrent Validate",
          description: "Summary text",
          start_date: old_start,
          end_date: DateTime.add(old_start, 1, :day),
          start_time: ~T[18:00:00],
          end_time: ~T[20:00:00]
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      new_date = Date.add(Date.utc_today(), 2)
      new_iso = "#{Date.to_iso8601(new_date)}T00:00:00Z"

      view
      |> element("#event_date [phx-click=open-calendar]")
      |> render_click()

      go_to_today(view)

      view
      |> element(~s|#event_date_calendar button[phx-value-date="#{new_iso}"]|)
      |> render_click()

      # Parent re-render while calendar is open (previously wiped the pick)
      view
      |> element("#new_event_form")
      |> render_change(%{
        "event" => %{
          "title" => "Concurrent Validate",
          "description" => "Summary text changed",
          "start_date" => DateTime.to_iso8601(old_start),
          "end_date" => DateTime.to_iso8601(DateTime.add(old_start, 1, :day)),
          "start_time" => "18:00:00",
          "end_time" => "20:00:00"
        }
      })

      view
      |> element(~s|#event_date_calendar button[phx-click="close-calendar"]|)
      |> render_click()

      _ = render(view)

      reloaded = Events.get_event!(event.id)
      assert DateTime.to_date(reloaded.start_date) == new_date
      assert DateTime.to_date(reloaded.end_date) == new_date
    end

    test "can move an existing later date back to an earlier single day", %{
      conn: conn,
      admin: admin
    } do
      later =
        Date.add(Date.utc_today(), 20)
        |> then(&DateTime.new!(&1, ~T[00:00:00], "Etc/UTC"))

      event =
        event_fixture(%{
          organizer_id: admin.id,
          title: "Move Earlier",
          description: "Summary text",
          start_date: later,
          end_date: later,
          start_time: ~T[18:31:00],
          end_time: ~T[20:30:00]
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      earlier = Date.utc_today()
      earlier_iso = "#{Date.to_iso8601(earlier)}T00:00:00Z"
      later_iso = "#{Date.to_iso8601(DateTime.to_date(later))}T00:00:00Z"

      view
      |> element("#event_date [phx-click=open-calendar]")
      |> render_click()

      # Mimic clicking the currently selected day first (enters :set_end), then
      # choosing an earlier day — previously those earlier days were disabled.
      view
      |> element(~s|#event_date_calendar button[phx-value-date="#{later_iso}"]|)
      |> render_click()

      # The calendar is still showing `later`'s month; jump to today's month
      # before looking for `earlier`'s button.
      go_to_today(view)

      assert has_element?(
               view,
               ~s|#event_date_calendar button[phx-value-date="#{earlier_iso}"]:not([disabled])|
             )

      view
      |> element(
        ~s|#event_date_calendar button[phx-value-date="#{earlier_iso}"]|
      )
      |> render_click()

      view
      |> element(~s|#event_date_calendar button[phx-click="close-calendar"]|)
      |> render_click()

      _ = render(view)

      reloaded = Events.get_event!(event.id)
      assert DateTime.to_date(reloaded.start_date) == earlier
      assert DateTime.to_date(reloaded.end_date) == earlier
    end

    test "single-day pick clears overnight end_time so the update can persist",
         %{
           conn: conn,
           admin: admin
         } do
      old_start =
        DateTime.utc_now()
        |> DateTime.add(15, :day)
        |> DateTime.to_date()
        |> then(&DateTime.new!(&1, ~T[00:00:00], "Etc/UTC"))

      event =
        event_fixture(%{
          organizer_id: admin.id,
          title: "Overnight Event",
          description: "Summary text",
          start_date: old_start,
          end_date: DateTime.add(old_start, 1, :day),
          start_time: ~T[18:00:00],
          # Next-morning end time is valid across two days, invalid on one day
          end_time: ~T[02:00:00]
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      new_date = Date.add(Date.utc_today(), 5)
      new_iso = "#{Date.to_iso8601(new_date)}T00:00:00Z"

      view
      |> element("#event_date [phx-click=open-calendar]")
      |> render_click()

      go_to_today(view)

      view
      |> element(~s|#event_date_calendar button[phx-value-date="#{new_iso}"]|)
      |> render_click()

      view
      |> element(~s|#event_date_calendar button[phx-click="close-calendar"]|)
      |> render_click()

      _ = render(view)

      reloaded = Events.get_event!(event.id)
      assert DateTime.to_date(reloaded.start_date) == new_date
      assert DateTime.to_date(reloaded.end_date) == new_date
      assert reloaded.start_time == ~T[18:00:00]
      assert reloaded.end_time == nil
    end

    test "published event with stale publish_at can move start earlier", %{
      conn: conn,
      admin: admin
    } do
      old_start =
        Date.utc_today()
        |> Date.add(20)
        |> then(&DateTime.new!(&1, ~T[18:31:00], "Etc/UTC"))

      # Historical schedule still on the event after it was published.
      publish_at =
        Date.utc_today()
        |> Date.add(12)
        |> then(&DateTime.new!(&1, ~T[15:45:00], "Etc/UTC"))

      event =
        event_fixture(%{
          organizer_id: admin.id,
          title: "Stale Publish At Event",
          description: "Summary text",
          start_date: old_start,
          end_date: old_start,
          start_time: ~T[18:31:00],
          end_time: ~T[20:30:00],
          state: :published,
          publish_at: publish_at
        })

      assert event.publish_at

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      # Move earlier than publish_at (same class of bug as Aug 7/8 on a
      # published event that still has publish_at set).
      new_date = Date.add(Date.utc_today(), 3)
      new_iso = "#{Date.to_iso8601(new_date)}T00:00:00Z"

      view
      |> element("#event_date [phx-click=open-calendar]")
      |> render_click()

      go_to_today(view)

      view
      |> element(~s|#event_date_calendar button[phx-value-date="#{new_iso}"]|)
      |> render_click()

      view
      |> element(~s|#event_date_calendar button[phx-click="close-calendar"]|)
      |> render_click()

      _ = render(view)

      reloaded = Events.get_event!(event.id)
      assert DateTime.to_date(reloaded.start_date) == new_date
      assert DateTime.to_date(reloaded.end_date) == new_date
      assert reloaded.publish_at == publish_at
    end
  end

  describe "editor validate auto-save" do
    setup [:create_admin]

    test "validate ignores client-supplied rendered_details", %{
      conn: conn,
      admin: admin
    } do
      event =
        event_fixture(%{
          organizer_id: admin.id,
          title: "Safe Overview",
          raw_details: "<p>Original overview</p>",
          rendered_details: "<p>Original overview</p>"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      view
      |> element("#new_event_form")
      |> render_change(%{
        "event" => %{
          "title" => "Safe Overview",
          "description" => event.description,
          "rendered_details" =>
            "<p>Injected</p><script>document.cookie</script><img src=x onerror=alert(1)>"
        }
      })

      reloaded = Events.get_event!(event.id)
      assert reloaded.rendered_details == "<p>Original overview</p>"
    end
  end

  describe "hosts - edit page UI" do
    setup [:create_admin]

    test "add agenda inserts an agenda card", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      refute has_element?(view, "#agendas .drag-handle")

      assert view |> element("#add-agenda-button") |> render_click()

      assert has_element?(view, "#agendas .drag-handle")

      html = render(view)
      {:ok, doc} = Floki.parse_fragment(html)
      agenda_cards = Floki.find(doc, "#agendas > li")

      assert length(agenda_cards) == 1,
             "expected a single agenda stream item (no duplicate PubSub + handler insert)"
    end

    test "shows Hosts section on edit tab", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "#hosts-section")
      assert has_element?(view, "#host-search-input")
    end

    test "shows host search input", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "#host-search-input")
    end

    test "renders organizer as a host pill on mount", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "#host-#{admin.id}")
    end

    test "renders each current host with a remove button", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "#host-#{admin.id}")

      assert has_element?(
               view,
               "#host-#{admin.id} button[phx-click='remove-host']"
             )
    end

    test "does not show hosts section on tickets tab", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, _view, html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      refute html =~ "event-hosts-manager"
    end
  end

  describe "updates tab - event photo uploads" do
    setup [:create_admin]

    test "shows photo upload link when patching to updates on a published event",
         %{
           conn: conn,
           admin: admin
         } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})
      assert {:ok, _} = EventPhotos.ensure_collection_for_event(event)
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      html = render_patch(view, ~p"/admin/events/#{event.id}/updates")

      assert html =~ "Event photo uploads"
      assert has_element?(view, "#event-photo-upload-link-card")
      assert has_element?(view, "#copy-photo-upload-url-btn")
    end

    test "shows photo upload link when opening updates directly", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})
      assert {:ok, _} = EventPhotos.ensure_collection_for_event(event)
      {:ok, view, html} = live(conn, ~p"/admin/events/#{event.id}/updates")

      assert html =~ "Event photo uploads"
      assert has_element?(view, "#event-photo-upload-link-card")
    end
  end

  describe "updates tab - communication timeline" do
    setup [:create_admin]

    test "shows communication timeline", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id, state: :published})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/updates")

      assert has_element?(view, "#communication-timeline")
      assert has_element?(view, "#preview-event-update-btn")
    end

    test "includes media library trigger for the update Trix editor", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/updates")

      assert has_element?(
               view,
               ~s([data-trix-library-trigger="update[raw_body]"])
             )
    end

    test "shows event update in timeline after send", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})

      {:ok, update} =
        Events.create_event_update(event, %{
          title: "Venue Change",
          raw_body: "<div>Please use the side entrance.</div>",
          rendered_body: "<div>Please use the side entrance.</div>",
          sent_by_id: admin.id
        })

      {:ok, _} = Events.mark_event_update_sent(update, 3)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/updates")

      assert has_element?(view, "#timeline-item-update-#{update.id}")

      assert has_element?(
               view,
               "#timeline-item-update-#{update.id}",
               "Venue Change"
             )
    end

    test "shows publication notification in timeline when marked sent", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})
      {:ok, event} = Events.mark_event_notification_sent(event, 25)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/updates")

      assert has_element?(view, "#timeline-item-publication-#{event.id}")

      assert has_element?(
               view,
               "#timeline-item-publication-#{event.id}",
               "New Event Announcement"
             )

      assert has_element?(
               view,
               "#timeline-item-publication-#{event.id}",
               "25 member(s) notified"
             )
    end

    test "preview modal opens with message body", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id, state: :published})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/updates")

      render_click(view, "editor-update", %{
        "field" => "update[raw_body]",
        "value" => "<div>Preview body content</div>"
      })

      view |> element("#preview-event-update-btn") |> render_click()

      assert has_element?(view, "#event-update-preview-modal")
      assert has_element?(view, "#event-update-preview-iframe")
    end

    test "preview shows error when body is empty", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id, state: :published})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/updates")

      view |> element("#preview-event-update-btn") |> render_click()

      refute has_element?(view, "#event-update-preview-modal")
    end
  end

  describe "updates tab - SMS preview" do
    setup [:create_admin]

    test "shows SMS preview and segment warning when send_sms is checked", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/updates")

      long_body = "<p>" <> String.duplicate("a", 200) <> "</p>"

      render_click(view, "editor-update", %{
        "field" => "update[raw_body]",
        "value" => long_body
      })

      view
      |> form("#event-update-form", %{
        "update" => %{
          "send_sms" => "true",
          "title" => "Update",
          "raw_body" => long_body
        }
      })
      |> render_change()

      assert has_element?(view, "#event-update-sms-preview")
      assert has_element?(view, "#sms-recipient-count")
      assert has_element?(view, "#event-update-sms-segment-warning")
    end

    test "hides SMS preview when send_sms is unchecked", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/updates")

      render_click(view, "editor-update", %{
        "field" => "update[raw_body]",
        "value" => "<p>Short update</p>"
      })

      view
      |> form("#event-update-form", %{
        "update" => %{
          "send_sms" => "true",
          "title" => "Update",
          "raw_body" => "<p>Short update</p>"
        }
      })
      |> render_change()

      assert has_element?(view, "#event-update-sms-preview")

      view
      |> form("#event-update-form", %{
        "update" => %{
          "send_sms" => "false",
          "title" => "Update",
          "raw_body" => "<p>Short update</p>"
        }
      })
      |> render_change()

      refute has_element?(view, "#event-update-sms-preview")
    end
  end

  describe "agendas - PubSub when switching events" do
    setup [:create_admin]

    test "does not apply agenda updates from a previous event after live-patching to another event",
         %{conn: conn, admin: admin} do
      event_a = event_fixture(%{organizer_id: admin.id})
      event_b = event_fixture(%{organizer_id: admin.id})

      {:ok, agenda_a} =
        Agendas.create_agenda(event_a, %{title: "Agenda on event A only"})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event_a.id}/edit")
      assert has_element?(view, "#agendas li[data-id='#{agenda_a.id}']")

      _html = render_patch(view, ~p"/admin/events/#{event_b.id}/edit")
      refute has_element?(view, "#agendas li[data-id='#{agenda_a.id}']")

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "agendas:#{event_a.id}",
        {Ysc.Agendas, %MessagePassingEvents.AgendaAdded{agenda: agenda_a}}
      )

      _html = render(view)
      refute has_element?(view, "#agendas li[data-id='#{agenda_a.id}']")
    end
  end

  describe "hosts - search-hosts event" do
    setup [:create_admin]

    test "empty query returns no results and clears dropdown", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      element(view, "#host-search-input") |> render_keyup(%{"value" => ""})

      refute has_element?(view, "#host-search-results")
    end

    test "query matching a user shows them in the dropdown", %{
      conn: conn,
      admin: admin
    } do
      other_user = user_fixture(%{first_name: "Solvieg", last_name: "Eriksson"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      element(view, "#host-search-input")
      |> render_keyup(%{"value" => "Solvieg"})

      assert has_element?(view, "#host-result-#{other_user.id}")
      assert has_element?(view, "#host-result-#{other_user.id}", "Solvieg")
    end

    test "query matching no user shows no-results message", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      element(view, "#host-search-input")
      |> render_keyup(%{"value" => "zzznomatch99xyz"})

      refute has_element?(view, "#host-search-results")
      assert has_element?(view, "#event-hosts-manager", "No members found")
    end

    test "matching user who is already a host shows check-circle icon", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      element(view, "#host-search-input")
      |> render_keyup(%{"value" => admin.first_name})

      assert has_element?(view, "#host-result-#{admin.id} .host-status-icon")
    end
  end

  describe "hosts - add-host event" do
    setup [:create_admin]

    test "adds a new user as host and shows them in the list", %{
      conn: conn,
      admin: admin
    } do
      other_user = user_fixture(%{first_name: "Bjorn", last_name: "Lindqvist"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      render_click(view, "add-host", %{"user-id" => other_user.id})

      assert has_element?(view, "#host-#{other_user.id}")
    end

    test "persists the added host to the database", %{conn: conn, admin: admin} do
      other_user = user_fixture(%{first_name: "Astrid", last_name: "Berg"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      render_click(view, "add-host", %{"user-id" => other_user.id})

      hosts = Events.list_event_hosts(event)
      host_ids = Enum.map(hosts, & &1.id)
      assert other_user.id in host_ids
    end

    test "adding same user twice does not duplicate them", %{
      conn: conn,
      admin: admin
    } do
      other_user = user_fixture(%{first_name: "Ingrid", last_name: "Holm"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      render_click(view, "add-host", %{"user-id" => other_user.id})
      render_click(view, "add-host", %{"user-id" => other_user.id})

      hosts = Events.list_event_hosts(event)
      assert length(Enum.filter(hosts, &(&1.id == other_user.id))) == 1
    end

    test "clears search query and results after adding a host", %{
      conn: conn,
      admin: admin
    } do
      other_user = user_fixture(%{first_name: "Gunnar", last_name: "Strand"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      element(view, "#host-search-input")
      |> render_keyup(%{"value" => "Gunnar"})

      element(view, "#host-result-#{other_user.id} button") |> render_click()

      refute has_element?(view, "#host-search-results")
    end

    test "does nothing for a nonexistent user id", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      initial_hosts = Events.list_event_hosts(event)

      render_click(view, "add-host", %{"user-id" => Ecto.ULID.generate()})

      assert Events.list_event_hosts(event) == initial_hosts
    end
  end

  describe "hosts - remove-host event" do
    setup [:create_admin]

    test "removes a host from the list", %{conn: conn, admin: admin} do
      other_user = user_fixture(%{first_name: "Freya", last_name: "Dahl"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, _} = Events.add_event_host(event, other_user)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "#host-#{other_user.id}")

      element(view, "#host-#{other_user.id} button[phx-click='remove-host']")
      |> render_click()

      refute has_element?(view, "#host-#{other_user.id}")
    end

    test "persists the removal to the database", %{conn: conn, admin: admin} do
      other_user = user_fixture(%{first_name: "Leif", last_name: "Carlsson"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, _} = Events.add_event_host(event, other_user)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      render_click(view, "remove-host", %{"user-id" => other_user.id})

      hosts = Events.list_event_hosts(event)
      refute Enum.any?(hosts, &(&1.id == other_user.id))
    end

    test "can remove the organizer from hosts", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      render_click(view, "remove-host", %{"user-id" => admin.id})

      refute has_element?(view, "#host-#{admin.id}")
      assert Events.list_event_hosts(event) == []
    end
  end

  describe "Admin Events New/Edit - Stale Entry Bug Fix" do
    setup [:create_admin]

    test "reproduces original bug: concurrent detail edits during capacity change",
         %{
           conn: conn,
           admin: admin
         } do
      # This test reproduces the EXACT scenario from the bug report:
      # User is editing event details (title, description, etc.) which auto-saves,
      # then tries to edit ticket tier capacity, which would fail with stale entry error

      event =
        event_fixture(%{
          title: "Original Title",
          description: "Original description",
          organizer_id: admin.id,
          max_attendees: 100
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      # Simulate what happens when editing event details on the "Event Details" tab
      # (the auto-save increments lock_version multiple times)
      {:ok, event} = Events.update_event(event, %{title: "Auto-save 1"})
      {:ok, event} = Events.update_event(event, %{description: "Auto-save 2"})
      {:ok, _event} = Events.update_event(event, %{title: "Auto-save 3"})

      # Now on the "Tickets" tab, try to change capacity
      # Before the fix, this would fail with Ecto.StaleEntryError because
      # socket.assigns[:event] had lock_version from mount time
      form = element(view, "#capacity_form")

      # This should NOT crash with stale entry error
      result =
        form
        |> render_change(%{
          "event" => %{
            "max_attendees" => "250"
          }
        })

      # Verify it worked
      assert result
      reloaded_event = Events.get_event!(event.id)
      assert reloaded_event.max_attendees == 250
      assert reloaded_event.title == "Auto-save 3"
    end

    test "handles concurrent event updates without stale entry error on capacity toggle",
         %{
           conn: conn,
           admin: admin
         } do
      # This test reproduces the original bug: editing event details while also
      # editing capacity would cause a stale entry error because the capacity
      # handlers weren't reloading the event before updating.

      event =
        event_fixture(%{
          title: "Test Event",
          description: "Original description",
          organizer_id: admin.id,
          max_attendees: 100
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      # Simulate a background update (like another tab or auto-save)
      # This increments lock_version in the database
      {:ok, _updated_event} =
        Events.update_event(event, %{
          title: "Updated Title",
          description: "Updated description"
        })

      # Now try to toggle capacity - this would have raised Ecto.StaleEntryError
      # before the fix, but should work now because we reload the event
      view
      |> element("input[type='checkbox'][name='event[unlimited_capacity]']")
      |> render_click()

      # Verify the capacity was updated (should be nil now for unlimited)
      reloaded_event = Events.get_event!(event.id)
      assert is_nil(reloaded_event.max_attendees)

      # Verify no crash occurred - the view is still functional
      assert render(view) =~ "Event Capacity"
    end

    test "handles validate-capacity with concurrent updates", %{
      conn: conn,
      admin: admin
    } do
      event =
        event_fixture(%{
          title: "Capacity Test",
          organizer_id: admin.id,
          max_attendees: 100
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      # Simulate background update
      {:ok, _} = Events.update_event(event, %{title: "Background Update"})

      # Try to change capacity - should not raise stale entry error
      form = element(view, "#capacity_form")

      assert form
             |> render_change(%{
               "event" => %{
                 "max_attendees" => "150"
               }
             })

      # Verify the capacity was updated
      reloaded_event = Events.get_event!(event.id)
      assert reloaded_event.max_attendees == 150
    end

    test "handles save-capacity with concurrent updates", %{
      conn: conn,
      admin: admin
    } do
      event =
        event_fixture(%{
          title: "Save Capacity Test",
          organizer_id: admin.id,
          max_attendees: 50
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      # Simulate background update
      {:ok, _} = Events.update_event(event, %{description: "Background change"})

      # Try to save capacity
      form = element(view, "#capacity_form")

      assert form
             |> render_submit(%{
               "event" => %{
                 "max_attendees" => "75"
               }
             })

      # Verify the capacity was updated successfully
      reloaded_event = Events.get_event!(event.id)
      assert reloaded_event.max_attendees == 75
    end

    test "multiple rapid capacity changes with concurrent event updates", %{
      conn: conn,
      admin: admin
    } do
      # This test simulates the real-world scenario where a user is editing
      # multiple fields rapidly while auto-save is updating in the background

      event =
        event_fixture(%{
          title: "Rapid Changes Test",
          organizer_id: admin.id,
          max_attendees: 100
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      form = element(view, "#capacity_form")

      # Make a capacity change
      form |> render_change(%{"event" => %{"max_attendees" => "150"}})

      # Background update happens
      {:ok, _} =
        Events.update_event(Events.get_event!(event.id), %{title: "Update 1"})

      # Another capacity change
      form |> render_change(%{"event" => %{"max_attendees" => "200"}})

      # Another background update
      {:ok, _} =
        Events.update_event(Events.get_event!(event.id), %{title: "Update 2"})

      # Final capacity change
      form |> render_change(%{"event" => %{"max_attendees" => "250"}})

      # Verify the final value is correct and no stale entry errors occurred
      reloaded_event = Events.get_event!(event.id)
      assert reloaded_event.max_attendees == 250
      assert reloaded_event.title == "Update 2"
    end
  end

  describe "location presets" do
    setup [:create_admin]

    test "renders preset pill buttons on edit tab", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "#location-presets")
      assert has_element?(view, "#location-preset-swedish_american_hall")
      assert has_element?(view, "#location-preset-clear_lake")
      assert has_element?(view, "#location-preset-norwegian_club")
      assert has_element?(view, "#event-location-search")
      assert has_element?(view, "span", "Frequent Venues")
      assert has_element?(view, "#event-location-search[data-presets]")

      assert has_element?(
               view,
               "#location-preset-swedish_american_hall",
               "Swedish American Hall"
             )
    end

    test "renders hidden latitude and longitude inputs", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "input[name='event[latitude]'][type='hidden']")
      assert has_element?(view, "input[name='event[longitude]'][type='hidden']")
      refute has_element?(view, "summary", "Advanced (Coordinates)")
    end

    test "apply-location-preset updates event location fields", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      view
      |> element("#location-preset-swedish_american_hall")
      |> render_click()

      reloaded = Events.get_event!(event.id)
      assert reloaded.location_name == "Swedish American Hall"
      assert reloaded.address == "2174 Market St, San Francisco, CA 94114"
      assert reloaded.latitude == 37.76667619093857
      assert reloaded.longitude == -122.4304435827406

      assert has_element?(view, "#location-display-details")

      assert has_element?(
               view,
               "input[name='event[location_name]'][value='Swedish American Hall']"
             )

      assert has_element?(
               view,
               "input[name='event[address]'][value='2174 Market St, San Francisco, CA 94114']"
             )
    end

    test "apply-location-preset clears stale place_id from prior search", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      view
      |> element("#event-location-search")
      |> render_hook("location-selected", %{
        "location_name" => "Test Venue",
        "address" => "123 Main St, San Francisco, CA",
        "latitude" => "37.77",
        "longitude" => "-122.42",
        "place_id" => "radar-place-123"
      })

      view
      |> element("#location-preset-swedish_american_hall")
      |> render_click()

      reloaded = Events.get_event!(event.id)
      assert reloaded.place_id == nil
      assert reloaded.location_name == "Swedish American Hall"
    end

    test "location-selected updates event location fields", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      view
      |> element("#event-location-search")
      |> render_hook("location-selected", %{
        "location_name" => "Test Venue",
        "address" => "123 Main St, San Francisco, CA",
        "latitude" => "37.77",
        "longitude" => "-122.42",
        "place_id" => "radar-place-123"
      })

      reloaded = Events.get_event!(event.id)
      assert reloaded.location_name == "Test Venue"
      assert reloaded.address == "123 Main St, San Francisco, CA"
      assert reloaded.latitude == 37.77
      assert reloaded.longitude == -122.42
      assert reloaded.place_id == "radar-place-123"
    end
  end

  describe "tickets tab - grant tickets" do
    setup [:create_admin]

    test "admin can grant tickets to a member from the tickets tab", %{
      conn: conn,
      admin: admin
    } do
      member =
        user_fixture(%{
          first_name: "Migrated",
          last_name: "Member",
          email: "migrated-#{System.unique_integer()}@example.com"
        })

      event = event_fixture(%{organizer_id: admin.id, state: :published})

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA Migration",
          quantity: 50
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      refute has_element?(view, "#grant-tickets-modal")

      view
      |> element("#ticket-tier-actions-#{tier.id}-grant")
      |> render_click()

      assert has_element?(view, "#grant-tickets-modal")
      assert has_element?(view, "#ticket-grant-form")

      view
      |> element("#ticket-grant-user-autocomplete-input")
      |> render_keyup(%{"value" => "Migrated"})

      view
      |> element(
        "#ticket-grant-user-autocomplete button[phx-click='select-user'][phx-value-id='#{member.id}']"
      )
      |> render_click()

      view
      |> element("#ticket-grant-form")
      |> render_submit(%{
        "ticket_grant" => %{
          "ticket_tier_id" => tier.id,
          "quantity" => "2",
          "override_limits" => "false",
          "send_email" => "false",
          "admin_grant_notes" => "Legacy purchase"
        }
      })

      summary = Events.get_ticket_purchase_summary(event.id)
      purchase = Enum.find(summary, &(&1.user_id == member.id))
      assert purchase.ticket_count == 2

      tickets = Events.list_tickets_for_user(member.id)
      assert length(tickets) == 2
      assert Enum.all?(tickets, &(&1.status == :confirmed))

      order_id = tickets |> List.first() |> Map.fetch!(:ticket_order_id)

      assert has_element?(view, "#ticket-order-#{order_id}", member.email)
      assert has_element?(view, "#ticket-order-#{order_id}", "GA Migration")
      assert has_element?(view, "#ticket-order-#{order_id}", "2 tickets")
    end

    test "volunteer cannot grant tickets from the tickets tab (Finding 46)", %{
      conn: conn
    } do
      volunteer = user_fixture(%{role: "volunteer"})
      conn = log_in_user(conn, volunteer)
      member = user_fixture()
      event = event_fixture(%{organizer_id: volunteer.id, state: :published})

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA Volunteer Grant",
          quantity: 50
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      refute has_element?(view, "#ticket-tier-actions-#{tier.id}-grant")

      view
      |> element("#ticket-tier-grant-event-#{event.id}")
      |> render_click(%{"id" => tier.id})

      refute has_element?(view, "#grant-tickets-modal")
      assert Events.list_tickets_for_user(member.id) == []
    end
  end

  describe "statistics tab" do
    setup [:create_admin]

    test "loads statistics content asynchronously", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, title: "Stats Event"})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/statistics")

      render_async(view)

      assert has_element?(view, "#event-statistics-content")
      refute has_element?(view, "#event-statistics-loading")
      assert has_element?(view, "#event-stats-kpis")
    end
  end

  describe "editing presence" do
    setup [:create_admin]

    test "shows an avatar for another admin currently editing", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, title: "Presence Event"})
      other_admin = user_fixture(%{role: "admin", first_name: "Jamie"})

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: "other-tab-#{System.unique_integer([:positive])}"},
          :event,
          event.id,
          other_admin
        )

      {:ok, _view, html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert html =~ "Jamie"
      assert html =~ "is editing"
    end

    test "does not show the current admin's own presence", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, title: "Self Presence"})

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: "self-tab-#{System.unique_integer([:positive])}"},
          :event,
          event.id,
          admin
        )

      {:ok, _view, html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      refute html =~ "is editing"
    end

    test "updates avatars live when another admin starts editing", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, title: "Live Presence"})

      {:ok, view, html} = live(conn, ~p"/admin/events/#{event.id}/edit")
      refute html =~ "is editing"

      other_admin = user_fixture(%{role: "admin", first_name: "Taylor"})

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: "live-tab-#{System.unique_integer([:positive])}"},
          :event,
          event.id,
          other_admin
        )

      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: YscWeb.Admin.EditingPresence.topic(:event),
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

    test "shows who last edited the event", %{conn: conn, admin: admin} do
      editor = user_fixture(%{role: "admin", first_name: "Morgan"})
      event = event_fixture(%{organizer_id: admin.id, title: "Edited event"})

      {:ok, _event} =
        Events.update_event_editor(event, %{"title" => "Edited event!"},
          updated_by_id: editor.id
        )

      {:ok, _view, html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert html =~ "Last edited by"
      assert html =~ "Morgan"
    end

    test "falls back to the organizer when the event has never been re-edited",
         %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id, title: "Never re-edited"})

      {:ok, _view, html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert html =~ "Last edited by"
    end

    test "formats the timestamp in Pacific time, not UTC", %{
      conn: conn,
      admin: admin
    } do
      # 05:00 UTC on Mar 15 is still Mar 14 10:00pm PDT.
      edited_at = ~U[2024-03-15 05:00:00Z]
      event = event_fixture(%{organizer_id: admin.id, title: "Timezone event"})
      stamp_updated_at(Event, event.id, edited_at)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "p", pacific_last_edited_label(edited_at))
      refute has_element?(view, "p", utc_last_edited_label(edited_at))
    end
  end

  describe "event preview link" do
    setup [:create_admin]

    test "labels the public page link Preview for draft events", %{
      conn: conn,
      admin: admin
    } do
      event =
        event_fixture(%{
          organizer_id: admin.id,
          state: :draft,
          title: "Draft preview"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(
               view,
               ~s|a[href="/events/#{event.id}"][target="_blank"]|,
               "Preview"
             )

      refute has_element?(
               view,
               ~s|a[href="/events/#{event.id}"]|,
               "View Event"
             )
    end

    test "labels the public page link View Event for published events", %{
      conn: conn,
      admin: admin
    } do
      event =
        event_fixture(%{
          organizer_id: admin.id,
          state: :published,
          title: "Published view"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(
               view,
               ~s|a[href="/events/#{event.id}"][target="_blank"]|,
               "View Event"
             )
    end
  end

  describe "agenda chronological warning after PubSub" do
    setup [:create_admin]

    test "clears a false warning after a drag-reorder that restores chronological order",
         %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id, title: "Agenda resync"})
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, late} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Late first",
          start_time: ~T[11:00:00]
        })

      {:ok, early} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Early second",
          start_time: ~T[09:00:00]
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")
      assert has_element?(view, "h3", "Chronological Warning")

      # Moving the 09:00 item to the top shifts sibling positions in the DB.
      # The old in-memory patch only updated this one item, so the warning
      # stayed up even though the agenda is now in order.
      assert :ok = Agendas.update_agenda_item_position(event.id, early, 0)

      html = render_agenda_item_event(view, early)
      refute html =~ "Chronological Warning"
      assert html =~ late.title
    end

    test "shows a warning after a drag-reorder that breaks chronological order",
         %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id, title: "Agenda break"})
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, _morning} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Morning",
          start_time: ~T[09:00:00]
        })

      {:ok, afternoon} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Afternoon",
          start_time: ~T[11:00:00]
        })

      {:ok, view, html} = live(conn, ~p"/admin/events/#{event.id}/edit")
      refute html =~ "Chronological Warning"

      assert :ok = Agendas.update_agenda_item_position(event.id, afternoon, 0)

      html = render_agenda_item_event(view, afternoon)
      assert html =~ "Chronological Warning"
    end
  end

  # send_update from handle_info is applied on the following render.
  defp render_agenda_item_event(view, agenda_item) do
    send(
      view.pid,
      {Ysc.Agendas,
       %MessagePassingEvents.AgendaItemRepositioned{agenda_item: agenda_item}}
    )

    _ = render(view)
    render(view)
  end

  defp stamp_updated_at(schema, id, datetime) do
    {1, _} =
      Repo.update_all(from(r in schema, where: r.id == ^id),
        set: [updated_at: datetime]
      )

    :ok
  end

  defp pacific_last_edited_label(datetime) do
    datetime
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> Timex.format!("{Mshort} {D}, {YYYY} at {h12}:{m}{am}")
  end

  defp utc_last_edited_label(datetime) do
    Timex.format!(datetime, "{Mshort} {D}, {YYYY} at {h12}:{m}{am}")
  end
end
