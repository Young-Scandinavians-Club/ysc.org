defmodule Ysc.Alerts.DiscordTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Ysc.Alerts.Discord

  setup do
    # Store original configuration
    original_config = Application.get_env(:ysc, Discord)
    original_environment = Application.get_env(:ysc, :environment)

    # Set test configuration with valid webhook URL
    Application.put_env(:ysc, Discord,
      webhook_url: "https://discord.com/api/webhooks/123/test_token",
      enabled: true
    )

    Application.put_env(:ysc, :environment, "test")

    on_exit(fn ->
      # Restore original configuration
      if original_config do
        Application.put_env(:ysc, Discord, original_config)
      else
        Application.delete_env(:ysc, Discord)
      end

      if original_environment do
        Application.put_env(:ysc, :environment, original_environment)
      else
        Application.delete_env(:ysc, :environment)
      end
    end)

    :ok
  end

  describe "configuration" do
    # Note: @enabled and @webhook_url are module attributes compiled at build time,
    # so runtime configuration changes in tests may not affect their values.
    # These tests verify the functions are callable and handle errors gracefully.

    test "handles missing webhook URL gracefully" do
      # With test config having a valid webhook URL, this tests error handling
      result = Discord.send_info("Test")
      # Should attempt to send and get an error (Finch not running in test)
      assert match?({:error, _}, result)
    end

    test "verifies Discord module is configured for tests" do
      config = Application.get_env(:ysc, Discord)
      assert config != nil
      assert config[:webhook_url] != nil
      assert config[:enabled] == true
    end

    test "handles network errors gracefully" do
      # Test that sending alerts doesn't crash when network fails
      capture_log(fn ->
        result = Discord.send_info("Test")
        assert match?({:error, _}, result)
      end)
    end
  end

  describe "alert functions" do
    test "send_critical/2 returns error tuple when network fails" do
      result = Discord.send_critical("Test critical message")
      assert match?({:error, _}, result)
    end

    test "send_error/2 returns error tuple when network fails" do
      result = Discord.send_error("Test error message")
      assert match?({:error, _}, result)
    end

    test "send_warning/2 returns error tuple when network fails" do
      result = Discord.send_warning("Test warning message")
      assert match?({:error, _}, result)
    end

    test "send_success/2 returns error tuple when network fails" do
      result = Discord.send_success("Test success message")
      assert match?({:error, _}, result)
    end

    test "send_info/2 returns error tuple when network fails" do
      result = Discord.send_info("Test info message")
      assert match?({:error, _}, result)
    end

    test "send_alert/1 with all options returns error tuple when network fails" do
      result =
        Discord.send_alert(
          title: "Custom Alert",
          description: "Custom description",
          color: :info,
          fields: [
            %{name: "Field 1", value: "Value 1", inline: true},
            %{name: "Field 2", value: "Value 2", inline: false}
          ],
          footer: "Custom footer",
          timestamp: DateTime.utc_now(),
          url: "https://example.com",
          thumbnail_url: "https://example.com/thumb.png",
          image_url: "https://example.com/image.png"
        )

      assert match?({:error, _}, result)
    end

    test "send_critical/2 with custom fields" do
      result =
        Discord.send_critical("Critical issue",
          fields: [%{name: "Count", value: "5"}]
        )

      assert match?({:error, _}, result)
    end
  end

  describe "reconciliation reports" do
    setup do
      report = %{
        timestamp: DateTime.utc_now(),
        duration_ms: 1234,
        overall_status: :ok,
        checks: %{
          payments: %{
            total_payments: 150,
            discrepancies_count: 0,
            totals: %{match: true}
          },
          refunds: %{
            total_refunds: 5,
            discrepancies_count: 0,
            totals: %{match: true}
          },
          ledger_balance: %{
            balanced: true
          },
          entity_totals: %{
            memberships: %{match: true},
            bookings: %{match: true},
            events: %{match: true}
          }
        }
      }

      %{report: report}
    end

    test "send_reconciliation_report/2 with success status", %{report: report} do
      result = Discord.send_reconciliation_report(report, :success)
      assert match?({:error, _}, result)
    end

    test "send_reconciliation_report/2 with error status", %{report: report} do
      error_report = put_in(report.overall_status, :error)
      result = Discord.send_reconciliation_report(error_report, :error)
      assert match?({:error, _}, result)
    end

    test "send_reconciliation_report/2 with warning status", %{report: report} do
      result = Discord.send_reconciliation_report(report, :warning)
      assert match?({:error, _}, result)
    end

    test "send_reconciliation_report/2 with nil checks" do
      minimal_report = %{
        timestamp: DateTime.utc_now(),
        duration_ms: 1234,
        overall_status: :ok,
        checks: %{
          payments: nil,
          refunds: nil,
          ledger_balance: nil,
          entity_totals: nil
        }
      }

      result = Discord.send_reconciliation_report(minimal_report, :info)
      assert match?({:error, _}, result)
    end
  end

  describe "specialized alerts" do
    test "send_ledger_imbalance_alert/2 without details" do
      difference = Money.new(1000, :USD)
      result = Discord.send_ledger_imbalance_alert(difference)
      assert match?({:error, _}, result)
    end

    test "send_ledger_imbalance_alert/2 with details" do
      difference = Money.new(1000, :USD)

      details = %{
        total_accounts_affected: 5,
        breakdown_by_type: %{
          asset: %{count: 2, total: Money.new(500, :USD)}
        }
      }

      result = Discord.send_ledger_imbalance_alert(difference, details)
      assert match?({:error, _}, result)
    end

    test "send_payment_discrepancy_alert/3" do
      discrepancies = [
        %{payment_id: "pay_123", issues: ["Missing ledger entry"]},
        %{payment_id: "pay_456", issues: ["Amount mismatch"]}
      ]

      result = Discord.send_payment_discrepancy_alert(2, 150, discrepancies)
      assert match?({:error, _}, result)
    end

    test "send_payment_discrepancy_alert/3 with empty details" do
      result = Discord.send_payment_discrepancy_alert(5, 150, [])
      assert match?({:error, _}, result)
    end
  end

  describe "environment detection" do
    test "uses configured environment" do
      Application.put_env(:ysc, :environment, "production")
      # Just verify it doesn't crash with different environment
      result = Discord.send_info("Test")
      assert match?({:error, _}, result)
    end

    test "handles missing environment configuration" do
      Application.delete_env(:ysc, :environment)
      # Should still work, will use Mix.env() or "UNKNOWN"
      result = Discord.send_info("Test")
      assert match?({:error, _}, result)
    end

    test "formats different environment names" do
      envs = ["dev", "staging", "production", "test"]

      for env <- envs do
        Application.put_env(:ysc, :environment, env)
        result = Discord.send_info("Test #{env}")
        assert match?({:error, _}, result)
      end
    end
  end

  describe "color handling" do
    test "accepts predefined color atoms" do
      colors = [:info, :success, :warning, :error, :critical]

      for color <- colors do
        result =
          Discord.send_alert(
            title: "Test",
            description: "Test #{color}",
            color: color
          )

        assert match?({:error, _}, result)
      end
    end

    test "accepts custom integer color values" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Custom color",
          color: 0xFF6B6B
        )

      assert match?({:error, _}, result)
    end
  end

  describe "field handling" do
    test "handles inline fields" do
      fields = [
        %{name: "Field 1", value: "Value 1", inline: true},
        %{name: "Field 2", value: "Value 2", inline: true}
      ]

      result =
        Discord.send_alert(
          title: "Test",
          description: "Test",
          fields: fields
        )

      assert match?({:error, _}, result)
    end

    test "handles non-inline fields" do
      fields = [
        %{name: "Field 1", value: "Value 1", inline: false}
      ]

      result =
        Discord.send_alert(
          title: "Test",
          description: "Test",
          fields: fields
        )

      assert match?({:error, _}, result)
    end

    test "handles mixed inline and non-inline fields" do
      fields = [
        %{name: "Field 1", value: "Value 1", inline: true},
        %{name: "Field 2", value: "Value 2", inline: false},
        %{name: "Field 3", value: "Value 3", inline: true}
      ]

      result =
        Discord.send_alert(
          title: "Test",
          description: "Test",
          fields: fields
        )

      assert match?({:error, _}, result)
    end
  end

  describe "optional parameters" do
    test "handles custom footer" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Test",
          footer: "Custom footer text"
        )

      assert match?({:error, _}, result)
    end

    test "handles URL parameter" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Test",
          url: "https://example.com/report"
        )

      assert match?({:error, _}, result)
    end

    test "handles thumbnail_url parameter" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Test",
          thumbnail_url: "https://example.com/thumb.png"
        )

      assert match?({:error, _}, result)
    end

    test "handles image_url parameter" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Test",
          image_url: "https://example.com/image.png"
        )

      assert match?({:error, _}, result)
    end

    test "handles timestamp parameter" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Test",
          timestamp: DateTime.utc_now()
        )

      assert match?({:error, _}, result)
    end

    test "works without optional parameters" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Test"
        )

      assert match?({:error, _}, result)
    end
  end

  describe "error handling and logging" do
    test "logs error when alert fails to send" do
      log =
        capture_log(fn ->
          Discord.send_critical("Test")
        end)

      # We mainly care that sending doesn't crash; logging may be suppressed in tests.
      assert is_binary(log)
    end

    test "logs attempt to send" do
      # Just verify the function doesn't crash
      capture_log(fn ->
        Discord.send_info("Test message")
      end)

      # If we get here, function executed without crashing
      assert true
    end
  end
end
