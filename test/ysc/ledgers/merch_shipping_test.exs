defmodule Ysc.Ledgers.MerchShippingTest do
  # Mutates the QuickBooks client in global app env. Claim Mox shared mode
  # before DataCase default stubs so the next test is not blocked by a leftover
  # global owner (`setup :set_mox_global` runs too late and never resets).
  use Ysc.DataCase, async: false, mox_global_first: true

  import Ecto.Query
  import Mox
  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures, only: [stub_quickbooks_sync!: 0]

  alias Ysc.Ledgers
  alias Ysc.Ledgers.LedgerEntry
  alias Ysc.Quickbooks.ClientMock

  setup do
    original = Application.get_env(:ysc, :quickbooks_client)
    Application.put_env(:ysc, :quickbooks_client, ClientMock)
    on_exit(fn -> Application.put_env(:ysc, :quickbooks_client, original) end)

    stub_quickbooks_sync!()
    Ledgers.ensure_basic_accounts()
    test_pid = self()

    # Two items so a receipt line can be traced to the product it is sold as.
    stub(ClientMock, :get_or_create_item, fn name, _opts ->
      {:ok, "item:#{name}"}
    end)

    stub(ClientMock, :create_sales_receipt, fn params, _opts ->
      send(test_pid, {:sales_receipt, params})
      {:ok, %{"Id" => "qb_sr", "TotalAmt" => "0.00"}}
    end)

    stub(ClientMock, :create_refund_receipt, fn params, _opts ->
      send(test_pid, {:refund_receipt, params})
      {:ok, %{"Id" => "qb_rr", "TotalAmt" => "0.00"}}
    end)

    %{user: user_fixture()}
  end

  defp pay(user, total, shipping) do
    attrs = %{
      user_id: user.id,
      amount: Money.new(:USD, total),
      entity_type: :merch,
      entity_id: Ecto.ULID.generate(),
      external_payment_id: "pi_ship_#{System.unique_integer([:positive])}",
      stripe_fee: Money.new(:USD, "1.50"),
      description: "Merch - Order MRC-TEST",
      property: nil,
      payment_method_id: nil
    }

    attrs =
      if shipping,
        do: Map.put(attrs, :shipping_amount, Money.new(:USD, shipping)),
        else: attrs

    {:ok, {payment, _transaction, _entries}} = Ledgers.process_payment(attrs)
    payment
  end

  defp entries(payment, account, debit_credit) do
    from(e in LedgerEntry,
      join: a in assoc(e, :account),
      where: e.payment_id == ^payment.id and a.name == ^account,
      where: e.debit_credit == ^debit_credit,
      select: e.amount
    )
    |> Repo.all()
  end

  defp dollars(money), do: money |> Money.to_decimal() |> Decimal.to_string()

  defp lines(%{line: lines}) do
    for l <- lines,
        do:
          {l.sales_item_line_detail.item_ref.value, Decimal.to_string(l.amount)}
  end

  describe "recording a payment" do
    test "books shipping to its own revenue account", %{user: user} do
      payment = pay(user, "30.00", "5.00")

      assert [sales] = entries(payment, "merch_revenue", "credit")
      assert [shipping] = entries(payment, "merch_shipping_revenue", "credit")
      assert dollars(sales) == "25.00"
      assert dollars(shipping) == "5.00"

      # Still balanced: the receivable is the whole payment.
      assert [receivable] = entries(payment, "stripe_account", "debit")
      assert dollars(receivable) == "30.00"
    end

    test "without shipping it is all merch sales", %{user: user} do
      payment = pay(user, "30.00", nil)

      assert [sales] = entries(payment, "merch_revenue", "credit")
      assert dollars(sales) == "30.00"
      assert entries(payment, "merch_shipping_revenue", "credit") == []
    end

    test "free shipping and shipping-only amounts are not split", %{user: user} do
      zero = pay(user, "30.00", "0.00")
      assert entries(zero, "merch_shipping_revenue", "credit") == []

      whole = pay(user, "30.00", "30.00")
      assert [sales] = entries(whole, "merch_revenue", "credit")
      assert dollars(sales) == "30.00"
      assert entries(whole, "merch_shipping_revenue", "credit") == []
    end

    test "shipping is not split for other kinds of payment", %{user: user} do
      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(:USD, "30.00"),
          entity_type: :donation,
          entity_id: Ecto.ULID.generate(),
          external_payment_id:
            "pi_ship_don_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(:USD, "1.50"),
          description: "Donation",
          property: nil,
          payment_method_id: nil,
          shipping_amount: Money.new(:USD, "5.00")
        })

      assert entries(payment, "merch_shipping_revenue", "credit") == []
    end
  end

  describe "QuickBooks sales receipt" do
    test "has a line for the items and a line for shipping", %{user: user} do
      pay(user, "30.00", "5.00")

      assert_received {:sales_receipt, params}

      assert lines(params) == [
               {"item:Merch Sales", "25.00"},
               {"item:Merch Shipping", "5.00"}
             ]

      assert Decimal.to_string(params.total_amt) == "30.00"
    end

    test "is a single line when there was no shipping", %{user: user} do
      pay(user, "30.00", nil)

      assert_received {:sales_receipt, params}
      assert [{"item:Merch Sales", "30.00"}] = lines(params)
    end

    test "puts shipping on the first income account that exists", %{user: user} do
      test_pid = self()

      # No "Merch Shipping Income" yet, but a general "Shipping Income" exists.
      stub(ClientMock, :query_account_by_name, fn
        "Merch Shipping Income" -> {:error, :not_found}
        "Shipping Income" -> {:ok, "acct:shipping"}
        name -> {:ok, "acct:#{name}"}
      end)

      stub(ClientMock, :get_or_create_item, fn name, opts ->
        send(test_pid, {:item, name, opts[:income_account_ref]})
        {:ok, "item:#{name}"}
      end)

      pay(user, "30.00", "5.00")

      assert_received {:item, "Merch Shipping", %{value: "acct:shipping"}}
    end

    test "uses a pinned shipping item when one is configured", %{user: user} do
      original = Application.get_env(:ysc, :quickbooks)

      Application.put_env(
        :ysc,
        :quickbooks,
        Keyword.put(original || [], :merch_shipping_item_id, "pinned_ship")
      )

      on_exit(fn -> Application.put_env(:ysc, :quickbooks, original) end)

      pay(user, "30.00", "5.00")

      assert_received {:sales_receipt, params}
      assert {"pinned_ship", "5.00"} in lines(params)
    end
  end

  describe "refunds" do
    defp refund(payment, amount) do
      {:ok, {_refund, _txn, _entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(:USD, amount),
          reason: "test",
          external_refund_id: "re_#{System.unique_integer([:positive])}"
        })
    end

    defp refund_debits(payment, account) do
      from(e in LedgerEntry,
        join: a in assoc(e, :account),
        where: e.payment_id == ^payment.id and a.name == ^account,
        where: e.debit_credit == "debit" and not is_nil(e.refund_id),
        select: e.amount
      )
      |> Repo.all()
      |> Enum.map(&dollars/1)
    end

    test "a full refund reverses both parts exactly", %{user: user} do
      payment = pay(user, "30.00", "5.00")
      refund(payment, "30.00")

      assert refund_debits(payment, "merch_revenue") == ["25.00"]
      assert refund_debits(payment, "merch_shipping_revenue") == ["5.00"]
    end

    test "a partial refund is shared in proportion", %{user: user} do
      payment = pay(user, "30.00", "5.00")
      refund(payment, "10.00")

      # 25/30 of 10.00 is 8.33; shipping takes the remaining 1.67.
      assert refund_debits(payment, "merch_revenue") == ["8.33"]
      assert refund_debits(payment, "merch_shipping_revenue") == ["1.67"]

      # The credit to Stripe is the whole refund.
      credits =
        from(e in LedgerEntry,
          join: a in assoc(e, :account),
          where: e.payment_id == ^payment.id and a.name == "stripe_account",
          where: e.debit_credit == "credit" and not is_nil(e.refund_id),
          select: e.amount
        )
        |> Repo.all()
        |> Enum.map(&dollars/1)

      assert credits == ["10.00"]
    end

    test "a payment booked before shipping was split refunds as it always did",
         %{user: user} do
      payment = pay(user, "30.00", nil)
      refund(payment, "10.00")

      assert refund_debits(payment, "merch_revenue") == ["10.00"]
      assert refund_debits(payment, "merch_shipping_revenue") == []
    end

    test "the QuickBooks refund receipt gives shipping back on its own line", %{
      user: user
    } do
      payment = pay(user, "30.00", "5.00")
      flush_mailbox()
      refund(payment, "10.00")

      assert_received {:refund_receipt, params}

      assert lines(params) == [
               {"item:Merch Sales", "8.33"},
               {"item:Merch Shipping", "1.67"}
             ]

      assert Decimal.to_string(params.total_amt) == "10.00"
    end

    test "a refund with no shipping part is a single line", %{user: user} do
      payment = pay(user, "30.00", nil)
      flush_mailbox()
      refund(payment, "10.00")

      assert_received {:refund_receipt, params}
      assert [{"item:Merch Sales", "10.00"}] = lines(params)
    end

    defp flush_mailbox do
      receive do
        {:sales_receipt, _} -> flush_mailbox()
      after
        0 -> :ok
      end
    end
  end
end
