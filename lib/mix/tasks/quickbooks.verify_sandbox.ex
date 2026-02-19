defmodule Mix.Tasks.Quickbooks.VerifySandbox do
  @moduledoc """
  Verify QuickBooks sandbox (or production) connection by querying accounts and classes.

  Uses the real QuickBooks API client and config from environment.
  Run with MIX_ENV=prod (so runtime.exs loads QUICKBOOKS_* config) and set env vars,
  or run on Fly with: `fly ssh console -C "bin/ysc rpc 'Mix.Tasks.Quickbooks.VerifySandbox.run([])'"`

  Usage:
    MIX_ENV=prod mix quickbooks.verify_sandbox

  Required env (for API calls to succeed):
    QUICKBOOKS_ACCESS_TOKEN, QUICKBOOKS_REFRESH_TOKEN, QUICKBOOKS_REALM_ID (or COMPANY_ID),
    QUICKBOOKS_BASE_URL (optional, defaults to sandbox URL)
  """

  use Mix.Task
  require Ysc.Logging

  @shortdoc "Verify QuickBooks sandbox: bank account, accounts, classes"

  def run(_args) do
    Mix.Task.run("app.start")

    client =
      Application.get_env(:ysc, :quickbooks_client, Ysc.Quickbooks.Client)

    if client == Ysc.Quickbooks.ClientMock do
      IO.puts("")
      IO.puts("QuickBooks client is set to ClientMock (test).")

      IO.puts(
        "Run with MIX_ENV=prod and QUICKBOOKS_* env vars set to verify the real API."
      )

      IO.puts("")
      System.halt(0)
    end

    qb_config = Application.get_env(:ysc, :quickbooks) || %{}
    bank_id = qb_config[:bank_account_id]
    stripe_account_id = qb_config[:stripe_account_id]
    realm = qb_config[:realm_id] || qb_config[:company_id]

    IO.puts("")
    IO.puts("=== QuickBooks connection verification ===")
    IO.puts("  Realm/Company ID: #{inspect(realm)}")
    IO.puts("  Bank account ID (config): #{inspect(bank_id)}")
    IO.puts("  Stripe account ID (config): #{inspect(stripe_account_id)}")
    IO.puts("  Client: #{inspect(client)}")
    IO.puts("")

    # 1) Bank account by ID (QUICKBOOKS_BANK_ACCOUNT_ID)
    if bank_id && String.trim(to_string(bank_id)) != "" do
      IO.puts("--- Bank account (by ID #{bank_id}) ---")

      case client.get_account_by_id(to_string(bank_id)) do
        {:ok, account} ->
          IO.puts("  OK  Id: #{account["Id"]}")
          IO.puts("      Name: #{account["Name"]}")

          IO.puts(
            "      Type: #{account["AccountType"]} / #{account["AccountSubType"]}"
          )

          IO.puts("      Active: #{account["Active"]}")

        {:error, reason} ->
          IO.puts("  FAIL: #{inspect(reason)}")
      end

      IO.puts("")
    else
      IO.puts("--- Bank account ---")
      IO.puts("  SKIP: QUICKBOOKS_BANK_ACCOUNT_ID not set")
      IO.puts("")
    end

    # 2) Stripe account by ID (QUICKBOOKS_STRIPE_ACCOUNT_ID)
    if stripe_account_id && String.trim(to_string(stripe_account_id)) != "" do
      IO.puts("--- Stripe settlement account (by ID #{stripe_account_id}) ---")

      case client.get_account_by_id(to_string(stripe_account_id)) do
        {:ok, account} ->
          IO.puts("  OK  Id: #{account["Id"]}")
          IO.puts("      Name: #{account["Name"]}")

          IO.puts(
            "      Type: #{account["AccountType"]} / #{account["AccountSubType"]}"
          )

        {:error, reason} ->
          IO.puts("  FAIL: #{inspect(reason)}")
      end

      IO.puts("")
    else
      IO.puts("--- Stripe settlement account ---")
      IO.puts("  SKIP: QUICKBOOKS_STRIPE_ACCOUNT_ID not set")
      IO.puts("")
    end

    # 3) Required accounts by name
    IO.puts("--- Required accounts (by name) ---")

    for name <- ["Undeposited Funds", "Stripe Fees"] do
      case client.query_account_by_name(name) do
        {:ok, id} -> IO.puts("  OK  #{name}: #{id}")
        {:error, reason} -> IO.puts("  FAIL #{name}: #{inspect(reason)}")
      end
    end

    IO.puts("")

    # 4) All classes
    IO.puts("--- Classes ---")

    case client.query_all_classes() do
      {:ok, classes} when classes == %{} ->
        IO.puts("  (none)")

      {:ok, classes} ->
        Enum.each(classes, fn {name, id} ->
          IO.puts("  #{name}: #{id}")
        end)

      {:error, reason} ->
        IO.puts("  FAIL: #{inspect(reason)}")
    end

    IO.puts("")

    # 5) All accounts (summary)
    IO.puts("--- Chart of Accounts (summary) ---")

    case client.query_all_accounts() do
      {:ok, accounts} ->
        IO.puts("  Total: #{length(accounts)} accounts")

        for a <- Enum.take(accounts, 30) do
          IO.puts("    #{a["Id"]}  #{a["Name"]}  (#{a["AccountType"]})")
        end

        if length(accounts) > 30 do
          IO.puts("    ... and #{length(accounts) - 30} more")
        end

      {:error, reason} ->
        IO.puts("  FAIL: #{inspect(reason)}")
    end

    IO.puts("")
    IO.puts("=== Done ===")
    IO.puts("")
  end
end
