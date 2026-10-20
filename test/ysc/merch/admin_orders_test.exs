defmodule Ysc.Merch.AdminOrdersTest do
  use Ysc.DataCase, async: false

  import Mox
  import Swoosh.TestAssertions
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Ledgers.Payment
  alias Ysc.Merch.{AdminOrders, EventCosts, Order, Orders}
  alias Ysc.Printful.{ClientMock, Error}
  alias Ysc.Repo

  setup :verify_on_exit!

  setup do
    Application.put_env(:ysc, :printful_estimate_wait_ms, 0)
    on_exit(fn -> Application.delete_env(:ysc, :printful_estimate_wait_ms) end)

    admin =
      user_fixture(%{role: "admin", first_name: "Lars", last_name: "Nilsson"})

    %{admin: admin}
  end

  defp printful_accepts(total \\ "118.40") do
    stub(ClientMock, :get_order_by_external_id, fn _ ->
      {:error, %Error{type: :not_found, status: 404, message: "Not found"}}
    end)

    stub(ClientMock, :create_order, fn payload, true ->
      send(self(), {:printful_payload, payload})

      {:ok,
       %{
         "id" => 9001,
         "status" => "pending",
         "costs" => %{"total" => total}
       }}
    end)
  end

  defp params(attrs \\ %{}) do
    variant = variant_fixture(nil, %{retail_price: Money.new(:USD, "25")})

    Map.merge(
      %{
        address: shipping_address_fixture(%{"email" => "ada@example.com"}),
        lines: [%{variant: variant, quantity: 5}],
        option: shipping_option_fixture(),
        purpose: "Happy hour giveaway",
        estimated_cost: Money.new(:USD, "118.40")
      },
      attrs
    )
  end

  # `{:ok, {orders, meta}}` -> the orders' ids
  defp page_ids({:ok, {orders, _meta}}), do: Enum.map(orders, & &1.id)

  describe "paginate_orders/3" do
    test "shows club-paid orders and paid purchases, not abandoned checkouts",
         %{admin: admin} do
      member = member_fixture()
      comp = admin_order_fixture(admin)
      paid = purchase_order_fixture(member, :submitted)

      paid =
        paid
        |> Ecto.Changeset.change(payment_id: payment_fixture(member).id)
        |> Repo.update!()

      pending = purchase_order_fixture(member, :pending)

      ids = page_ids(AdminOrders.paginate_orders(:all, nil, %{}))

      assert comp.id in ids
      assert paid.id in ids
      refute pending.id in ids
    end

    test "filters", %{admin: admin} do
      member = member_fixture()
      comp = admin_order_fixture(admin)
      failed = admin_order_fixture(admin, %{status: :failed})

      purchase =
        member
        |> purchase_order_fixture(:submitted)
        |> Ecto.Changeset.change(payment_id: payment_fixture(member).id)
        |> Repo.update!()

      ids = fn filter -> page_ids(AdminOrders.paginate_orders(filter)) end

      assert ids.(:needs_attention) == [failed.id]
      assert Enum.sort(ids.(:club_paid)) == Enum.sort([comp.id, failed.id])
      assert ids.(:purchases) == [purchase.id]
      assert AdminOrders.needs_attention_count() == 1
    end

    test "pages are newest first, without gaps or repeats", %{admin: admin} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      orders =
        for n <- 1..5 do
          admin_order_fixture(admin, %{inserted_at: DateTime.add(now, -n * 60)})
        end

      expected = Enum.map(orders, & &1.id)

      {:ok, {first, meta}} =
        AdminOrders.paginate_orders(:all, nil, %{"page_size" => "2"})

      assert meta.total_count == 5
      assert meta.total_pages == 3
      assert meta.has_next_page?
      refute meta.has_previous_page?

      pages =
        for page <- 1..3 do
          page_ids(
            AdminOrders.paginate_orders(:all, nil, %{
              "page" => to_string(page),
              "page_size" => "2"
            })
          )
        end

      assert Enum.map(first, & &1.id) == hd(pages)
      assert List.flatten(pages) == expected
    end

    test "a page past the end is empty, not an error" do
      assert {:ok, {[], meta}} =
               AdminOrders.paginate_orders(:all, nil, %{"page" => "9"})

      assert meta.total_count == 0
    end

    test "junk paging params fall back to something sensible", %{admin: admin} do
      admin_order_fixture(admin)

      result =
        AdminOrders.paginate_orders(:all, nil, %{
          "page" => "banana",
          "page_size" => "-3"
        })

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "a huge page size is capped", %{admin: admin} do
      admin_order_fixture(admin)

      case AdminOrders.paginate_orders(:all, nil, %{"page_size" => "100000"}) do
        {:ok, {_orders, meta}} -> assert meta.page_size <= 100
        {:error, _meta} -> :ok
      end
    end

    test "omits member secrets, addresses, and unused associations", %{
      admin: admin
    } do
      member = member_fixture(%{first_name: "Astrid", last_name: "Lindgren"})

      member
      |> Ecto.Changeset.change(board_bio: "board bio the list must not load")
      |> Repo.update!()

      event = event_fixture()

      order =
        admin_order_fixture(admin, %{
          user_id: member.id,
          event_id: event.id,
          purpose: "Gala giveaway",
          address1: "1 Market St"
        })

      {{:ok, {orders, _meta}}, fat_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> AdminOrders.paginate_orders(:all, nil, %{}) end,
          pattern:
            ~r/hashed_password|board_bio|address1|payment_intent_id|printful_order_id|raw_details|rendered_details/i,
          caller_pids: [self()]
        )

      shown = Enum.find(orders, &(&1.id == order.id))
      assert shown
      assert shown.user.id == member.id
      assert shown.user.first_name == "Astrid"
      assert is_nil(shown.user.hashed_password)
      assert is_nil(shown.user.board_bio)
      assert is_nil(shown.address1)
      refute Ecto.assoc_loaded?(shown.granted_by)
      refute Ecto.assoc_loaded?(shown.event)
      assert shown.items != []
      assert fat_cols == 0
    end
  end

  describe "search" do
    setup %{admin: admin} do
      member = member_fixture(%{first_name: "Astrid", last_name: "Lindgren"})
      sticker = variant_fixture(nil, %{name: "Tomte Sticker"})
      tee = variant_fixture(nil, %{name: "Viking Tee / Black / M"})

      %{
        by_member:
          admin_order_fixture(admin, %{
            user_id: member.id,
            recipient_name: "Someone Else",
            purpose: "Midsummer table",
            items: [{tee, 1}]
          }),
        by_item:
          admin_order_fixture(admin, %{
            recipient_name: "Bar Staff",
            email: "bar@example.org",
            purpose: "Happy hour",
            items: [{sticker, 20}]
          }),
        member: member
      }
    end

    defp found(term), do: page_ids(AdminOrders.paginate_orders(:all, term, %{}))

    test "by order number", %{by_member: order, by_item: other} do
      assert found(order.reference_id) == [order.id]
      assert found(String.downcase(other.reference_id)) == [other.id]
    end

    test "by recipient name, email and purpose", %{by_item: order} do
      assert found("bar staff") == [order.id]
      assert found("bar@example") == [order.id]
      assert found("happy") == [order.id]
    end

    test "by the member's name or email", %{by_member: order, member: member} do
      assert found("astrid") == [order.id]
      assert found("Astrid Lindgren") == [order.id]
      assert found(member.email) == [order.id]
    end

    test "member search does not SELECT users.*", %{member: member} do
      {_ids, fat_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> found(member.email) end,
          pattern: ~r/hashed_password|board_bio/i,
          caller_pids: [self()]
        )

      assert fat_cols == 0
    end

    test "by item name", %{by_item: order, by_member: other} do
      assert found("sticker") == [order.id]
      assert found("viking") == [other.id]
    end

    test "nothing matches nothing" do
      assert found("zzz-nobody") == []
    end

    test "blank search is no search", %{by_item: a, by_member: b} do
      assert Enum.sort(found("")) == Enum.sort([a.id, b.id])
      assert Enum.sort(found(nil)) == Enum.sort([a.id, b.id])
      assert Enum.sort(found("   ")) == Enum.sort([a.id, b.id])
    end

    test "% and _ are searched for, not treated as patterns", %{by_item: order} do
      assert found("%") == []
      assert found("_") == []
      assert found("bar_staff") == []

      order |> Ecto.Changeset.change(purpose: "50% off_day") |> Repo.update!()
      assert found("50% off_day") == [order.id]
    end

    test "quotes and SQL are just text", %{} do
      assert found("'; DROP TABLE merch_orders; --") == []
      assert Repo.aggregate(Order, :count) == 2
    end

    test "works together with a filter and with paging", %{admin: admin} do
      for n <- 1..3, do: admin_order_fixture(admin, %{purpose: "Gala #{n}"})

      {:ok, {first, meta}} =
        AdminOrders.paginate_orders(:club_paid, "gala", %{"page_size" => "2"})

      assert length(first) == 2
      assert meta.total_count == 3

      assert {:ok, {[_], _}} =
               AdminOrders.paginate_orders(:club_paid, "gala", %{
                 "page" => "2",
                 "page_size" => "2"
               })

      assert [] == page_ids(AdminOrders.paginate_orders(:purchases, "gala"))
    end

    test "a member matching several ways is listed once", %{by_member: order} do
      # Name, email and purpose all contain "a"; the order must still appear once.
      ids = found("a")
      assert Enum.count(ids, &(&1 == order.id)) == 1
    end
  end

  describe "paginate_for_user/2" do
    test "returns what the member received, a page at a time", %{admin: admin} do
      member = member_fixture()

      mine =
        for _ <- 1..3, do: admin_order_fixture(admin, %{user_id: member.id})

      _someone_elses = admin_order_fixture(admin)

      assert {:ok, {first, meta}} =
               AdminOrders.paginate_for_user(member.id, %{"page_size" => "2"})

      assert length(first) == 2
      assert meta.total_count == 3
      assert Enum.all?(first, &(&1.id in Enum.map(mine, fn o -> o.id end)))
    end
  end

  describe "resolve_lines/1" do
    test "merges the same variant picked twice" do
      v = variant_fixture()

      assert {:ok, [%{quantity: 7, variant: %{id: id}}]} =
               AdminOrders.resolve_lines([
                 %{variant_id: v.id, quantity: 3},
                 %{variant_id: v.id, quantity: 4}
               ])

      assert id == v.id
    end

    test "rejects empty, bad quantities and unavailable variants" do
      v = variant_fixture()
      gone = variant_fixture(nil, %{available: false})

      assert {:error, :no_items} = AdminOrders.resolve_lines([])

      assert {:error, :no_items} =
               AdminOrders.resolve_lines([%{variant_id: "", quantity: 1}])

      assert {:error, :invalid_quantity} =
               AdminOrders.resolve_lines([%{variant_id: v.id, quantity: 0}])

      assert {:error, :invalid_quantity} =
               AdminOrders.resolve_lines([%{variant_id: v.id, quantity: 501}])

      assert {:error, :unavailable_variant} =
               AdminOrders.resolve_lines([%{variant_id: gone.id, quantity: 1}])
    end
  end

  describe "estimate_cost/3" do
    test "reads Printful's total and shipping" do
      expect(ClientMock, :estimate_costs, fn payload ->
        assert payload.shipping == "STANDARD"
        assert [%{quantity: 5}] = payload.items

        {:ok,
         %{
           "costs" => %{
             "calculation_status" => "done",
             "shipping" => "9.40",
             "total" => "118.40"
           }
         }}
      end)

      %{address: address, lines: lines} = params()

      assert {:ok, %{total: total, shipping: shipping}} =
               AdminOrders.estimate_cost(address, lines, "STANDARD")

      assert Money.equal?(total, Money.new(:USD, "118.40"))
      assert Money.equal?(shipping, Money.new(:USD, "9.40"))
    end

    test "reads the response Printful really sends: numbers, no calculation status" do
      # Captured from POST /orders/estimate-costs on the live API.
      expect(ClientMock, :estimate_costs, fn _ ->
        {:ok,
         %{
           "costs" => %{
             "currency" => "USD",
             "shipping" => 7.550000000000001,
             "subtotal" => 27.84,
             "tax" => 2.64,
             "total" => 38.03
           },
           "retail_costs" => %{"currency" => "USD", "total" => nil}
         }}
      end)

      %{address: address, lines: lines} = params()

      assert {:ok, %{total: total, shipping: shipping}} =
               AdminOrders.estimate_cost(address, lines, "STANDARD")

      assert Money.equal?(total, Money.new(:USD, "38.03"))
      assert Money.equal?(shipping, Money.new(:USD, "7.55"))
    end

    test "waits for Printful while it is still calculating" do
      calls = :counters.new(1, [])

      stub(ClientMock, :estimate_costs, fn _ ->
        :counters.add(calls, 1, 1)

        if :counters.get(calls, 1) < 3 do
          {:ok, %{"costs" => %{"calculation_status" => "calculating"}}}
        else
          {:ok,
           %{"costs" => %{"calculation_status" => "done", "total" => "20.00"}}}
        end
      end)

      %{address: address, lines: lines} = params()

      assert {:ok, %{total: total}} =
               AdminOrders.estimate_cost(address, lines, "STANDARD")

      assert Money.equal?(total, Money.new(:USD, "20.00"))
    end

    test "is unavailable when Printful fails or never finishes" do
      %{address: address, lines: lines} = params()

      stub(ClientMock, :estimate_costs, fn _ ->
        {:error, %Error{type: :server, status: 500, message: "boom"}}
      end)

      assert {:error, :unavailable} =
               AdminOrders.estimate_cost(address, lines, "STANDARD")

      stub(ClientMock, :estimate_costs, fn _ ->
        {:ok, %{"costs" => %{"calculation_status" => "calculating"}}}
      end)

      assert {:error, :unavailable} =
               AdminOrders.estimate_cost(address, lines, "STANDARD")
    end
  end

  describe "create_comp_order/2" do
    test "places a free order: $0, no payment, sent to Printful", %{
      admin: admin
    } do
      printful_accepts()
      member = member_fixture()
      event = event_fixture()

      assert {:ok, %Order{} = order} =
               AdminOrders.create_comp_order(
                 admin,
                 params(%{user_id: member.id, event_id: event.id})
               )

      assert order.kind == :admin_comp
      assert order.granted_by_id == admin.id
      assert order.user_id == member.id
      assert order.event_id == event.id
      assert order.purpose == "Happy hour giveaway"

      for field <- [:subtotal, :shipping_amount, :total_amount] do
        assert Money.zero?(Map.fetch!(order, field))
      end

      # The submit job runs inline in tests.
      assert order.status == :submitted
      assert order.printful_order_id == 9001
      assert Money.equal?(order.printful_cost, Money.new(:USD, "118.40"))
      assert Money.equal?(order.estimated_cost, Money.new(:USD, "118.40"))

      assert [%{quantity: 5}] = order.items
      assert Repo.aggregate(Payment, :count) == 0

      assert_received {:printful_payload, payload}
      assert payload.external_id == order.reference_id
    end

    test "the recipient is told, and the board hears who placed it", %{
      admin: admin
    } do
      printful_accepts()
      event = event_fixture()

      {:ok, order} =
        AdminOrders.create_comp_order(admin, params(%{event_id: event.id}))

      assert_email_sent(
        subject: "We've got your order (#{order.reference_id})",
        to: {nil, "ada@example.com"}
      )

      assert_email_sent(fn email ->
        assert email.subject =~ "Lars Nilsson placed a club-paid merch order"
        assert email.subject =~ order.reference_id
        assert {_, to} = List.first(email.to)
        assert to == Ysc.EmailConfig.board_email()
        assert email.html_body =~ "Happy hour giveaway"
        assert email.html_body =~ event.title
        assert email.html_body =~ "$118.40"
        assert email.html_body =~ admin.email
      end)
    end

    test "a custom address with no email gets no confirmation, the board still hears",
         %{admin: admin} do
      printful_accepts()

      address =
        shipping_address_fixture(%{"name" => "Bar Staff", "email" => ""})

      {:ok, order} =
        AdminOrders.create_comp_order(admin, params(%{address: address}))

      assert is_nil(order.user_id)

      assert_email_sent(subject: ~r/placed a club-paid merch order/)
      # Nothing else went out: no confirmation without an address to send it to.
      refute_email_sent()
    end

    test "the cost lands on the linked event's dashboard", %{admin: admin} do
      printful_accepts()
      event = event_fixture()

      {:ok, order} =
        AdminOrders.create_comp_order(admin, params(%{event_id: event.id}))

      assert [%{id: id}] = EventCosts.list_orders(event.id)
      assert id == order.id
    end

    test "keeps the delivery estimate of the shipping option", %{admin: admin} do
      printful_accepts()

      option =
        shipping_option_fixture(%{
          min_date: ~D[2026-10-26],
          max_date: ~D[2026-10-29]
        })

      {:ok, order} =
        AdminOrders.create_comp_order(admin, params(%{option: option}))

      assert order.delivery_estimate_min == ~D[2026-10-26]
      assert order.delivery_estimate_max == ~D[2026-10-29]
    end

    test "only full admins can place orders" do
      volunteer = user_fixture(%{role: "volunteer"})
      member = member_fixture()

      for user <- [volunteer, member] do
        assert {:error, :not_authorized} =
                 AdminOrders.create_comp_order(user, params())
      end

      assert Repo.aggregate(Order, :count) == 0
    end

    test "needs a purpose and items", %{admin: admin} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               AdminOrders.create_comp_order(admin, params(%{purpose: ""}))

      assert %{purpose: [_]} = errors_on(changeset)

      assert {:error, :no_items} =
               AdminOrders.create_comp_order(admin, params(%{lines: []}))

      # A failed order leaves nothing behind.
      assert Repo.aggregate(Order, :count) == 0
    end

    test "a Printful rejection leaves a failed order for the board", %{
      admin: admin
    } do
      stub(ClientMock, :get_order_by_external_id, fn _ ->
        {:error, %Error{type: :not_found, status: 404, message: "Not found"}}
      end)

      stub(ClientMock, :create_order, fn _, true ->
        {:error, %Error{type: :invalid, status: 400, message: "Bad address"}}
      end)

      {:ok, order} = AdminOrders.create_comp_order(admin, params())
      assert Orders.get_order!(order.id).status == :failed

      assert Enum.any?(
               sent_subjects(),
               &String.contains?(&1, "Merch order needs attention")
             )
    end
  end

  describe "retry_submission/1" do
    test "sends a failed order again", %{admin: admin} do
      printful_accepts()
      order = admin_order_fixture(admin, %{status: :failed})

      assert :ok = AdminOrders.retry_submission(Orders.get_order!(order.id))
      assert Orders.get_order!(order.id).status == :submitted
    end

    test "only failed orders, and only once", %{admin: admin} do
      printful_accepts()
      order = admin_order_fixture(admin, %{status: :failed})

      assert :ok = AdminOrders.retry_submission(Orders.get_order!(order.id))

      assert {:error, :not_failed} =
               AdminOrders.retry_submission(Orders.get_order!(order.id))

      shipped = admin_order_fixture(admin, %{status: :shipped})
      assert {:error, :not_failed} = AdminOrders.retry_submission(shipped)
    end

    test "never if Printful already has it", %{admin: admin} do
      order =
        admin_order_fixture(admin, %{status: :failed, printful_order_id: 77})

      assert {:error, :already_submitted} = AdminOrders.retry_submission(order)
    end

    test "never for a purchase that was refunded" do
      member = member_fixture()
      payment = payment_fixture(member)

      order =
        member
        |> purchase_order_fixture(:failed)
        |> Ecto.Changeset.change(payment_id: payment.id, printful_order_id: nil)
        |> Repo.update!()

      {:ok, _} =
        Ysc.Ledgers.create_refund(%{
          payment_id: payment.id,
          user_id: member.id,
          amount: payment.amount,
          external_provider: :stripe,
          external_refund_id: "re_test_#{System.unique_integer([:positive])}",
          reason: "requested",
          status: :completed
        })

      assert {:error, :refunded} = AdminOrders.retry_submission(order)
      assert Orders.get_order!(order.id).status == :failed
    end
  end

  defp sent_subjects do
    receive do
      {:email, email} -> [email.subject | sent_subjects()]
    after
      0 -> []
    end
  end

  # A recorded member payment, enough to make a purchase visible to admins.
  defp payment_fixture(user) do
    Ysc.Ledgers.ensure_basic_accounts()

    {:ok, {payment, _, _}} =
      Ysc.Ledgers.process_payment(%{
        user_id: user.id,
        amount: Money.new(:USD, "55.95"),
        entity_type: :merch,
        entity_id: nil,
        external_payment_id:
          "pi_admin_orders_#{System.unique_integer([:positive])}",
        stripe_fee: Money.new(:USD, "1.92"),
        description: "Merch",
        property: nil,
        payment_method_id: nil
      })

    payment
  end
end
