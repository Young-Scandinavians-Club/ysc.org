defmodule YscWeb.EventDetailsLive.MemberOnlyTiersTest do
  @moduledoc """
  LiveView tests for member-only ticket tier checkout UI.

  Server-side plan limits are covered in `Ysc.TicketsTest`. These tests pin the
  public event-page gates: the Members-only badge, the + button disable, and
  the inline explanation when a Single member hits their one-ticket limit.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import EventDetailsLiveHelpers
  import Mox

  alias Ysc.Accounts.MembershipCache
  alias Ysc.Events
  alias Ysc.Repo
  alias Ysc.Subscriptions

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

  defp membership_user do
    user_fixture()
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()
  end

  defp give_single_membership(user) do
    plans = Application.fetch_env!(:ysc, :membership_plans)
    single = Enum.find(plans, &(&1.id == :single))

    {:ok, subscription} =
      Subscriptions.create_subscription(%{
        user_id: user.id,
        stripe_id: "sub_single_#{System.unique_integer([:positive])}",
        stripe_status: "active",
        name: "Membership",
        current_period_start: DateTime.truncate(DateTime.utc_now(), :second),
        current_period_end:
          DateTime.utc_now()
          |> DateTime.add(30, :day)
          |> DateTime.truncate(:second)
      })

    {:ok, _} =
      Subscriptions.create_subscription_item(%{
        subscription_id: subscription.id,
        stripe_id: "si_single_#{System.unique_integer([:positive])}",
        stripe_product_id: "prod_single",
        stripe_price_id: single.stripe_price_id,
        quantity: 1
      })

    MembershipCache.invalidate_user(user.id)
    user
  end

  defp event_with_member_only_and_regular_tiers do
    organizer = membership_user()

    {:ok, event} =
      Events.create_event(%{
        title: "Member-only checkout #{System.unique_integer([:positive])}",
        description: "Member-only ticket UI",
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
        name: "Members GA",
        type: :paid,
        price: Money.new(20, :USD),
        quantity: 20,
        member_only: true,
        event_id: event.id
      })

    {:ok, regular_tier} =
      Events.create_ticket_tier(%{
        name: "General Admission",
        type: :paid,
        price: Money.new(40, :USD),
        quantity: 20,
        event_id: event.id
      })

    %{event: event, member_tier: member_tier, regular_tier: regular_tier}
  end

  defp open_tickets_modal(conn, event) do
    {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
    html = render_async(view)
    {view, html}
  end

  defp increase_disabled?(view, tier_id) do
    has_element?(
      view,
      "button[data-ticket-action='increase'][data-tier-id='#{tier_id}'][disabled]"
    )
  end

  defp increase_enabled?(view, tier_id) do
    has_element?(
      view,
      "button[data-ticket-action='increase'][data-tier-id='#{tier_id}']:not([disabled])"
    )
  end

  describe "member-only checkout UI" do
    test "shows Members only badge on the flagged tier", %{conn: conn} do
      ctx = event_with_member_only_and_regular_tiers()
      user = give_single_membership(user_fixture())
      conn = log_in_user(conn, user)

      {_view, html} = open_tickets_modal(conn, ctx.event)

      assert html =~ "Members only"
      assert html =~ "Members GA"
    end

    test "single member can add one member-only ticket then the + button locks",
         %{conn: conn} do
      ctx = event_with_member_only_and_regular_tiers()
      user = give_single_membership(user_fixture())
      conn = log_in_user(conn, user)

      {view, _html} = open_tickets_modal(conn, ctx.event)

      assert increase_enabled?(view, ctx.member_tier.id)
      assert increase_enabled?(view, ctx.regular_tier.id)

      render_click(view, "increase-ticket-quantity", %{
        "tier-id" => ctx.member_tier.id
      })

      assert increase_disabled?(view, ctx.member_tier.id)
      assert increase_enabled?(view, ctx.regular_tier.id)

      html = render(view)

      assert html =~ "members-only ticket per event"
      assert html =~ "reached that limit"
    end

    test "lifetime member is not blocked after adding one member-only ticket",
         %{conn: conn} do
      ctx = event_with_member_only_and_regular_tiers()
      conn = log_in_user(conn, membership_user())

      {view, _html} = open_tickets_modal(conn, ctx.event)

      render_click(view, "increase-ticket-quantity", %{
        "tier-id" => ctx.member_tier.id
      })

      assert increase_enabled?(view, ctx.member_tier.id)
      refute render(view) =~ "reached that limit"
    end
  end
end
