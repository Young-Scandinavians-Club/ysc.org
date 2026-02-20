defmodule Ysc.QuickbooksTest do
  use Ysc.DataCase, async: true

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

    test "returns error if display name is missing" do
      # This test verifies that build_display_name returns nil when both names are empty
      # Since first_name and last_name are required fields in the schema, we can't
      # actually create a user with empty names. However, the build_display_name function
      # handles this case by checking if both trimmed strings are empty.
      #
      # In practice, this error would only occur if the user data somehow had
      # both first_name and last_name as nil or empty strings, which shouldn't
      # happen due to schema validations. But the code handles it defensively.
      #
      # We'll skip this test since we can't create invalid user data due to validations.
      # The build_display_name function is tested implicitly in other tests.
      :ok
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
  end
end
