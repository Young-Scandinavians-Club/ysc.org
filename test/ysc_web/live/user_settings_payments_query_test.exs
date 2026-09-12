defmodule YscWeb.UserSettingsPaymentsQueryTest do
  @moduledoc """
  Query-count assertions for the member payments tab.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.Ledgers
  alias Ysc.Repo

  @event_toast "<p>toast body that payments tab must not load</p>"

  setup %{conn: conn} do
    user =
      user_fixture(%{state: :active, first_name: "History", last_name: "Payer"})

    %{conn: log_in_user(conn, user), user: user}
  end

  test "dead render does not SELECT event HTML before connect", %{
    conn: conn,
    user: user
  } do
    seed_event_payment!(user, "Dead Render Gala XYZ")

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get(~p"/users/payments")
          |> html_response(200)
        end,
        pattern: ~r/raw_details|rendered_details/i,
        caller_pids: [self()]
      )

    assert query_count == 0
    refute html =~ "Dead Render Gala XYZ"
  end

  test "connected payments tab loads event title without event HTML", %{
    conn: conn,
    user: user
  } do
    %{event: event} = seed_event_payment!(user, "Connected Gala XYZ")

    {{:ok, view, _html}, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          {:ok, view, html} = live(conn, ~p"/users/payments")
          _html = render(view)
          {:ok, view, html}
        end,
        pattern: ~r/raw_details|rendered_details/i
      )

    html = render(view)
    assert query_count == 0
    assert html =~ event.title
    assert has_element?(view, "#payments-list")
  end

  defp seed_event_payment!(user, title) do
    event =
      event_fixture(%{
        title: title,
        raw_details: @event_toast,
        rendered_details: @event_toast
      })

    tier = ticket_tier_fixture(%{event_id: event.id, name: "VIP"})

    ticket_order =
      ticket_order_fixture(%{
        user: user,
        event: event,
        tier: tier,
        status: :completed
      })

    {:ok, {payment, _, _}} =
      Ledgers.process_payment(%{
        user_id: user.id,
        amount: Money.new(10_000, :USD),
        entity_type: :event,
        entity_id: event.id,
        external_payment_id:
          "pi_settings_hist_#{System.unique_integer([:positive])}",
        stripe_fee: Money.new(320, :USD),
        description: "Event tickets",
        property: nil,
        payment_method_id: nil
      })

    ticket_order
    |> Ecto.Changeset.change(payment_id: payment.id)
    |> Repo.update!()

    %{event: event, payment: payment}
  end
end
