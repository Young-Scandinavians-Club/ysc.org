defmodule YscWeb.Components.Events.EventCardTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias YscWeb.EventCardTestHost

  defp pacific_today do
    DateTime.now!("America/Los_Angeles")
    |> DateTime.to_date()
  end

  defp utc_midnight(date) do
    DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  end

  defp base_event(overrides) do
    today = pacific_today()

    Map.merge(
      %{
        id: Ecto.ULID.generate(),
        title: "Test Event",
        description: "Description",
        state: :published,
        start_date: utc_midnight(Date.add(today, 7)),
        end_date: utc_midnight(Date.add(today, 8)),
        start_time: nil,
        image: nil,
        location_name: nil,
        published_at: DateTime.utc_now() |> DateTime.truncate(:second),
        tickets_tbd: false,
        pricing_info: %{display_text: "Free"}
      },
      overrides
    )
  end

  defp render_card(_conn, event, opts \\ []) do
    render_component(EventCardTestHost,
      id: "event-card-test-host",
      event: event,
      sold_out: Keyword.get(opts, :sold_out, false),
      selling_fast: Keyword.get(opts, :selling_fast, false)
    )
  end

  describe "badge priority" do
    test "cancelled events only show the Cancelled badge", %{conn: conn} do
      today = pacific_today()

      event =
        base_event(%{
          state: :cancelled,
          start_date: utc_midnight(today),
          end_date: utc_midnight(today),
          tickets_tbd: true,
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      html = render_card(conn, event, sold_out: true, selling_fast: true)

      assert html =~ "Cancelled"
      refute html =~ ">Today<"
      refute html =~ ">Tomorrow<"
      refute html =~ "Sold Out"
      refute html =~ "Save the Date"
      refute html =~ "Going Fast!"
    end

    test "sold out suppresses proximity and marketing badges", %{conn: conn} do
      today = pacific_today()

      event =
        base_event(%{
          start_date: utc_midnight(today),
          end_date: utc_midnight(today),
          tickets_tbd: true,
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      html = render_card(conn, event, sold_out: true, selling_fast: true)

      assert html =~ "Sold Out"
      refute html =~ ">Today<"
      refute html =~ "Save the Date"
      refute html =~ "Going Fast!"
    end

    test "unpublished events show no badges", %{conn: conn} do
      today = pacific_today()

      event =
        base_event(%{
          published_at: nil,
          start_date: utc_midnight(today),
          end_date: utc_midnight(today)
        })

      html = render_card(conn, event, selling_fast: true)

      refute html =~ ">Today<"
      refute html =~ ">Tomorrow<"
      refute html =~ "Just Added"
      refute html =~ "Going Fast!"
    end
  end

  describe "proximity badges" do
    test "shows Today badge for events on the Pacific calendar day", %{
      conn: conn
    } do
      today = pacific_today()

      event =
        base_event(%{
          start_date: utc_midnight(today),
          end_date: utc_midnight(today),
          published_at: DateTime.add(DateTime.utc_now(), -72, :hour)
        })

      html = render_card(conn, event)

      assert html =~ ">Today<"
      refute html =~ ">Tomorrow<"
    end

    test "shows Tomorrow badge for the next Pacific calendar day", %{conn: conn} do
      today = pacific_today()
      tomorrow = Date.add(today, 1)

      event =
        base_event(%{
          start_date: utc_midnight(tomorrow),
          end_date: utc_midnight(tomorrow),
          published_at: DateTime.add(DateTime.utc_now(), -72, :hour)
        })

      html = render_card(conn, event)

      assert html =~ ">Tomorrow<"
      refute html =~ ">Today<"
    end

    test "shows days-left badge for events two or three days out", %{conn: conn} do
      today = pacific_today()

      for days <- [2, 3] do
        target = Date.add(today, days)

        event =
          base_event(%{
            start_date: utc_midnight(target),
            end_date: utc_midnight(target),
            published_at: DateTime.add(DateTime.utc_now(), -72, :hour)
          })

        html = render_card(conn, event)
        assert html =~ "#{days} days left"
      end
    end

    test "does not show days-left badge four or more days out", %{conn: conn} do
      today = pacific_today()
      target = Date.add(today, 4)

      event =
        base_event(%{
          start_date: utc_midnight(target),
          end_date: utc_midnight(target),
          published_at: DateTime.add(DateTime.utc_now(), -72, :hour)
        })

      html = render_card(conn, event)

      refute html =~ "days left"
    end
  end

  describe "marketing badges" do
    test "shows Save the Date when tickets are TBD", %{conn: conn} do
      event =
        base_event(%{
          tickets_tbd: true,
          start_date: utc_midnight(Date.add(pacific_today(), 10)),
          end_date: utc_midnight(Date.add(pacific_today(), 11)),
          published_at: DateTime.add(DateTime.utc_now(), -72, :hour)
        })

      html = render_card(conn, event)

      assert html =~ "Save the Date"
    end

    test "shows Just Added within 48 hours of publishing", %{conn: conn} do
      event =
        base_event(%{
          published_at: DateTime.add(DateTime.utc_now(), -12, :hour),
          start_date: utc_midnight(Date.add(pacific_today(), 10)),
          end_date: utc_midnight(Date.add(pacific_today(), 11))
        })

      html = render_card(conn, event)

      assert html =~ "Just Added"
    end

    test "shows Going Fast when selling_fast is true", %{conn: conn} do
      event =
        base_event(%{
          published_at: DateTime.add(DateTime.utc_now(), -72, :hour),
          start_date: utc_midnight(Date.add(pacific_today(), 10)),
          end_date: utc_midnight(Date.add(pacific_today(), 11))
        })

      html = render_card(conn, event, selling_fast: true)

      assert html =~ "Going Fast!"
    end
  end
end
