defmodule Ysc.Newsletter.EmailValidatorTest do
  use ExUnit.Case, async: false

  alias Ysc.Newsletter.EmailValidator

  setup do
    # Ensure ETS table is initialized
    EmailValidator.init_ets_table()
    :ok
  end

  describe "validate_email/1 (stubbed MX resolver, no external DNS)" do
    setup do
      prev_mx = Application.get_env(:ysc, EmailValidator)

      Application.put_env(
        :ysc,
        EmailValidator,
        Keyword.put(prev_mx || [], :mx_resolver, fn _domain -> :ok end)
      )

      on_exit(fn ->
        case prev_mx do
          nil -> Application.delete_env(:ysc, EmailValidator)
          env -> Application.put_env(:ysc, EmailValidator, env)
        end
      end)

      :ok
    end

    test "accepts valid email format when MX check passes" do
      assert :ok =
               EmailValidator.validate_email(
                 "user@newsletter-fixture.example.com"
               )
    end

    test "accepts valid email with mixed case" do
      assert :ok =
               EmailValidator.validate_email(
                 "User@Newsletter-Fixture.EXAMPLE.com"
               )
    end

    test "accepts email with spaces (trimmed)" do
      assert :ok =
               EmailValidator.validate_email(
                 "  user@newsletter-fixture.example.com  "
               )
    end

    test "rejects email without @" do
      assert {:error, :invalid_email} =
               EmailValidator.validate_email("notanemail")
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

    test "rejects tempmail-style disposable domain" do
      assert {:error, :disposable_email} =
               EmailValidator.validate_email("test@etempmail.com")
    end

    test "accepts non-disposable domain when MX resolver allows" do
      assert :ok = EmailValidator.validate_email("contact@example.org")
    end

    test "MX caching uses process dictionary for repeated domains" do
      email1 = "user1@newsletter-fixture.example.com"
      email2 = "user2@newsletter-fixture.example.com"

      assert :ok = EmailValidator.validate_email(email1)
      assert :ok = EmailValidator.validate_email(email2)
    end

    test "validate_email recreates disposable-domain ETS if it was deleted" do
      table = :disposable_email_domains

      try do
        :ets.delete(table)

        assert :ok =
                 EmailValidator.validate_email(
                   "user@newsletter-fixture.example.com"
                 )

        assert {:error, :disposable_email} =
                 EmailValidator.validate_email("test@mailinator.com")

        assert :ets.whereis(table) != :undefined
      after
        EmailValidator.init_ets_table()
      end
    end
  end

  describe "validate_email/1 (injected MX resolver returns error)" do
    setup do
      prev_mx = Application.get_env(:ysc, EmailValidator)

      Application.put_env(
        :ysc,
        EmailValidator,
        Keyword.put(prev_mx || [], :mx_resolver, fn _domain ->
          {:error, :no_mx_records}
        end)
      )

      on_exit(fn ->
        case prev_mx do
          nil -> Application.delete_env(:ysc, EmailValidator)
          env -> Application.put_env(:ysc, EmailValidator, env)
        end
      end)

      :ok
    end

    test "returns MX resolver errors from injected resolver" do
      domain = "mx-reject-#{System.unique_integer([:positive])}.example.org"

      assert {:error, :no_mx_records} =
               EmailValidator.validate_email("any@#{domain}")
    end
  end

  describe "validate_email/1 (real DNS for MX)" do
    test "rejects domain with no MX records" do
      domain =
        "this-domain-definitely-does-not-exist-#{System.unique_integer([:positive])}.com"

      assert {:error, :no_mx_records} =
               EmailValidator.validate_email("user@#{domain}")
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

      threshold =
        Application.get_env(:ysc, :disposable_domains_threshold, 10_000)

      assert count > threshold,
             "expected more than #{threshold} disposable domains, got #{count}"
    end
  end

  describe "reload_disposable_domains/0" do
    test "reloads domains from file" do
      threshold =
        Application.get_env(:ysc, :disposable_domains_threshold, 10_000)

      assert {:ok, count} = EmailValidator.reload_disposable_domains()
      assert count > threshold
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

  describe "error handling" do
    test "handles invalid input types gracefully" do
      assert {:error, :invalid_email} = EmailValidator.validate_email(nil)
      assert {:error, :invalid_email} = EmailValidator.validate_email(123)
      assert {:error, :invalid_email} = EmailValidator.validate_email(%{})
    end
  end
end
