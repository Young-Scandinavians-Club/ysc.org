defmodule YscWeb.AdminTicketTierUrlTest do
  @moduledoc """
  The ticket tier form is addressed by the `tier` query param on the tickets
  tab (`?tier=new` or `?tier=<tier id>`), so it can be linked to and survives a
  reload. The param is untrusted input: these tests cover that it opens the same
  forms the UI would, and nothing else.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  setup %{conn: conn} do
    admin = user_fixture(%{role: "admin"})
    event = event_fixture(%{organizer_id: admin.id})
    tier = ticket_tier_fixture(%{event_id: event.id, name: "Early Bird"})

    %{conn: log_in_user(conn, admin), event: event, tier: tier}
  end

  defp tickets_path(event), do: ~p"/admin/events/#{event.id}/tickets"
  defp form_root(event), do: "#tier-form-#{event.id}"

  describe "opening from the URL" do
    test "?tier=<id> opens the edit form for that tier", %{
      conn: conn,
      event: event,
      tier: tier
    } do
      {:ok, view, _html} = live(conn, "#{tickets_path(event)}?tier=#{tier.id}")

      assert has_element?(view, "#edit-ticket-tier-modal")
      assert has_element?(view, "#edit-ticket-tier-form-#{tier.id}")

      assert has_element?(
               view,
               ~s(#ticket_tier_name[value="Early Bird"])
             )
    end

    test "?tier=new opens the add form", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, "#{tickets_path(event)}?tier=new")

      assert has_element?(view, "#add-ticket-tier-modal")
      refute has_element?(view, "#edit-ticket-tier-modal")
    end

    test "no param means no modal", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, tickets_path(event))

      refute has_element?(view, "#add-ticket-tier-modal")
      refute has_element?(view, "#edit-ticket-tier-modal")
    end

    test "the edit action links to the tier so it can be opened in a new tab",
         %{
           conn: conn,
           event: event,
           tier: tier
         } do
      {:ok, view, _html} = live(conn, tickets_path(event))

      href =
        view
        |> element("#ticket-tier-actions-#{tier.id}-edit")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("href")

      assert href == ["#{tickets_path(event)}?tier=#{tier.id}"]
    end

    test "clicking edit and add puts the tier in the URL", %{
      conn: conn,
      event: event,
      tier: tier
    } do
      {:ok, view, _html} = live(conn, tickets_path(event))

      view |> element("#ticket-tier-actions-#{tier.id}-edit") |> render_click()
      assert_patch(view, "#{tickets_path(event)}?tier=#{tier.id}")
      assert has_element?(view, "#edit-ticket-tier-modal")

      {:ok, view, _html} = live(conn, tickets_path(event))

      view |> element("#add-ticket-tier-btn-#{event.id}") |> render_click()
      assert_patch(view, "#{tickets_path(event)}?tier=new")
      assert has_element?(view, "#add-ticket-tier-modal")
    end
  end

  describe "untrusted param" do
    # Patching an already-mounted view lets us observe the redirect that drops
    # the bad param; on first load the test client applies it silently.
    defp patch_to(conn, event, query) do
      {:ok, view, _html} = live(conn, tickets_path(event))
      render_patch(view, "#{tickets_path(event)}?#{query}")
      view
    end

    test "an unknown tier id closes the modal and drops the param", %{
      conn: conn,
      event: event
    } do
      view = patch_to(conn, event, "tier=01HZZZZZZZZZZZZZZZZZZZZZZZ")

      assert_patch(view, tickets_path(event))
      refute has_element?(view, "#edit-ticket-tier-modal")
    end

    test "a malformed tier id never reaches the database", %{
      conn: conn,
      event: event
    } do
      view = patch_to(conn, event, "tier=%27%3B%20drop%20table")

      assert_patch(view, tickets_path(event))
      refute has_element?(view, "#edit-ticket-tier-modal")
    end

    test "another event's tier is treated as missing", %{
      conn: conn,
      event: event
    } do
      other_tier = ticket_tier_fixture(%{event_id: event_fixture().id})
      view = patch_to(conn, event, "tier=#{other_tier.id}")

      assert_patch(view, tickets_path(event))
      refute has_element?(view, "#edit-ticket-tier-modal")
    end

    test "other params survive when the bad one is dropped", %{
      conn: conn,
      event: event
    } do
      view = patch_to(conn, event, "page=2&tier=nope")

      assert_patch(view, "#{tickets_path(event)}?page=2")
    end

    test "a bad param on first load opens nothing", %{
      conn: conn,
      event: event
    } do
      {:ok, view, _html} = live(conn, "#{tickets_path(event)}?tier=nope")

      refute has_element?(view, "#add-ticket-tier-modal")
      refute has_element?(view, "#edit-ticket-tier-modal")
    end
  end

  describe "volunteer deep links" do
    test "?tier=new and ?tier=<id> do not open the forms", %{
      conn: _conn,
      event: event,
      tier: tier
    } do
      volunteer = user_fixture(%{role: "volunteer"})
      conn = log_in_user(build_conn(), volunteer)

      {:ok, view, _html} = live(conn, "#{tickets_path(event)}?tier=new")
      refute has_element?(view, "#add-ticket-tier-modal")

      {:ok, view, _html} = live(conn, "#{tickets_path(event)}?tier=#{tier.id}")
      refute has_element?(view, "#edit-ticket-tier-modal")

      # And once mounted, patching to either is refused and the param dropped.
      render_patch(view, "#{tickets_path(event)}?tier=new")
      assert_patch(view, tickets_path(event))
      refute has_element?(view, "#add-ticket-tier-modal")
    end
  end

  describe "closing" do
    test "an untouched form closes straight away", %{
      conn: conn,
      event: event,
      tier: tier
    } do
      {:ok, view, _html} = live(conn, "#{tickets_path(event)}?tier=#{tier.id}")

      refute has_element?(view, "#tier-form-unsaved")

      view |> with_target(form_root(event)) |> render_click("request-close")

      assert_patch(view, tickets_path(event))
      refute has_element?(view, "#edit-ticket-tier-modal")
    end

    test "closing keeps the tab's other params", %{conn: conn, event: event} do
      {:ok, view, _html} =
        live(conn, "#{tickets_path(event)}?page=2&tier=new")

      view |> with_target(form_root(event)) |> render_click("request-close")

      assert_patch(view, "#{tickets_path(event)}?page=2")
    end

    test "an edited form asks before discarding", %{
      conn: conn,
      event: event,
      tier: tier
    } do
      {:ok, view, _html} = live(conn, "#{tickets_path(event)}?tier=#{tier.id}")

      view
      |> form("#edit-ticket-tier-form-#{tier.id}", %{
        "ticket_tier" => %{"name" => "Renamed"}
      })
      |> render_change()

      assert has_element?(view, "#tier-form-unsaved")
      assert has_element?(view, ~s(#tier-form-#{event.id}[data-dirty="true"]))

      view |> with_target(form_root(event)) |> render_click("request-close")

      # Still open, now asking.
      assert has_element?(view, "#tier-form-discard-confirm")
      assert has_element?(view, "#edit-ticket-tier-modal")
      assert_patched_stays(view, tier, event)

      # Keep editing returns to the form with the edit intact.
      view |> element("#tier-form-keep-editing") |> render_click()
      refute has_element?(view, "#tier-form-discard-confirm")
      assert has_element?(view, ~s(#ticket_tier_name[value="Renamed"]))

      # Discard closes without saving.
      view |> with_target(form_root(event)) |> render_click("request-close")
      view |> element("#tier-form-discard") |> render_click()

      assert_patch(view, tickets_path(event))
      assert Ysc.Events.get_ticket_tier!(tier.id).name == "Early Bird"
    end

    test "typing again dismisses a pending discard prompt", %{
      conn: conn,
      event: event,
      tier: tier
    } do
      {:ok, view, _html} = live(conn, "#{tickets_path(event)}?tier=#{tier.id}")
      form = "#edit-ticket-tier-form-#{tier.id}"

      view
      |> form(form, %{"ticket_tier" => %{"name" => "A"}})
      |> render_change()

      view |> with_target(form_root(event)) |> render_click("request-close")
      assert has_element?(view, "#tier-form-discard-confirm")

      view
      |> form(form, %{"ticket_tier" => %{"name" => "AB"}})
      |> render_change()

      refute has_element?(view, "#tier-form-discard-confirm")
    end

    test "saving from a deep link lands back on the tab without the param", %{
      conn: conn,
      event: event,
      tier: tier
    } do
      {:ok, view, _html} = live(conn, "#{tickets_path(event)}?tier=#{tier.id}")

      view
      |> form("#edit-ticket-tier-form-#{tier.id}", %{
        "ticket_tier" => %{"name" => "Renamed"}
      })
      |> render_submit()

      assert_redirect(view, tickets_path(event))
      assert Ysc.Events.get_ticket_tier!(tier.id).name == "Renamed"
    end
  end

  # The URL must not change while the discard prompt is up.
  defp assert_patched_stays(view, tier, event) do
    refute_patched(view, tickets_path(event))
    assert has_element?(view, "#edit-ticket-tier-form-#{tier.id}")
  end
end
