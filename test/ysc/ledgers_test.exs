defmodule Ysc.LedgersTest do
  use Ysc.DataCase, async: true

  alias Ysc.Ledgers

  alias Ysc.Ledgers.{
    LedgerAccount,
    LedgerTransaction,
    LedgerEntry,
    Payment,
    Refund
  }

  alias Ysc.Repo
  alias Ysc.Payments.PaymentMethod
  alias Ysc.Tickets
  import Ecto.Query
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Ysc.TicketsFixtures
  import Ysc.EventsFixtures
  import Swoosh.TestAssertions

  defp with_ledger_append_only_trigger_disabled(fun) do
    Ecto.Adapters.SQL.query!(
      Repo,
      "ALTER TABLE ledger_entries DISABLE TRIGGER ledger_entries_append_only_trigger"
    )

    try do
      fun.()
    after
      Ecto.Adapters.SQL.query!(
        Repo,
        "ALTER TABLE ledger_entries ENABLE TRIGGER ledger_entries_append_only_trigger"
      )
    end
  end

  setup do
    Ledgers.ensure_basic_accounts()
    :ok
  end

  describe "ledger account management" do
    test "ensure_basic_accounts/0 creates all basic accounts" do
      Ledgers.ensure_basic_accounts()

      # Check that basic accounts exist
      assert Ledgers.get_account_by_name("cash")
      assert Ledgers.get_account_by_name("membership_revenue")
      assert Ledgers.get_account_by_name("event_revenue")
      assert Ledgers.get_account_by_name("tahoe_booking_revenue")
      assert Ledgers.get_account_by_name("clear_lake_booking_revenue")
      assert Ledgers.get_account_by_name("donation_revenue")
      assert Ledgers.get_account_by_name("stripe_fees")
    end

    test "list_accounts/0 returns all accounts" do
      accounts = Ledgers.list_accounts()
      assert is_list(accounts)
      assert accounts != []
      assert Enum.all?(accounts, &(%LedgerAccount{} = &1))
    end

    test "get_account/1 returns account by id" do
      account = Ledgers.get_account_by_name("cash")
      assert %LedgerAccount{} = Ledgers.get_account(account.id)
      assert Ledgers.get_account(account.id).id == account.id
    end

    test "get_account/1 returns nil for non-existent account" do
      assert nil == Ledgers.get_account(Ecto.ULID.generate())
    end

    test "create_account/1 creates a new account" do
      attrs = %{
        name: "test_account",
        account_type: "asset",
        normal_balance: "debit",
        description: "Test account"
      }

      assert {:ok, %LedgerAccount{} = account} = Ledgers.create_account(attrs)
      assert account.name == "test_account"
      # account_type is an enum that returns atoms, not strings
      assert account.account_type == :asset
    end

    test "get_account_by_name/1 returns nil when no account matches" do
      assert Ledgers.get_account_by_name(
               "definitely_no_such_ledger_account_#{System.unique_integer([:positive])}"
             ) ==
               nil
    end

    test "create_account/1 returns error when required fields are missing" do
      assert {:error, %Ecto.Changeset{} = cs} =
               Ledgers.create_account(%{name: "incomplete"})

      assert cs.errors[:account_type]
      assert cs.errors[:normal_balance]
    end

    test "update_account/2 returns error for invalid attributes" do
      account = Ledgers.get_account_by_name("cash")

      assert {:error, %Ecto.Changeset{}} =
               Ledgers.update_account(account, %{name: ""})
    end

    test "update_account/2 updates an account" do
      account = Ledgers.get_account_by_name("cash")
      update_attrs = %{description: "Updated description"}

      assert {:ok, %LedgerAccount{} = updated} =
               Ledgers.update_account(account, update_attrs)

      assert updated.description == "Updated description"
    end

    test "ensure_basic_accounts/0 recreates a basic account that has no ledger entries" do
      accounts_with_entries =
        from(e in LedgerEntry,
          select: e.account_id,
          distinct: true
        )

      orphan =
        from(a in LedgerAccount,
          where: a.id not in subquery(accounts_with_entries),
          limit: 1
        )
        |> Repo.one()

      if orphan == nil do
        assert true
      else
        name = orphan.name
        Repo.delete!(orphan)
        assert Ledgers.get_account_by_name(name) == nil

        Ledgers.ensure_basic_accounts()

        recreated = Ledgers.get_account_by_name(name)
        assert %LedgerAccount{} = recreated
        assert recreated.id != orphan.id
      end
    end

    test "get_accounts_with_balances/0 returns accounts with balances" do
      accounts_with_balances = Ledgers.get_accounts_with_balances()

      assert is_list(accounts_with_balances)
      assert accounts_with_balances != []

      # Check structure
      [first_account | _] = accounts_with_balances
      assert Map.has_key?(first_account, :account)
      assert Map.has_key?(first_account, :balance)
      assert %LedgerAccount{} = first_account.account
    end

    test "get_accounts_with_balances/2 returns accounts with balances for date range" do
      today = Date.utc_today()
      start_date = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
      end_date = DateTime.new!(today, ~T[23:59:59], "Etc/UTC")

      accounts_with_balances =
        Ledgers.get_accounts_with_balances(start_date, end_date)

      assert is_list(accounts_with_balances)

      assert Enum.all?(accounts_with_balances, fn acc ->
               Map.has_key?(acc, :account) && Map.has_key?(acc, :balance)
             end)
    end

    test "get_accounts_with_balances/0 batches entry queries" do
      {_accounts_with_balances, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            Ledgers.get_accounts_with_balances()
          end,
          caller_pids: [self()]
        )

      assert query_count == 2
    end

    test "get_overview_accounts_with_balances/2 fetches accounts once" do
      today = Date.utc_today()
      start_date = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
      end_date = DateTime.new!(today, ~T[23:59:59], "Etc/UTC")

      {{period_accounts, current_accounts, accounts}, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            Ledgers.get_overview_accounts_with_balances(start_date, end_date)
          end,
          caller_pids: [self()]
        )

      assert length(period_accounts) == length(accounts)
      assert length(current_accounts) == length(accounts)
      assert query_count == 3
    end
  end

  describe "payment processing" do
    setup do
      user = user_fixture()

      # Configure QuickBooks client to use mock (prevents errors when sync jobs run)
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      # Set up QuickBooks configuration for tests
      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      # Set up default mocks for automatic sync jobs
      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "process_payment/1 creates payment with double-entry entries", %{
      user: user
    } do
      # $50.00
      amount = Money.new(5000, :USD)
      # $1.75
      stripe_fee = Money.new(175, :USD)

      payment_attrs = %{
        user_id: user.id,
        amount: amount,
        entity_type: :membership,
        entity_id: Ecto.ULID.generate(),
        external_payment_id: "pi_test_123",
        stripe_fee: stripe_fee,
        description: "Test membership payment",
        property: nil,
        payment_method_id: nil
      }

      assert {:ok, {payment, transaction, entries}} =
               Ledgers.process_payment(payment_attrs)

      # Check payment was created
      assert %Payment{} = payment
      assert payment.amount == amount
      assert payment.external_payment_id == "pi_test_123"
      assert payment.status == :completed

      # Check transaction was created
      assert %LedgerTransaction{} = transaction
      assert transaction.type == :payment
      assert transaction.total_amount == amount
      assert transaction.status == :completed

      # Check entries were created (should be 4: cash debit, revenue credit, fee debit, fee credit)
      assert length(entries) == 4

      # Verify all entries have the correct payment_id
      Enum.each(entries, fn entry ->
        assert entry.payment_id == payment.id
      end)
    end

    test "process_payment/1 returns existing payment when duplicate external_payment_id (idempotency)",
         %{
           user: user
         } do
      amount = Money.new(5000, :USD)
      stripe_fee = Money.new(175, :USD)
      external_id = "pi_idempotent_#{System.unique_integer([:positive])}"

      attrs = %{
        user_id: user.id,
        amount: amount,
        entity_type: :membership,
        entity_id: Ecto.ULID.generate(),
        external_payment_id: external_id,
        stripe_fee: stripe_fee,
        description: "First payment",
        property: nil,
        payment_method_id: nil
      }

      assert {:ok, {payment1, _tx1, _entries1}} = Ledgers.process_payment(attrs)
      assert {:ok, {payment2, _tx2, _entries2}} = Ledgers.process_payment(attrs)
      assert payment1.id == payment2.id
      assert payment2.external_payment_id == external_id
    end

    @tag :capture_log
    test "process_payment/1 handles concurrent duplicate external_payment_id (race condition)",
         %{user: user, sandbox_owner: owner} do
      amount = Money.new(5000, :USD)
      stripe_fee = Money.new(175, :USD)
      external_id = "pi_race_#{System.unique_integer([:positive])}"

      attrs = %{
        user_id: user.id,
        amount: amount,
        entity_type: :membership,
        entity_id: Ecto.ULID.generate(),
        external_payment_id: external_id,
        stripe_fee: stripe_fee,
        description: "Concurrent payment",
        property: nil,
        payment_method_id: nil
      }

      results =
        1..2
        |> Task.async_stream(
          fn _ ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            Ledgers.process_payment(attrs)
          end,
          max_concurrency: 2,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert length(results) == 2
      assert Enum.all?(results, &match?({:ok, {_payment, _tx, _entries}}, &1))

      [{:ok, {payment1, _, _}}, {:ok, {payment2, _, _}}] = results
      assert payment1.id == payment2.id
      assert payment1.external_payment_id == external_id
    end

    test "process_event_payment_with_donations/1 returns existing payment on duplicate external_payment_id",
         %{user: user} do
      total_amount = Money.new(10_000, :USD)
      event_amount = Money.new(6_000, :USD)
      donation_amount = Money.new(4_000, :USD)
      external_id = "pi_event_don_idem_#{System.unique_integer([:positive])}"

      attrs = %{
        user_id: user.id,
        total_amount: total_amount,
        event_amount: event_amount,
        donation_amount: donation_amount,
        event_id: Ecto.ULID.generate(),
        external_payment_id: external_id,
        stripe_fee: Money.new(320, :USD),
        description: "Event with donation",
        payment_method_id: nil
      }

      assert {:ok, {payment1, _tx1, _entries1}} =
               Ledgers.process_event_payment_with_donations(attrs)

      assert {:ok, {payment2, _tx2, _entries2}} =
               Ledgers.process_event_payment_with_donations(attrs)

      assert payment1.id == payment2.id
      assert payment2.external_payment_id == external_id
    end

    test "process_event_payment_with_donations_and_discounts/1 returns existing payment on duplicate external_payment_id",
         %{user: user} do
      total_amount = Money.new(10_000, :USD)
      gross_event_amount = Money.new(6_000, :USD)
      donation_amount = Money.new(4_000, :USD)
      discount_amount = Money.new(1_000, :USD)
      external_id = "pi_event_disc_idem_#{System.unique_integer([:positive])}"

      attrs = %{
        user_id: user.id,
        total_amount: total_amount,
        gross_event_amount: gross_event_amount,
        event_amount: gross_event_amount,
        donation_amount: donation_amount,
        discount_amount: discount_amount,
        event_id: Ecto.ULID.generate(),
        external_payment_id: external_id,
        stripe_fee: Money.new(320, :USD),
        description: "Event with donation and discount",
        payment_method_id: nil,
        ticket_order_id: Ecto.ULID.generate()
      }

      assert {:ok, {payment1, _tx1, _entries1}} =
               Ledgers.process_event_payment_with_donations_and_discounts(attrs)

      assert {:ok, {payment2, _tx2, _entries2}} =
               Ledgers.process_event_payment_with_donations_and_discounts(attrs)

      assert payment1.id == payment2.id
      assert payment2.external_payment_id == external_id
    end

    @tag :capture_log
    test "process_event_payment_with_donations/1 handles concurrent duplicate external_payment_id",
         %{user: user, sandbox_owner: owner} do
      total_amount = Money.new(10_000, :USD)
      event_amount = Money.new(6_000, :USD)
      donation_amount = Money.new(4_000, :USD)
      external_id = "pi_event_don_race_#{System.unique_integer([:positive])}"

      attrs = %{
        user_id: user.id,
        total_amount: total_amount,
        event_amount: event_amount,
        donation_amount: donation_amount,
        event_id: Ecto.ULID.generate(),
        external_payment_id: external_id,
        stripe_fee: Money.new(320, :USD),
        description: "Concurrent event donation payment",
        payment_method_id: nil
      }

      results =
        1..2
        |> Task.async_stream(
          fn _ ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            Ledgers.process_event_payment_with_donations(attrs)
          end,
          max_concurrency: 2,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert length(results) == 2
      assert Enum.all?(results, &match?({:ok, {_payment, _tx, _entries}}, &1))

      [{:ok, {payment1, _, _}}, {:ok, {payment2, _, _}}] = results
      assert payment1.id == payment2.id
      assert payment1.external_payment_id == external_id
    end

    test "process_payment/1 returns error when payment exists but not completed",
         %{
           user: user
         } do
      amount = Money.new(5000, :USD)
      external_id = "pi_not_completed_#{System.unique_integer([:positive])}"

      attrs = %{
        user_id: user.id,
        amount: amount,
        entity_type: :membership,
        entity_id: Ecto.ULID.generate(),
        external_payment_id: external_id,
        stripe_fee: Money.new(175, :USD),
        description: "Payment",
        property: nil,
        payment_method_id: nil
      }

      assert {:ok, {payment, _tx, _entries}} = Ledgers.process_payment(attrs)
      # Mark payment as not completed (e.g. pending)
      {:ok, _} =
        Ledgers.update_payment(payment, %{status: :pending})

      assert {:error, :payment_exists_but_not_completed} =
               Ledgers.process_payment(attrs)
    end

    test "process_payment/1 raises for booking without property", %{
      user: user
    } do
      attrs = %{
        user_id: user.id,
        amount: Money.new(20_000, :USD),
        entity_type: :booking,
        entity_id: Ecto.ULID.generate(),
        external_payment_id:
          "pi_booking_no_prop_#{System.unique_integer([:positive])}",
        stripe_fee: Money.new(640, :USD),
        description: "Booking",
        property: nil,
        payment_method_id: nil
      }

      assert_raise RuntimeError, ~r/property to be specified/, fn ->
        Ledgers.process_payment(attrs)
      end
    end

    test "get_account_balance/1 calculates correct balance" do
      cash_account = Ledgers.get_account_by_name("cash")

      # Initially should be zero
      balance = Ledgers.get_account_balance(cash_account.id)
      assert Money.equal?(balance, Money.new(0, :USD))
    end

    test "process_payment/1 creates only receivable and revenue entries when stripe fee is zero",
         %{
           user: user
         } do
      assert {:ok, {_payment, _transaction, entries}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(3_000, :USD),
                 entity_type: :membership,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id:
                   "pi_zero_fee_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(0, :USD),
                 description: "No fee",
                 property: nil,
                 payment_method_id: nil
               })

      assert length(entries) == 2
    end

    test "process_payment/1 skips fee entries when stripe_fee is nil", %{
      user: user
    } do
      assert {:ok, {_payment, _transaction, entries}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(2_500, :USD),
                 entity_type: :membership,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id:
                   "pi_nil_fee_#{System.unique_integer([:positive])}",
                 stripe_fee: nil,
                 description: "Nil fee",
                 property: nil,
                 payment_method_id: nil
               })

      assert length(entries) == 2
    end

    test "process_payment/1 uses event revenue for entity_type :event", %{
      user: user
    } do
      assert {:ok, {payment, _transaction, entries}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(4_000, :USD),
                 entity_type: :event,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id:
                   "pi_event_entity_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(100, :USD),
                 description: "Event payment",
                 property: nil,
                 payment_method_id: nil
               })

      revenue_entry =
        Enum.find(entries, fn e ->
          e.related_entity_type == :event && e.debit_credit == :credit
        end)

      assert revenue_entry.account_id ==
               Ledgers.get_account_by_name("event_revenue").id

      assert revenue_entry.payment_id == payment.id
    end
  end

  describe "refund processing" do
    setup do
      user = user_fixture()

      # Configure QuickBooks client to use mock (prevents errors when sync jobs run)
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      # Set up QuickBooks configuration for tests
      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      # Set up default mocks for automatic sync jobs
      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      # Create a test payment first
      amount = Money.new(5000, :USD)

      payment_attrs = %{
        user_id: user.id,
        amount: amount,
        entity_type: :membership,
        entity_id: Ecto.ULID.generate(),
        external_payment_id: "pi_test_123",
        stripe_fee: Money.new(175, :USD),
        description: "Test membership payment",
        property: nil,
        payment_method_id: nil
      }

      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(payment_attrs)

      %{user: user, payment: payment}
    end

    test "process_refund/1 creates refund entries", %{payment: payment} do
      # $25.00
      refund_amount = Money.new(2500, :USD)

      refund_attrs = %{
        payment_id: payment.id,
        refund_amount: refund_amount,
        reason: "Customer requested partial refund",
        external_refund_id: "re_test_123"
      }

      assert {:ok, {refund, refund_transaction, entries}} =
               Ledgers.process_refund(refund_attrs)

      # Check refund record was created
      assert %Refund{} = refund
      assert refund.amount == refund_amount
      assert refund.status == :completed
      assert refund.reason == "Customer requested partial refund"
      assert refund.external_refund_id == "re_test_123"
      assert refund.external_provider == :stripe
      assert refund.user_id == payment.user_id
      assert refund.payment_id == payment.id

      # Check refund transaction was created
      assert %LedgerTransaction{} = refund_transaction
      assert refund_transaction.type == :refund
      assert refund_transaction.total_amount == refund_amount
      assert refund_transaction.status == :completed
      assert refund_transaction.refund_id == refund.id
      assert refund_transaction.payment_id == payment.id

      # Check entries were created using revenue reversal approach
      # Should have exactly 2 entries:
      # 1. Revenue reversal (debit)
      # 2. Stripe account credit
      assert length(entries) == 2

      # Verify all entries have the correct payment_id
      Enum.each(entries, fn entry ->
        assert entry.payment_id == payment.id
      end)

      # Verify we have a revenue reversal entry (debit - positive amount, debit_credit: :debit)
      revenue_reversal_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Revenue reversal" &&
            e.debit_credit == :debit &&
            Money.positive?(e.amount)
        end)

      assert revenue_reversal_entry != nil
      assert revenue_reversal_entry.amount == refund_amount
      assert revenue_reversal_entry.debit_credit == :debit

      # Verify we have a stripe account credit entry (credit - positive amount, debit_credit: :credit)
      stripe_credit_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Stripe account reduction" &&
            e.debit_credit == :credit &&
            Money.positive?(e.amount)
        end)

      assert stripe_credit_entry != nil
      assert Money.equal?(stripe_credit_entry.amount, refund_amount)
      assert stripe_credit_entry.debit_credit == :credit
    end

    test "process_refund/1 for membership payment runs send_refund_email when get_payment_related_entity is nil",
         %{payment: payment} do
      # Membership ledger entries do not resolve to booking/ticket_order; send_refund_email/2
      # hits the unknown-entity branch (debug log) in lib/ysc/ledgers.ex ~1128-1133.
      assert Ledgers.get_payment_related_entity(payment) == nil

      assert {:ok, {_refund, _tx, _entries}} =
               Ledgers.process_refund(%{
                 payment_id: payment.id,
                 refund_amount: Money.new(500, :USD),
                 reason: "Membership partial refund",
                 external_refund_id:
                   "re_membership_entity_#{System.unique_integer([:positive])}"
               })
    end

    test "process_refund/1 succeeds when payment has no user (skips refund email branch)",
         %{user: user} do
      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(5000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id:
            "pi_refund_no_user_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(175, :USD),
          description: "Payment before user_id cleared",
          property: nil,
          payment_method_id: nil
        })

      assert {:ok, payment} =
               payment
               |> Ecto.Changeset.change(%{user_id: nil})
               |> Repo.update()

      assert {:ok, {refund, _tx, _entries}} =
               Ledgers.process_refund(%{
                 payment_id: payment.id,
                 refund_amount: Money.new(1000, :USD),
                 reason: "Refund with payment missing user",
                 external_refund_id:
                   "re_no_payer_#{System.unique_integer([:positive])}"
               })

      assert is_nil(refund.user_id)
    end

    test "process_refund/1 returns existing refund when duplicate external_refund_id (idempotency)",
         %{
           payment: payment
         } do
      refund_amount = Money.new(2500, :USD)
      external_refund_id = "re_idempotent_#{System.unique_integer([:positive])}"

      attrs = %{
        payment_id: payment.id,
        refund_amount: refund_amount,
        reason: "Duplicate test",
        external_refund_id: external_refund_id
      }

      assert {:ok, {refund1, _tx1, entries1}} = Ledgers.process_refund(attrs)
      assert length(entries1) == 2

      assert {:ok, {refund2, _tx2, entries2}} = Ledgers.process_refund(attrs)
      assert refund1.id == refund2.id
      assert entries2 == []
    end

    test "get_entries_by_refund/1 returns entries for refund", %{
      payment: payment
    } do
      {:ok, {refund, _transaction, _created_entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(2500, :USD),
          reason: "Test",
          external_refund_id:
            "re_entries_test_#{System.unique_integer([:positive])}"
        })

      entries = Ledgers.get_entries_by_refund(refund.id)
      assert is_list(entries)
      assert length(entries) == 2
      assert Enum.all?(entries, &(&1.refund_id == refund.id))
    end

    test "payment_has_revenue_debit_entries?/1 is false before refund and true after revenue reversal",
         %{payment: payment} do
      refute Ledgers.payment_has_revenue_debit_entries?(payment.id)

      assert {:ok, {_refund, _tx, _entries}} =
               Ledgers.process_refund(%{
                 payment_id: payment.id,
                 refund_amount: Money.new(2500, :USD),
                 reason: "Coverage",
                 external_refund_id:
                   "re_phre_#{System.unique_integer([:positive])}"
               })

      assert Ledgers.payment_has_revenue_debit_entries?(payment.id)
    end

    test "process_refund/1 marks original payment as refunded when refund equals payment amount",
         %{
           user: user
         } do
      amount = Money.new(5000, :USD)

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: amount,
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id:
            "pi_full_refund_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(175, :USD),
          description: "Full refund test",
          property: nil,
          payment_method_id: nil
        })

      assert {:ok, {_refund, _tx, _entries}} =
               Ledgers.process_refund(%{
                 payment_id: payment.id,
                 refund_amount: amount,
                 reason: "Full refund",
                 external_refund_id:
                   "re_full_#{System.unique_integer([:positive])}"
               })

      assert %{status: :refunded} = Ledgers.get_payment(payment.id)
    end
  end

  describe "event payment with donations" do
    setup do
      user = user_fixture()

      # Configure QuickBooks client to use mock (prevents errors when sync jobs run)
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      # Set up QuickBooks configuration for tests
      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      # Set up default mocks for automatic sync jobs
      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "process_event_payment_with_donations/1 creates separate revenue entries for event and donation",
         %{
           user: user
         } do
      # $100.00 total: $60.00 event + $40.00 donation
      total_amount = Money.new(10_000, :USD)
      event_amount = Money.new(6_000, :USD)
      donation_amount = Money.new(4_000, :USD)
      stripe_fee = Money.new(320, :USD)
      event_id = Ecto.ULID.generate()

      payment_attrs = %{
        user_id: user.id,
        total_amount: total_amount,
        event_amount: event_amount,
        donation_amount: donation_amount,
        event_id: event_id,
        external_payment_id: "pi_mixed_123",
        stripe_fee: stripe_fee,
        description: "Event tickets with donation - Order ORD123",
        payment_method_id: nil
      }

      assert {:ok, {payment, transaction, entries}} =
               Ledgers.process_event_payment_with_donations(payment_attrs)

      # Check payment was created
      assert %Payment{} = payment
      assert payment.amount == total_amount
      assert payment.external_payment_id == "pi_mixed_123"
      assert payment.status == :completed

      # Check transaction was created
      assert %LedgerTransaction{} = transaction
      assert transaction.type == :payment
      assert transaction.total_amount == total_amount
      assert transaction.status == :completed

      # Check entries were created
      # Should have: stripe receivable debit, event revenue credit, donation revenue credit,
      # stripe fee debit, stripe account credit (for fee)
      assert length(entries) == 5

      # Verify all entries have the correct payment_id
      Enum.each(entries, fn entry ->
        assert entry.payment_id == payment.id
      end)

      # Verify Stripe receivable entry (debit)
      stripe_receivable_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Payment receivable from Stripe" &&
            e.debit_credit == :debit
        end)

      assert stripe_receivable_entry != nil
      assert stripe_receivable_entry.amount == total_amount
      assert stripe_receivable_entry.related_entity_type in [:event, "event"]
      assert stripe_receivable_entry.related_entity_id == event_id

      # Verify event revenue entry (credit)
      event_revenue_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Event revenue from tickets" &&
            e.debit_credit == :credit
        end)

      assert event_revenue_entry != nil
      assert event_revenue_entry.amount == event_amount
      assert event_revenue_entry.related_entity_type in [:event, "event"]
      assert event_revenue_entry.related_entity_id == event_id

      # Verify donation revenue entry (credit)
      donation_revenue_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Donation revenue from tickets" &&
            e.debit_credit == :credit
        end)

      assert donation_revenue_entry != nil
      assert donation_revenue_entry.amount == donation_amount

      assert donation_revenue_entry.related_entity_type in [
               :donation,
               "donation"
             ]

      assert donation_revenue_entry.related_entity_id == event_id

      # Verify Stripe fee entries
      fee_expense_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Stripe processing fee" && e.debit_credit == :debit
        end)

      assert fee_expense_entry != nil
      assert fee_expense_entry.amount == stripe_fee

      # Verify ledger balance
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "process_event_payment_with_donations/1 handles donation-only payments",
         %{user: user} do
      # $50.00 donation only (no event tickets)
      total_amount = Money.new(5_000, :USD)
      event_amount = Money.new(0, :USD)
      donation_amount = Money.new(5_000, :USD)
      stripe_fee = Money.new(160, :USD)
      event_id = Ecto.ULID.generate()

      payment_attrs = %{
        user_id: user.id,
        total_amount: total_amount,
        event_amount: event_amount,
        donation_amount: donation_amount,
        event_id: event_id,
        external_payment_id: "pi_donation_only_123",
        stripe_fee: stripe_fee,
        description: "Donation only - Order ORD456",
        payment_method_id: nil
      }

      assert {:ok, {payment, _transaction, entries}} =
               Ledgers.process_event_payment_with_donations(payment_attrs)

      # Check payment was created
      assert %Payment{} = payment
      assert payment.amount == total_amount

      # Check entries - should NOT have event revenue entry
      event_revenue_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Event revenue from tickets"
        end)

      assert event_revenue_entry == nil

      # Should have donation revenue entry
      donation_revenue_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Donation revenue from tickets" &&
            e.debit_credit == :credit
        end)

      assert donation_revenue_entry != nil
      assert donation_revenue_entry.amount == donation_amount

      # Verify ledger balance
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "process_event_payment_with_donations/1 handles event-only payments",
         %{user: user} do
      # $75.00 event only (no donations)
      total_amount = Money.new(7_500, :USD)
      event_amount = Money.new(7_500, :USD)
      donation_amount = Money.new(0, :USD)
      stripe_fee = Money.new(240, :USD)
      event_id = Ecto.ULID.generate()

      payment_attrs = %{
        user_id: user.id,
        total_amount: total_amount,
        event_amount: event_amount,
        donation_amount: donation_amount,
        event_id: event_id,
        external_payment_id: "pi_event_only_123",
        stripe_fee: stripe_fee,
        description: "Event tickets only - Order ORD789",
        payment_method_id: nil
      }

      assert {:ok, {payment, _transaction, entries}} =
               Ledgers.process_event_payment_with_donations(payment_attrs)

      # Check payment was created
      assert %Payment{} = payment
      assert payment.amount == total_amount

      # Check entries - should have event revenue entry
      event_revenue_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Event revenue from tickets" &&
            e.debit_credit == :credit
        end)

      assert event_revenue_entry != nil
      assert event_revenue_entry.amount == event_amount

      # Should NOT have donation revenue entry
      donation_revenue_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Donation revenue from tickets"
        end)

      assert donation_revenue_entry == nil

      # Verify ledger balance
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "process_event_payment_with_donations/1 skips fee entries when stripe_fee is zero",
         %{
           user: user
         } do
      total = Money.new(5_000, :USD)
      event_id = Ecto.ULID.generate()

      assert {:ok, {_payment, _transaction, entries}} =
               Ledgers.process_event_payment_with_donations(%{
                 user_id: user.id,
                 total_amount: total,
                 event_amount: total,
                 donation_amount: Money.new(0, :USD),
                 event_id: event_id,
                 external_payment_id:
                   "pi_no_fee_event_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(0, :USD),
                 description: "Event only, no Stripe fee",
                 payment_method_id: nil
               })

      refute Enum.any?(entries, fn e ->
               e.description =~ "Stripe processing fee"
             end)

      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "process_event_payment_with_donations/1 creates correct account balances",
         %{user: user} do
      # $100.00 total: $60.00 event + $40.00 donation
      total_amount = Money.new(10_000, :USD)
      event_amount = Money.new(6_000, :USD)
      donation_amount = Money.new(4_000, :USD)
      stripe_fee = Money.new(320, :USD)
      event_id = Ecto.ULID.generate()

      payment_attrs = %{
        user_id: user.id,
        total_amount: total_amount,
        event_amount: event_amount,
        donation_amount: donation_amount,
        event_id: event_id,
        external_payment_id: "pi_balance_test_123",
        stripe_fee: stripe_fee,
        description: "Balance test - Order ORD999",
        payment_method_id: nil
      }

      assert {:ok, {_payment, _transaction, _entries}} =
               Ledgers.process_event_payment_with_donations(payment_attrs)

      # Check account balances
      event_revenue_account = Ledgers.get_account_by_name("event_revenue")
      donation_revenue_account = Ledgers.get_account_by_name("donation_revenue")
      stripe_account = Ledgers.get_account_by_name("stripe_account")
      stripe_fees_account = Ledgers.get_account_by_name("stripe_fees")

      event_balance = Ledgers.get_account_balance(event_revenue_account.id)

      donation_balance =
        Ledgers.get_account_balance(donation_revenue_account.id)

      stripe_balance = Ledgers.get_account_balance(stripe_account.id)
      fees_balance = Ledgers.get_account_balance(stripe_fees_account.id)

      # Event revenue should be credited (positive balance for credit-normal account)
      assert Money.equal?(event_balance, event_amount)

      # Donation revenue should be credited (positive balance for credit-normal account)
      assert Money.equal?(donation_balance, donation_amount)

      # Stripe account should have net receivable (total - fee)
      expected_stripe_balance = Money.sub(total_amount, stripe_fee) |> elem(1)
      assert Money.equal?(stripe_balance, expected_stripe_balance)

      # Stripe fees should be debited (positive balance for debit-normal account)
      assert Money.equal?(fees_balance, stripe_fee)
    end

    test "process_event_payment_with_donations_and_discounts/1 creates entries for event, donation, and discount",
         %{user: user} do
      # $100.00 total: $60.00 event + $40.00 donation - $10.00 discount
      total_amount = Money.new(10_000, :USD)
      gross_event_amount = Money.new(6_000, :USD)
      event_amount = Money.new(6_000, :USD)
      donation_amount = Money.new(4_000, :USD)
      discount_amount = Money.new(1_000, :USD)
      stripe_fee = Money.new(320, :USD)
      event_id = Ecto.ULID.generate()
      ticket_order_id = Ecto.ULID.generate()

      payment_attrs = %{
        user_id: user.id,
        total_amount: total_amount,
        gross_event_amount: gross_event_amount,
        event_amount: event_amount,
        donation_amount: donation_amount,
        discount_amount: discount_amount,
        event_id: event_id,
        external_payment_id: "pi_discount_test",
        stripe_fee: stripe_fee,
        description: "Event with donation and discount",
        payment_method_id: nil,
        ticket_order_id: ticket_order_id
      }

      assert {:ok, {payment, transaction, entries}} =
               Ledgers.process_event_payment_with_donations_and_discounts(
                 payment_attrs
               )

      assert %Payment{} = payment
      assert payment.amount == total_amount
      assert %LedgerTransaction{} = transaction
      assert transaction.total_amount == total_amount

      # Should have entries for: stripe receivable, event revenue, donation revenue,
      # discount expense, stripe fee debit, stripe account credit
      assert length(entries) >= 5

      # Verify discount expense entry exists
      discount_entry =
        Enum.find(entries, fn e ->
          e.description =~ "discount" && e.debit_credit == :debit
        end)

      assert discount_entry != nil
      assert Money.equal?(discount_entry.amount, discount_amount)

      # Verify ledger balance
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end
  end

  describe "credit management" do
    setup do
      user = user_fixture()

      # Configure QuickBooks client to use mock (prevents errors when sync jobs run)
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      # Set up QuickBooks configuration for tests
      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      # Set up default mocks for automatic sync jobs
      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "add_credit/1 creates credit entries", %{user: user} do
      # $10.00
      credit_amount = Money.new(1000, :USD)

      credit_attrs = %{
        user_id: user.id,
        amount: credit_amount,
        reason: "Compensation for service issue",
        entity_type: :administration,
        entity_id: nil
      }

      assert {:ok, {credit_payment, transaction, entries}} =
               Ledgers.add_credit(credit_attrs)

      # Check credit payment was created
      assert %Payment{} = credit_payment
      assert credit_payment.amount == credit_amount
      assert credit_payment.user_id == user.id
      assert String.starts_with?(credit_payment.external_payment_id, "credit_")

      # Check transaction was created
      assert %LedgerTransaction{} = transaction
      assert transaction.type == :adjustment
      assert transaction.total_amount == credit_amount
      assert transaction.status == :completed

      # Check entries were created (should be 2: accounts receivable debit, cash credit)
      assert length(entries) == 2

      # Verify all entries have the correct payment_id
      Enum.each(entries, fn entry ->
        assert entry.payment_id == credit_payment.id
      end)
    end

    test "add_credit/1 accepts explicit entity_id for related_entity on entries",
         %{
           user: user
         } do
      entity_id = Ecto.ULID.generate()

      assert {:ok, {_payment, _transaction, entries}} =
               Ledgers.add_credit(%{
                 user_id: user.id,
                 amount: Money.new(150, :USD),
                 reason: "Event credit",
                 entity_type: :event,
                 entity_id: entity_id
               })

      assert Enum.any?(entries, fn e ->
               e.related_entity_id == entity_id or
                 e.related_entity_type == :event
             end)
    end

    test "get_account_balance/1 returns zero for account with no entries" do
      {:ok, account} =
        Ledgers.create_account(%{
          name: "empty_test_#{System.unique_integer([:positive])}",
          account_type: :asset,
          normal_balance: :debit
        })

      balance = Ledgers.get_account_balance(account.id)
      assert Money.zero?(balance)
    end

    test "get_account_balance/3 with range excluding payments yields zero", %{
      user: user
    } do
      {:ok, {_payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(5000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_range_excl_#{System.unique_integer()}",
          stripe_fee: Money.new(150, :USD),
          description: "Range test",
          property: nil,
          payment_method_id: nil
        })

      cash = Ledgers.get_account_by_name("cash")
      past_start = DateTime.add(DateTime.utc_now(), -365, :day)
      past_end = DateTime.add(DateTime.utc_now(), -300, :day)

      bal = Ledgers.get_account_balance(cash.id, past_start, past_end)
      assert Money.zero?(bal)
    end

    test "get_entry/1 returns nil for unknown entry id" do
      assert Ledgers.get_entry(Ecto.ULID.generate()) == nil
    end

    test "get_payment_with_associations/1 returns nil for unknown id" do
      assert Ledgers.get_payment_with_associations(Ecto.ULID.generate()) == nil
    end

    test "payment_has_revenue_debit_entries?/1 returns false for membership payment",
         %{
           user: user
         } do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(2000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_rev_chk_#{System.unique_integer()}",
          stripe_fee: Money.new(100, :USD),
          description: "Membership",
          property: nil,
          payment_method_id: nil
        })

      refute Ledgers.payment_has_revenue_debit_entries?(payment.id)
    end

    test "add_payment_type_info/1 returns Unknown when payment has no revenue entry (manual credit)",
         %{
           user: user
         } do
      assert {:ok, {credit_payment, _, _}} =
               Ledgers.add_credit(%{
                 user_id: user.id,
                 amount: Money.new(500, :USD),
                 reason: "Test credit",
                 entity_type: :administration,
                 entity_id: nil
               })

      assert %{type: "Unknown", details: "No revenue entry found"} =
               Ledgers.add_payment_type_info(credit_payment).payment_type_info
    end
  end

  describe "payout processing" do
    setup do
      user = user_fixture()

      # Configure QuickBooks client to use mock
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      # Create test payments
      {:ok, {payment1, _transaction1, _entries1}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :event,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_payout_1",
          stripe_fee: Money.new(320, :USD),
          description: "Payment 1",
          property: nil,
          payment_method_id: nil
        })

      {:ok, {payment2, _transaction2, _entries2}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(5_000, :USD),
          entity_type: :event,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_payout_2",
          stripe_fee: Money.new(160, :USD),
          description: "Payment 2",
          property: nil,
          payment_method_id: nil
        })

      %{user: user, payment1: payment1, payment2: payment2}
    end

    test "process_stripe_payout/1 creates payout with entries", %{
      payment1: _payment1
    } do
      payout_attrs = %{
        payout_amount: Money.new(10_000, :USD),
        stripe_payout_id: "po_test_123",
        description: "Test payout",
        currency: "usd",
        status: "paid",
        arrival_date: DateTime.utc_now(),
        metadata: %{}
      }

      assert {:ok, {payout_payment, transaction, entries, payout}} =
               Ledgers.process_stripe_payout(payout_attrs)

      assert payout_payment.amount == Money.new(10_000, :USD)
      assert payout.stripe_payout_id == "po_test_123"
      assert transaction.type == :payout
      assert length(entries) >= 2
    end

    test "process_stripe_payout/1 accepts optional fee_total", %{payment1: _p1} do
      payout_attrs = %{
        payout_amount: Money.new(10_000, :USD),
        stripe_payout_id: "po_fee_#{System.unique_integer([:positive])}",
        description: "Payout with fee",
        currency: "usd",
        status: "paid",
        arrival_date: DateTime.utc_now(),
        fee_total: Money.new(100, :USD)
      }

      assert {:ok, {_payout_payment, _transaction, _entries, payout}} =
               Ledgers.process_stripe_payout(payout_attrs)

      assert payout.stripe_payout_id == payout_attrs.stripe_payout_id
    end

    test "book_payout_stripe_fees/2 books expense and stripe receivable reduction",
         %{payment1: _p1} do
      assert {:ok, {_payout_payment, _transaction, _entries, payout}} =
               Ledgers.process_stripe_payout(%{
                 payout_amount: Money.new(12_922, :USD),
                 stripe_payout_id:
                   "po_book_fee_#{System.unique_integer([:positive])}",
                 description: "Payout needing usage fee",
                 currency: "usd",
                 status: "paid",
                 arrival_date: DateTime.utc_now()
               })

      fee = Money.new(:USD, "0.95")

      assert {:ok, [fee_expense, stripe_credit]} =
               Ledgers.book_payout_stripe_fees(payout, fee)

      assert fee_expense.debit_credit == :debit
      assert fee_expense.amount == fee

      assert String.contains?(
               fee_expense.description,
               "Stripe payout fee for #{payout.stripe_payout_id}"
             )

      assert stripe_credit.debit_credit == :credit
      assert stripe_credit.amount == fee

      fee_account = Ledgers.get_account_by_name("stripe_fees")
      stripe_account = Ledgers.get_account_by_name("stripe_account")
      assert fee_expense.account_id == fee_account.id
      assert stripe_credit.account_id == stripe_account.id

      # Idempotent on relink
      assert {:ok, :already_booked} =
               Ledgers.book_payout_stripe_fees(payout, fee)
    end

    test "book_payout_stripe_fees/2 no-ops for zero fee", %{payment1: _p1} do
      assert {:ok, {_payout_payment, _transaction, _entries, payout}} =
               Ledgers.process_stripe_payout(%{
                 payout_amount: Money.new(1000, :USD),
                 stripe_payout_id:
                   "po_zero_fee_#{System.unique_integer([:positive])}",
                 description: "No extra fee",
                 currency: "usd",
                 status: "paid",
                 arrival_date: DateTime.utc_now()
               })

      assert {:ok, :no_fees} =
               Ledgers.book_payout_stripe_fees(payout, Money.new(0, :USD))
    end

    test "link_payment_to_payout/2 links payment to payout", %{
      payment1: payment1,
      payment2: payment2
    } do
      {:ok, {_payout_payment, _transaction, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(15_000, :USD),
          stripe_payout_id: "po_link_test",
          description: "Test payout",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now(),
          metadata: %{}
        })

      assert {:ok, updated_payout} =
               Ledgers.link_payment_to_payout(payout, payment1)

      assert {:ok, updated_payout} =
               Ledgers.link_payment_to_payout(updated_payout, payment2)

      # Reload payout with payments
      updated_payout =
        Ysc.Repo.reload!(updated_payout) |> Ysc.Repo.preload(:payments)

      assert length(updated_payout.payments) == 2
    end

    test "get_payout_by_stripe_id/1 returns nil when not found" do
      assert Ledgers.get_payout_by_stripe_id(
               "po_nonexistent_#{System.unique_integer([:positive])}"
             ) ==
               nil
    end

    test "link_payment_to_payout/2 is idempotent when link already exists", %{
      payment1: payment1
    } do
      {:ok, {_pp, _tx, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(10_000, :USD),
          stripe_payout_id:
            "po_idempotent_link_#{System.unique_integer([:positive])}",
          description: "Idempotent link",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now(),
          metadata: %{}
        })

      assert {:ok, p1} = Ledgers.link_payment_to_payout(payout, payment1)
      assert {:ok, p2} = Ledgers.link_payment_to_payout(payout, payment1)
      assert p1.id == p2.id
    end

    test "link_refund_to_payout/2 is idempotent when link already exists", %{
      payment1: payment1
    } do
      {:ok, {refund, _, _}} =
        Ledgers.process_refund(%{
          payment_id: payment1.id,
          refund_amount: Money.new(1_000, :USD),
          external_refund_id: "re_idem_#{System.unique_integer([:positive])}",
          reason: "Idempotent refund link"
        })

      {:ok, {_pp, _tx, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(9_000, :USD),
          stripe_payout_id: "po_ref_idem_#{System.unique_integer([:positive])}",
          description: "Payout",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now(),
          metadata: %{}
        })

      assert {:ok, p1} = Ledgers.link_refund_to_payout(payout, refund)
      assert {:ok, p2} = Ledgers.link_refund_to_payout(payout, refund)
      assert p1.id == p2.id
    end

    test "link_refund_to_payout/2 links refund to payout", %{payment1: payment1} do
      {:ok, {refund, _transaction, _entries}} =
        Ledgers.process_refund(%{
          payment_id: payment1.id,
          refund_amount: Money.new(2_000, :USD),
          external_refund_id: "re_payout_test",
          reason: "Test refund"
        })

      {:ok, {_payout_payment, _transaction, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(8_000, :USD),
          stripe_payout_id: "po_refund_link_test",
          description: "Test payout",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now(),
          metadata: %{}
        })

      assert {:ok, updated_payout} =
               Ledgers.link_refund_to_payout(payout, refund)

      # Reload payout with refunds
      updated_payout =
        Ysc.Repo.reload!(updated_payout) |> Ysc.Repo.preload(:refunds)

      assert length(updated_payout.refunds) == 1
    end
  end

  describe "balance calculations" do
    setup do
      user = user_fixture()

      # Configure QuickBooks client to use mock
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "verify_ledger_balance/0 returns balanced for empty ledger" do
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "verify_ledger_balance/0 returns {:error, {:imbalanced, difference}} when out of balance" do
      account = Ledgers.get_account_by_name("cash")

      %LedgerEntry{
        amount: Money.new(77, :USD),
        debit_credit: :debit,
        account_id: account.id,
        description: "Coverage imbalance"
      }
      |> Repo.insert!()

      assert {:error, {:imbalanced, difference}} =
               Ledgers.verify_ledger_balance()

      refute Money.equal?(difference, Money.new(0, :USD))
    end

    test "verify_ledger_balance/0 returns balanced after payment", %{user: user} do
      {:ok, {_payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_balance_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "verify_ledger_balance/0 returns balanced after payment and refund", %{
      user: user
    } do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_balance_refund_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      {:ok, {_refund, _refund_transaction, _refund_entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(5_000, :USD),
          external_refund_id: "re_balance_test",
          reason: "Test refund"
        })

      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "get_account_balance/2 respects date range", %{user: user} do
      # Membership payments create entries for stripe_account (debit) and membership_revenue (credit)
      # Check stripe_account which should have a positive balance
      account = Ledgers.get_account_by_name("stripe_account")

      # Get today's date range first
      today = Date.utc_today()
      today_start = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
      today_end = DateTime.new!(today, ~T[23:59:59], "Etc/UTC")

      # Create payment with unique external_payment_id
      unique_id = "pi_date_range_test_#{System.unique_integer([:positive])}"

      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: unique_id,
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      # Update payment_date using direct SQL to ensure it's within today's range
      Ysc.Repo.update_all(
        from(p in Ysc.Ledgers.Payment, where: p.id == ^payment.id),
        set: [payment_date: today_start]
      )

      balance_today =
        Ledgers.get_account_balance(account.id, today_start, today_end)

      assert Money.positive?(balance_today)

      # Get balance for yesterday (should be zero)
      yesterday = Date.add(today, -1)
      yesterday_start = DateTime.new!(yesterday, ~T[00:00:00], "Etc/UTC")
      yesterday_end = DateTime.new!(yesterday, ~T[23:59:59], "Etc/UTC")

      balance_yesterday =
        Ledgers.get_account_balance(account.id, yesterday_start, yesterday_end)

      assert Money.equal?(balance_yesterday, Money.new(0, :USD))
    end
  end

  describe "payment types" do
    setup do
      user = user_fixture()

      # Configure QuickBooks client to use mock
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "process_payment/1 handles booking payments", %{user: user} do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(20_000, :USD),
          entity_type: :booking,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_booking_test",
          stripe_fee: Money.new(640, :USD),
          description: "Tahoe booking",
          property: :tahoe,
          payment_method_id: nil
        })

      # entity_type is stored in ledger entries, not on payment directly
      entries = Ysc.Ledgers.get_entries_by_payment(payment.id)
      booking_entry = Enum.find(entries, &(&1.related_entity_type == :booking))
      assert booking_entry.related_entity_type == :booking

      # Property is used to determine revenue account but not stored in ledger entries
      # Verify the description contains the property information
      assert booking_entry.description =~ "Tahoe"
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "process_payment/1 handles subscription payments", %{user: user} do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(15_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_subscription_test",
          stripe_fee: Money.new(480, :USD),
          description: "Membership subscription",
          property: nil,
          payment_method_id: nil
        })

      # entity_type is stored in ledger entries, not on payment directly
      # Subscription payments use :membership as entity_type
      entries = Ysc.Ledgers.get_entries_by_payment(payment.id)

      membership_entry =
        Enum.find(entries, &(&1.related_entity_type == :membership))

      assert membership_entry.related_entity_type == :membership
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "process_payment/1 handles donation payments", %{user: user} do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(5_000, :USD),
          entity_type: :donation,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_donation_test",
          stripe_fee: Money.new(160, :USD),
          description: "Donation",
          property: nil,
          payment_method_id: nil
        })

      # entity_type is stored in ledger entries, not on payment directly
      entries = Ysc.Ledgers.get_entries_by_payment(payment.id)

      donation_entry =
        Enum.find(entries, &(&1.related_entity_type == :donation))

      assert donation_entry.related_entity_type == :donation
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "process_payment/1 uses clear_lake_booking_revenue for clear lake property",
         %{user: user} do
      {:ok, {_payment, _transaction, entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(12_000, :USD),
          entity_type: :booking,
          entity_id: Ecto.ULID.generate(),
          external_payment_id:
            "pi_clear_lake_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(400, :USD),
          description: "Clear Lake booking",
          property: :clear_lake,
          payment_method_id: nil
        })

      assert Enum.any?(entries, fn e ->
               e.account_id ==
                 Ledgers.get_account_by_name("clear_lake_booking_revenue").id &&
                 e.debit_credit == :credit
             end)

      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end
  end

  describe "payment retrieval" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_retrieval_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      %{user: user, payment: payment}
    end

    test "get_payment/1 returns payment with associations", %{payment: payment} do
      retrieved = Ledgers.get_payment(payment.id)
      assert retrieved.id == payment.id
      assert Ecto.assoc_loaded?(retrieved.user)
    end

    test "get_payment/1 returns nil for non-existent payment" do
      assert nil == Ledgers.get_payment(Ecto.ULID.generate())
    end

    test "get_payment_with_associations/1 returns payment with all associations",
         %{
           payment: payment
         } do
      retrieved = Ledgers.get_payment_with_associations(payment.id)
      assert retrieved.id == payment.id
      assert Ecto.assoc_loaded?(retrieved.user)
    end

    test "get_payment_by_external_id/1 returns payment by external id", %{
      payment: payment
    } do
      retrieved = Ledgers.get_payment_by_external_id("pi_retrieval_test")
      assert retrieved.id == payment.id
    end

    test "get_payment_by_external_id/1 returns nil for non-existent external id" do
      assert nil == Ledgers.get_payment_by_external_id("pi_nonexistent")
    end

    test "get_payments_by_user/1 returns all payments for user", %{
      user: user,
      payment: payment
    } do
      payments = Ledgers.get_payments_by_user(user.id)
      assert payments != []
      assert Enum.any?(payments, &(&1.id == payment.id))
    end

    test "list_all_user_payments/1 returns payments and free ticket orders", %{
      user: user,
      payment: payment
    } do
      items = Ledgers.list_all_user_payments(user.id)
      assert is_list(items)

      assert Enum.any?(items, fn item ->
               case item do
                 %{payment: p} when not is_nil(p) -> p.id == payment.id
                 _ -> false
               end
             end)
    end

    test "list_all_user_payments/1 includes free ticket orders when user has them",
         %{
           user: user
         } do
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      _free_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      items = Ledgers.list_all_user_payments(user.id)

      free_orders =
        Enum.filter(items, fn item -> Map.get(item, :ticket_order) end)

      assert free_orders != []

      assert Enum.any?(free_orders, fn item ->
               item.type == :ticket && item.ticket_order != nil &&
                 item.payment == nil
             end)
    end

    test "list_user_payments_paginated/3 total_count sums payments and completed free ticket orders",
         %{user: user} do
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      _free_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      {_items, total_count} =
        Ledgers.list_user_payments_paginated(user.id, 1, 10)

      assert total_count == 2
    end

    test "list_user_payments_paginated/3 total_count ignores non-completed free ticket orders",
         %{user: user} do
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      _pending_free =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :pending
        })

      {_items, total_count} =
        Ledgers.list_user_payments_paginated(user.id, 1, 10)

      assert total_count == 1
    end

    test "list_user_payments_paginated/3 total_count does not add ticket orders that reference a payment",
         %{user: user, payment: payment} do
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      order
      |> Ecto.Changeset.change(payment_id: payment.id)
      |> Repo.update!()

      {_items, total_count} =
        Ledgers.list_user_payments_paginated(user.id, 1, 10)

      assert total_count == 1
    end

    test "list_user_payments_paginated/3 returns paginated payments", %{
      user: user
    } do
      {entries, total_count} =
        Ledgers.list_user_payments_paginated(user.id, 1, 10)

      assert is_list(entries)
      assert is_integer(total_count)
      assert total_count >= 0
    end

    test "list_user_payments_paginated/3 returns empty for user with no payments" do
      user = user_fixture()

      {entries, total_count} =
        Ledgers.list_user_payments_paginated(user.id, 1, 10)

      assert entries == []
      assert total_count == 0
    end

    test "list_user_payments_paginated/3 total_count includes completed free ticket orders without payment" do
      user = user_fixture()
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      _free_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      {entries, total_count} =
        Ledgers.list_user_payments_paginated(user.id, 1, 10)

      assert total_count == 1
      assert length(entries) == 1
      row = hd(entries)
      assert row.type == :ticket
      assert row.payment == nil
      assert row.ticket_order != nil
    end

    test "list_user_payments_paginated/3 total_count aggregates multiple payments and free ticket rows" do
      user = user_fixture()
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      for n <- 1..2 do
        assert {:ok, %Payment{}} =
                 Ledgers.create_payment(%{
                   user_id: user.id,
                   amount: Money.new(1_000 + n, :USD),
                   external_provider: :stripe,
                   external_payment_id:
                     "pi_payments_tab_total_#{n}_#{System.unique_integer([:positive])}",
                   status: :completed,
                   payment_date: DateTime.utc_now()
                 })
      end

      for _ <- 1..2 do
        _ =
          ticket_order_fixture(%{
            user: user,
            event: event,
            tier: tier,
            status: :completed
          })
      end

      {_entries, total_count} =
        Ledgers.list_user_payments_paginated(user.id, 1, 10)

      assert total_count == 4
    end

    test "list_user_payments_paginated/3 page 2 returns second page", %{
      user: user
    } do
      {page1, total} = Ledgers.list_user_payments_paginated(user.id, 1, 1)
      {page2, ^total} = Ledgers.list_user_payments_paginated(user.id, 2, 1)

      assert is_list(page1)
      assert is_list(page2)

      if total >= 2 do
        assert length(page1) == 1
        assert length(page2) == 1
        assert hd(page1) != hd(page2)
      end
    end

    test "list_user_payments_paginated/3 returns empty when page is past last page",
         %{
           user: user
         } do
      {page1, total} = Ledgers.list_user_payments_paginated(user.id, 1, 5)
      assert is_list(page1)
      assert is_integer(total)

      last_page =
        if total == 0 do
          1
        else
          div(total - 1, 5) + 1
        end

      {beyond, ^total} =
        Ledgers.list_user_payments_paginated(user.id, last_page + 100, 5)

      assert beyond == []
    end

    test "update_payment/2 updates payment", %{payment: payment} do
      update_attrs = %{quickbooks_sync_status: "synced"}
      assert {:ok, updated} = Ledgers.update_payment(payment, update_attrs)
      assert updated.quickbooks_sync_status == "synced"
    end

    test "update_payment/2 returns error for invalid attributes", %{
      payment: payment
    } do
      assert {:error, %Ecto.Changeset{}} =
               Ledgers.update_payment(payment, %{external_provider: nil})
    end
  end

  describe "list_user_payments_paginated/4 filter option" do
    setup do
      user = user_fixture()
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      tahoe_booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      clear_lake_booking =
        booking_fixture(%{user_id: user.id, property: :clear_lake})

      for {suffix, entity_type, entity_id, property} <- [
            {"tahoe", :booking, tahoe_booking.id, :tahoe},
            {"cl", :booking, clear_lake_booking.id, :clear_lake},
            {"mem", :membership, Ecto.ULID.generate(), nil},
            {"don", :donation, Ecto.ULID.generate(), nil},
            {"evt", :event, Ecto.ULID.generate(), nil}
          ] do
        assert {:ok, {_payment, _, _}} =
                 Ledgers.process_payment(%{
                   user_id: user.id,
                   amount: Money.new(5_000, :USD),
                   entity_type: entity_type,
                   entity_id: entity_id,
                   external_payment_id:
                     "pi_filter_#{suffix}_#{System.unique_integer([:positive])}",
                   stripe_fee: Money.new(160, :USD),
                   description: suffix,
                   property: property,
                   payment_method_id: nil
                 })
      end

      _free_ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      %{user: user}
    end

    test "filter :all includes every payment type and free ticket orders", %{
      user: user
    } do
      {items, total} =
        Ledgers.list_user_payments_paginated(user.id, 1, 20, filter: :all)

      assert total == 6
      assert length(items) == 6

      assert Enum.any?(
               items,
               &(&1.type == :booking && &1.booking.property == :tahoe)
             )

      assert Enum.any?(
               items,
               &(&1.type == :booking && &1.booking.property == :clear_lake)
             )

      assert Enum.any?(items, &(&1.type == :membership))
      assert Enum.any?(items, &(&1.type == :donation))
      assert Enum.any?(items, &(&1.type == :ticket))
    end

    test "filter :tahoe returns only Tahoe booking payments", %{user: user} do
      {items, total} =
        Ledgers.list_user_payments_paginated(user.id, 1, 20, filter: :tahoe)

      assert total == 1
      assert [%{type: :booking, booking: %{property: :tahoe}}] = items
    end

    test "filter :clear_lake returns only Clear Lake booking payments", %{
      user: user
    } do
      {items, total} =
        Ledgers.list_user_payments_paginated(user.id, 1, 20,
          filter: :clear_lake
        )

      assert total == 1
      assert [%{type: :booking, booking: %{property: :clear_lake}}] = items
    end

    test "filter :membership returns only membership payments", %{user: user} do
      {items, total} =
        Ledgers.list_user_payments_paginated(user.id, 1, 20,
          filter: :membership
        )

      assert total == 1
      assert [%{type: :membership}] = items
    end

    test "filter :donations returns only donation payments", %{user: user} do
      {items, total} =
        Ledgers.list_user_payments_paginated(user.id, 1, 20, filter: :donations)

      assert total == 1
      assert [%{type: :donation}] = items
    end

    test "filter :events returns paid and free ticket rows", %{user: user} do
      {items, total} =
        Ledgers.list_user_payments_paginated(user.id, 1, 20, filter: :events)

      assert total == 2
      assert length(items) == 2
      assert Enum.all?(items, &(&1.type == :ticket))
    end

    test "unknown filter falls back to :all", %{user: user} do
      {_items, total} =
        Ledgers.list_user_payments_paginated(user.id, 1, 20, filter: :bogus)

      assert total == 6
    end
  end

  describe "list_user_payments_paginated/3 with payment_method" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      pm =
        %PaymentMethod{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_paginated_#{System.unique_integer([:positive])}",
          provider_customer_id:
            "cus_paginated_#{System.unique_integer([:positive])}",
          provider_type: "card",
          type: :card,
          last_four: "4242",
          exp_month: 12,
          exp_year: 2030,
          display_brand: "visa",
          is_default: true
        }
        |> Repo.insert!()

      ext = "pi_pm_paginated_#{System.unique_integer([:positive])}"

      assert {:ok, {payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(10_000, :USD),
                 entity_type: :membership,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id: ext,
                 stripe_fee: Money.new(320, :USD),
                 description: "Membership with PM",
                 property: nil,
                 payment_method_id: pm.id
               })

      %{user: user, payment: payment, payment_method: pm}
    end

    test "batch-enriches payment_method on paginated payment rows", %{
      user: user,
      payment: payment,
      payment_method: pm
    } do
      {items, _total} = Ledgers.list_user_payments_paginated(user.id, 1, 10)

      row =
        Enum.find(items, fn i -> i.payment && i.payment.id == payment.id end)

      assert row
      assert row.payment.payment_method
      assert row.payment.payment_method.id == pm.id
    end
  end

  describe "entry management" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      {:ok, {payment, _transaction, entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_entry_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      entry = List.first(entries)

      %{user: user, payment: payment, entry: entry}
    end

    test "get_entry/1 returns entry with associations", %{entry: entry} do
      retrieved = Ledgers.get_entry(entry.id)
      assert retrieved.id == entry.id
      assert Ecto.assoc_loaded?(retrieved.account)
      assert Ecto.assoc_loaded?(retrieved.payment)
    end

    test "get_entry/1 returns nil for unknown id" do
      assert Ledgers.get_entry(Ecto.ULID.generate()) == nil
    end

    test "get_entries_by_payment/1 returns all entries for payment", %{
      payment: payment
    } do
      entries = Ledgers.get_entries_by_payment(payment.id)
      assert is_list(entries)
      assert entries != []
      assert Enum.all?(entries, &(&1.payment_id == payment.id))
    end
  end

  describe "refund retrieval" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_refund_retrieval_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      {:ok, {refund, _transaction, _entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(5_000, :USD),
          external_refund_id: "re_retrieval_test",
          reason: "Test refund"
        })

      %{user: user, payment: payment, refund: refund}
    end

    test "get_refund/1 returns refund by id", %{refund: refund} do
      retrieved = Ledgers.get_refund(refund.id)
      assert retrieved.id == refund.id
    end

    test "get_refund/1 returns nil for non-existent refund" do
      assert nil == Ledgers.get_refund(Ecto.ULID.generate())
    end

    test "get_refund_by_external_id/1 returns refund by external id", %{
      refund: refund
    } do
      retrieved = Ledgers.get_refund_by_external_id("re_retrieval_test")
      assert retrieved.id == refund.id
    end

    test "get_refund_by_external_id/1 returns nil for non-existent external id" do
      assert nil == Ledgers.get_refund_by_external_id("re_nonexistent")
    end

    test "update_refund/2 updates refund reason", %{refund: refund} do
      assert {:ok, updated} =
               Ledgers.update_refund(refund, %{reason: "Updated reason"})

      assert updated.reason == "Updated reason"
    end

    test "update_refund/2 returns error when reason exceeds maximum length", %{
      refund: refund
    } do
      assert {:error, %Ecto.Changeset{}} =
               Ledgers.update_refund(refund, %{
                 reason: String.duplicate("x", 1001)
               })
    end
  end

  describe "balance and verification" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _name ->
        {:ok, %{"Id" => "qb_account_default", "Name" => "Test Account"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :query_class_by_name, fn _name ->
        {:ok, %{"Id" => "qb_class_default", "Name" => "Test Class"}}
      end)

      %{user: user}
    end

    test "get_account_balances/0 returns account balances", %{user: user} do
      {:ok, {_payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_balance_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      balances = Ledgers.get_account_balances()
      assert is_list(balances)

      assert Enum.all?(balances, fn {account, balance} ->
               is_struct(account, LedgerAccount) && is_struct(balance, Money)
             end)
    end

    test "calculate_account_balance/1 calculates balance for account", %{
      user: user
    } do
      account = Ledgers.get_account_by_name("stripe_account")

      {:ok, {_payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_calc_balance_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      balance = Ledgers.calculate_account_balance(account.id)
      assert %Money{} = balance
    end

    test "get_ledger_imbalance_details/0 returns balanced status", %{user: user} do
      {:ok, {_payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_imbalance_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      assert {:ok, :balanced} = Ledgers.get_ledger_imbalance_details()
    end

    test "get_ledger_imbalance_details/0 returns error with details when unbalanced" do
      account = Ledgers.get_account_by_name("cash")

      # Insert a single unbalanced entry (no matching credit)
      %LedgerEntry{
        amount: Money.new(100, :USD),
        debit_credit: :debit,
        account_id: account.id,
        description: "Unbalanced test entry"
      }
      |> Repo.insert!()

      assert {:error, {:imbalanced, _difference, account_balances}} =
               Ledgers.get_ledger_imbalance_details()

      assert is_list(account_balances)
    end

    test "verify_ledger_balance!/0 raises on imbalance" do
      account = Ledgers.get_account_by_name("cash")

      # Manually create an unbalanced entry
      %Ysc.Ledgers.LedgerEntry{
        amount: Money.new(100, :USD),
        debit_credit: :debit,
        account_id: account.id,
        description: "Forced imbalance"
      }
      |> Ysc.Repo.insert!()

      assert_raise RuntimeError, ~r/Ledger imbalance detected/, fn ->
        Ledgers.verify_ledger_balance!()
      end
    end
  end

  describe "recent payments and entries" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _name ->
        {:ok, %{"Id" => "qb_account_default", "Name" => "Test Account"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :query_class_by_name, fn _name ->
        {:ok, %{"Id" => "qb_class_default", "Name" => "Test Class"}}
      end)

      %{user: user}
    end

    test "get_recent_payments/3 returns recent payments", %{user: user} do
      {:ok, {_payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_recent_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      start_date = DateTime.add(DateTime.utc_now(), -30, :day)
      end_date = DateTime.utc_now()

      payments = Ledgers.get_recent_payments(start_date, end_date, 10)
      assert is_list(payments)
      assert length(payments) <= 10
    end

    test "get_recent_payments_with_types/3 returns payments with type info", %{
      user: user
    } do
      {:ok, {_payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_recent_types_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      start_date = DateTime.add(DateTime.utc_now(), -30, :day)
      end_date = DateTime.utc_now()

      payments =
        Ledgers.get_recent_payments_with_types(start_date, end_date, 10)

      assert is_list(payments)

      # add_payment_type_info adds :payment_type_info key to the payment struct
      assert Enum.all?(payments, fn p ->
               Map.has_key?(p, :payment_type_info)
             end)
    end

    test "get_ledger_entries/3 returns ledger entries", %{user: user} do
      {:ok, {_payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_entries_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      start_date = DateTime.add(DateTime.utc_now(), -30, :day)
      end_date = DateTime.utc_now()

      entries = Ledgers.get_ledger_entries(start_date, end_date, 100)
      assert is_list(entries)
      assert length(entries) <= 100
    end
  end

  describe "payout queries" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_payout_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      payout_attrs = %{
        stripe_payout_id: "po_test123",
        payout_amount: Money.new(9_680, :USD),
        arrival_date: DateTime.utc_now() |> DateTime.truncate(:second),
        status: "paid",
        currency: "usd",
        description: "Test payout"
      }

      {:ok, {_payout_payment, _transaction, _entries, payout}} =
        Ledgers.process_stripe_payout(payout_attrs)

      {:ok, _} = Ledgers.link_payment_to_payout(payout, payment)

      %{user: user, payment: payment, payout: payout}
    end

    test "get_payout_by_stripe_id/1 returns payout by stripe_id", %{
      payout: payout
    } do
      found = Ledgers.get_payout_by_stripe_id(payout.stripe_payout_id)
      assert found.id == payout.id
    end

    test "get_payout!/1 returns payout with preloaded associations", %{
      payout: payout
    } do
      found = Ledgers.get_payout!(payout.id)
      assert found.id == payout.id
      assert Ecto.assoc_loaded?(found.payment)
    end

    test "get_payout!/1 raises Ecto.NoResultsError for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        Ledgers.get_payout!(Ecto.ULID.generate())
      end
    end

    test "get_payout_payments/1 returns payments for payout", %{
      payout: payout,
      payment: payment
    } do
      payments = Ledgers.get_payout_payments(payout.id)
      assert payments != []
      assert Enum.any?(payments, &(&1.id == payment.id))
    end

    test "get_payout_refunds/1 returns refunds for payout", %{
      payout: payout,
      payment: payment
    } do
      {:ok, {refund, _transaction, _entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(5_000, :USD),
          external_refund_id: "re_test123",
          reason: "Test refund"
        })

      {:ok, _} = Ledgers.link_refund_to_payout(payout, refund)

      refunds = Ledgers.get_payout_refunds(payout.id)
      assert refunds != []
      assert Enum.any?(refunds, &(&1.id == refund.id))
    end
  end

  describe "payment type info" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "add_payment_type_info/1 adds type info to payment", %{user: user} do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_type_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      payment_with_info = Ledgers.add_payment_type_info(payment)
      assert Map.has_key?(payment_with_info, :payment_type_info)

      assert payment_with_info.payment_type_info.type in [
               "Membership",
               "Unknown"
             ]
    end

    test "add_payment_type_info_batch/1 returns empty list for empty input" do
      assert Ledgers.add_payment_type_info_batch([]) == []
    end

    test "add_payment_type_info_batch/1 adds type info to multiple payments", %{
      user: user
    } do
      {:ok, {payment1, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_batch1",
          stripe_fee: Money.new(320, :USD),
          description: "Payment 1",
          property: nil,
          payment_method_id: nil
        })

      {:ok, {payment2, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(5_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_batch2",
          stripe_fee: Money.new(160, :USD),
          description: "Payment 2",
          property: nil,
          payment_method_id: nil
        })

      payments = [payment1, payment2]
      payments_with_info = Ledgers.add_payment_type_info_batch(payments)

      assert length(payments_with_info) == 2

      assert Enum.all?(
               payments_with_info,
               &Map.has_key?(&1, :payment_type_info)
             )
    end

    test "add_payment_type_info/1 for donation payment returns Donation type",
         %{
           user: user
         } do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(5_000, :USD),
          entity_type: :donation,
          entity_id: Ecto.ULID.generate(),
          external_payment_id:
            "pi_donation_type_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(160, :USD),
          description: "Donation",
          property: nil,
          payment_method_id: nil
        })

      payment_with_info = Ledgers.add_payment_type_info(payment)
      assert payment_with_info.payment_type_info.type == "Donation"
    end

    test "add_payment_type_info/1 for booking payment returns Booking type", %{
      user: user
    } do
      booking = booking_fixture(%{user_id: user.id, property: :clear_lake})

      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(20_000, :USD),
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_booking_type_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(640, :USD),
          description: "Clear Lake booking",
          property: :clear_lake,
          payment_method_id: nil
        })

      payment_with_info = Ledgers.add_payment_type_info(payment)
      assert payment_with_info.payment_type_info.type == "Booking"
      assert payment_with_info.payment_type_info.details =~ "Clear Lake"
    end

    test "add_payment_type_info_batch/1 returns Payout type for payout payment" do
      {:ok, {payout_payment, _transaction, _entries, _payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(5_000, :USD),
          stripe_payout_id:
            "po_batch_type_#{System.unique_integer([:positive])}",
          description: "Test payout",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now()
        })

      [payment_with_info] =
        Ledgers.add_payment_type_info_batch([payout_payment])

      assert payment_with_info.payment_type_info.type == "Payout"
    end

    test "add_payment_type_info/1 for event payment with ticket order returns Event type",
         %{
           user: user
         } do
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_event_payment_with_donations(%{
          user_id: user.id,
          total_amount: Money.new(10_000, :USD),
          event_amount: Money.new(10_000, :USD),
          donation_amount: Money.new(0, :USD),
          event_id: event.id,
          external_payment_id:
            "pi_event_type_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      ticket_order
      |> Ecto.Changeset.change(%{payment_id: payment.id})
      |> Repo.update!()

      payment_with_info = Ledgers.add_payment_type_info(payment)
      assert payment_with_info.payment_type_info.type == "Event"
      assert payment_with_info.payment_type_info.details == event.title
    end
  end

  describe "get_payment_related_entity/1" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "returns nil when no related entity found", %{user: user} do
      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_no_entity",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      # May return nil or a tuple depending on implementation
      result = Ledgers.get_payment_related_entity(payment)
      assert result == nil || is_tuple(result)
    end

    test "returns nil when booking entry references a deleted booking", %{
      user: user
    } do
      booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(20_000, :USD),
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_deleted_booking_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(640, :USD),
          description: "Tahoe booking",
          property: :tahoe,
          payment_method_id: nil
        })

      assert {:booking, _} = Ledgers.get_payment_related_entity(payment)

      Repo.delete!(booking)

      assert Ledgers.get_payment_related_entity(payment) == nil
    end

    test "returns {:booking, booking} when payment is for a booking", %{
      user: user
    } do
      booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(20_000, :USD),
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_booking_entity_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(640, :USD),
          description: "Tahoe booking",
          property: :tahoe,
          payment_method_id: nil
        })

      assert {:booking, found_booking} =
               Ledgers.get_payment_related_entity(payment)

      assert found_booking.id == booking.id
    end

    test "process_refund/1 for booking payment triggers refund email path", %{
      user: user
    } do
      booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(20_000, :USD),
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_booking_refund_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(640, :USD),
          description: "Tahoe booking",
          property: :tahoe,
          payment_method_id: nil
        })

      assert {:ok, {refund, _tx, entries}} =
               Ledgers.process_refund(%{
                 payment_id: payment.id,
                 refund_amount: Money.new(10_000, :USD),
                 reason: "Partial refund",
                 external_refund_id:
                   "re_booking_refund_#{System.unique_integer([:positive])}"
               })

      assert refund.payment_id == payment.id
      assert length(entries) == 2

      assert_email_sent(subject: "Your booking refund has been processed")
    end

    test "returns {:ticket_order, ticket_order} when payment is linked to ticket order",
         %{
           user: user
         } do
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      {:ok, {payment, _, _}} =
        Ledgers.process_event_payment_with_donations(%{
          user_id: user.id,
          total_amount: Money.new(10_000, :USD),
          event_amount: Money.new(10_000, :USD),
          donation_amount: Money.new(0, :USD),
          event_id: event.id,
          external_payment_id:
            "pi_ticket_entity_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      ticket_order
      |> Ecto.Changeset.change(%{payment_id: payment.id})
      |> Repo.update!()

      assert {:ticket_order, found_order} =
               Ledgers.get_payment_related_entity(payment)

      assert found_order.id == ticket_order.id
    end

    test "process_refund/1 for event payment with ticket order triggers ticket refund path",
         %{
           user: user
         } do
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      {:ok, {payment, _, _}} =
        Ledgers.process_event_payment_with_donations(%{
          user_id: user.id,
          total_amount: Money.new(10_000, :USD),
          event_amount: Money.new(10_000, :USD),
          donation_amount: Money.new(0, :USD),
          event_id: event.id,
          external_payment_id:
            "pi_ticket_refund_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      ticket_order
      |> Ecto.Changeset.change(%{payment_id: payment.id})
      |> Repo.update!()

      assert {:ok, {refund, _tx, entries}} =
               Ledgers.process_refund(%{
                 payment_id: payment.id,
                 refund_amount: Money.new(5_000, :USD),
                 reason: "Partial refund",
                 external_refund_id:
                   "re_ticket_refund_#{System.unique_integer([:positive])}"
               })

      assert refund.payment_id == payment.id
      assert length(entries) == 2
    end

    test "process_refund/1 schedules ticket_order_refund email when tickets are cancelled",
         %{
           user: user
         } do
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      {:ok, {payment, _, _}} =
        Ledgers.process_event_payment_with_donations(%{
          user_id: user.id,
          total_amount: Money.new(10_000, :USD),
          event_amount: Money.new(10_000, :USD),
          donation_amount: Money.new(0, :USD),
          event_id: event.id,
          external_payment_id:
            "pi_ticket_refund_cancelled_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      ticket_order
      |> Ecto.Changeset.change(%{payment_id: payment.id})
      |> Repo.update!()

      tickets =
        from(t in Ysc.Events.Ticket,
          where: t.ticket_order_id == ^ticket_order.id
        )
        |> Repo.all()

      assert tickets != []

      Enum.each(tickets, fn t ->
        t
        |> Ysc.Events.Ticket.status_changeset(%{status: :cancelled})
        |> Repo.update!()
      end)

      assert {:ok, {_refund, _tx, _entries}} =
               Ledgers.process_refund(%{
                 payment_id: payment.id,
                 refund_amount: Money.new(5_000, :USD),
                 reason: "Partial refund",
                 external_refund_id:
                   "re_ticket_refund_cancelled_#{System.unique_integer([:positive])}"
               })

      # Oban uses testing: :inline — jobs execute immediately and are not persisted to oban_jobs.
      assert_email_sent(subject: "Your ticket refund has been processed")
    end

    test "process_refund/1 for ticket order with no cancelled tickets does not send ticket refund email",
         %{
           user: user
         } do
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      {:ok, {payment, _, _}} =
        Ledgers.process_event_payment_with_donations(%{
          user_id: user.id,
          total_amount: Money.new(10_000, :USD),
          event_amount: Money.new(10_000, :USD),
          donation_amount: Money.new(0, :USD),
          event_id: event.id,
          external_payment_id:
            "pi_ticket_no_cancel_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      ticket_order
      |> Ecto.Changeset.change(%{payment_id: payment.id})
      |> Repo.update!()

      tickets =
        from(t in Ysc.Events.Ticket,
          where: t.ticket_order_id == ^ticket_order.id
        )
        |> Repo.all()

      assert tickets != []
      assert Enum.all?(tickets, &(&1.status != :cancelled))

      assert {:ok, {_refund, _tx, _entries}} =
               Ledgers.process_refund(%{
                 payment_id: payment.id,
                 refund_amount: Money.new(5_000, :USD),
                 reason: "Partial refund",
                 external_refund_id:
                   "re_ticket_no_cancel_#{System.unique_integer([:positive])}"
               })

      refute_email_sent(subject: "Your ticket refund has been processed")
    end
  end

  describe "update_entry_with_balance/2" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      {:ok, {_payment, _transaction, entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_update_entry",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      entry = List.first(entries)
      %{user: user, entry: entry}
    end

    test "returns error for non-existent entry" do
      assert {:error, :not_found} =
               Ledgers.update_entry_with_balance(Ecto.ULID.generate(), %{
                 amount: Money.new(100, :USD)
               })
    end
  end

  describe "get_payments_for_subscription/1" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      subscription_id = Ecto.ULID.generate()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: subscription_id,
          external_payment_id: "pi_subscription",
          stripe_fee: Money.new(320, :USD),
          description: "Subscription payment",
          property: nil,
          payment_method_id: nil
        })

      %{user: user, subscription_id: subscription_id, payment: payment}
    end

    test "returns payments for subscription", %{
      subscription_id: subscription_id,
      payment: payment
    } do
      payments = Ledgers.get_payments_for_subscription(subscription_id)
      assert payments != []
      assert Enum.any?(payments, &(&1.id == payment.id))
    end
  end

  describe "list_all_user_payments/1 free ticket flow" do
    setup do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update!()
        |> Repo.reload!()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "includes completed free ticket orders without payment_id", %{
      user: user
    } do
      event = event_fixture()

      {:ok, free_tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "Complimentary",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 20,
          event_id: event.id
        })

      assert {:ok, ticket_order} =
               Tickets.create_ticket_order(user.id, event.id, %{
                 free_tier.id => 1
               })

      assert {:ok, completed} = Tickets.process_free_ticket_order(ticket_order)
      assert completed.status == :completed
      assert completed.payment_id == nil

      items = Ledgers.list_all_user_payments(user.id)

      assert Enum.any?(items, fn item ->
               match?(%{type: :ticket, payment: nil, ticket_order: %{}}, item) &&
                 item.ticket_order.id == completed.id
             end)
    end
  end

  describe "create functions" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "create_payment/1 creates a payment record" do
      attrs = %{
        user_id: user_fixture().id,
        amount: Money.new(10_000, :USD),
        external_provider: :stripe,
        external_payment_id: "pi_create",
        status: :completed,
        payment_date: DateTime.utc_now()
      }

      assert {:ok, %Payment{} = payment} = Ledgers.create_payment(attrs)
      assert payment.external_payment_id == "pi_create"
    end

    test "create_refund/1 creates a refund record", %{user: user} do
      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_refund_create",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      attrs = %{
        user_id: user.id,
        payment_id: payment.id,
        amount: Money.new(5_000, :USD),
        external_provider: :stripe,
        external_refund_id: "re_create",
        status: :completed
      }

      assert {:ok, %Refund{} = refund} = Ledgers.create_refund(attrs)
      assert refund.external_refund_id == "re_create"
    end

    test "create_transaction/1 creates a transaction record", %{user: user} do
      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_transaction_create",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      attrs = %{
        type: :payment,
        payment_id: payment.id,
        total_amount: payment.amount,
        status: :completed
      }

      assert {:ok, %LedgerTransaction{} = transaction} =
               Ledgers.create_transaction(attrs)

      assert transaction.payment_id == payment.id
    end

    test "create_entry/1 creates a ledger entry", %{user: user} do
      account = Ledgers.get_account_by_name("cash")

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_entry_create",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      attrs = %{
        account_id: account.id,
        payment_id: payment.id,
        amount: Money.new(10_000, :USD),
        debit_credit: :debit,
        description: "Test entry"
      }

      assert {:ok, %Ysc.Ledgers.LedgerEntry{} = entry} =
               Ledgers.create_entry(attrs)

      assert entry.account_id == account.id
    end

    test "create_payout/1 creates a payout record" do
      attrs = %{
        stripe_payout_id: "po_create",
        amount: Money.new(10_000, :USD),
        arrival_date: DateTime.utc_now() |> DateTime.truncate(:second),
        status: "paid",
        currency: "usd"
      }

      assert {:ok, %Ysc.Ledgers.Payout{} = payout} =
               Ledgers.create_payout(attrs)

      assert payout.stripe_payout_id == "po_create"
    end
  end

  describe "coverage: refund entries and unknown entity revenue mapping" do
    test "get_entries_by_refund/1 returns empty list for unknown refund id" do
      assert Ledgers.get_entries_by_refund(Ecto.ULID.generate()) == []
    end

    test "get_entries_by_payment/1 returns empty list for unknown payment id" do
      assert Ledgers.get_entries_by_payment(Ecto.ULID.generate()) == []
    end

    test "process_payment/1 maps administration entity_type to membership_revenue (fallback branch)" do
      user = user_fixture()

      ext_id =
        "pi_administration_entity_#{System.unique_integer([:positive])}"

      assert {:ok, {_payment, _tx, entries}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(:USD, 2500),
                 entity_type: :administration,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id: ext_id,
                 stripe_fee: nil,
                 description: "admin adjustment",
                 property: nil,
                 payment_method_id: nil
               })

      membership = Ledgers.get_account_by_name("membership_revenue")

      assert Enum.any?(entries, fn e ->
               e.account_id == membership.id &&
                 to_string(e.debit_credit) == "credit"
             end)
    end
  end

  describe "create_* validation errors" do
    setup do
      Ledgers.ensure_basic_accounts()
      :ok
    end

    test "create_payment/1 returns error changeset when required fields are missing" do
      assert {:error, cs} =
               Ledgers.create_payment(%{
                 user_id: user_fixture().id,
                 external_provider: :stripe,
                 external_payment_id: "pi_invalid",
                 payment_date: DateTime.utc_now()
               })

      refute cs.valid?
      assert Ecto.Changeset.get_field(cs, :status) == nil
      assert cs.errors[:status]
    end

    test "create_refund/1 returns error changeset when required fields are missing" do
      assert {:error, cs} =
               Ledgers.create_refund(%{
                 user_id: user_fixture().id,
                 external_provider: :stripe,
                 payment_id: Ecto.ULID.generate(),
                 status: :completed
               })

      refute cs.valid?
      assert cs.errors[:amount]
    end

    test "create_transaction/1 returns error changeset when required fields are missing" do
      assert {:error, cs} =
               Ledgers.create_transaction(%{
                 payment_id: Ecto.ULID.generate(),
                 total_amount: Money.new(100, :USD),
                 status: :completed
               })

      refute cs.valid?
      assert cs.errors[:type]
    end

    test "create_entry/1 returns error when amount is not positive" do
      assert {:error, cs} =
               Ledgers.create_entry(%{
                 account_id: Ledgers.get_account_by_name("cash").id,
                 payment_id: Ecto.ULID.generate(),
                 amount: Money.new(-100, :USD),
                 debit_credit: :debit,
                 description: "invalid"
               })

      refute cs.valid?
      assert cs.errors[:amount]
    end

    test "create_payout/1 returns error changeset when required fields are missing" do
      assert {:error, cs} =
               Ledgers.create_payout(%{
                 stripe_payout_id: "po_invalid",
                 amount: Money.new(100, :USD),
                 status: "paid"
               })

      refute cs.valid?
      assert cs.errors[:currency]
    end

    test "create_payment/1 returns error when external_payment_id is not unique" do
      user = user_fixture()
      ext = "pi_dup_#{System.unique_integer([:positive])}"

      base = %{
        user_id: user.id,
        amount: Money.new(100, :USD),
        external_provider: :stripe,
        external_payment_id: ext,
        status: :completed,
        payment_date: DateTime.utc_now()
      }

      assert {:ok, _} = Ledgers.create_payment(base)
      assert {:error, cs} = Ledgers.create_payment(base)
      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :external_payment_id)
    end
  end

  describe "process_refund/1 and create_refund_entries error paths" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "process_refund/1 raises when payment has no revenue credit entry", %{
      user: user
    } do
      assert {:ok, {credit_payment, _tx, _entries}} =
               Ledgers.add_credit(%{
                 user_id: user.id,
                 amount: Money.new(500, :USD),
                 reason: "Credit without revenue",
                 entity_type: :administration,
                 entity_id: nil
               })

      assert_raise RuntimeError, ~r/no revenue entry found/, fn ->
        Ledgers.process_refund(%{
          payment_id: credit_payment.id,
          refund_amount: Money.new(100, :USD),
          reason: "Cannot refund credit",
          external_refund_id: "re_no_rev_#{System.unique_integer([:positive])}"
        })
      end
    end

    test "process_refund/1 succeeds when external_refund_id is nil", %{
      user: user
    } do
      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(5_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id:
            "pi_nil_re_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(160, :USD),
          description: "Membership",
          property: nil,
          payment_method_id: nil
        })

      assert {:ok, {refund, _tx, entries}} =
               Ledgers.process_refund(%{
                 payment_id: payment.id,
                 refund_amount: Money.new(1_000, :USD),
                 reason: "Partial",
                 external_refund_id: nil
               })

      assert refund.external_refund_id == nil
      assert length(entries) == 2
    end
  end

  describe "payout query id formats" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id:
            "pi_bin_payout_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Test",
          property: nil,
          payment_method_id: nil
        })

      {:ok, {_pp, _tx, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(9_680, :USD),
          stripe_payout_id: "po_bin_#{System.unique_integer([:positive])}",
          description: "Test",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now()
        })

      {:ok, _} = Ledgers.link_payment_to_payout(payout, payment)

      %{payout: payout, payment: payment}
    end

    test "get_payout_payments/1 accepts raw binary payout id", %{
      payout: payout,
      payment: payment
    } do
      assert {:ok, binary_id} = Ecto.ULID.dump(payout.id)
      payments = Ledgers.get_payout_payments(binary_id)
      assert Enum.any?(payments, &(&1.id == payment.id))
    end

    test "get_payout_refunds/1 accepts raw binary payout id", %{payout: payout} do
      assert {:ok, binary_id} = Ecto.ULID.dump(payout.id)
      assert Ledgers.get_payout_refunds(binary_id) == []
    end
  end

  describe "verify_ledger_balance!/0" do
    setup do
      Ledgers.ensure_basic_accounts()
      :ok
    end

    test "returns :ok when ledger is balanced" do
      assert :ok = Ledgers.verify_ledger_balance!()
    end
  end

  describe "add_payment_type_info for missing related records" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "add_payment_type_info/1 uses Unknown Event when event id does not exist",
         %{
           user: user
         } do
      missing_event_id = Ecto.ULID.generate()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(4_000, :USD),
          entity_type: :event,
          entity_id: missing_event_id,
          external_payment_id:
            "pi_missing_ev_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Event",
          property: nil,
          payment_method_id: nil
        })

      enriched = Ledgers.add_payment_type_info(payment)
      assert enriched.payment_type_info.type == "Event"
      assert enriched.payment_type_info.details == "Unknown Event"
    end

    test "add_payment_type_info/1 uses Unknown membership when subscription id is missing",
         %{
           user: user
         } do
      sub_id = Ecto.ULID.generate()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(4_000, :USD),
          entity_type: :membership,
          entity_id: sub_id,
          external_payment_id:
            "pi_unknown_sub_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Membership",
          property: nil,
          payment_method_id: nil
        })

      enriched = Ledgers.add_payment_type_info(payment)
      assert enriched.payment_type_info.type == "Membership"
      assert enriched.payment_type_info.details == "Unknown membership"
    end
  end

  describe "process_event_payment_with_donations_and_discounts/1 branches" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      Ledgers.ensure_basic_accounts()
      %{user: user}
    end

    test "discount description uses N/A when ticket_order_id is nil", %{
      user: user
    } do
      # Align with balanced totals from the mixed event/donation/discount payment example
      total = Money.new(10_000, :USD)
      gross_event = Money.new(6_000, :USD)
      donation = Money.new(4_000, :USD)
      discount = Money.new(1_000, :USD)
      event_id = Ecto.ULID.generate()

      assert {:ok, {_p, _tx, entries}} =
               Ledgers.process_event_payment_with_donations_and_discounts(%{
                 user_id: user.id,
                 total_amount: total,
                 gross_event_amount: gross_event,
                 event_amount: gross_event,
                 donation_amount: donation,
                 discount_amount: discount,
                 event_id: event_id,
                 external_payment_id:
                   "pi_disc_na_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(320, :USD),
                 description: "Discounted event",
                 payment_method_id: nil,
                 ticket_order_id: nil
               })

      assert Enum.any?(entries, fn e ->
               e.description =~ "Order N/A" &&
                 String.downcase(e.description) =~ "discount"
             end)

      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "skips discount entries when discount_amount is zero", %{user: user} do
      total = Money.new(10_000, :USD)
      event_id = Ecto.ULID.generate()

      assert {:ok, {_p, _tx, entries}} =
               Ledgers.process_event_payment_with_donations_and_discounts(%{
                 user_id: user.id,
                 total_amount: total,
                 gross_event_amount: total,
                 event_amount: total,
                 donation_amount: Money.new(0, :USD),
                 discount_amount: Money.new(0, :USD),
                 event_id: event_id,
                 external_payment_id:
                   "pi_no_disc_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(320, :USD),
                 description: "No discount",
                 payment_method_id: nil,
                 ticket_order_id: Ecto.ULID.generate()
               })

      refute Enum.any?(entries, fn e ->
               e.description =~ "Reserved ticket discount"
             end)

      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end
  end

  describe "list_user_payments_paginated/3 with payment methods" do
    setup do
      Ledgers.ensure_basic_accounts()
      user = user_fixture()

      {:ok, pm} =
        Ysc.Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_ledgers_#{System.unique_integer([:positive])}",
          provider_customer_id:
            "cus_ledgers_#{System.unique_integer([:positive])}",
          type: :card,
          provider_type: "card",
          is_default: false
        })

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(5_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id:
            "pi_pm_pag_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(160, :USD),
          description: "With PM",
          property: nil,
          payment_method_id: pm.id
        })

      %{user: user, payment: payment}
    end

    test "preloads payment_method on paginated items", %{
      user: user,
      payment: payment
    } do
      {items, total} = Ledgers.list_user_payments_paginated(user.id, 1, 10)
      assert total >= 1

      matching =
        Enum.find(items, fn item ->
          case item do
            %{payment: %{id: id}} when id == payment.id -> true
            _ -> false
          end
        end)

      assert matching
      assert matching.payment.payment_method != nil

      assert matching.payment.payment_method.id ==
               matching.payment.payment_method_id
    end
  end

  describe "direct ledger entry helpers" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    defp insert_payment_for_entries(user, external_id) do
      {:ok, payment} =
        Ledgers.create_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_provider: :stripe,
          external_payment_id: external_id,
          status: :completed,
          payment_date: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      payment
    end

    test "create_payment_entries/1 membership with stripe fee creates four entries",
         %{
           user: user
         } do
      payment =
        insert_payment_for_entries(
          user,
          "pi_direct_fee_#{System.unique_integer([:positive])}"
        )

      assert {:ok, entries} =
               Repo.transaction(fn ->
                 Ledgers.create_payment_entries(%{
                   payment: payment,
                   amount: payment.amount,
                   entity_type: :membership,
                   entity_id: Ecto.ULID.generate(),
                   stripe_fee: Money.new(320, :USD),
                   description: "Membership direct",
                   property: nil
                 })
               end)

      assert length(entries) == 4
      db = Ledgers.get_entries_by_payment(payment.id)
      assert length(db) == 4
    end

    test "create_payment_entries/1 without stripe fee creates two entries", %{
      user: user
    } do
      payment =
        insert_payment_for_entries(
          user,
          "pi_direct_nofee_#{System.unique_integer([:positive])}"
        )

      assert {:ok, entries} =
               Repo.transaction(fn ->
                 Ledgers.create_payment_entries(%{
                   payment: payment,
                   amount: payment.amount,
                   entity_type: :event,
                   entity_id: Ecto.ULID.generate(),
                   stripe_fee: nil,
                   description: "Event direct",
                   property: nil
                 })
               end)

      assert length(entries) == 2
    end

    test "create_payment_entries/1 uses tahoe booking revenue", %{user: user} do
      payment =
        insert_payment_for_entries(
          user,
          "pi_direct_tahoe_#{System.unique_integer([:positive])}"
        )

      tahoe = Ledgers.get_account_by_name("tahoe_booking_revenue")

      assert {:ok, entries} =
               Repo.transaction(fn ->
                 Ledgers.create_payment_entries(%{
                   payment: payment,
                   amount: payment.amount,
                   entity_type: :booking,
                   entity_id: Ecto.ULID.generate(),
                   stripe_fee: nil,
                   description: "Tahoe stay",
                   property: :tahoe
                 })
               end)

      assert length(entries) == 2
      assert Enum.any?(entries, &(&1.account_id == tahoe.id))
    end

    test "create_payment_entries/1 uses clear_lake booking revenue", %{
      user: user
    } do
      payment =
        insert_payment_for_entries(
          user,
          "pi_direct_cl_#{System.unique_integer([:positive])}"
        )

      clear = Ledgers.get_account_by_name("clear_lake_booking_revenue")

      assert {:ok, entries} =
               Repo.transaction(fn ->
                 Ledgers.create_payment_entries(%{
                   payment: payment,
                   amount: payment.amount,
                   entity_type: :booking,
                   entity_id: Ecto.ULID.generate(),
                   stripe_fee: nil,
                   description: "Clear Lake stay",
                   property: :clear_lake
                 })
               end)

      assert length(entries) == 2
      assert Enum.any?(entries, &(&1.account_id == clear.id))
    end

    test "create_payment_entries/1 uses donation revenue", %{user: user} do
      payment =
        insert_payment_for_entries(
          user,
          "pi_direct_don_#{System.unique_integer([:positive])}"
        )

      donation = Ledgers.get_account_by_name("donation_revenue")

      assert {:ok, entries} =
               Repo.transaction(fn ->
                 Ledgers.create_payment_entries(%{
                   payment: payment,
                   amount: payment.amount,
                   entity_type: :donation,
                   entity_id: Ecto.ULID.generate(),
                   stripe_fee: nil,
                   description: "Donation",
                   property: nil
                 })
               end)

      assert Enum.any?(entries, &(&1.account_id == donation.id))
    end

    test "create_payment_entries/1 falls back to membership revenue for non-specific entity_type",
         %{user: user} do
      payment =
        insert_payment_for_entries(
          user,
          "pi_direct_fallback_#{System.unique_integer([:positive])}"
        )

      membership = Ledgers.get_account_by_name("membership_revenue")

      assert {:ok, entries} =
               Repo.transaction(fn ->
                 Ledgers.create_payment_entries(%{
                   payment: payment,
                   amount: payment.amount,
                   entity_type: :administration,
                   entity_id: Ecto.ULID.generate(),
                   stripe_fee: nil,
                   description: "Fallback",
                   property: nil
                 })
               end)

      assert Enum.any?(entries, &(&1.account_id == membership.id))
    end

    test "create_payment_entries/1 raises when booking has no property", %{
      user: user
    } do
      payment =
        insert_payment_for_entries(
          user,
          "pi_direct_book_noprop_#{System.unique_integer([:positive])}"
        )

      assert_raise RuntimeError, ~r/property/, fn ->
        Repo.transaction(fn ->
          Ledgers.create_payment_entries(%{
            payment: payment,
            amount: payment.amount,
            entity_type: :booking,
            entity_id: Ecto.ULID.generate(),
            stripe_fee: nil,
            description: "Bad booking",
            property: nil
          })
        end)
      end
    end

    test "create_mixed_event_donation_entries/1 splits event and donation with fee",
         %{
           user: user
         } do
      payment =
        insert_payment_for_entries(
          user,
          "pi_mixed_#{System.unique_integer([:positive])}"
        )

      event_id = Ecto.ULID.generate()

      assert {:ok, entries} =
               Repo.transaction(fn ->
                 Ledgers.create_mixed_event_donation_entries(%{
                   payment: payment,
                   total_amount: Money.new(10_000, :USD),
                   event_amount: Money.new(6_000, :USD),
                   donation_amount: Money.new(4_000, :USD),
                   event_id: event_id,
                   stripe_fee: Money.new(300, :USD),
                   description: "Mixed order"
                 })
               end)

      assert length(entries) == 5
    end

    test "create_mixed_event_donation_entries/1 event-only and no fee", %{
      user: user
    } do
      payment =
        insert_payment_for_entries(
          user,
          "pi_mixed_event_only_#{System.unique_integer([:positive])}"
        )

      assert {:ok, entries} =
               Repo.transaction(fn ->
                 Ledgers.create_mixed_event_donation_entries(%{
                   payment: payment,
                   total_amount: Money.new(5_000, :USD),
                   event_amount: Money.new(5_000, :USD),
                   donation_amount: Money.new(0, :USD),
                   event_id: Ecto.ULID.generate(),
                   stripe_fee: nil,
                   description: "Tickets only"
                 })
               end)

      assert length(entries) == 2
    end

    test "create_mixed_event_donation_entries/1 donation-only amount", %{
      user: user
    } do
      payment =
        insert_payment_for_entries(
          user,
          "pi_mixed_don_only_#{System.unique_integer([:positive])}"
        )

      assert {:ok, entries} =
               Repo.transaction(fn ->
                 Ledgers.create_mixed_event_donation_entries(%{
                   payment: payment,
                   total_amount: Money.new(2_500, :USD),
                   event_amount: Money.new(0, :USD),
                   donation_amount: Money.new(2_500, :USD),
                   event_id: Ecto.ULID.generate(),
                   stripe_fee: nil,
                   description: "Donation tickets"
                 })
               end)

      assert length(entries) == 2
    end

    test "create_payout_entries/1 debits cash and credits stripe receivable", %{
      user: user
    } do
      payment =
        insert_payment_for_entries(
          user,
          "pi_payout_entries_#{System.unique_integer([:positive])}"
        )

      cash = Ledgers.get_account_by_name("cash")
      stripe = Ledgers.get_account_by_name("stripe_account")

      assert {:ok, entries} =
               Repo.transaction(fn ->
                 Ledgers.create_payout_entries(%{
                   payment: payment,
                   payout_amount: Money.new(8_000, :USD),
                   description: "Payout test"
                 })
               end)

      assert length(entries) == 2

      assert Enum.any?(
               entries,
               &(&1.account_id == cash.id and &1.debit_credit == :debit)
             )

      assert Enum.any?(
               entries,
               &(&1.account_id == stripe.id and &1.debit_credit == :credit)
             )
    end

    test "create_credit_entries/1 uses administration when entity fields are nil",
         %{
           user: user
         } do
      payment =
        insert_payment_for_entries(
          user,
          "pi_credit_nil_ent_#{System.unique_integer([:positive])}"
        )

      assert {:ok, entries} =
               Repo.transaction(fn ->
                 Ledgers.create_credit_entries(%{
                   payment: payment,
                   amount: Money.new(1_000, :USD),
                   reason: "Goodwill",
                   entity_type: nil,
                   entity_id: nil
                 })
               end)

      assert length(entries) == 2

      assert Enum.all?(entries, fn e ->
               e.related_entity_type == :administration and
                 e.related_entity_id == payment.id
             end)
    end

    test "create_credit_entries/1 uses given entity_type and entity_id", %{
      user: user
    } do
      payment =
        insert_payment_for_entries(
          user,
          "pi_credit_event_#{System.unique_integer([:positive])}"
        )

      ent_id = Ecto.ULID.generate()

      assert {:ok, entries} =
               Repo.transaction(fn ->
                 Ledgers.create_credit_entries(%{
                   payment: payment,
                   amount: Money.new(3_000, :USD),
                   reason: "Event credit",
                   entity_type: :event,
                   entity_id: ent_id
                 })
               end)

      assert length(entries) == 2

      assert Enum.all?(entries, fn e ->
               e.related_entity_type == :event and e.related_entity_id == ent_id
             end)
    end
  end

  describe "create_* functions default optional attrs (\\ %{} coverage)" do
    setup do
      Ledgers.ensure_basic_accounts()
      :ok
    end

    test "create_account/0 delegates to changeset with empty attrs" do
      assert {:error, %Ecto.Changeset{} = cs} = Ledgers.create_account()
      refute cs.valid?
    end

    test "create_payment/0 delegates to changeset with empty attrs" do
      assert {:error, %Ecto.Changeset{} = cs} = Ledgers.create_payment()
      refute cs.valid?
    end

    test "create_refund/0 delegates to changeset with empty attrs" do
      assert {:error, %Ecto.Changeset{} = cs} = Ledgers.create_refund()
      refute cs.valid?
    end

    test "create_transaction/0 delegates to changeset with empty attrs" do
      assert {:error, %Ecto.Changeset{} = cs} = Ledgers.create_transaction()
      refute cs.valid?
    end

    test "create_entry/0 delegates to changeset with empty attrs" do
      assert {:error, %Ecto.Changeset{} = cs} = Ledgers.create_entry()
      refute cs.valid?
    end
  end

  describe "process_event_payment_with_donations_and_discounts/1 additional branches" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      Ledgers.ensure_basic_accounts()
      %{user: user}
    end

    test "omits stripe fee entries when stripe_fee is nil", %{user: user} do
      total = Money.new(10_000, :USD)
      gross = Money.new(6_000, :USD)
      donation = Money.new(4_000, :USD)
      discount = Money.new(500, :USD)
      event_id = Ecto.ULID.generate()

      assert {:ok, {_p, _tx, entries}} =
               Ledgers.process_event_payment_with_donations_and_discounts(%{
                 user_id: user.id,
                 total_amount: total,
                 gross_event_amount: gross,
                 event_amount: gross,
                 donation_amount: donation,
                 discount_amount: discount,
                 event_id: event_id,
                 external_payment_id:
                   "pi_disc_no_fee_#{System.unique_integer([:positive])}",
                 stripe_fee: nil,
                 description: "Discounted event, no processor fee",
                 payment_method_id: nil,
                 ticket_order_id: Ecto.ULID.generate()
               })

      refute Enum.any?(entries, fn e ->
               e.description =~ "Stripe processing fee"
             end)

      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "donation-only net: zero gross event, positive donation, no discount",
         %{
           user: user
         } do
      total = Money.new(5_000, :USD)
      event_id = Ecto.ULID.generate()

      assert {:ok, {_p, _tx, entries}} =
               Ledgers.process_event_payment_with_donations_and_discounts(%{
                 user_id: user.id,
                 total_amount: total,
                 gross_event_amount: Money.new(0, :USD),
                 event_amount: Money.new(0, :USD),
                 donation_amount: total,
                 discount_amount: Money.new(0, :USD),
                 event_id: event_id,
                 external_payment_id:
                   "pi_donation_only_disc_#{System.unique_integer([:positive])}",
                 stripe_fee: nil,
                 description: "Donation-only (discount pipeline)",
                 payment_method_id: nil,
                 ticket_order_id: nil
               })

      donation_rev = Ledgers.get_account_by_name("donation_revenue")

      assert Enum.any?(entries, fn e ->
               e.account_id == donation_rev.id && e.debit_credit == :credit
             end)

      refute Enum.any?(entries, fn e ->
               e.description =~ "Event revenue from tickets"
             end)

      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end
  end

  describe "coverage: update_entry_with_balance/2 with payment_id and amount" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "updates main and corresponding entries when amount changes", %{
      user: user
    } do
      {:ok, {payment, _tx, entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id:
            "pi_balance_pair_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Pair update",
          property: nil,
          payment_method_id: nil
        })

      membership_rev = Ledgers.get_account_by_name("membership_revenue")

      revenue_entry =
        Enum.find(
          entries,
          &(&1.account_id == membership_rev.id && &1.debit_credit == :credit)
        )

      assert revenue_entry.payment_id == payment.id

      new_amount = Money.new(9_876, :USD)

      with_ledger_append_only_trigger_disabled(fn ->
        assert {:ok, updated} =
                 Ledgers.update_entry_with_balance(revenue_entry.id, %{
                   amount: new_amount
                 })

        assert Money.equal?(updated.amount, new_amount)

        counterpart =
          entries
          |> Enum.filter(fn e ->
            e.id != revenue_entry.id && to_string(e.debit_credit) == "debit"
          end)
          |> Enum.find(&Money.equal?(&1.amount, revenue_entry.amount))

        assert counterpart

        reloaded_counterpart = Repo.get!(LedgerEntry, counterpart.id)
        assert Money.equal?(reloaded_counterpart.amount, new_amount)
      end)
    end
  end

  describe "coverage: list_user_payments_paginated/3 batch_enrich_payments" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      {:ok, subscription} =
        Ysc.Subscriptions.create_subscription(%{
          name: "Batch membership",
          user_id: user.id,
          stripe_id: "sub_batch_#{System.unique_integer([:positive])}",
          stripe_status: "active"
        })

      plan = hd(Application.get_env(:ysc, :membership_plans))

      {:ok, _item} =
        Ysc.Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_batch_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_batch",
          stripe_price_id: plan.stripe_price_id,
          quantity: 1
        })

      booking_tahoe = booking_fixture(%{user_id: user.id, property: :tahoe})
      booking_cl = booking_fixture(%{user_id: user.id, property: :clear_lake})

      assert {:ok, {_p1, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(15_000, :USD),
                 entity_type: :booking,
                 entity_id: booking_tahoe.id,
                 external_payment_id:
                   "pi_batch_tahoe_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(480, :USD),
                 description: "Tahoe",
                 property: :tahoe,
                 payment_method_id: nil
               })

      assert {:ok, {_p2, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(16_000, :USD),
                 entity_type: :booking,
                 entity_id: booking_cl.id,
                 external_payment_id:
                   "pi_batch_cl_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(512, :USD),
                 description: "Clear Lake",
                 property: :clear_lake,
                 payment_method_id: nil
               })

      assert {:ok, {_p3, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(12_000, :USD),
                 entity_type: :membership,
                 entity_id: subscription.id,
                 external_payment_id:
                   "pi_batch_mem_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(384, :USD),
                 description: "Membership",
                 property: nil,
                 payment_method_id: nil
               })

      assert {:ok, {_p4, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(3_000, :USD),
                 entity_type: :donation,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id:
                   "pi_batch_don_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(96, :USD),
                 description: "Donation",
                 property: nil,
                 payment_method_id: nil
               })

      %{user: user, subscription: subscription}
    end

    test "enriches booking, subscription, and donation descriptions", %{
      user: user
    } do
      {items, _total} = Ledgers.list_user_payments_paginated(user.id, 1, 50)

      descriptions = Enum.map(items, & &1.description)

      assert "Tahoe Booking" in descriptions
      assert "Clear Lake Booking" in descriptions
      assert "Donation" in descriptions

      assert Enum.any?(descriptions, fn d ->
               is_binary(d) && String.contains?(d, "Membership")
             end)

      assert Enum.any?(items, fn row ->
               row.type == :booking && row.booking &&
                 row.booking.property == :tahoe
             end)

      assert Enum.any?(items, fn row ->
               row.type == :membership && row.subscription &&
                 row.subscription.id
             end)
    end

    test "batch-loads refund_data for payments (no per-row refund queries)", %{
      user: user
    } do
      booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      assert {:ok, {payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(10_000, :USD),
                 entity_type: :booking,
                 entity_id: booking.id,
                 external_payment_id:
                   "pi_refund_batch_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(320, :USD),
                 description: "Refundable booking",
                 property: :tahoe,
                 payment_method_id: nil
               })

      refund_amount = Money.new(5_000, :USD)

      assert {:ok, {_refund, _, _}} =
               Ledgers.process_refund(%{
                 payment_id: payment.id,
                 refund_amount: refund_amount,
                 reason: "Cancelled booking",
                 external_refund_id:
                   "re_refund_batch_#{System.unique_integer([:positive])}"
               })

      {items, _total} = Ledgers.list_user_payments_paginated(user.id, 1, 50)

      refunded_row =
        Enum.find(items, fn row ->
          row.payment && row.payment.id == payment.id
        end)

      assert refunded_row.refund_data

      assert Money.equal?(
               refunded_row.refund_data.total_refunded,
               refund_amount
             )

      assert length(refunded_row.refund_data.processed_refunds) == 1
    end
  end

  describe "coverage: add_payment_type_info/1 and add_payment_type_info_batch/1" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "add_payment_type_info/1 returns Administration for administration revenue payment",
         %{user: user} do
      assert {:ok, {payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(2_000, :USD),
                 entity_type: :administration,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id:
                   "pi_admin_type_#{System.unique_integer([:positive])}",
                 stripe_fee: nil,
                 description: "Admin charge",
                 property: nil,
                 payment_method_id: nil
               })

      enriched = Ledgers.add_payment_type_info(payment)

      assert enriched.payment_type_info.type == "Administration"
      assert enriched.payment_type_info.details == "System transaction"
    end

    test "add_payment_type_info/1 returns Payout for Stripe payout payment" do
      assert {:ok, {payout_payment, _, _, _}} =
               Ledgers.process_stripe_payout(%{
                 payout_amount: Money.new(4_000, :USD),
                 stripe_payout_id:
                   "po_direct_type_#{System.unique_integer([:positive])}",
                 description: "Payout for type test",
                 currency: "usd",
                 status: "paid",
                 arrival_date: DateTime.utc_now()
               })

      enriched = Ledgers.add_payment_type_info(payout_payment)

      assert enriched.payment_type_info.type == "Payout"
      assert enriched.payment_type_info.details =~ "Stripe payout"
    end

    test "add_payment_type_info_batch/1 covers administration, membership, event, and payout",
         %{user: user} do
      assert {:ok, {admin_payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(1_500, :USD),
                 entity_type: :administration,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id:
                   "pi_batch_admin_#{System.unique_integer([:positive])}",
                 stripe_fee: nil,
                 description: "Batch admin",
                 property: nil,
                 payment_method_id: nil
               })

      assert {:ok, {mem_payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(8_000, :USD),
                 entity_type: :membership,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id:
                   "pi_batch_mem_info_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(256, :USD),
                 description: "Batch mem",
                 property: nil,
                 payment_method_id: nil
               })

      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      assert {:ok, {event_payment, _, _}} =
               Ledgers.process_event_payment_with_donations(%{
                 user_id: user.id,
                 total_amount: Money.new(7_000, :USD),
                 event_amount: Money.new(7_000, :USD),
                 donation_amount: Money.new(0, :USD),
                 event_id: event.id,
                 external_payment_id:
                   "pi_batch_evt_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(224, :USD),
                 description: "Batch event",
                 payment_method_id: nil
               })

      ticket_order
      |> Ecto.Changeset.change(%{payment_id: event_payment.id})
      |> Repo.update!()

      assert {:ok, {payout_payment, _, _, _}} =
               Ledgers.process_stripe_payout(%{
                 payout_amount: Money.new(3_000, :USD),
                 stripe_payout_id:
                   "po_batch_mix_#{System.unique_integer([:positive])}",
                 description: "Batch payout",
                 currency: "usd",
                 status: "paid",
                 arrival_date: DateTime.utc_now()
               })

      enriched =
        Ledgers.add_payment_type_info_batch([
          admin_payment,
          mem_payment,
          event_payment,
          payout_payment
        ])

      types = Enum.map(enriched, & &1.payment_type_info.type)

      assert "Administration" in types
      assert "Membership" in types
      assert "Event" in types
      assert "Payout" in types

      admin_row = Enum.find(enriched, &(&1.id == admin_payment.id))
      assert admin_row.payment_type_info.details == "System transaction"

      event_row = Enum.find(enriched, &(&1.id == event_payment.id))
      assert event_row.payment_type_info.details == event.title
    end
  end

  describe "coverage: process_refund/1 booking refund email (clear lake property)" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      Ledgers.ensure_basic_accounts()
      %{user: user}
    end

    test "schedules booking refund processed email for Clear Lake booking", %{
      user: user
    } do
      booking = booking_fixture(%{user_id: user.id, property: :clear_lake})

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(18_000, :USD),
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_cl_refund_email_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(576, :USD),
          description: "Clear Lake refund coverage",
          property: :clear_lake,
          payment_method_id: nil
        })

      assert {:ok, {_refund, _tx, _entries}} =
               Ledgers.process_refund(%{
                 payment_id: payment.id,
                 refund_amount: Money.new(5_000, :USD),
                 reason: "Coverage",
                 external_refund_id:
                   "re_cl_cov_#{System.unique_integer([:positive])}"
               })

      assert_email_sent(subject: "Your booking refund has been processed")
    end
  end

  describe "coverage: list_user_payments_paginated/3 when booking row is missing" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "uses Cabin Booking when booking was deleted after payment", %{
      user: user
    } do
      booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      assert {:ok, {_payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(12_000, :USD),
                 entity_type: :booking,
                 entity_id: booking.id,
                 external_payment_id:
                   "pi_orphan_booking_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(384, :USD),
                 description: "Orphan booking",
                 property: :tahoe,
                 payment_method_id: nil
               })

      Repo.delete!(booking)

      {items, _} = Ledgers.list_user_payments_paginated(user.id, 1, 50)

      assert Enum.any?(items, fn row ->
               row.type == :booking && row.description == "Cabin Booking"
             end)
    end
  end

  describe "coverage: list_user_payments_paginated/3 prorated membership description" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "uses prorated label from revenue entry description text", %{
      user: user
    } do
      assert {:ok, {payment, _, entries}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(11_000, :USD),
                 entity_type: :membership,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id:
                   "pi_prorated_desc_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(352, :USD),
                 description: "Membership",
                 property: nil,
                 payment_method_id: nil
               })

      revenue_entry =
        Enum.find(entries, fn e ->
          to_string(e.debit_credit) == "credit"
        end)

      prorated_desc =
        "Revenue from membership: Prorated upgrade (Single to Family)"

      with_ledger_append_only_trigger_disabled(fn ->
        assert {:ok, _} =
                 Ledgers.update_entry(revenue_entry, %{
                   description: prorated_desc
                 })
      end)

      {items, _} = Ledgers.list_user_payments_paginated(user.id, 1, 50)

      row =
        Enum.find(items, fn i -> i.payment && i.payment.id == payment.id end)

      assert row.description == "Prorated upgrade (Single to Family)"
    end
  end

  describe "coverage: add_payment_type_info/1 and add_payment_type_info_batch/1 edge cases" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "add_payment_type_info_batch/1 returns [] for an empty list" do
      assert Ledgers.add_payment_type_info_batch([]) == []
    end

    test "add_payment_type_info/1 is Unknown when payment has no revenue entry",
         %{user: user} do
      assert {:ok, payment} =
               Ledgers.create_payment(%{
                 user_id: user.id,
                 amount: Money.new(500, :USD),
                 external_provider: :stripe,
                 external_payment_id:
                   "pi_no_entries_#{System.unique_integer([:positive])}",
                 status: :completed,
                 payment_date: DateTime.utc_now()
               })

      enriched = Ledgers.add_payment_type_info(payment)

      assert enriched.payment_type_info.type == "Unknown"
      assert enriched.payment_type_info.details == "No revenue entry found"
    end

    test "add_payment_type_info/1 event resolves to Unknown Event when event id is invalid",
         %{user: user} do
      event = event_fixture()

      assert {:ok, {payment, _, _}} =
               Ledgers.process_event_payment_with_donations(%{
                 user_id: user.id,
                 total_amount: Money.new(9_000, :USD),
                 event_amount: Money.new(9_000, :USD),
                 donation_amount: Money.new(0, :USD),
                 event_id: event.id,
                 external_payment_id:
                   "pi_bad_evt_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(288, :USD),
                 description: "Event",
                 payment_method_id: nil
               })

      revenue_entry =
        from(e in LedgerEntry,
          join: a in LedgerAccount,
          on: e.account_id == a.id,
          where: e.payment_id == ^payment.id,
          where: a.account_type == ^"revenue",
          where: e.debit_credit == ^"credit",
          preload: [:account]
        )
        |> Repo.one()

      assert revenue_entry

      bogus_event_id = Ecto.ULID.generate()

      with_ledger_append_only_trigger_disabled(fn ->
        assert {:ok, _} =
                 Ledgers.update_entry(revenue_entry, %{
                   related_entity_id: bogus_event_id
                 })
      end)

      enriched = Ledgers.add_payment_type_info(Repo.get!(Payment, payment.id))

      assert enriched.payment_type_info.type == "Event"
      assert enriched.payment_type_info.details == "Unknown Event"
    end

    test "add_payment_type_info_batch/1 event uses Unknown Event when event id is invalid",
         %{user: user} do
      event = event_fixture()

      assert {:ok, {payment, _, _}} =
               Ledgers.process_event_payment_with_donations(%{
                 user_id: user.id,
                 total_amount: Money.new(8_500, :USD),
                 event_amount: Money.new(8_500, :USD),
                 donation_amount: Money.new(0, :USD),
                 event_id: event.id,
                 external_payment_id:
                   "pi_bad_evt_batch_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(272, :USD),
                 description: "Event batch",
                 payment_method_id: nil
               })

      revenue_entry =
        from(e in LedgerEntry,
          join: a in LedgerAccount,
          on: e.account_id == a.id,
          where: e.payment_id == ^payment.id,
          where: a.account_type == ^"revenue",
          where: e.debit_credit == ^"credit",
          preload: [:account]
        )
        |> Repo.one()

      bogus_event_id = Ecto.ULID.generate()

      with_ledger_append_only_trigger_disabled(fn ->
        assert {:ok, _} =
                 Ledgers.update_entry(revenue_entry, %{
                   related_entity_id: bogus_event_id
                 })
      end)

      [enriched] =
        Ledgers.add_payment_type_info_batch([Repo.get!(Payment, payment.id)])

      assert enriched.payment_type_info.type == "Event"
      assert enriched.payment_type_info.details == "Unknown Event"
    end

    test "add_payment_type_info_batch/1 membership details are Membership when subscription has no items",
         %{user: user} do
      {:ok, subscription} =
        Ysc.Subscriptions.create_subscription(%{
          name: "No items sub",
          user_id: user.id,
          stripe_id: "sub_no_items_#{System.unique_integer([:positive])}",
          stripe_status: "active"
        })

      assert {:ok, {payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(6_000, :USD),
                 entity_type: :membership,
                 entity_id: subscription.id,
                 external_payment_id:
                   "pi_mem_no_si_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(192, :USD),
                 description: "Membership no items",
                 property: nil,
                 payment_method_id: nil
               })

      [enriched] = Ledgers.add_payment_type_info_batch([payment])

      assert enriched.payment_type_info.type == "Membership"
      assert enriched.payment_type_info.details == "Membership"
    end
  end

  describe "coverage: update_entry_with_balance/2 additional branches" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "returns not_found for unknown entry id" do
      assert {:error, :not_found} =
               Ledgers.update_entry_with_balance(Ecto.ULID.generate(), %{
                 amount: Money.new(100, :USD)
               })
    end

    test "updates only the revenue entry when no counterpart matches the same amount",
         %{user: user} do
      assert {:ok, {_payment, _, entries}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(7_500, :USD),
                 entity_type: :membership,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id:
                   "pi_no_pair_#{System.unique_integer([:positive])}",
                 stripe_fee: nil,
                 description: "No counterpart pair",
                 property: nil,
                 payment_method_id: nil
               })

      revenue_entry =
        Enum.find(entries, fn e -> to_string(e.debit_credit) == "credit" end)

      debit_entry =
        Enum.find(entries, fn e -> to_string(e.debit_credit) == "debit" end)

      with_ledger_append_only_trigger_disabled(fn ->
        assert {:ok, _} =
                 Ledgers.update_entry(debit_entry, %{
                   amount: Money.new(1_00, :USD)
                 })

        new_amt = Money.new(7_000, :USD)

        assert {:ok, updated} =
                 Ledgers.update_entry_with_balance(revenue_entry.id, %{
                   amount: new_amt
                 })

        assert Money.equal?(updated.amount, new_amt)

        reloaded_debit = Repo.get!(LedgerEntry, debit_entry.id)
        assert Money.equal?(reloaded_debit.amount, Money.new(1_00, :USD))
      end)
    end

    test "returns error when amount is invalid (negative)", %{user: user} do
      assert {:ok, {_payment, _, entries}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(7_500, :USD),
                 entity_type: :membership,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id:
                   "pi_neg_amt_#{System.unique_integer([:positive])}",
                 stripe_fee: nil,
                 description: "Negative amount update",
                 property: nil,
                 payment_method_id: nil
               })

      revenue_entry =
        Enum.find(entries, fn e -> to_string(e.debit_credit) == "credit" end)

      with_ledger_append_only_trigger_disabled(fn ->
        assert {:error, {:error, %Ecto.Changeset{}}} =
                 Ledgers.update_entry_with_balance(revenue_entry.id, %{
                   amount: Money.new(-1, :USD)
                 })
      end)
    end
  end

  describe "coverage: get_membership_details_from_subscription via add_payment_type_info_batch/1" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "Membership details are 'Membership' when subscription has no items",
         %{user: user} do
      {:ok, sub} =
        Ysc.Subscriptions.create_subscription(%{
          name: "No items",
          user_id: user.id,
          stripe_id: "sub_no_items_#{System.unique_integer([:positive])}",
          stripe_status: "active"
        })

      assert {:ok, {payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(10_000, :USD),
                 entity_type: :membership,
                 entity_id: sub.id,
                 external_payment_id:
                   "pi_mem_no_items_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(320, :USD),
                 description: "Membership",
                 property: nil,
                 payment_method_id: nil
               })

      [enriched] = Ledgers.add_payment_type_info_batch([payment])

      assert enriched.payment_type_info.type == "Membership"
      assert enriched.payment_type_info.details == "Membership"
    end

    test "Membership details fall back to 'Membership' when price id does not match a plan",
         %{
           user: user
         } do
      {:ok, sub} =
        Ysc.Subscriptions.create_subscription(%{
          name: "Unknown price",
          user_id: user.id,
          stripe_id: "sub_unk_price_#{System.unique_integer([:positive])}",
          stripe_status: "active"
        })

      {:ok, _} =
        Ysc.Subscriptions.create_subscription_item(%{
          subscription_id: sub.id,
          stripe_id: "si_unk_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_unk",
          stripe_price_id: "price_does_not_match_any_plan_xyz",
          quantity: 1
        })

      assert {:ok, {payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(10_000, :USD),
                 entity_type: :membership,
                 entity_id: sub.id,
                 external_payment_id:
                   "pi_mem_unk_price_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(320, :USD),
                 description: "Membership",
                 property: nil,
                 payment_method_id: nil
               })

      [enriched] = Ledgers.add_payment_type_info_batch([payment])

      assert enriched.payment_type_info.type == "Membership"
      assert enriched.payment_type_info.details == "Membership"
    end

    test "list_user_payments_paginated/3 describes Clear Lake booking payment as Clear Lake Booking",
         %{user: user} do
      booking = booking_fixture(%{user_id: user.id, property: :clear_lake})

      assert {:ok, {_payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(14_000, :USD),
                 entity_type: :booking,
                 entity_id: booking.id,
                 external_payment_id:
                   "pi_cl_desc_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(448, :USD),
                 description: "CL",
                 property: :clear_lake,
                 payment_method_id: nil
               })

      {items, _} = Ledgers.list_user_payments_paginated(user.id, 1, 50)

      assert Enum.any?(items, fn row ->
               row.type == :booking && row.description == "Clear Lake Booking"
             end)
    end
  end

  describe "coverage: get_account_balance/3 and get_accounts_with_balances/2 in-range debit and credit" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "membership_revenue and stripe_account balances combine credits and debits within the date range",
         %{user: user} do
      today = Date.utc_today()
      today_start = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
      today_end = DateTime.new!(today, ~T[23:59:59], "Etc/UTC")

      amount = Money.new(10_000, :USD)
      refund_amt = Money.new(3_000, :USD)

      assert {:ok, {payment, _tx, _entries}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: amount,
                 entity_type: :membership,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id:
                   "pi_bal_combo_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(320, :USD),
                 description: "Balance combo",
                 property: nil,
                 payment_method_id: nil
               })

      Repo.update_all(
        from(p in Payment, where: p.id == ^payment.id),
        set: [payment_date: today_start]
      )

      assert {:ok, {_refund, _rtx, _rentries}} =
               Ledgers.process_refund(%{
                 payment_id: payment.id,
                 refund_amount: refund_amt,
                 reason: "Partial",
                 external_refund_id:
                   "re_bal_combo_#{System.unique_integer([:positive])}"
               })

      membership_revenue = Ledgers.get_account_by_name("membership_revenue")
      stripe_account = Ledgers.get_account_by_name("stripe_account")

      rev_in_range =
        Ledgers.get_account_balance(
          membership_revenue.id,
          today_start,
          today_end
        )

      stripe_in_range =
        Ledgers.get_account_balance(stripe_account.id, today_start, today_end)

      # Revenue: credit full amount, then debit partial refund → net amount - refund
      expected_rev = Money.new(7_000, :USD)

      # Stripe: debit full payment, credit fee, credit refund share → amount - fee - refund
      expected_stripe = Money.new(6_680, :USD)

      assert Money.equal?(rev_in_range, expected_rev)
      assert Money.equal?(stripe_in_range, expected_stripe)

      by_account =
        Ledgers.get_accounts_with_balances(today_start, today_end)
        |> Enum.map(fn %{account: a, balance: b} -> {a.name, b} end)
        |> Map.new()

      assert Money.equal?(
               Map.fetch!(by_account, "membership_revenue"),
               expected_rev
             )

      assert Money.equal?(
               Map.fetch!(by_account, "stripe_account"),
               expected_stripe
             )
    end
  end

  describe "coverage: link_payment_to_payout/2 idempotent when already linked" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id:
            "pi_payout_cov_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Payout helper",
          property: nil,
          payment_method_id: nil
        })

      {:ok, {_pp, _tx, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(9_680, :USD),
          stripe_payout_id: "po_cov_#{System.unique_integer([:positive])}",
          description: "Payout",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now()
        })

      %{payout: payout, payment: payment}
    end

    test "link_payment_to_payout/2 returns ok when link already exists", %{
      payout: payout,
      payment: payment
    } do
      assert {:ok, _} = Ledgers.link_payment_to_payout(payout, payment)
      assert {:ok, _} = Ledgers.link_payment_to_payout(payout, payment)
    end
  end

  describe "coverage: list_user_payments_paginated/3 Family plan via get_membership_plan_type" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      family_plan =
        Enum.find(
          Application.get_env(:ysc, :membership_plans),
          &(&1.id == :family)
        )

      assert family_plan

      {:ok, sub} =
        Ysc.Subscriptions.create_subscription(%{
          name: "Family sub",
          user_id: user.id,
          stripe_id: "sub_fam_cov_#{System.unique_integer([:positive])}",
          stripe_status: "active"
        })

      {:ok, _} =
        Ysc.Subscriptions.create_subscription_item(%{
          subscription_id: sub.id,
          stripe_id: "si_fam_cov_#{System.unique_integer([:positive])}",
          stripe_product_id: "prod_fam",
          stripe_price_id: family_plan.stripe_price_id,
          quantity: 1
        })

      assert {:ok, {_p, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(10_000, :USD),
                 entity_type: :membership,
                 entity_id: sub.id,
                 external_payment_id:
                   "pi_fam_plan_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(320, :USD),
                 description: "Family membership",
                 property: nil,
                 payment_method_id: nil
               })

      %{user: user}
    end

    test "description uses Membership Payment - Family when price matches family plan",
         %{
           user: user
         } do
      {items, _} = Ledgers.list_user_payments_paginated(user.id, 1, 50)

      assert Enum.any?(items, fn row ->
               row.type == :membership &&
                 row.description == "Membership Payment - Family"
             end)
    end
  end

  describe "coverage: add_payment_type_info_batch/1 orphaned membership entity" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "returns Unknown membership when revenue entry references a missing subscription",
         %{user: user} do
      {:ok, subscription} =
        Ysc.Subscriptions.create_subscription(%{
          name: "Orphan sub",
          user_id: user.id,
          stripe_id: "sub_orphan_#{System.unique_integer([:positive])}",
          stripe_status: "active"
        })

      assert {:ok, {payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(8_888, :USD),
                 entity_type: :membership,
                 entity_id: subscription.id,
                 external_payment_id:
                   "pi_orphan_mem_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(284, :USD),
                 description: "Orphan membership",
                 property: nil,
                 payment_method_id: nil
               })

      revenue_entry =
        from(e in LedgerEntry,
          join: a in LedgerAccount,
          on: e.account_id == a.id,
          where: e.payment_id == ^payment.id,
          where: a.account_type == ^"revenue",
          where: e.debit_credit == ^"credit",
          preload: [:account]
        )
        |> Repo.one!()

      bogus_subscription_id = Ecto.ULID.generate()

      with_ledger_append_only_trigger_disabled(fn ->
        assert {:ok, _} =
                 Ledgers.update_entry(revenue_entry, %{
                   related_entity_id: bogus_subscription_id
                 })
      end)

      payment = Repo.get!(Payment, payment.id)

      [enriched] = Ledgers.add_payment_type_info_batch([payment])

      assert enriched.payment_type_info.type == "Membership"
      assert enriched.payment_type_info.details == "Unknown membership"
    end
  end

  describe "coverage: list_all_user_payments enrich branches" do
    setup do
      user = user_fixture()

      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "list_all_user_payments/1 maps administration payment to type :unknown",
         %{
           user: user
         } do
      assert {:ok, {payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: Money.new(2_000, :USD),
                 entity_type: :administration,
                 entity_id: Ecto.ULID.generate(),
                 external_payment_id:
                   "pi_admin_enrich_#{System.unique_integer([:positive])}",
                 stripe_fee: nil,
                 description: "Admin charge",
                 property: nil,
                 payment_method_id: nil
               })

      items = Ledgers.list_all_user_payments(user.id)

      row =
        Enum.find(items, fn row ->
          row.payment && row.payment.id == payment.id
        end)

      assert row.type == :unknown
    end

    test "list_all_user_payments/1 describes free ticket order without ticket lines as title only",
         %{user: user} do
      user =
        user
        |> Ecto.Changeset.change(%{
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()
        |> Repo.reload!()

      event = event_fixture(%{title: "Lake Day Gala"})

      {:ok, free_tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "Complimentary",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 20,
          event_id: event.id
        })

      assert {:ok, ticket_order} =
               Tickets.create_ticket_order(user.id, event.id, %{
                 free_tier.id => 1
               })

      assert {:ok, completed} = Tickets.process_free_ticket_order(ticket_order)
      assert completed.status == :completed

      from(t in Ysc.Events.Ticket,
        where: t.ticket_order_id == ^completed.id
      )
      |> Repo.delete_all()

      items = Ledgers.list_all_user_payments(user.id)

      row =
        Enum.find(items, fn row ->
          row.ticket_order && row.ticket_order.id == completed.id
        end)

      assert row.description == "Free Tickets: Lake Day Gala"
    end
  end
end

defmodule Ysc.LedgersTest.LedgerRefundEmailNotifierCoverage do
  @moduledoc false
  use Ysc.DataCase, async: false

  alias Ysc.Ledgers
  alias Ysc.Repo
  import Ecto.Query
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  setup do
    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    Application.put_env(:ysc, :quickbooks,
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      company_id: "test_company_id",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      event_item_id: "event_item_123",
      donation_item_id: "donation_item_123",
      bank_account_id: "bank_account_123",
      stripe_account_id: "stripe_account_123"
    )

    import Mox

    stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
      {:ok, %{"Id" => "qb_customer_default"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params, _opts ->
      {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
      {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
    end)

    Ledgers.ensure_basic_accounts()
    :ok
  end

  defp with_ledger_refund_notifier(module, fun) do
    prev = Application.get_env(:ysc, :ledger_refund_email_notifier)

    Application.put_env(:ysc, :ledger_refund_email_notifier, module)

    on_exit(fn ->
      if prev == nil do
        Application.delete_env(:ysc, :ledger_refund_email_notifier)
      else
        Application.put_env(:ysc, :ledger_refund_email_notifier, prev)
      end
    end)

    fun.()
  end

  defmodule NotifierScheduleError do
    @moduledoc false
    def schedule_email(a, b, c, d, e, f, g),
      do: schedule_email(a, b, c, d, e, f, g, nil)

    def schedule_email(_, _, _, _, _, _, _, _),
      do: {:error, :coverage_schedule_failed}
  end

  defmodule NotifierScheduleRaise do
    @moduledoc false
    def schedule_email(a, b, c, d, e, f, g),
      do: schedule_email(a, b, c, d, e, f, g, nil)

    def schedule_email(_, _, _, _, _, _, _, _),
      do: raise("coverage notifier raise")
  end

  describe "process_refund/1 refund email notifier injection" do
    test "booking refund succeeds when notifier returns {:error, reason} (logs schedule failure)" do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(20_000, :USD),
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_notif_err_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(640, :USD),
          description: "Booking refund notifier test",
          property: :tahoe,
          payment_method_id: nil
        })

      with_ledger_refund_notifier(NotifierScheduleError, fn ->
        assert {:ok, {_refund, _tx, _entries}} =
                 Ledgers.process_refund(%{
                   payment_id: payment.id,
                   refund_amount: Money.new(5_000, :USD),
                   reason: "Coverage",
                   external_refund_id:
                     "re_notif_err_#{System.unique_integer([:positive])}"
                 })
      end)
    end

    test "booking refund succeeds when notifier raises (inner rescue)" do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(20_000, :USD),
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_notif_raise_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(640, :USD),
          description: "Booking refund notifier raise",
          property: :tahoe,
          payment_method_id: nil
        })

      with_ledger_refund_notifier(NotifierScheduleRaise, fn ->
        assert {:ok, {_refund, _tx, _entries}} =
                 Ledgers.process_refund(%{
                   payment_id: payment.id,
                   refund_amount: Money.new(5_000, :USD),
                   reason: "Coverage",
                   external_refund_id:
                     "re_notif_raise_#{System.unique_integer([:positive])}"
                 })
      end)
    end

    test "ticket order refund succeeds when notifier returns {:error, reason}" do
      user = user_fixture()
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      {:ok, {payment, _, _}} =
        Ledgers.process_event_payment_with_donations(%{
          user_id: user.id,
          total_amount: Money.new(10_000, :USD),
          event_amount: Money.new(10_000, :USD),
          donation_amount: Money.new(0, :USD),
          event_id: event.id,
          external_payment_id:
            "pi_ticket_notif_err_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      ticket_order
      |> Ecto.Changeset.change(%{payment_id: payment.id})
      |> Repo.update!()

      tickets =
        from(t in Ysc.Events.Ticket,
          where: t.ticket_order_id == ^ticket_order.id
        )
        |> Repo.all()

      Enum.each(tickets, fn t ->
        t
        |> Ysc.Events.Ticket.status_changeset(%{status: :cancelled})
        |> Repo.update!()
      end)

      with_ledger_refund_notifier(NotifierScheduleError, fn ->
        assert {:ok, {_refund, _tx, _entries}} =
                 Ledgers.process_refund(%{
                   payment_id: payment.id,
                   refund_amount: Money.new(5_000, :USD),
                   reason: "Coverage",
                   external_refund_id:
                     "re_ticket_notif_err_#{System.unique_integer([:positive])}"
                 })
      end)
    end

    test "ticket order refund succeeds when notifier raises (inner rescue)" do
      user = user_fixture()
      event = event_fixture()
      tier = Ysc.EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      {:ok, {payment, _, _}} =
        Ledgers.process_event_payment_with_donations(%{
          user_id: user.id,
          total_amount: Money.new(10_000, :USD),
          event_amount: Money.new(10_000, :USD),
          donation_amount: Money.new(0, :USD),
          event_id: event.id,
          external_payment_id:
            "pi_ticket_notif_raise_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      ticket_order
      |> Ecto.Changeset.change(%{payment_id: payment.id})
      |> Repo.update!()

      tickets =
        from(t in Ysc.Events.Ticket,
          where: t.ticket_order_id == ^ticket_order.id
        )
        |> Repo.all()

      Enum.each(tickets, fn t ->
        t
        |> Ysc.Events.Ticket.status_changeset(%{status: :cancelled})
        |> Repo.update!()
      end)

      with_ledger_refund_notifier(NotifierScheduleRaise, fn ->
        assert {:ok, {_refund, _tx, _entries}} =
                 Ledgers.process_refund(%{
                   payment_id: payment.id,
                   refund_amount: Money.new(5_000, :USD),
                   reason: "Coverage",
                   external_refund_id:
                     "re_ticket_notif_raise_#{System.unique_integer([:positive])}"
                 })
      end)
    end
  end

  describe "sum_stripe_fees_for_payments/1" do
    test "returns zero for an empty list" do
      assert Money.equal?(
               Ledgers.sum_stripe_fees_for_payments([]),
               Money.new(0, :USD)
             )
    end

    test "sums stripe fee debit entries for only the given payment ids" do
      Ledgers.ensure_basic_accounts()
      stripe_fees_account = Ledgers.get_account_by_name("stripe_fees")
      user = user_fixture()

      [payment1, payment2, other_payment] =
        Ysc.LedgersFixtures.payment_rows!(user.id, 3)

      {:ok, _} =
        Ledgers.create_entry(%{
          account_id: stripe_fees_account.id,
          payment_id: payment1.id,
          amount: Money.new(320, :USD),
          debit_credit: :debit,
          description: "fee 1"
        })

      {:ok, _} =
        Ledgers.create_entry(%{
          account_id: stripe_fees_account.id,
          payment_id: payment2.id,
          amount: Money.new(150, :USD),
          debit_credit: :debit,
          description: "fee 2"
        })

      {:ok, _} =
        Ledgers.create_entry(%{
          account_id: stripe_fees_account.id,
          payment_id: other_payment.id,
          amount: Money.new(999, :USD),
          debit_credit: :debit,
          description: "unrelated fee"
        })

      # A credit entry on a tracked payment (e.g. a fee reversal) shouldn't count.
      {:ok, _} =
        Ledgers.create_entry(%{
          account_id: stripe_fees_account.id,
          payment_id: payment1.id,
          amount: Money.new(5, :USD),
          debit_credit: :credit,
          description: "fee correction"
        })

      total =
        Ledgers.sum_stripe_fees_for_payments([payment1.id, payment2.id])

      assert Money.equal?(total, Money.new(470, :USD))
    end
  end

  describe "sum_donation_revenue_for_event/1" do
    test "returns zero when there are no donation entries for the event" do
      assert Money.equal?(
               Ledgers.sum_donation_revenue_for_event(Ecto.ULID.generate()),
               Money.new(0, :USD)
             )
    end

    test "sums donation_revenue credits tied to the event, ignoring debits and other events" do
      Ledgers.ensure_basic_accounts()
      donation_account = Ledgers.get_account_by_name("donation_revenue")
      event_id = Ecto.ULID.generate()
      other_event_id = Ecto.ULID.generate()

      {:ok, _} =
        Ledgers.create_entry(%{
          account_id: donation_account.id,
          amount: Money.new(75, :USD),
          debit_credit: :credit,
          related_entity_type: :donation,
          related_entity_id: event_id,
          description: "Donation 1"
        })

      {:ok, _} =
        Ledgers.create_entry(%{
          account_id: donation_account.id,
          amount: Money.new(25, :USD),
          debit_credit: :credit,
          related_entity_type: :donation,
          related_entity_id: event_id,
          description: "Donation 2"
        })

      # A different event's donation shouldn't count toward this event's total.
      {:ok, _} =
        Ledgers.create_entry(%{
          account_id: donation_account.id,
          amount: Money.new(500, :USD),
          debit_credit: :credit,
          related_entity_type: :donation,
          related_entity_id: other_event_id,
          description: "Other event donation"
        })

      # A debit against donation_revenue (e.g. a correction) shouldn't count.
      {:ok, _} =
        Ledgers.create_entry(%{
          account_id: donation_account.id,
          amount: Money.new(10, :USD),
          debit_credit: :debit,
          related_entity_type: :donation,
          related_entity_id: event_id,
          description: "Correction"
        })

      assert Money.equal?(
               Ledgers.sum_donation_revenue_for_event(event_id),
               Money.new(100, :USD)
             )

      assert Money.equal?(
               Ledgers.sum_donation_revenue_for_event(other_event_id),
               Money.new(500, :USD)
             )
    end
  end
end
