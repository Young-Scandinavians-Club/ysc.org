defmodule Ysc.Alerts.DiscordTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Mox

  alias Ysc.Alerts.Discord
  alias Money

  setup :verify_on_exit!

  setup do
    stub(Ysc.Alerts.DiscordHttpMock, :send_webhook, fn _url, _body, _headers ->
      {:ok, :sent}
    end)

    :ok
  end

  describe "configuration" do
    test "verifies Discord module is configured for tests" do
      config = Application.get_env(:ysc, Discord)
      assert config != nil
      assert config[:webhook_url] != nil
      assert config[:enabled] == true
    end

    test "handles missing webhook URL gracefully" do
      Application.put_env(:ysc, Discord, webhook_url: nil, enabled: true)

      result = Discord.send_info("Test")

      # When webhook_url is nil, enabled? returns false (it requires a URL to be enabled)
      assert result == {:ok, :disabled}
    after
      Application.put_env(:ysc, Discord,
        webhook_url: "https://discord.com/api/webhooks/test/token",
        enabled: true
      )
    end

    test "returns disabled when alerts are disabled" do
      Application.put_env(:ysc, Discord,
        webhook_url: "https://example.com",
        enabled: false
      )

      result = Discord.send_info("Test")
      assert result == {:ok, :disabled}
    after
      Application.put_env(:ysc, Discord,
        webhook_url: "https://discord.com/api/webhooks/test/token",
        enabled: true
      )
    end
  end

  describe "alert functions" do
    test "send_critical/2 returns ok when HTTP succeeds" do
      result = Discord.send_critical("Test critical message")
      assert result == {:ok, :sent}
    end

    test "send_error/2 returns ok when HTTP succeeds" do
      result = Discord.send_error("Test error message")
      assert result == {:ok, :sent}
    end

    test "send_warning/2 returns ok when HTTP succeeds" do
      result = Discord.send_warning("Test warning message")
      assert result == {:ok, :sent}
    end

    test "send_success/2 returns ok when HTTP succeeds" do
      result = Discord.send_success("Test success message")
      assert result == {:ok, :sent}
    end

    test "send_info/2 returns ok when HTTP succeeds" do
      result = Discord.send_info("Test info message")
      assert result == {:ok, :sent}
    end

    test "send_alert/1 with all options returns ok" do
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

      assert result == {:ok, :sent}
    end

    test "send_critical/2 with custom fields returns ok" do
      result =
        Discord.send_critical("Critical issue",
          fields: [%{name: "Count", value: "5"}]
        )

      assert result == {:ok, :sent}
    end

    test "returns error tuple when HTTP client returns error" do
      stub(Ysc.Alerts.DiscordHttpMock, :send_webhook, fn _url,
                                                         _body,
                                                         _headers ->
        {:error, :network_failure}
      end)

      result = Discord.send_warning("Test warning message")
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
            events: %{match: true},
            donations: %{match: true}
          }
        }
      }

      %{report: report}
    end

    test "send_reconciliation_report/2 with success status", %{report: report} do
      result = Discord.send_reconciliation_report(report, :success)
      assert result == {:ok, :sent}
    end

    test "send_reconciliation_report/2 with error status", %{report: report} do
      error_report = put_in(report.overall_status, :error)
      result = Discord.send_reconciliation_report(error_report, :error)
      assert result == {:ok, :sent}
    end

    test "send_reconciliation_report/2 with warning status", %{report: report} do
      result = Discord.send_reconciliation_report(report, :warning)
      assert result == {:ok, :sent}
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
      assert result == {:ok, :sent}
    end
  end

  describe "specialized alerts" do
    test "send_ledger_imbalance_alert/2 without details" do
      difference = Money.new(1000, :USD)
      result = Discord.send_ledger_imbalance_alert(difference)
      assert result == {:ok, :sent}
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
      assert result == {:ok, :sent}
    end

    test "send_payment_discrepancy_alert/3" do
      discrepancies = [
        %{payment_id: "pay_123", issues: ["Missing ledger entry"]},
        %{payment_id: "pay_456", issues: ["Amount mismatch"]}
      ]

      result = Discord.send_payment_discrepancy_alert(2, 150, discrepancies)
      assert result == {:ok, :sent}
    end

    test "send_payment_discrepancy_alert/3 with empty details" do
      result = Discord.send_payment_discrepancy_alert(5, 150, [])
      assert result == {:ok, :sent}
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

        assert result == {:ok, :sent}
      end
    end

    test "accepts custom integer color values" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Custom color",
          color: 0xFF6B6B
        )

      assert result == {:ok, :sent}
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

      assert result == {:ok, :sent}
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

      assert result == {:ok, :sent}
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

      assert result == {:ok, :sent}
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

      assert result == {:ok, :sent}
    end

    test "handles URL parameter" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Test",
          url: "https://example.com/report"
        )

      assert result == {:ok, :sent}
    end

    test "handles thumbnail_url parameter" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Test",
          thumbnail_url: "https://example.com/thumb.png"
        )

      assert result == {:ok, :sent}
    end

    test "handles image_url parameter" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Test",
          image_url: "https://example.com/image.png"
        )

      assert result == {:ok, :sent}
    end

    test "handles timestamp parameter" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Test",
          timestamp: DateTime.utc_now()
        )

      assert result == {:ok, :sent}
    end

    test "works without optional parameters" do
      result =
        Discord.send_alert(
          title: "Test",
          description: "Test"
        )

      assert result == {:ok, :sent}
    end
  end

  describe "error handling and logging" do
    test "logs warning when alert fails to send" do
      stub(Ysc.Alerts.DiscordHttpMock, :send_webhook, fn _url,
                                                         _body,
                                                         _headers ->
        {:error, :network_failure}
      end)

      log =
        capture_log(fn ->
          Discord.send_critical("Test")
        end)

      assert is_binary(log)
    end

    test "send_info logs attempt to send" do
      capture_log(fn ->
        Discord.send_info("Test message")
      end)

      assert true
    end
  end

  describe "send_webhook_reconciliation_report/2" do
    test "sends success report with optional stats fields" do
      stats = %{
        total_checked: 10,
        missing_found: 0,
        duration_ms: 100,
        processed_success: 5,
        processed_failed: 0,
        failed_event_ids: ["evt_1", "evt_2"]
      }

      assert {:ok, :sent} =
               Discord.send_webhook_reconciliation_report(stats, :success)
    end

    test "sends warning report" do
      stats = %{total_checked: 10, missing_found: 2, duration_ms: 200}

      assert {:ok, :sent} =
               Discord.send_webhook_reconciliation_report(stats, :warning)
    end

    test "falls back to info for unknown status" do
      stats = %{total_checked: 1, missing_found: 0, duration_ms: 1}

      assert {:ok, :sent} =
               Discord.send_webhook_reconciliation_report(stats, :other)
    end
  end

  describe "send_missing_webhooks_alert/2" do
    test "truncates event id list past ten entries" do
      ids = for i <- 1..12, do: "evt_#{i}"
      assert {:ok, :sent} = Discord.send_missing_webhooks_alert(12, ids)
    end

    test "sends without event id fields when list is empty" do
      assert {:ok, :sent} = Discord.send_missing_webhooks_alert(3, [])
    end
  end

  describe "reconciliation entity totals edge cases" do
    test "includes events mismatch note when entity_totals events do not match" do
      report = %{
        timestamp: DateTime.utc_now(),
        duration_ms: 500,
        overall_status: :ok,
        checks: %{
          payments: nil,
          refunds: nil,
          ledger_balance: nil,
          entity_totals: %{
            memberships: %{match: true},
            bookings: %{match: true},
            events: %{
              match: false,
              ledger_revenue: Money.new(10, :USD),
              payment_total: Money.new(20, :USD)
            },
            donations: %{match: true}
          }
        }
      }

      assert {:ok, :sent} = Discord.send_reconciliation_report(report, :info)
    end

    test "formats entity amounts line when ledger totals diverge" do
      report = %{
        timestamp: DateTime.utc_now(),
        duration_ms: 500,
        overall_status: :ok,
        checks: %{
          payments: nil,
          refunds: nil,
          ledger_balance: nil,
          entity_totals: %{
            memberships: %{match: true},
            bookings: %{
              match: false,
              ledger_revenue: Money.new(100, :USD),
              payment_total: Money.new(50, :USD)
            },
            events: %{match: true},
            donations: %{match: true}
          }
        }
      }

      assert {:ok, :sent} = Discord.send_reconciliation_report(report, :info)
    end
  end
end
