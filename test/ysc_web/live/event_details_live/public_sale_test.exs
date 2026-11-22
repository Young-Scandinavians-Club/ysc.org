defmodule YscWeb.EventDetailsLive.PublicSaleTest do
  @moduledoc """
  Event page for events that sell some tiers to the general public
  (`TicketTier.sale_audience == :public`): the ticket CTA and public tiers are
  buyable by anyone, while member tiers stay visible but ask for a sign-in
  (anonymous) or a membership (signed-in non-member).
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

  defp member_user do
    user_fixture()
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()
  end

  defp event_with_tiers(public?) do
    organizer = member_user()

    {:ok, event} =
      Events.create_event(%{
        title: "Public sale #{System.unique_integer([:positive])}",
        description: "Open event",
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

    create_tier = fn name, attrs ->
      {:ok, tier} =
        Events.create_ticket_tier(
          Map.merge(
            %{
              name: name,
              type: :paid,
              price: Money.new(30, :USD),
              quantity: 20,
              event_id: event.id
            },
            attrs
          )
        )

      tier
    end

    public_tier =
      create_tier.(
        "Public GA",
        %{sale_audience: if(public?, do: :public, else: :member_guests)}
      )

    member_tier =
      create_tier.("Members GA", %{sale_audience: :members_only})

    %{event: event, public_tier: public_tier, member_tier: member_tier}
  end

  defp increase_enabled?(view, tier_id) do
    has_element?(
      view,
      "button[data-ticket-action='increase'][data-tier-id='#{tier_id}']:not([disabled])"
    )
  end

  describe "event page when some tiers are public" do
    test "anonymous visitors get a Get Tickets button and no member-only gate",
         %{conn: conn} do
      %{event: event} = event_with_tiers(true)

      {:ok, view, html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert has_element?(view, "#event-get-tickets-button")
      assert has_element?(view, "#event-get-tickets-button-mobile")
      assert has_element?(view, "#event-tickets-public-cta")
      assert has_element?(view, "#event-tickets-member-signin-link")
      refute has_element?(view, "#event-tickets-guest-cta")
      refute html =~ "Tickets are for YSC members"
    end

    test "signed-in non-members can open the ticket modal", %{conn: conn} do
      %{event: event} = event_with_tiers(true)
      conn = log_in_user(conn, user_fixture())

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert has_element?(view, "#event-get-tickets-button")
      assert has_element?(view, "#event-tickets-membership-note")
      refute has_element?(view, "#event-tickets-membership-link")
    end

    test "members see the Get Tickets button without public prompts", %{
      conn: conn
    } do
      %{event: event} = event_with_tiers(true)
      conn = log_in_user(conn, member_user())

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert has_element?(view, "#event-get-tickets-button")
      refute has_element?(view, "#event-tickets-public-cta")
      refute has_element?(view, "#event-tickets-membership-note")
    end
  end

  describe "event page when no tier is public" do
    test "anonymous visitors keep the members-only prompt", %{conn: conn} do
      %{event: event} = event_with_tiers(false)

      {:ok, view, html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert has_element?(view, "#event-tickets-guest-cta")
      refute has_element?(view, "#event-get-tickets-button")
      assert html =~ "Tickets are for YSC members"
    end

    test "non-members keep the membership prompt", %{conn: conn} do
      %{event: event} = event_with_tiers(false)
      conn = log_in_user(conn, user_fixture())

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      refute has_element?(view, "#event-get-tickets-button")
      assert has_element?(view, "#event-tickets-membership-link")
    end
  end

  describe "ticket modal" do
    test "anonymous visitors can buy public tiers and are asked to sign in for member tiers",
         %{conn: conn} do
      %{event: event, public_tier: public_tier, member_tier: member_tier} =
        event_with_tiers(true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
      render_async(view)

      assert has_element?(view, "#tier-badge-public-#{public_tier.id}")
      assert increase_enabled?(view, public_tier.id)
      assert has_element?(view, "#tier-sign-in-#{member_tier.id}")
      assert has_element?(view, "#tier-sign-in-link-#{member_tier.id}")

      refute has_element?(
               view,
               "button[data-ticket-action='increase'][data-tier-id='#{member_tier.id}']"
             )
    end

    test "a visitor who may not buy a tier cannot raise its quantity", %{
      conn: conn
    } do
      %{event: event, member_tier: member_tier} = event_with_tiers(true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
      render_async(view)

      render_click(view, "increase-ticket-quantity", %{
        "tier-id" => member_tier.id
      })

      selected = :sys.get_state(view.pid).socket.assigns.selected_tickets
      assert Map.get(selected, member_tier.id, 0) == 0
    end

    test "signed-in non-members see a membership prompt on member tiers", %{
      conn: conn
    } do
      %{event: event, public_tier: public_tier, member_tier: member_tier} =
        event_with_tiers(true)

      conn = log_in_user(conn, user_fixture())

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
      render_async(view)

      assert has_element?(view, "#tier-membership-required-#{member_tier.id}")
      assert has_element?(view, "#tier-membership-link-#{member_tier.id}")
      assert increase_enabled?(view, public_tier.id)
    end

    test "a signed-in non-member can check out a public tier", %{conn: conn} do
      %{event: event, public_tier: public_tier} = event_with_tiers(true)
      conn = log_in_user(conn, user_fixture())

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
      render_async(view)

      render_click(view, "increase-ticket-quantity", %{
        "tier-id" => public_tier.id
      })

      render_click(view, "proceed-to-checkout")
      html = render(view)

      refute html =~ "active, paid YSC membership"
      assert has_element?(view, "#payment-modal")
    end

    test "anonymous checkout of public tiers continues as a guest", %{
      conn: conn
    } do
      %{event: event, public_tier: public_tier} = event_with_tiers(true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
      render_async(view)

      render_click(view, "increase-ticket-quantity", %{
        "tier-id" => public_tier.id
      })

      render_click(view, "proceed-to-checkout")

      {path, _flash} = assert_redirect(view)
      assert path =~ "/events/#{event.id}/checkout?s="
    end

    test "anonymous checkout with nothing buyable goes to sign in", %{
      conn: conn
    } do
      %{event: event} = event_with_tiers(true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
      render_async(view)

      render_click(view, "proceed-to-checkout")

      {path, _flash} = assert_redirect(view)
      assert path =~ "/users/log-in"
    end
  end
end
