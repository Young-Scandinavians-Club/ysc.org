defmodule YscWeb.EventDetailsLive.TierPurchaseLimitsTest do
  @moduledoc """
  LiveView tests for per-buyer ticket limits (`max_per_buyer`) on the public
  event page. Server-side enforcement is covered in `Ysc.TicketsTest`; these
  tests pin the limit note and the + button lock.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import EventDetailsLiveHelpers
  import Mox

  alias Ysc.Events
  alias Ysc.Repo

  setup :verify_on_exit!

  setup %{conn: conn} do
    setup_stripe_mocks()

    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    stub(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
      {:ok, build_payment_intent(%{amount: params.amount})}
    end)

    stub(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
      {:ok, build_payment_intent(%{id: id, status: "requires_payment_method"})}
    end)

    %{conn: conn}
  end

  defp lifetime_member do
    user_fixture()
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()
  end

  defp event_with_guest_tier(max_per_buyer) do
    organizer = lifetime_member()

    {:ok, event} =
      Events.create_event(%{
        title: "Limit checkout #{System.unique_integer([:positive])}",
        description: "Per-buyer limit UI",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.add(
            DateTime.utc_now() |> DateTime.truncate(:second),
            30,
            :day
          ),
        max_attendees: 50,
        published_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, member_tier} =
      Events.create_ticket_tier(%{
        name: "Member ticket",
        type: :paid,
        price: Money.new(20, :USD),
        quantity: 20,
        member_only: true,
        event_id: event.id
      })

    {:ok, guest_tier} =
      Events.create_ticket_tier(%{
        name: "Guest ticket",
        type: :paid,
        price: Money.new(30, :USD),
        quantity: 20,
        max_per_buyer: max_per_buyer,
        event_id: event.id
      })

    %{event: event, member_tier: member_tier, guest_tier: guest_tier}
  end

  defp open_tickets_modal(conn, event) do
    {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
    render_async(view)
    view
  end

  defp increase_enabled?(view, tier_id) do
    has_element?(
      view,
      "button[data-ticket-action='increase'][data-tier-id='#{tier_id}']:not([disabled])"
    )
  end

  defp increase_disabled?(view, tier_id) do
    has_element?(
      view,
      "button[data-ticket-action='increase'][data-tier-id='#{tier_id}'][disabled]"
    )
  end

  describe "per-buyer limit UI" do
    test "shows the limit note only on the limited tier", %{conn: conn} do
      ctx = event_with_guest_tier(1)
      view = open_tickets_modal(log_in_user(conn, lifetime_member()), ctx.event)

      assert has_element?(view, "#tier-limit-#{ctx.guest_tier.id}")
      refute has_element?(view, "#tier-limit-#{ctx.member_tier.id}")
    end

    test "locks the + button once the limit is selected", %{conn: conn} do
      ctx = event_with_guest_tier(1)
      view = open_tickets_modal(log_in_user(conn, lifetime_member()), ctx.event)

      assert increase_enabled?(view, ctx.guest_tier.id)

      render_click(view, "increase-ticket-quantity", %{
        "tier-id" => ctx.guest_tier.id
      })

      assert increase_disabled?(view, ctx.guest_tier.id)
      assert increase_enabled?(view, ctx.member_tier.id)
      assert has_element?(view, "#tier-limit-#{ctx.guest_tier.id}", "reached")
    end

    test "ignores increase events past the limit", %{conn: conn} do
      ctx = event_with_guest_tier(1)
      view = open_tickets_modal(log_in_user(conn, lifetime_member()), ctx.event)

      for _ <- 1..3 do
        render_click(view, "increase-ticket-quantity", %{
          "tier-id" => ctx.guest_tier.id
        })
      end

      assert has_element?(view, "#ticket-qty-#{ctx.guest_tier.id}", "1")
    end

    test "a limit of 2 allows two tickets", %{conn: conn} do
      ctx = event_with_guest_tier(2)
      view = open_tickets_modal(log_in_user(conn, lifetime_member()), ctx.event)

      for _ <- 1..3 do
        render_click(view, "increase-ticket-quantity", %{
          "tier-id" => ctx.guest_tier.id
        })
      end

      assert has_element?(view, "#ticket-qty-#{ctx.guest_tier.id}", "2")
      assert increase_disabled?(view, ctx.guest_tier.id)
    end
  end
end
