defmodule Ysc.Newsletter.EmailValidatorTest do
  use ExUnit.Case, async: false

  alias Ysc.Newsletter.EmailValidator

  setup do
    # Ensure ETS table is initialized
    EmailValidator.init_ets_table()
    :ok
  end

  describe "validate_email/1" do
    test "accepts valid email with MX records" do
      # gmail.com has MX records
      assert :ok = EmailValidator.validate_email("user@gmail.com")
    end

    test "accepts valid email with mixed case" do
      assert :ok = EmailValidator.validate_email("User@Gmail.COM")
    end

    test "accepts email with spaces (trimmed)" do
      assert :ok = EmailValidator.validate_email("  user@gmail.com  ")
    end

    test "rejects email without @" do
      assert {:error, :invalid_email} = EmailValidator.validate_email("notanemail")
    end

    test "rejects empty string" do
      assert {:error, :invalid_email} = EmailValidator.validate_email("")
    end

    test "rejects email with only @" do
      assert {:error, :invalid_email} = EmailValidator.validate_email("@")
    end

    test "rejects disposable email domains" do
      # mailinator.com is in the disposable domains list
      assert {:error, :disposable_email} =
               EmailValidator.validate_email("test@mailinator.com")
    end

    test "rejects disposable domain with mixed case" do
      assert {:error, :disposable_email} =
               EmailValidator.validate_email("test@MAILINATOR.COM")
    end

    test "rejects guerrillamail disposable domain" do
      assert {:error, :disposable_email} =
               EmailValidator.validate_email("test@guerrillamail.com")
    end

    test "rejects 10minutemail disposable domain" do
      assert {:error, :disposable_email} =
               EmailValidator.validate_email("test@10minutemail.com")
    end

    test "rejects tempmail disposable domain" do
      assert {:error, :disposable_email} =
               EmailValidator.validate_email("test@tempmail.com")
    end

    test "rejects domain with no MX records" do
      # Using a non-existent domain that definitely has no MX records
      domain = "this-domain-definitely-does-not-exist-#{System.unique_integer([:positive])}.com"

      assert {:error, :no_mx_records} =
               EmailValidator.validate_email("user@#{domain}")
    end

    test "accepts non-disposable domain with MX records" do
      # Using a known domain with MX records
      assert :ok = EmailValidator.validate_email("contact@example.org")
    end
  end

  describe "init_ets_table/0" do
    test "creates ETS table if it doesn't exist" do
      table_name = :disposable_email_domains

      # Table should exist after setup
      assert :ets.whereis(table_name) != :undefined
    end

    test "loads disposable domains into ETS" do
      table_name = :disposable_email_domains

      # Check that mailinator.com is in the table
      assert [{_domain, true}] = :ets.lookup(table_name, "mailinator.com")
    end

    test "table has many domains loaded" do
      table_name = :disposable_email_domains
      count = :ets.info(table_name, :size)

      # Should have loaded tens of thousands of domains
      assert count > 50_000
    end
  end

  describe "reload_disposable_domains/0" do
    test "reloads domains from file" do
      assert {:ok, count} = EmailValidator.reload_disposable_domains()
      assert count > 50_000
    end

    test "clears and reloads ETS table" do
      table_name = :disposable_email_domains

      # Get initial count
      initial_count = :ets.info(table_name, :size)

      # Reload
      {:ok, reloaded_count} = EmailValidator.reload_disposable_domains()

      # Count should be the same (or very close if file changed)
      assert abs(initial_count - reloaded_count) < 100
    end
  end

  describe "MX caching" do
    test "caches MX lookup results" do
      email1 = "user1@gmail.com"
      email2 = "user2@gmail.com"

      # First call - should do DNS lookup
      assert :ok = EmailValidator.validate_email(email1)

      # Second call to same domain - should use cache
      # We can't directly test cache usage, but this shouldn't fail
      assert :ok = EmailValidator.validate_email(email2)
    end
  end

  describe "error handling" do
    test "handles invalid input types gracefully" do
      assert {:error, :invalid_email} = EmailValidator.validate_email(nil)
      assert {:error, :invalid_email} = EmailValidator.validate_email(123)
      assert {:error, :invalid_email} = EmailValidator.validate_email(%{})
    end
  end
end
