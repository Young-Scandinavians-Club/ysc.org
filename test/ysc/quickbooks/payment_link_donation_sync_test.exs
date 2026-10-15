defmodule Ysc.Quickbooks.PaymentLinkDonationSyncTest do
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures

  alias Ysc.Ledgers
  alias Ysc.Quickbooks.ClientMock
  alias Ysc.Quickbooks.Sync
  alias Ysc.Repo

  setup :verify_on_exit!

  setup do
    Cachex.clear(:ysc_cache)
    Ledgers.ensure_basic_accounts()

    Application.put_env(:ysc, :quickbooks_client, ClientMock)

    Application.put_env(:ysc, :quickbooks,
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      company_id: "test_company_id",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      donation_item_id: "donation_item_123",
      bank_account_id: "bank_account_123",
      stripe_account_id: "stripe_account_123"
    )

    user = user_fixture()
    %{user: user}
  end

  test "posts a payment-link donation to its own income account", %{user: user} do
    stub_common_quickbooks()

    stub(ClientMock, :query_account_by_name, fn
      "Undeposited Funds" ->
        {:ok, "undeposited_funds"}

      "Tahoe Kitchen Fund" ->
        {:ok, "tahoe_kitchen_fund"}

      "Special Project Fundraising" ->
        send(self(), :used_special_project_fundraising)
        {:ok, "special_project"}

      _ ->
        {:error, :not_found}
    end)

    stub(ClientMock, :get_or_create_item, fn name, opts ->
      send(self(), {:item, name, opts})
      {:ok, "plink_item_77"}
    end)

    stub(ClientMock, :get_item_by_id, fn "plink_item_77" ->
      {:ok,
       %{
         "Id" => "plink_item_77",
         "Name" => "Tahoe Kitchen Fund",
         "IncomeAccountRef" => %{"value" => "tahoe_kitchen_fund"}
       }}
    end)

    stub(ClientMock, :create_sales_receipt, fn params, _opts ->
      send(self(), {:receipt, params})
      {:ok, %{"Id" => "sr_plink", "TotalAmt" => "50.00"}}
    end)

    {:ok, {payment, _transaction, _entries}} = book_payment_link_donation(user)

    payment = Repo.reload!(payment)
    assert payment.quickbooks_sync_status == "synced"
    assert payment.quickbooks_sales_receipt_id == "sr_plink"

    assert_received {:item, "Tahoe Kitchen Fund", item_opts}

    assert item_opts[:income_account_ref] == %{
             value: "tahoe_kitchen_fund",
             name: "Tahoe Kitchen Fund"
           }

    assert_received {:receipt, params}

    item_ref =
      params.line
      |> List.first()
      |> get_in([:sales_item_line_detail, :item_ref, :value])

    assert item_ref == "plink_item_77"
    refute item_ref == "donation_item_123"

    class_ref =
      params.line
      |> List.first()
      |> get_in([:sales_item_line_detail, :class_ref])

    assert class_ref == %{name: "Administration", value: "admin_class"}

    description = params.line |> List.first() |> Map.get(:description)
    assert description =~ "Tahoe Kitchen Fund"
    refute_received :used_special_project_fundraising
  end

  test "does not repoint an existing item onto the fund account", %{user: user} do
    stub_common_quickbooks()

    stub(ClientMock, :query_account_by_name, fn
      "Undeposited Funds" -> {:ok, "undeposited_funds"}
      "Tahoe Kitchen Fund" -> {:ok, "tahoe_kitchen_fund"}
      _ -> {:error, :not_found}
    end)

    stub(ClientMock, :get_or_create_item, fn _name, _opts ->
      {:ok, "plink_item_77"}
    end)

    stub(ClientMock, :get_item_by_id, fn "plink_item_77" ->
      {:ok,
       %{
         "Id" => "plink_item_77",
         "IncomeAccountRef" => %{"value" => "special_project_fundraising"}
       }}
    end)

    stub(ClientMock, :update_item_income_account, fn item_id, account_ref ->
      send(self(), {:updated_account, item_id, account_ref})
      {:ok, %{"Id" => item_id}}
    end)

    stub(ClientMock, :create_sales_receipt, fn params, _opts ->
      send(self(), {:receipt, params})
      {:ok, %{"Id" => "sr_plink", "TotalAmt" => "50.00"}}
    end)

    {:ok, {payment, _, _}} = book_payment_link_donation(user)

    assert {:error, :payment_link_item_income_account_mismatch} =
             Sync.sync_payment(payment)

    payment = Repo.reload!(payment)
    assert payment.quickbooks_sync_status == "failed"
    refute_received {:receipt, _}
  end

  test "creates the QuickBooks income account and item when the payment-link account does not exist yet",
       %{user: user} do
    stub_common_quickbooks()

    stub(ClientMock, :query_account_by_name, fn
      "Undeposited Funds" -> {:ok, "undeposited_funds"}
      "Special Project Fundraising" -> {:ok, "special_project"}
      "Sauna Roof Fund" -> {:error, :not_found}
      _ -> {:error, :not_found}
    end)

    stub(ClientMock, :create_account, fn name, opts ->
      send(self(), {:created_account, name, opts})
      {:ok, "sauna_roof_account_id"}
    end)

    stub(ClientMock, :get_or_create_item, fn name, opts ->
      send(self(), {:item, name, opts})
      {:ok, "sauna_roof_item_id"}
    end)

    stub(ClientMock, :get_item_by_id, fn "sauna_roof_item_id" ->
      {:ok,
       %{
         "Id" => "sauna_roof_item_id",
         "Name" => "Sauna Roof Fund",
         "IncomeAccountRef" => %{"value" => "sauna_roof_account_id"}
       }}
    end)

    stub(ClientMock, :create_sales_receipt, fn params, _opts ->
      send(self(), {:receipt, params})
      {:ok, %{"Id" => "sr_sauna", "TotalAmt" => "50.00"}}
    end)

    {:ok, {payment, _, _}} = book_payment_link_donation(user, "Sauna Roof Fund")

    payment = Repo.reload!(payment)
    assert payment.quickbooks_sync_status == "synced"
    assert payment.quickbooks_sales_receipt_id == "sr_sauna"

    assert_received {:created_account, "Sauna Roof Fund",
                     [
                       account_type: "Income",
                       account_sub_type: "NonProfitIncome"
                     ]}

    assert_received {:item, "Sauna Roof Fund", item_opts}

    assert item_opts[:income_account_ref] == %{
             value: "sauna_roof_account_id",
             name: "Sauna Roof Fund"
           }

    assert_received {:receipt, _params}
  end

  test "does not fall back to Special Project Fundraising when creating the payment-link account fails",
       %{user: user} do
    stub_common_quickbooks()

    stub(ClientMock, :query_account_by_name, fn
      "Undeposited Funds" -> {:ok, "undeposited_funds"}
      "Special Project Fundraising" -> {:ok, "special_project"}
      "Tahoe Kitchen Fund" -> {:error, :not_found}
      _ -> {:error, :not_found}
    end)

    stub(ClientMock, :create_account, fn "Tahoe Kitchen Fund", _opts ->
      {:error, :api_error}
    end)

    stub(ClientMock, :get_or_create_item, fn name, opts ->
      send(self(), {:item, name, opts})
      {:ok, "should_not_be_created"}
    end)

    stub(ClientMock, :create_sales_receipt, fn params, _opts ->
      send(self(), {:receipt, params})
      {:ok, %{"Id" => "sr_wrong", "TotalAmt" => "50.00"}}
    end)

    {:ok, {payment, _, _}} = book_payment_link_donation(user)

    assert {:error, :no_income_account_for_item} = Sync.sync_payment(payment)

    payment = Repo.reload!(payment)
    assert payment.quickbooks_sync_status == "failed"
    refute_received {:item, _, _}
    refute_received {:receipt, _}
  end

  test "refuses to post a payment-link donation on the event donation item", %{
    user: user
  } do
    stub_common_quickbooks()

    stub(ClientMock, :query_account_by_name, fn
      "Undeposited Funds" -> {:ok, "undeposited_funds"}
      "Tahoe Kitchen Fund" -> {:ok, "tahoe_kitchen_fund"}
      _ -> {:error, :not_found}
    end)

    stub(ClientMock, :get_or_create_item, fn "Tahoe Kitchen Fund", _opts ->
      {:ok, "donation_item_123"}
    end)

    stub(ClientMock, :create_sales_receipt, fn params, _opts ->
      send(self(), {:receipt, params})
      {:ok, %{"Id" => "sr_wrong", "TotalAmt" => "50.00"}}
    end)

    {:ok, {payment, _, _}} = book_payment_link_donation(user)

    assert {:error, :payment_link_donation_uses_donation_item} =
             Sync.sync_payment(payment)

    refute_received {:receipt, _}
  end

  test "exports a donor who is not a member on the system customer" do
    Application.put_env(
      :ysc,
      :quickbooks,
      Keyword.put(
        Application.get_env(:ysc, :quickbooks),
        :system_customer_id,
        "system_customer_1"
      )
    )

    stub_common_quickbooks()

    stub(ClientMock, :query_account_by_name, fn
      "Undeposited Funds" -> {:ok, "undeposited_funds"}
      "Tahoe Kitchen Fund" -> {:ok, "tahoe_kitchen_fund"}
      _ -> {:error, :not_found}
    end)

    stub(ClientMock, :get_or_create_item, fn _name, _opts ->
      {:ok, "plink_item_77"}
    end)

    stub(ClientMock, :get_item_by_id, fn "plink_item_77" ->
      {:ok,
       %{
         "Id" => "plink_item_77",
         "IncomeAccountRef" => %{"value" => "tahoe_kitchen_fund"}
       }}
    end)

    stub(ClientMock, :create_sales_receipt, fn params, _opts ->
      send(self(), {:receipt, params})
      {:ok, %{"Id" => "sr_guest", "TotalAmt" => "50.00"}}
    end)

    {:ok, _} = book_payment_link_donation(nil)

    assert_received {:receipt, params}
    assert get_in(params, [:customer_ref, :value]) == "system_customer_1"
  end

  test "keeps an income account name that contains the description separator",
       %{
         user: user
       } do
    account = "Tahoe Kitchen Fund | Phase 2"

    stub_common_quickbooks()

    stub(ClientMock, :query_account_by_name, fn
      "Undeposited Funds" -> {:ok, "undeposited_funds"}
      ^account -> {:ok, "phase_two"}
      _ -> {:error, :not_found}
    end)

    stub(ClientMock, :get_or_create_item, fn name, opts ->
      send(self(), {:item, name, opts})
      {:ok, "phase_item"}
    end)

    stub(ClientMock, :get_item_by_id, fn "phase_item" ->
      {:ok,
       %{
         "Id" => "phase_item",
         "IncomeAccountRef" => %{"value" => "phase_two"}
       }}
    end)

    stub(ClientMock, :create_sales_receipt, fn params, _opts ->
      send(self(), {:receipt, params})
      {:ok, %{"Id" => "sr_phase", "TotalAmt" => "50.00"}}
    end)

    {:ok, {payment, _, _}} = book_payment_link_donation(user, account)

    assert Ysc.Stripe.DonationPaymentLink.payment_link_fund(payment) == %{
             account: account,
             class: "Administration"
           }

    assert_received {:item, ^account, _opts}
    assert_received {:receipt, _params}
  end

  defp book_payment_link_donation(user, account \\ "Tahoe Kitchen Fund") do
    Ledgers.process_payment(%{
      user_id: if(is_map(user), do: user.id),
      amount: Money.new(5_000, :USD),
      external_payment_id: "pi_plink_#{System.unique_integer([:positive])}",
      entity_type: :donation,
      entity_id: nil,
      stripe_fee: Money.new(175, :USD),
      description:
        "Stripe payment link donation | #{account} | from Ada Lovelace <ada@example.com>",
      property: nil,
      payment_method_id: nil,
      metadata: %{"quickbooks_income_account" => account}
    })
  end

  defp stub_common_quickbooks do
    stub(ClientMock, :create_customer, fn _params ->
      {:ok, %{"Id" => "qb_customer_123", "DisplayName" => "Test User"}}
    end)

    stub(ClientMock, :query_class_by_name, fn
      "Administration" -> {:ok, "admin_class"}
      _ -> {:error, :not_found}
    end)
  end
end
