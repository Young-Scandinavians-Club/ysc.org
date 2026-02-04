defmodule Ysc.ExpenseReports.BankAccount do
  @moduledoc """
  Bank account schema with encrypted routing and account numbers.

  **SECURITY NOTE**: Account numbers and routing numbers are encrypted at rest.
  They are NEVER logged and are only decrypted when explicitly requested via
  `get_decrypted_details/1`. Never access `.account_number` or `.routing_number`
  directly unless you absolutely need the decrypted values.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.User

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "bank_accounts" do
    belongs_to :user, User, foreign_key: :user_id, references: :id

    # Encrypted fields using Cloak.Ecto
    field :routing_number, Ysc.Encrypted.Binary
    field :account_number, Ysc.Encrypted.Binary

    # Last 4 digits for display (not encrypted)
    field :account_number_last_4, :string

    timestamps()
  end

  @doc """
  Creates a changeset for a bank account.
  """
  def changeset(bank_account, attrs) do
    bank_account
    |> cast(attrs, [
      :user_id,
      :routing_number,
      :account_number,
      :account_number_last_4
    ])
    |> validate_required([:user_id, :routing_number, :account_number])
    |> validate_routing_number()
    |> validate_account_number()
    |> validate_routing_number_checksum()
    |> maybe_extract_last_4()
    |> validate_length(:account_number_last_4,
      is: 4,
      message: "must be 4 digits"
    )
    |> validate_format(:account_number_last_4, ~r/^\d{4}$/,
      message: "must be 4 digits"
    )
    |> unique_constraint(:user_id)
  end

  defp validate_routing_number(changeset) do
    changeset
    |> validate_change(:routing_number, fn :routing_number, value ->
      cond do
        is_nil(value) ->
          []

        not is_binary(value) ->
          [routing_number: "must be a string"]

        String.length(value) != 9 ->
          [routing_number: "must be 9 digits"]

        not String.match?(value, ~r/^\d{9}$/) ->
          [routing_number: "must be 9 digits"]

        true ->
          []
      end
    end)
  end

  defp validate_account_number(changeset) do
    changeset
    |> validate_change(:account_number, fn :account_number, value ->
      cond do
        is_nil(value) ->
          []

        not is_binary(value) ->
          [account_number: "must be a string"]

        String.length(value) < 4 ->
          [account_number: "must be at least 4 digits"]

        not String.match?(value, ~r/^\d+$/) ->
          [account_number: "must contain only digits"]

        true ->
          []
      end
    end)
  end

  defp validate_routing_number_checksum(changeset) do
    case get_change(changeset, :routing_number) do
      nil ->
        changeset

      routing_number when is_binary(routing_number) ->
        if valid_routing_number_checksum?(routing_number) do
          changeset
        else
          add_error(
            changeset,
            :routing_number,
            "is not a valid US routing number"
          )
        end

      _ ->
        changeset
    end
  end

  defp valid_routing_number_checksum?(<<_::bytes-size(9)>> = routing_number) do
    # Regex check to ensure all characters are digits
    if String.match?(routing_number, ~r/^\d{9}$/) do
      # Faster parsing using binary comprehension
      digits = for <<d::utf8 <- routing_number>>, do: d - ?0

      # ABA Routing Number Weights: 3, 7, 1 pattern repeats for all 9 digits
      # Formula: 3(d₁) + 7(d₂) + 1(d₃) + 3(d₄) + 7(d₅) + 1(d₆) + 3(d₇) + 7(d₈) + 1(d₉) ≡ 0 (mod 10)
      multipliers = [3, 7, 1, 3, 7, 1, 3, 7, 1]

      sum =
        Enum.zip_with(digits, multipliers, fn d, m -> d * m end)
        |> Enum.sum()

      rem(sum, 10) == 0
    else
      false
    end
  end

  defp valid_routing_number_checksum?(_), do: false

  @doc """
  Explicitly decrypts bank account details. Use this ONLY when you need the
  actual account number or routing number (e.g., for processing payments).

  Returns a map with decrypted :account_number and :routing_number.
  All other fields remain unchanged.
  """
  def get_decrypted_details(%__MODULE__{} = bank_account) do
    %{
      id: bank_account.id,
      user_id: bank_account.user_id,
      account_number_last_4: bank_account.account_number_last_4,
      # Cloak auto-decrypts on access
      account_number: bank_account.account_number,
      # Cloak auto-decrypts on access
      routing_number: bank_account.routing_number,
      inserted_at: bank_account.inserted_at,
      updated_at: bank_account.updated_at
    }
  end

  @doc """
  Returns a safe representation of the bank account that excludes sensitive fields.
  Use this for logging, debugging, or serialization.
  """
  def to_safe_map(%__MODULE__{} = bank_account) do
    %{
      id: bank_account.id,
      user_id: bank_account.user_id,
      account_number_last_4: bank_account.account_number_last_4,
      inserted_at: bank_account.inserted_at,
      updated_at: bank_account.updated_at
    }
  end

  defp maybe_extract_last_4(changeset) do
    case get_change(changeset, :account_number) do
      nil ->
        changeset

      account_number when is_binary(account_number) ->
        last_4 = String.slice(account_number, -4, 4)
        put_change(changeset, :account_number_last_4, last_4)

      _ ->
        changeset
    end
  end

  # Implement Inspect protocol to prevent sensitive data from being logged
  defimpl Inspect, for: __MODULE__ do
    def inspect(bank_account, _opts) do
      safe_data = Ysc.ExpenseReports.BankAccount.to_safe_map(bank_account)
      "#Ysc.ExpenseReports.BankAccount<#{inspect(safe_data)}>"
    end
  end

  # Implement Jason.Encoder protocol to prevent sensitive data from being serialized to JSON
  defimpl Jason.Encoder, for: __MODULE__ do
    def encode(bank_account, opts) do
      safe_data = Ysc.ExpenseReports.BankAccount.to_safe_map(bank_account)
      Jason.Encode.map(safe_data, opts)
    end
  end
end
