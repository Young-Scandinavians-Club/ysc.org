defmodule Ysc.Events.TicketTest do
  use Ysc.DataCase, async: true

  alias Ysc.Events.Ticket
  alias Ysc.Repo
  alias Ysc.Subscriptions

  import Ysc.AccountsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    buyer =
      user_fixture(%{
        email: "ticketcs#{System.unique_integer([:positive])}@example.com"
      })

    buyer =
      buyer
      |> Ecto.Changeset.change(%{
        lifetime_membership_awarded_at:
          DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Ysc.Repo.update!()

    organizer = user_fixture()

    {:ok, event} =
      Ysc.Events.create_event(%{
        title: "Ticket changeset event",
        description: "Test",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.utc_now()
          |> DateTime.add(30, :day)
          |> DateTime.truncate(:second),
        end_date:
          DateTime.utc_now()
          |> DateTime.add(31, :day)
          |> DateTime.truncate(:second),
        max_attendees: 100,
        published_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, tier} =
      Ysc.Events.create_ticket_tier(%{
        name: "GA",
        type: :paid,
        price: Money.new(25, :USD),
        quantity: 50,
        event_id: event.id
      })

    expires =
      DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.truncate(:second)

    %{
      user: buyer,
      event: event,
      tier: tier,
      expires_at: expires
    }
  end

  describe "changeset/2" do
    test "valid with active membership and future event", %{
      user: user,
      event: event,
      tier: tier,
      expires_at: expires_at
    } do
      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          expires_at: expires_at
        })

      assert cs.valid?
    end

    @user_pk ~r/FROM "users" AS u0 WHERE \(u0\."id" = \$/

    test "skips the membership user SELECT when the buyer is passed in", %{
      user: user,
      event: event,
      tier: tier,
      expires_at: expires_at
    } do
      {cs, user_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            Ticket.changeset(
              %Ticket{},
              %{
                event_id: event.id,
                ticket_tier_id: tier.id,
                user_id: user.id,
                expires_at: expires_at
              },
              user: user
            )
          end,
          pattern: @user_pk,
          caller_pids: [self()]
        )

      assert cs.valid?
      assert user_lookups == 0
    end

    test "does not skip membership lookup when the passed user is a different id",
         %{
           user: member,
           event: event,
           tier: tier,
           expires_at: expires_at
         } do
      guest = user_fixture()

      {cs, user_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            Ticket.changeset(
              %Ticket{},
              %{
                event_id: event.id,
                ticket_tier_id: tier.id,
                user_id: guest.id,
                expires_at: expires_at
              },
              user: member
            )
          end,
          pattern: @user_pk,
          caller_pids: [self()]
        )

      refute cs.valid?
      assert {msg, _} = cs.errors[:user_id]
      assert msg == "active membership required to purchase tickets"
      assert user_lookups == 1
    end

    test "valid when the event start is still in the future in Pacific time", %{
      user: user,
      event: event,
      tier: tier,
      expires_at: expires_at
    } do
      # start_date's calendar day + start_time, read as naive UTC, is ~1h in the
      # past; read as Pacific wall-clock (the real semantics) it is 6-7h out.
      target = DateTime.add(DateTime.utc_now(), -1, :hour)

      {:ok, event} =
        Ysc.Events.update_event(event, %{
          start_date:
            DateTime.new!(DateTime.to_date(target), ~T[00:00:00], "Etc/UTC"),
          start_time: target |> DateTime.to_time() |> Time.truncate(:second),
          end_date: nil,
          end_time: nil
        })

      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          expires_at: expires_at
        })

      assert cs.valid?, "unexpected errors: #{inspect(cs.errors)}"
    end

    test "adds error when user has no membership", %{
      event: event,
      tier: tier,
      expires_at: expires_at
    } do
      nomember = user_fixture()

      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: nomember.id,
          expires_at: expires_at
        })

      refute cs.valid?

      assert {msg, _} = cs.errors[:user_id]
      assert msg == "active membership required to purchase tickets"
    end

    test "adds error when event has already ended", %{
      user: user,
      expires_at: expires_at
    } do
      organizer = user_fixture()

      {:ok, past_event} =
        Ysc.Events.create_event(%{
          title: "Past ticket event",
          description: "Past",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.utc_now()
            |> DateTime.add(-5, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.utc_now()
            |> DateTime.add(-4, :day)
            |> DateTime.truncate(:second),
          max_attendees: 100,
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, past_tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "Past GA",
          type: :paid,
          price: Money.new(25, :USD),
          quantity: 50,
          event_id: past_event.id
        })

      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          event_id: past_event.id,
          ticket_tier_id: past_tier.id,
          user_id: user.id,
          expires_at: expires_at
        })

      refute cs.valid?

      assert {msg, _} = cs.errors[:event_id]
      assert msg == "cannot purchase tickets for events that have already ended"
    end

    test "keeps an explicit reference_id from attrs", %{
      user: user,
      event: event,
      tier: tier,
      expires_at: expires_at
    } do
      ref = "TKT-MANUAL-#{System.unique_integer([:positive])}"

      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          reference_id: ref,
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          expires_at: expires_at
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :reference_id) == ref
    end

    test "does not add past-event error when event row is missing", %{
      user: user,
      tier: tier,
      expires_at: expires_at
    } do
      missing_event_id = Ecto.ULID.generate()

      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          event_id: missing_event_id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          expires_at: expires_at
        })

      past_msg? =
        Enum.any?(cs.errors, fn
          {:event_id,
           {"cannot purchase tickets for events that have already ended", _}} ->
            true

          _ ->
            false
        end)

      refute past_msg?
    end

    test "skips past-event check when event_id is absent", %{
      user: user,
      tier: tier,
      expires_at: expires_at
    } do
      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          ticket_tier_id: tier.id,
          user_id: user.id,
          expires_at: expires_at
        })

      refute Enum.any?(cs.errors, fn
               {:event_id,
                {"cannot purchase tickets for events that have already ended",
                 _}} ->
                 true

               _ ->
                 false
             end)
    end

    test "skips membership check when user_id is absent", %{
      event: event,
      tier: tier,
      expires_at: expires_at
    } do
      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          expires_at: expires_at
        })

      assert Ecto.Changeset.get_field(cs, :user_id) == nil

      refute match?(
               {"active membership required to purchase tickets", _},
               cs.errors[:user_id]
             )
    end

    test "does not add membership error when user_id is unknown in database", %{
      event: event,
      tier: tier,
      expires_at: expires_at
    } do
      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: Ecto.ULID.generate(),
          expires_at: expires_at
        })

      refute match?(
               {"active membership required to purchase tickets", _},
               cs.errors[:user_id]
             )

      assert cs.valid?
    end

    test "sub-account inherits primary active subscription", %{
      event: event,
      tier: tier,
      expires_at: expires_at
    } do
      primary = user_fixture()
      period_end = DateTime.add(DateTime.utc_now(), 365, :day)

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: primary.id,
          stripe_id: "cus_subacct_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          name: "Membership",
          current_period_end: period_end
        })

      assert {:ok, _} =
               Subscriptions.create_subscription_item(%{
                 subscription_id: subscription.id,
                 stripe_price_id: "price_subacct_ticket",
                 stripe_product_id: "prod_subacct_ticket",
                 stripe_id: "si_subacct_#{System.unique_integer([:positive])}",
                 quantity: 1
               })

      sub =
        user_fixture()
        |> Ecto.Changeset.change(%{primary_user_id: primary.id})
        |> Repo.update!()

      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: sub.id,
          expires_at: expires_at
        })

      assert cs.valid?
    end

    test "membership passes when user has multiple active subscriptions (no lifetime)",
         %{
           event: event,
           tier: tier,
           expires_at: expires_at
         } do
      buyer = user_fixture()
      period_end = DateTime.add(DateTime.utc_now(), 365, :day)

      for i <- 1..2 do
        assert {:ok, _} =
                 Subscriptions.create_subscription(%{
                   user_id: buyer.id,
                   stripe_id:
                     "cus_multi_#{i}_#{System.unique_integer([:positive])}",
                   stripe_status: "active",
                   name: "Membership",
                   current_period_end: period_end
                 })
      end

      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: buyer.id,
          expires_at: expires_at
        })

      assert cs.valid?
    end

    test "future event with nil start_time uses start_date for end check", %{
      user: user,
      expires_at: expires_at
    } do
      organizer = user_fixture()

      {:ok, ev} =
        Ysc.Events.create_event(%{
          title: "No start time event",
          description: "Test",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.utc_now()
            |> DateTime.add(20, :day)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.utc_now()
            |> DateTime.add(21, :day)
            |> DateTime.truncate(:second),
          max_attendees: 100,
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, ev} =
        ev
        |> Ecto.Changeset.change(%{start_time: nil})
        |> Repo.update()

      {:ok, t} =
        Ysc.Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(25, :USD),
          quantity: 50,
          event_id: ev.id
        })

      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          event_id: ev.id,
          ticket_tier_id: t.id,
          user_id: user.id,
          expires_at: expires_at
        })

      assert cs.valid?
    end

    test "auto-generates reference_id when omitted", %{
      user: user,
      event: event,
      tier: tier,
      expires_at: expires_at
    } do
      cs =
        %Ticket{}
        |> Ticket.changeset(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          expires_at: expires_at
        })

      ref = Ecto.Changeset.get_field(cs, :reference_id)
      assert is_binary(ref)
      assert String.starts_with?(ref, "TKT")
    end
  end

  describe "door_sale_changeset/2" do
    test "allows a ticket for an event that has already started", %{
      user: user,
      event: event,
      tier: tier,
      expires_at: expires_at
    } do
      {:ok, event} =
        Ysc.Events.update_event(event, %{
          start_date:
            DateTime.utc_now()
            |> DateTime.add(-2, :day)
            |> DateTime.truncate(:second)
        })

      purchase =
        %Ticket{}
        |> Ticket.changeset(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          expires_at: expires_at
        })

      refute purchase.valid?
      assert {msg, _} = purchase.errors[:event_id]
      assert msg == "cannot purchase tickets for events that have already ended"

      door_sale =
        %Ticket{}
        |> Ticket.door_sale_changeset(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          expires_at: expires_at
        })

      assert door_sale.valid?, "unexpected errors: #{inspect(door_sale.errors)}"
    end

    test "still requires membership when the guest is passed in", %{
      event: event,
      tier: tier,
      expires_at: expires_at
    } do
      guest = user_fixture()

      cs =
        Ticket.door_sale_changeset(
          %Ticket{},
          %{
            event_id: event.id,
            ticket_tier_id: tier.id,
            user_id: guest.id,
            expires_at: expires_at
          },
          user: guest
        )

      refute cs.valid?
      assert {msg, _} = cs.errors[:user_id]
      assert msg == "active membership required to purchase tickets"
    end

    test "still requires an active membership", %{
      event: event,
      tier: tier,
      expires_at: expires_at
    } do
      nomember = user_fixture()

      cs =
        %Ticket{}
        |> Ticket.door_sale_changeset(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: nomember.id,
          expires_at: expires_at
        })

      refute cs.valid?
      assert {msg, _} = cs.errors[:user_id]
      assert msg == "active membership required to purchase tickets"
    end

    test "still requires core ticket fields", %{user: user} do
      cs = Ticket.door_sale_changeset(%Ticket{}, %{user_id: user.id})

      refute cs.valid?
      assert "can't be blank" in errors_on(cs).event_id
      assert "can't be blank" in errors_on(cs).ticket_tier_id
      assert "can't be blank" in errors_on(cs).expires_at
    end
  end

  describe "status_changeset/2" do
    test "allows status transitions" do
      cs = Ticket.status_changeset(%Ticket{}, %{status: :expired})
      assert cs.valid?
    end

    test "rejects invalid status" do
      cs = Ticket.status_changeset(%Ticket{}, %{status: :not_a_status})
      refute cs.valid?
    end
  end

  describe "check_in_changeset/2 and undo_check_in_changeset/1" do
    test "sets checked_in and timestamp once" do
      ticket = %Ticket{checked_in_at: nil}

      cs = Ticket.check_in_changeset(ticket, %{})
      assert Ecto.Changeset.get_field(cs, :checked_in) == true
      assert %DateTime{} = Ecto.Changeset.get_field(cs, :checked_in_at)

      cs2 = Ticket.check_in_changeset(Ecto.Changeset.apply_changes(cs), %{})

      assert Ecto.Changeset.get_field(cs2, :checked_in_at) ==
               Ecto.Changeset.get_field(cs, :checked_in_at)
    end

    test "undo_check_in clears flags" do
      at = DateTime.utc_now() |> DateTime.truncate(:second)

      ticket = %Ticket{checked_in: true, checked_in_at: at}

      cs = Ticket.undo_check_in_changeset(ticket)
      assert Ecto.Changeset.get_field(cs, :checked_in) == false
      assert Ecto.Changeset.get_field(cs, :checked_in_at) == nil
    end
  end

  describe "put_new_reference_id/1" do
    test "generates a new reference id" do
      cs =
        Ecto.Changeset.change(%Ticket{}, %{}) |> Ticket.put_new_reference_id()

      ref = Ecto.Changeset.get_field(cs, :reference_id)
      assert is_binary(ref)
      assert String.starts_with?(ref, "TKT")
    end
  end
end
