defmodule YscWeb.AdminTicketTierSaleDatesTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  @days_until_event 10

  setup %{conn: conn} do
    admin = user_fixture(%{role: "admin"})

    event =
      event_fixture(%{
        organizer_id: admin.id,
        start_date:
          DateTime.utc_now()
          |> DateTime.add(@days_until_event, :day)
          |> DateTime.truncate(:second)
      })

    {:ok, view, _html} =
      live(log_in_user(conn, admin), ~p"/admin/events/#{event.id}/tickets")

    view |> element("#add-ticket-tier-btn-#{event.id}") |> render_click()

    %{view: view, event_start: DateTime.to_date(event.start_date)}
  end

  # Reopens the calendar (which resets to the current month) and pages forward
  # until the day's button is rendered.
  defp day_button(view, picker_id, %Date{} = day) do
    view
    |> element("##{picker_id} [phx-click='open-calendar']")
    |> render_click()

    selector =
      "##{picker_id} button[phx-click='pick-date'][phx-value-date='#{Date.to_iso8601(day)}T00:00:00Z']"

    Enum.reduce_while(1..3, selector, fn _, selector ->
      if has_element?(view, selector) do
        {:halt, selector}
      else
        view |> element("##{picker_id}-next-month") |> render_click()
        {:cont, selector}
      end
    end)
  end

  defp first_saturday_on_or_after(%Date{} = date) do
    Enum.find(
      Stream.iterate(date, &Date.add(&1, 1)),
      &(Date.day_of_week(&1) == 6)
    )
  end

  for picker_id <- ["sales_start", "sale_ends"] do
    test "#{picker_id} allows a Saturday before the event and blocks days after event start",
         %{view: view, event_start: event_start} do
      saturday = first_saturday_on_or_after(Date.utc_today())
      assert Date.compare(saturday, event_start) != :gt

      refute view
             |> element(day_button(view, unquote(picker_id), saturday))
             |> render()
             |> String.contains?("disabled")

      day_after = Date.add(event_start, 1)

      assert view
             |> element(day_button(view, unquote(picker_id), day_after))
             |> render()
             |> String.contains?("disabled")
    end
  end
end
