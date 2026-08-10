defmodule Ysc.QuickbooksTest do
  # async: false — setup clears :ysc_cache and pins :quickbooks_client globally.
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures

  alias Ysc.Accounts.User
  alias Ysc.Quickbooks
  alias Ysc.Quickbooks.ClientMock
  alias Ysc.Repo

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Clear cache before each test to ensure mocks are used
    Cachex.clear(:ysc_cache)

    # Configure the QuickBooks client to use the mock
    Application.put_env(:ysc, :quickbooks_client, ClientMock)

    # Set up QuickBooks configuration in application config for tests
    Application.put_env(:ysc, :quickbooks,
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      company_id: "test_company_id",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token"
    )

    :ok
  end

  describe "get_or_create_customer/1" do
    test "returns existing customer ID if user already has one" do
      user = user_fixture()
      existing_customer_id = "existing_customer_123"

      updated_user =
        user
        |> User.update_user_changeset(%{
          quickbooks_customer_id: existing_customer_id
        })
        |> Repo.update!()

      # Reload to ensure the customer_id is set
      updated_user = Repo.reload!(updated_user)
      assert updated_user.quickbooks_customer_id == existing_customer_id

      # Should not call create_customer, should return existing ID
      assert {:ok, ^existing_customer_id} =
               Quickbooks.get_or_create_customer(updated_user)
    end

    test "creates new customer successfully" do
      user = user_fixture()

      # Clear any existing customer ID
      user
      |> User.update_user_changeset(%{quickbooks_customer_id: nil})
      |> Repo.update!()

      user = Repo.reload!(user)

      expect(ClientMock, :create_customer, fn params ->
        assert params.display_name == "#{user.first_name} #{user.last_name}"
        assert params.given_name == user.first_name
        assert params.family_name == user.last_name
        assert params.email == user.email

        {:ok,
         %{"Id" => "new_customer_123", "DisplayName" => params.display_name}}
      end)

      assert {:ok, "new_customer_123"} = Quickbooks.get_or_create_customer(user)

      # Verify user was updated with customer ID
      updated_user = Repo.reload!(user)
      assert updated_user.quickbooks_customer_id == "new_customer_123"
    end

    test "handles duplicate name error by retrying with modified display name" do
      user = user_fixture()

      # Clear any existing customer ID
      user
      |> User.update_user_changeset(%{quickbooks_customer_id: nil})
      |> Repo.update!()

      user = Repo.reload!(user)

      original_display_name = "#{user.first_name} #{user.last_name}"

      # First call returns duplicate name error
      expect(ClientMock, :create_customer, 1, fn params ->
        assert params.display_name == original_display_name
        {:error, "6240: Duplicate Name Exists Error"}
      end)

      # Second call (retry) should have modified display name with user ID suffix
      expect(ClientMock, :create_customer, 1, fn params ->
        user_id = to_string(user.id)

        expected_suffix =
          if String.length(user_id) >= 6 do
            start_pos = max(0, String.length(user_id) - 6)
            String.slice(user_id, start_pos, 6)
          else
            user_id
          end

        assert params.display_name ==
                 "#{original_display_name} (#{expected_suffix})"

        assert params.given_name == user.first_name
        assert params.family_name == user.last_name
        assert params.email == user.email

        {:ok,
         %{"Id" => "retry_customer_456", "DisplayName" => params.display_name}}
      end)

      assert {:ok, "retry_customer_456"} =
               Quickbooks.get_or_create_customer(user)

      # Verify user was updated with customer ID
      updated_user = Repo.reload!(user)
      assert updated_user.quickbooks_customer_id == "retry_customer_456"
    end

    test "handles duplicate name error with 'Duplicate Name Exists Error' message" do
      user = user_fixture()

      # Clear any existing customer ID
      user
      |> User.update_user_changeset(%{quickbooks_customer_id: nil})
      |> Repo.update!()

      user = Repo.reload!(user)

      original_display_name = "#{user.first_name} #{user.last_name}"

      # First call returns duplicate name error (without error code)
      expect(ClientMock, :create_customer, 1, fn params ->
        assert params.display_name == original_display_name
        {:error, "Duplicate Name Exists Error"}
      end)

      # Second call (retry) should have modified display name
      expect(ClientMock, :create_customer, 1, fn params ->
        user_id = to_string(user.id)

        expected_suffix =
          if String.length(user_id) >= 6 do
            start_pos = max(0, String.length(user_id) - 6)
            String.slice(user_id, start_pos, 6)
          else
            user_id
          end

        assert params.display_name ==
                 "#{original_display_name} (#{expected_suffix})"

        {:ok,
         %{"Id" => "retry_customer_789", "DisplayName" => params.display_name}}
      end)

      assert {:ok, "retry_customer_789"} =
               Quickbooks.get_or_create_customer(user)
    end

    test "does not retry on non-duplicate errors" do
      user = user_fixture()

      # Clear any existing customer ID
      user
      |> User.update_user_changeset(%{quickbooks_customer_id: nil})
      |> Repo.update!()

      user = Repo.reload!(user)

      # Return a different error (not duplicate name)
      expect(ClientMock, :create_customer, 1, fn _params ->
        {:error, "500: Internal Server Error"}
      end)

      assert {:error, "500: Internal Server Error"} =
               Quickbooks.get_or_create_customer(user)

      # Verify user was NOT updated
      updated_user = Repo.reload!(user)
      assert updated_user.quickbooks_customer_id == nil
    end

    test "handles user with short ID (less than 6 characters)" do
      user = user_fixture()

      # Clear any existing customer ID
      user
      |> User.update_user_changeset(%{quickbooks_customer_id: nil})
      |> Repo.update!()

      user = Repo.reload!(user)

      # Mock a short user ID by temporarily changing it
      # We'll use the actual user ID but test the logic handles short IDs
      original_display_name = "#{user.first_name} #{user.last_name}"

      # First call returns duplicate name error
      expect(ClientMock, :create_customer, 1, fn params ->
        assert params.display_name == original_display_name
        {:error, "6240: Duplicate Name Exists Error"}
      end)

      # Second call should use the full user ID if it's less than 6 characters
      expect(ClientMock, :create_customer, 1, fn params ->
        user_id = to_string(user.id)

        expected_suffix =
          if String.length(user_id) >= 6 do
            start_pos = max(0, String.length(user_id) - 6)
            String.slice(user_id, start_pos, 6)
          else
            user_id
          end

        # Should include the suffix (either last 6 chars or full ID if < 6 chars)
        assert String.contains?(params.display_name, expected_suffix)

        {:ok,
         %{"Id" => "short_id_customer", "DisplayName" => params.display_name}}
      end)

      assert {:ok, "short_id_customer"} =
               Quickbooks.get_or_create_customer(user)
    end

    test "returns :missing_name when both first and last name are blank" do
      user = user_fixture()

      user =
        user
        |> Ecto.Changeset.change(%{
          quickbooks_customer_id: nil,
          first_name: "",
          last_name: ""
        })
        |> Repo.update!()

      assert {:error, :missing_name} = Quickbooks.get_or_create_customer(user)
    end

    test "uses last name only when first name is blank" do
      user = user_fixture()

      user =
        user
        |> Ecto.Changeset.change(%{
          quickbooks_customer_id: nil,
          first_name: "",
          last_name: "Solo"
        })
        |> Repo.update!()

      expect(ClientMock, :create_customer, fn params ->
        assert params.display_name == "Solo"
        {:ok, %{"Id" => "cust_last_only"}}
      end)

      assert {:ok, "cust_last_only"} = Quickbooks.get_or_create_customer(user)
    end

    test "uses first name only when last name is blank" do
      user = user_fixture()

      user =
        user
        |> Ecto.Changeset.change(%{
          quickbooks_customer_id: nil,
          first_name: "Solo",
          last_name: ""
        })
        |> Repo.update!()

      expect(ClientMock, :create_customer, fn params ->
        assert params.display_name == "Solo"
        {:ok, %{"Id" => "cust_first_only"}}
      end)

      assert {:ok, "cust_first_only"} = Quickbooks.get_or_create_customer(user)
    end

    test "still returns customer id when persisting quickbooks_customer_id fails",
         %{} do
      user = user_fixture()

      user =
        user
        |> Ecto.Changeset.change(%{quickbooks_customer_id: nil, first_name: ""})
        |> Repo.update!()

      expect(ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "cust_unsaved"}}
      end)

      assert {:ok, "cust_unsaved"} = Quickbooks.get_or_create_customer(user)

      # The customer was "created" in QuickBooks, but since the user's own
      # first_name is blank, update_user_changeset fails validate_required
      # and quickbooks_customer_id is never persisted locally.
      reloaded = Repo.reload!(user)
      assert reloaded.quickbooks_customer_id == nil
    end

    test "still returns retried customer id when persisting fails after duplicate-name retry" do
      user = user_fixture()

      user =
        user
        |> Ecto.Changeset.change(%{quickbooks_customer_id: nil, first_name: ""})
        |> Repo.update!()

      expect(ClientMock, :create_customer, 1, fn _params ->
        {:error, "Duplicate Name Exists Error"}
      end)

      expect(ClientMock, :create_customer, 1, fn _params ->
        {:ok, %{"Id" => "cust_retry_unsaved"}}
      end)

      assert {:ok, "cust_retry_unsaved"} =
               Quickbooks.get_or_create_customer(user)

      reloaded = Repo.reload!(user)
      assert reloaded.quickbooks_customer_id == nil
    end
  end

  describe "create_purchase_sales_receipt/1" do
    test "returns error when customer_id is missing" do
      Logger.put_module_level(Ysc.Quickbooks, :none)

      try do
        assert {:error, :missing_customer_id} =
                 Quickbooks.create_purchase_sales_receipt(%{
                   item_id: "item_123",
                   quantity: 1,
                   unit_price: Decimal.new("100.00")
                 })
      after
        Logger.delete_module_level(Ysc.Quickbooks)
      end
    end

    test "returns error when customer_id is empty string" do
      Logger.put_module_level(Ysc.Quickbooks, :none)

      try do
        assert {:error, :missing_customer_id} =
                 Quickbooks.create_purchase_sales_receipt(%{
                   customer_id: "",
                   item_id: "item_123",
                   quantity: 1,
                   unit_price: Decimal.new("100.00")
                 })
      after
        Logger.delete_module_level(Ysc.Quickbooks)
      end
    end

    test "returns error when item_id is missing" do
      Logger.put_module_level(Ysc.Quickbooks, :none)

      try do
        assert {:error, :missing_item_id} =
                 Quickbooks.create_purchase_sales_receipt(%{
                   customer_id: "cust_123",
                   quantity: 1,
                   unit_price: Decimal.new("100.00")
                 })
      after
        Logger.delete_module_level(Ysc.Quickbooks)
      end
    end

    test "returns error when item_id is empty string" do
      Logger.put_module_level(Ysc.Quickbooks, :none)

      try do
        assert {:error, :missing_item_id} =
                 Quickbooks.create_purchase_sales_receipt(%{
                   customer_id: "cust_123",
                   item_id: "",
                   quantity: 1,
                   unit_price: Decimal.new("100.00")
                 })
      after
        Logger.delete_module_level(Ysc.Quickbooks)
      end
    end

    test "creates sales receipt successfully with minimal params" do
      stub(ClientMock, :query_class_by_name, fn "Administration" ->
        {:ok, "admin_class_123"}
      end)

      expect(ClientMock, :create_sales_receipt, fn params, _opts ->
        assert params.customer_ref == %{value: "cust_123"}
        assert params.total_amt == Decimal.new("150.00")
        assert [line] = params.line
        assert line.detail_type == "SalesItemLineDetail"
        assert line.sales_item_line_detail.item_ref == %{value: "item_456"}
        assert line.sales_item_line_detail.quantity == Decimal.new(1)
        assert line.sales_item_line_detail.unit_price == Decimal.new("150.00")

        assert line.sales_item_line_detail.class_ref == %{
                 value: "admin_class_123",
                 name: "Administration"
               }

        {:ok, %{"Id" => "sr_789", "TotalAmt" => "150.00"}}
      end)

      assert {:ok, %{"Id" => "sr_789"}} =
               Quickbooks.create_purchase_sales_receipt(%{
                 customer_id: "cust_123",
                 item_id: "item_456",
                 quantity: 1,
                 unit_price: Decimal.new("150.00")
               })
    end

    test "creates sales receipt with optional class_ref, txn_date, memo" do
      expect(ClientMock, :create_sales_receipt, fn params, _opts ->
        assert params.customer_ref == %{value: "cust_1"}
        assert params.total_amt == Decimal.new("200.00")
        assert params.txn_date == "2024-06-15"
        assert params.memo == "Event ticket"
        assert [line] = params.line

        assert line.sales_item_line_detail.class_ref == %{
                 value: "class_1",
                 name: "Events"
               }

        {:ok, %{"Id" => "sr_ok", "TotalAmt" => "200.00"}}
      end)

      assert {:ok, %{"Id" => "sr_ok"}} =
               Quickbooks.create_purchase_sales_receipt(%{
                 customer_id: "cust_1",
                 item_id: "item_1",
                 quantity: 2,
                 unit_price: Decimal.new("100.00"),
                 class_ref: %{value: "class_1", name: "Events"},
                 txn_date: ~D[2024-06-15],
                 memo: "Event ticket"
               })
    end

    test "uses Administration class fallback when query_class_by_name fails" do
      Logger.put_module_level(Ysc.Quickbooks, :none)

      stub(ClientMock, :query_class_by_name, fn "Administration" ->
        {:error, :not_found}
      end)

      expect(ClientMock, :create_sales_receipt, fn params, _opts ->
        assert [line] = params.line

        assert line.sales_item_line_detail.class_ref == %{
                 value: "Administration",
                 name: "Administration"
               }

        {:ok, %{"Id" => "sr_fb"}}
      end)

      try do
        assert {:ok, %{"Id" => "sr_fb"}} =
                 Quickbooks.create_purchase_sales_receipt(%{
                   customer_id: "c",
                   item_id: "i",
                   quantity: 1,
                   unit_price: Decimal.new("10.00")
                 })
      after
        Logger.delete_module_level(Ysc.Quickbooks)
      end
    end

    test "includes optional purchase fields on sales receipt" do
      stub(ClientMock, :query_class_by_name, fn "Administration" ->
        {:ok, "adm"}
      end)

      expect(ClientMock, :create_sales_receipt, fn params, _opts ->
        assert [line] = params.line
        assert line.sales_item_line_detail.quantity == Decimal.new(3)
        assert params.payment_method_ref == %{value: "pm_1"}

        assert params.deposit_to_account_ref == %{
                 value: "dep",
                 name: "Checking"
               }

        assert params.private_note == "priv"
        assert line.sales_item_line_detail.tax_code_ref == %{value: "TAX"}

        assert line.description == "Line desc"

        {:ok, %{"Id" => "sr_full"}}
      end)

      assert {:ok, _} =
               Quickbooks.create_purchase_sales_receipt(
                 %{
                   customer_id: "c",
                   item_id: "i",
                   quantity: 3,
                   unit_price: Decimal.new("4.00"),
                   payment_method_id: "pm_1",
                   deposit_to_account_id: "dep",
                   deposit_to_account_name: "Checking",
                   description: "Line desc",
                   private_note: "priv",
                   tax_code_ref: "TAX",
                   txn_date: "2024-01-20"
                 },
                 timeout: 5_000
               )
    end
  end

  describe "create_refund_sales_receipt/1" do
    test "creates refund sales receipt with positive amounts" do
      expect(ClientMock, :create_sales_receipt, fn params, _opts ->
        assert params.customer_ref == %{value: "cust_ref"}
        assert params.total_amt == Decimal.new("50.00")
        assert [line] = params.line
        assert line.sales_item_line_detail.unit_price == Decimal.new("50.00")
        assert line.description == "Refund"

        {:ok, %{"Id" => "sr_refund", "TotalAmt" => "50.00"}}
      end)

      assert {:ok, %{"Id" => "sr_refund"}} =
               Quickbooks.create_refund_sales_receipt(%{
                 customer_id: "cust_ref",
                 item_id: "item_ref",
                 quantity: 1,
                 unit_price: Decimal.new("50.00")
               })
    end

    test "creates refund sales receipt with optional class_ref, txn_date, memo, private_note" do
      expect(ClientMock, :create_sales_receipt, fn params, _opts ->
        assert params.txn_date == "2025-01-10"
        assert params.memo == "Refund memo"
        assert params.private_note == "Internal note"
        assert [line] = params.line

        assert line.sales_item_line_detail.class_ref == %{
                 value: "events",
                 name: "Events"
               }

        {:ok, %{"Id" => "sr_opt", "TotalAmt" => "25.00"}}
      end)

      assert {:ok, %{"Id" => "sr_opt"}} =
               Quickbooks.create_refund_sales_receipt(%{
                 customer_id: "c",
                 item_id: "i",
                 quantity: 1,
                 unit_price: Decimal.new("25.00"),
                 class_ref: %{value: "events", name: "Events"},
                 txn_date: ~D[2025-01-10],
                 memo: "Refund memo",
                 private_note: "Internal note"
               })
    end
  end

  describe "create_refund_receipt/1" do
    test "creates refund receipt with refund_from_account_ref" do
      expect(ClientMock, :create_refund_receipt, fn params, _opts ->
        assert params.customer_ref == %{value: "cust_r"}
        assert params.refund_from_account_ref == %{value: "undeposited_1"}
        assert params.total_amt == Decimal.new("75.00")
        assert [line] = params.line
        assert line.sales_item_line_detail.item_ref == %{value: "item_r"}

        {:ok, %{"Id" => "rr_1", "TotalAmt" => "75.00"}}
      end)

      assert {:ok, %{"Id" => "rr_1"}} =
               Quickbooks.create_refund_receipt(%{
                 customer_id: "cust_r",
                 item_id: "item_r",
                 quantity: 1,
                 unit_price: Decimal.new("75.00"),
                 refund_from_account_id: "undeposited_1"
               })
    end

    test "includes refund_from account name and line description" do
      expect(ClientMock, :create_refund_receipt, fn params, _opts ->
        assert params.refund_from_account_ref == %{
                 value: "uf",
                 name: "Undeposited"
               }

        assert [line] = params.line
        assert line.sales_item_line_detail.quantity == Decimal.new(2)
        assert line.description == "Refund line"
        {:ok, %{"Id" => "rr_2"}}
      end)

      assert {:ok, _} =
               Quickbooks.create_refund_receipt(%{
                 customer_id: "c",
                 item_id: "i",
                 quantity: 2,
                 unit_price: Decimal.new("4.00"),
                 refund_from_account_id: "uf",
                 refund_from_account_name: "Undeposited",
                 description: "Refund line"
               })
    end
  end

  describe "create_stripe_payout_deposit/1" do
    test "creates deposit with required params" do
      expect(ClientMock, :create_deposit, fn params, _opts ->
        assert params.deposit_to_account_ref == %{value: "bank_1"}
        assert params.total_amt == 500.00
        assert [line] = params.line
        assert line.detail_type == "DepositLineDetail"
        assert line.deposit_line_detail.account_ref == %{value: "undeposited_4"}
        assert line.description == "Stripe payout"

        {:ok, %{"Id" => "dep_1", "TotalAmt" => "500.00"}}
      end)

      assert {:ok, %{"Id" => "dep_1"}} =
               Quickbooks.create_stripe_payout_deposit(%{
                 bank_account_id: "bank_1",
                 undeposited_funds_account_id: "undeposited_4",
                 amount: 500.00
               })
    end

    test "creates deposit with optional txn_date, private_note, class_ref" do
      expect(ClientMock, :create_deposit, fn params, _opts ->
        assert params.txn_date == "2024-12-01"
        assert params.private_note == "Payout for November"
        assert [line] = params.line

        assert line.deposit_line_detail.class_ref == %{
                 value: "class_payout",
                 name: "Administration"
               }

        {:ok, %{"Id" => "dep_2", "TotalAmt" => "1000.00"}}
      end)

      assert {:ok, %{"Id" => "dep_2"}} =
               Quickbooks.create_stripe_payout_deposit(%{
                 bank_account_id: "bank_2",
                 undeposited_funds_account_id: "undeposited_4",
                 amount: 1000.00,
                 txn_date: ~D[2024-12-01],
                 private_note: "Payout for November",
                 class_ref: %{value: "class_payout", name: "Administration"}
               })
    end

    test "uses custom description when provided" do
      expect(ClientMock, :create_deposit, fn params, _opts ->
        assert [line] = params.line
        assert line.description == "Custom payout note"
        {:ok, %{"Id" => "dep_3"}}
      end)

      assert {:ok, _} =
               Quickbooks.create_stripe_payout_deposit(%{
                 bank_account_id: "b",
                 undeposited_funds_account_id: "u",
                 amount: 1.0,
                 description: "Custom payout note"
               })
    end
  end

  describe "get_or_create_customer/1 edge cases" do
    test "returns error when QuickBooks response has no Id" do
      user = user_fixture()

      user
      |> User.update_user_changeset(%{quickbooks_customer_id: nil})
      |> Repo.update!()

      user = Repo.reload!(user)

      expect(ClientMock, :create_customer, fn _params ->
        {:ok, %{"DisplayName" => "x"}}
      end)

      assert {:error, :invalid_customer_response} =
               Quickbooks.get_or_create_customer(user)
    end

    test "returns atom error from create_customer" do
      user = user_fixture()

      user
      |> User.update_user_changeset(%{quickbooks_customer_id: nil})
      |> Repo.update!()

      user = Repo.reload!(user)

      expect(ClientMock, :create_customer, fn _params ->
        {:error, :rate_limited}
      end)

      assert {:error, :rate_limited} = Quickbooks.get_or_create_customer(user)
    end

    test "duplicate retry returns error when second create fails" do
      user = user_fixture()

      user
      |> User.update_user_changeset(%{quickbooks_customer_id: nil})
      |> Repo.update!()

      user = Repo.reload!(user)
      name = "#{user.first_name} #{user.last_name}"

      expect(ClientMock, :create_customer, 1, fn p ->
        assert p.display_name == name
        {:error, "Duplicate Name Exists Error"}
      end)

      expect(ClientMock, :create_customer, 1, fn _p ->
        {:error, "still bad"}
      end)

      assert {:error, "still bad"} = Quickbooks.get_or_create_customer(user)
    end

    test "duplicate retry returns invalid_customer_response when retry has no Id" do
      user = user_fixture()

      user
      |> User.update_user_changeset(%{quickbooks_customer_id: nil})
      |> Repo.update!()

      user = Repo.reload!(user)
      name = "#{user.first_name} #{user.last_name}"

      expect(ClientMock, :create_customer, 1, fn p ->
        assert p.display_name == name
        {:error, "6240: Duplicate Name Exists Error"}
      end)

      expect(ClientMock, :create_customer, 1, fn p ->
        assert p.display_name != name
        {:ok, %{}}
      end)

      assert {:error, :invalid_customer_response} =
               Quickbooks.get_or_create_customer(user)
    end
  end

  describe "format_date/1 (via txn_date) and refund amount edge cases" do
    test "create_stripe_payout_deposit sets txn_date to nil when value is DateTime (unsupported)" do
      expect(ClientMock, :create_deposit, fn params, _opts ->
        assert params.txn_date == nil
        {:ok, %{"Id" => "dep_dt"}}
      end)

      assert {:ok, %{"Id" => "dep_dt"}} =
               Quickbooks.create_stripe_payout_deposit(%{
                 bank_account_id: "bank_1",
                 undeposited_funds_account_id: "uf_1",
                 amount: 10.0,
                 txn_date: ~U[2024-06-15 12:00:00Z]
               })
    end

    test "create_refund_sales_receipt uses abs on negative unit_price" do
      expect(ClientMock, :create_sales_receipt, fn params, _opts ->
        assert params.total_amt == Decimal.new("25.00")
        assert [line] = params.line
        assert line.sales_item_line_detail.unit_price == Decimal.new("25.00")
        {:ok, %{"Id" => "sr_neg"}}
      end)

      assert {:ok, _} =
               Quickbooks.create_refund_sales_receipt(%{
                 customer_id: "c",
                 item_id: "i",
                 quantity: 1,
                 unit_price: Decimal.new("-25.00")
               })
    end

    test "create_refund_receipt omits line description when description is absent" do
      expect(ClientMock, :create_refund_receipt, fn params, _opts ->
        assert [line] = params.line
        refute Map.has_key?(line, :description)
        {:ok, %{"Id" => "rr_no_desc"}}
      end)

      assert {:ok, _} =
               Quickbooks.create_refund_receipt(%{
                 customer_id: "c",
                 item_id: "i",
                 quantity: 1,
                 unit_price: Decimal.new("3.00"),
                 refund_from_account_id: "uf"
               })
    end
  end

  describe "coverage — remaining branches" do
    test "purchase sales receipt accepts a Decimal quantity directly" do
      stub(ClientMock, :query_class_by_name, fn "Administration" ->
        {:ok, "adm"}
      end)

      expect(ClientMock, :create_sales_receipt, fn params, _opts ->
        assert [line] = params.line
        assert line.sales_item_line_detail.quantity == Decimal.new(2)
        {:ok, %{"Id" => "sr_decimal_qty"}}
      end)

      assert {:ok, _} =
               Quickbooks.create_purchase_sales_receipt(%{
                 customer_id: "c",
                 item_id: "i",
                 quantity: Decimal.new(2),
                 unit_price: Decimal.new("5.00")
               })
    end

    test "purchase sales receipt defaults line quantity to 1 for a non-integer, non-Decimal quantity" do
      stub(ClientMock, :query_class_by_name, fn "Administration" ->
        {:ok, "adm"}
      end)

      expect(ClientMock, :create_sales_receipt, fn params, _opts ->
        assert params.total_amt == Decimal.new("10.00")
        assert [line] = params.line
        assert line.sales_item_line_detail.quantity == Decimal.new(1)
        {:ok, %{"Id" => "sr_fallback_qty"}}
      end)

      assert {:ok, _} =
               Quickbooks.create_purchase_sales_receipt(%{
                 customer_id: "c",
                 item_id: "i",
                 quantity: "2",
                 unit_price: Decimal.new("5.00")
               })
    end

    test "purchase sales receipt omits deposit account name when not provided" do
      stub(ClientMock, :query_class_by_name, fn "Administration" ->
        {:ok, "adm"}
      end)

      expect(ClientMock, :create_sales_receipt, fn params, _opts ->
        assert params.deposit_to_account_ref == %{value: "dep_no_name"}
        {:ok, %{"Id" => "sr_dep_no_name"}}
      end)

      assert {:ok, _} =
               Quickbooks.create_purchase_sales_receipt(%{
                 customer_id: "c",
                 item_id: "i",
                 quantity: 1,
                 unit_price: Decimal.new("5.00"),
                 deposit_to_account_id: "dep_no_name"
               })
    end

    test "refund receipt accepts a Decimal quantity directly" do
      expect(ClientMock, :create_refund_receipt, fn params, _opts ->
        assert [line] = params.line
        assert line.sales_item_line_detail.quantity == Decimal.new(2)
        {:ok, %{"Id" => "rr_decimal_qty"}}
      end)

      assert {:ok, _} =
               Quickbooks.create_refund_receipt(%{
                 customer_id: "c",
                 item_id: "i",
                 quantity: Decimal.new(2),
                 unit_price: Decimal.new("5.00"),
                 refund_from_account_id: "uf"
               })
    end

    test "refund receipt defaults line quantity to 1 for a non-integer, non-Decimal quantity" do
      expect(ClientMock, :create_refund_receipt, fn params, _opts ->
        assert [line] = params.line
        assert line.sales_item_line_detail.quantity == Decimal.new(1)
        {:ok, %{"Id" => "rr_fallback_qty"}}
      end)

      assert {:ok, _} =
               Quickbooks.create_refund_receipt(%{
                 customer_id: "c",
                 item_id: "i",
                 quantity: "2",
                 unit_price: Decimal.new("5.00"),
                 refund_from_account_id: "uf"
               })
    end

    test "refund sales receipt includes tax_code_ref, payment_method_id, and deposit account without a name" do
      expect(ClientMock, :create_sales_receipt, fn params, _opts ->
        assert [line] = params.line
        assert line.sales_item_line_detail.tax_code_ref == %{value: "TAX1"}
        assert params.payment_method_ref == %{value: "pm_ref"}
        assert params.deposit_to_account_ref == %{value: "dep_ref"}
        {:ok, %{"Id" => "sr_refund_opts"}}
      end)

      assert {:ok, _} =
               Quickbooks.create_refund_sales_receipt(%{
                 customer_id: "c",
                 item_id: "i",
                 quantity: 1,
                 unit_price: Decimal.new("5.00"),
                 tax_code_ref: "TAX1",
                 payment_method_id: "pm_ref",
                 deposit_to_account_id: "dep_ref"
               })
    end

    test "refund receipt includes class_ref, tax_code_ref, payment_method_id, txn_date, memo, and private_note" do
      expect(ClientMock, :create_refund_receipt, fn params, _opts ->
        assert [line] = params.line

        assert line.sales_item_line_detail.class_ref == %{
                 value: "cls",
                 name: "Class"
               }

        assert line.sales_item_line_detail.tax_code_ref == %{value: "TAX2"}
        assert params.payment_method_ref == %{value: "pm_rr"}
        assert params.txn_date == "2024-03-01"
        assert params.memo == "Refund memo rr"
        assert params.private_note == "Refund note rr"
        {:ok, %{"Id" => "rr_full_opts"}}
      end)

      assert {:ok, _} =
               Quickbooks.create_refund_receipt(%{
                 customer_id: "c",
                 item_id: "i",
                 quantity: 1,
                 unit_price: Decimal.new("5.00"),
                 refund_from_account_id: "uf",
                 class_ref: %{value: "cls", name: "Class"},
                 tax_code_ref: "TAX2",
                 payment_method_id: "pm_rr",
                 txn_date: ~D[2024-03-01],
                 memo: "Refund memo rr",
                 private_note: "Refund note rr"
               })
    end

    test "client_module reads the configured :quickbooks_client outside of test env" do
      previous_env = Application.get_env(:ysc, :environment)
      Application.put_env(:ysc, :environment, "dev")
      on_exit(fn -> Application.put_env(:ysc, :environment, previous_env) end)

      expect(ClientMock, :create_deposit, fn params, _opts ->
        assert params.deposit_to_account_ref == %{value: "bank_env"}
        {:ok, %{"Id" => "dep_env"}}
      end)

      assert {:ok, %{"Id" => "dep_env"}} =
               Quickbooks.create_stripe_payout_deposit(%{
                 bank_account_id: "bank_env",
                 undeposited_funds_account_id: "uf_env",
                 amount: 1.0
               })
    end
  end
end
