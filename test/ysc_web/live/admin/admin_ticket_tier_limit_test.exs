defmodule YscWeb.AdminTicketTierLimitTest do
  @moduledoc """
  Admin form coverage for the per-member ticket limit (`max_per_buyer`).
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events.TicketTier
  alias Ysc.Repo

  setup %{conn: conn} do
    admin = user_fixture(%{role: "admin"})
    event = event_fixture(%{organizer_id: admin.id})
    %{conn: log_in_user(conn, admin), event: event}
  end

  defp open_new_tier_form(conn, event) do
    {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")
    view |> element("#add-ticket-tier-btn-#{event.id}") |> render_click()
    view
  end

  defp tier_form(event), do: "#ticket-tier-form-#{event.id}"

  test "the limit field is blank by default and not offered for donations", %{
    conn: conn,
    event: event
  } do
    view = open_new_tier_form(conn, event)

    assert has_element?(view, ~s(input[name="ticket_tier[max_per_buyer]"]))

    view
    |> form(tier_form(event), %{"ticket_tier" => %{"type" => "donation"}})
    |> render_change()

    refute has_element?(view, ~s(input[name="ticket_tier[max_per_buyer]"]))
  end

  test "saving a tier with a limit persists it", %{conn: conn, event: event} do
    view = open_new_tier_form(conn, event)

    view
    |> form(tier_form(event), %{
      "ticket_tier" => %{
        "name" => "Guest (+1)",
        "type" => "free",
        "unlimited_quantity" => "true",
        "max_per_buyer" => "1"
      }
    })
    |> render_submit()

    tier = Repo.get_by!(TicketTier, name: "Guest (+1)")
    assert tier.max_per_buyer == 1

    {:ok, _view, html} = live(conn, ~p"/admin/events/#{event.id}/tickets")
    assert html =~ "Limit 1 per member"
  end

  test "a blank limit saves as no limit", %{conn: conn, event: event} do
    view = open_new_tier_form(conn, event)

    view
    |> form(tier_form(event), %{
      "ticket_tier" => %{
        "name" => "Open tier",
        "type" => "free",
        "unlimited_quantity" => "true",
        "max_per_buyer" => ""
      }
    })
    |> render_submit()

    assert Repo.get_by!(TicketTier, name: "Open tier").max_per_buyer == nil
  end

  test "a zero limit is rejected", %{conn: conn, event: event} do
    view = open_new_tier_form(conn, event)

    view
    |> form(tier_form(event), %{
      "ticket_tier" => %{
        "name" => "Zero tier",
        "type" => "free",
        "unlimited_quantity" => "true",
        "max_per_buyer" => "0"
      }
    })
    |> render_submit()

    assert Repo.get_by(TicketTier, name: "Zero tier") == nil
  end
end
