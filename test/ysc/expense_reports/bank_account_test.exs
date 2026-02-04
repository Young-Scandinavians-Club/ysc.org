defmodule Ysc.ExpenseReports.BankAccountTest do
  use Ysc.DataCase

  alias Ysc.ExpenseReports.BankAccount
  import Ysc.AccountsFixtures

  describe "routing number validation" do
    test "accepts valid routing numbers" do
      user = user_fixture()

      valid_routing_numbers = [
        "021000021",
        "011401533",
        "091000019"
      ]

      for routing_number <- valid_routing_numbers do
        changeset =
          %BankAccount{}
          |> BankAccount.changeset(%{
            user_id: user.id,
            routing_number: routing_number,
            account_number: "1234567890"
          })

        assert changeset.valid?
        refute has_error?(changeset, :routing_number)
      end
    end

    test "rejects routing numbers with invalid checksum" do
      user = user_fixture()

      invalid_routing_numbers = [
        # Wrong check digit
        "021000022",
        # Wrong check digit
        "011401534",
        # Wrong check digit
        "091000010",
        # Invalid checksum
        "123456789"
      ]

      for routing_number <- invalid_routing_numbers do
        changeset =
          %BankAccount{}
          |> BankAccount.changeset(%{
            user_id: user.id,
            routing_number: routing_number,
            account_number: "1234567890"
          })

        refute changeset.valid?

        # Check that routing_number has an error (may be checksum or format error)
        assert has_error?(changeset, :routing_number)
      end
    end

    test "rejects routing numbers that are too short" do
      user = user_fixture()

      changeset =
        %BankAccount{}
        |> BankAccount.changeset(%{
          user_id: user.id,
          # 8 digits
          routing_number: "12345678",
          account_number: "1234567890"
        })

      refute changeset.valid?
      # Should have errors for both length and checksum
      assert has_error?(changeset, :routing_number)
    end

    test "rejects routing numbers that are too long" do
      user = user_fixture()

      changeset =
        %BankAccount{}
        |> BankAccount.changeset(%{
          user_id: user.id,
          # 10 digits
          routing_number: "1234567890",
          account_number: "1234567890"
        })

      refute changeset.valid?
      # Should have errors for both length and checksum
      assert has_error?(changeset, :routing_number)
    end

    test "rejects routing numbers with non-numeric characters" do
      user = user_fixture()

      invalid_routing_numbers = [
        # Contains letter
        "02100002a",
        # Contains space
        "02100002 ",
        # Contains dash
        "02100002-",
        # Contains letters
        "abc123456"
      ]

      for routing_number <- invalid_routing_numbers do
        changeset =
          %BankAccount{}
          |> BankAccount.changeset(%{
            user_id: user.id,
            routing_number: routing_number,
            account_number: "1234567890"
          })

        refute changeset.valid?
        assert has_error?(changeset, :routing_number)
      end
    end

    test "rejects empty routing number" do
      user = user_fixture()

      changeset =
        %BankAccount{}
        |> BankAccount.changeset(%{
          user_id: user.id,
          routing_number: "",
          account_number: "1234567890"
        })

      refute changeset.valid?
      assert has_error?(changeset, :routing_number)
    end

    test "accepts routing number with leading zeros" do
      user = user_fixture()
      # 021000021 is a valid routing number with leading zero
      changeset =
        %BankAccount{}
        |> BankAccount.changeset(%{
          user_id: user.id,
          routing_number: "021000021",
          account_number: "1234567890"
        })

      assert changeset.valid?
    end

    test "validates checksum calculation correctly" do
      user = user_fixture()

      # Test the checksum formula: 3(d₁) + 7(d₂) + 1(d₃) + 3(d₄) + 7(d₅) + 1(d₆) + 3(d₇) + 7(d₈) + 1(d₉) ≡ 0 (mod 10)
      # For 021000021:
      # 3(0) + 7(2) + 1(1) + 3(0) + 7(0) + 1(0) + 3(0) + 7(2) + 1(1)
      # = 0 + 14 + 1 + 0 + 0 + 0 + 0 + 14 + 1
      # = 30
      # 30 mod 10 = 0 ✓

      changeset =
        %BankAccount{}
        |> BankAccount.changeset(%{
          user_id: user.id,
          routing_number: "021000021",
          account_number: "1234567890"
        })

      assert changeset.valid?
    end
  end

  describe "account number validation" do
    test "accepts valid account numbers" do
      user = user_fixture()

      valid_account_numbers = [
        "1234567890",
        "1234",
        # 17 digits (max length)
        "12345678901234567"
      ]

      for account_number <- valid_account_numbers do
        changeset =
          %BankAccount{}
          |> BankAccount.changeset(%{
            user_id: user.id,
            routing_number: "021000021",
            account_number: account_number
          })

        assert changeset.valid?
        refute has_error?(changeset, :account_number)
      end
    end

    test "rejects account numbers that are too short" do
      user = user_fixture()

      changeset =
        %BankAccount{}
        |> BankAccount.changeset(%{
          user_id: user.id,
          routing_number: "021000021",
          # 3 digits (minimum is 4)
          account_number: "123"
        })

      refute changeset.valid?
      assert has_error?(changeset, :account_number)
    end

    test "rejects account numbers with non-numeric characters" do
      user = user_fixture()

      invalid_account_numbers = [
        "1234a",
        "1234 ",
        "1234-"
      ]

      for account_number <- invalid_account_numbers do
        changeset =
          %BankAccount{}
          |> BankAccount.changeset(%{
            user_id: user.id,
            routing_number: "021000021",
            account_number: account_number
          })

        refute changeset.valid?
        assert has_error?(changeset, :account_number)
      end
    end

    test "extracts last 4 digits from account number" do
      user = user_fixture()

      changeset =
        %BankAccount{}
        |> BankAccount.changeset(%{
          user_id: user.id,
          routing_number: "021000021",
          account_number: "1234567890"
        })

      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :account_number_last_4) ==
               "7890"
    end
  end

  describe "complete bank account validation" do
    test "accepts valid bank account with all required fields" do
      user = user_fixture()

      changeset =
        %BankAccount{}
        |> BankAccount.changeset(%{
          user_id: user.id,
          routing_number: "021000021",
          account_number: "1234567890"
        })

      assert changeset.valid?
    end

    test "rejects bank account without user_id" do
      changeset =
        %BankAccount{}
        |> BankAccount.changeset(%{
          routing_number: "021000021",
          account_number: "1234567890"
        })

      refute changeset.valid?
      assert has_error?(changeset, :user_id)
    end

    test "rejects bank account without routing_number" do
      user = user_fixture()

      changeset =
        %BankAccount{}
        |> BankAccount.changeset(%{
          user_id: user.id,
          account_number: "1234567890"
        })

      refute changeset.valid?
      assert has_error?(changeset, :routing_number)
    end

    test "rejects bank account without account_number" do
      user = user_fixture()

      changeset =
        %BankAccount{}
        |> BankAccount.changeset(%{
          user_id: user.id,
          routing_number: "021000021"
        })

      refute changeset.valid?
      assert has_error?(changeset, :account_number)
    end
  end

  # Helper function to check for errors
  defp has_error?(changeset, field) do
    Keyword.has_key?(changeset.errors, field)
  end
end
