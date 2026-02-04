defmodule Ysc.Alerts.Discord do
  @moduledoc """
  Discord webhook integration for sending alerts and notifications.

  Supports:
  - Critical financial alerts
  - Reconciliation discrepancies
  - Ledger imbalance notifications
  - General system alerts

  ## Configuration

  Set the Discord webhook URL in your config:

      config :ysc, Ysc.Alerts.Discord,
        webhook_url: System.get_env("DISCORD_WEBHOOK_URL"),
        enabled: true

  ## Usage

      # Send a critical alert
      Ysc.Alerts.Discord.send_critical("Ledger imbalance detected!")

      # Send with custom embed
      Ysc.Alerts.Discord.send_alert(
        title: "Payment Discrepancy",
        description: "Found 5 payments without ledger entries",
        color: :error,
        fields: [
          %{name: "Total Amount", value: "$1,234.56", inline: true},
          %{name: "Affected Payments", value: "5", inline: true}
        ]
      )
  """

  require Logger

  # Discord color codes
  @colors %{
    # Blue
    info: 0x3498DB,
    # Green
    success: 0x2ECC71,
    # Orange
    warning: 0xF39C12,
    # Red
    error: 0xE74C3C,
    # Dark Red
    critical: 0x992D22
  }

  @doc """
  Sends a critical alert to Discord.

  ## Examples

      send_critical("Ledger imbalance detected!")
      send_critical("Financial reconciliation failed", fields: [
        %{name: "Discrepancies", value: "15"}
      ])
  """
  def send_critical(message, opts \\ []) do
    send_alert(
      [
        title: "🚨 CRITICAL ALERT",
        description: message,
        color: :critical,
        timestamp: DateTime.utc_now()
      ] ++ opts
    )
  end

  @doc """
  Sends an error alert to Discord.
  """
  def send_error(message, opts \\ []) do
    send_alert(
      [
        title: "❌ Error",
        description: message,
        color: :error,
        timestamp: DateTime.utc_now()
      ] ++ opts
    )
  end

  @doc """
  Sends a warning alert to Discord.
  """
  def send_warning(message, opts \\ []) do
    send_alert(
      [
        title: "⚠️ Warning",
        description: message,
        color: :warning,
        timestamp: DateTime.utc_now()
      ] ++ opts
    )
  end

  @doc """
  Sends a success notification to Discord.
  """
  def send_success(message, opts \\ []) do
    send_alert(
      [
        title: "✅ Success",
        description: message,
        color: :success,
        timestamp: DateTime.utc_now()
      ] ++ opts
    )
  end

  @doc """
  Sends an info notification to Discord.
  """
  def send_info(message, opts \\ []) do
    send_alert(
      [
        title: "ℹ️ Information",
        description: message,
        color: :info,
        timestamp: DateTime.utc_now()
      ] ++ opts
    )
  end

  @doc """
  Sends a custom alert to Discord with full control over the embed.

  ## Options

    * `:title` - Title of the embed
    * `:description` - Main message content
    * `:color` - Color of the embed (:info, :success, :warning, :error, :critical)
    * `:fields` - List of field maps with :name, :value, and optional :inline
    * `:footer` - Footer text
    * `:timestamp` - DateTime for the embed
    * `:url` - URL to make the title clickable
    * `:thumbnail_url` - URL for a thumbnail image
    * `:image_url` - URL for a full-size image

  ## Examples

      send_alert(
        title: "Reconciliation Report",
        description: "Daily reconciliation completed",
        color: :success,
        fields: [
          %{name: "Payments", value: "150", inline: true},
          %{name: "Refunds", value: "5", inline: true},
          %{name: "Status", value: "✅ Balanced", inline: false}
        ],
        footer: "YSC Financial System",
        timestamp: DateTime.utc_now()
      )
  """
  def send_alert(opts) do
    cond do
      !enabled?() ->
        Logger.debug(
          "Discord alerts disabled, skipping message: #{inspect(opts[:title])}"
        )

        {:ok, :disabled}

      !webhook_url() ->
        Logger.warning("Discord webhook URL not configured, cannot send alert")
        {:error, :no_webhook_url}

      true ->
        embed = build_embed(opts)
        payload = %{embeds: [embed]}

        case send_webhook(payload) do
          {:ok, _response} ->
            Logger.info("Discord alert sent successfully", title: opts[:title])
            {:ok, :sent}

          {:error, reason} ->
            Logger.warning("Failed to send Discord alert",
              title: opts[:title],
              reason: inspect(reason)
            )

            {:error, reason}
        end
    end
  end

  @doc """
  Sends a reconciliation report to Discord.

  ## Examples

      send_reconciliation_report(report, :success)
      send_reconciliation_report(report, :error)
  """
  def send_reconciliation_report(report, status \\ :info) do
    {title, color, emoji} =
      case status do
        :success -> {"Reconciliation Passed", :success, "✅"}
        :error -> {"Reconciliation Failed", :error, "❌"}
        :warning -> {"Reconciliation Warnings", :warning, "⚠️"}
        _ -> {"Reconciliation Report", :info, "ℹ️"}
      end

    fields = build_reconciliation_fields(report)

    send_alert(
      title: "#{emoji} #{title}",
      description: "Financial reconciliation completed at #{report.timestamp}",
      color: color,
      fields: fields,
      footer: "Duration: #{report.duration_ms}ms",
      timestamp: report.timestamp
    )
  end

  @doc """
  Sends a ledger imbalance alert to Discord.
  """
  def send_ledger_imbalance_alert(difference, details \\ nil) do
    description = """
    A ledger imbalance has been detected!

    **Difference:** #{Money.to_string!(difference)}
    **Timestamp:** #{DateTime.utc_now()}

    This requires immediate investigation.
    """

    fields =
      if details do
        [
          %{
            name: "Total Accounts Affected",
            value: to_string(details.total_accounts_affected),
            inline: true
          },
          %{
            name: "Action Required",
            value: "Investigate immediately",
            inline: true
          }
        ]
      else
        []
      end

    send_critical(description, fields: fields)
  end

  @doc """
  Sends a payment discrepancy alert to Discord.
  """
  def send_payment_discrepancy_alert(
        discrepancies_count,
        total_payments,
        details \\ []
      ) do
    description = """
    Payment discrepancies detected during reconciliation.

    **Total Discrepancies:** #{discrepancies_count}
    **Total Payments:** #{total_payments}
    """

    fields =
      Enum.map(Enum.take(details, 3), fn disc ->
        %{
          name: "Payment #{disc.payment_id}",
          value: Enum.join(disc.issues, "\n"),
          inline: false
        }
      end)

    send_error(description, fields: fields)
  end

  ## Private Functions

  defp enabled? do
    Application.get_env(:ysc, __MODULE__)[:enabled] != false &&
      webhook_url() != nil
  end

  defp webhook_url do
    # Read from runtime configuration first, then fall back to environment variable
    Application.get_env(:ysc, __MODULE__)[:webhook_url] ||
      System.get_env("DISCORD_WEBHOOK_URL")
  end

  defp get_environment do
    # Try to get environment from runtime config first (set in runtime.exs)
    config_env = Ysc.Env.current()

    # Fallback to Mix.env() if available
    env =
      config_env || :unknown

    # Format environment name
    env
    |> to_string()
    |> String.upcase()
  end

  defp build_footer(custom_footer) when is_binary(custom_footer) do
    env = get_environment()
    "YSC Financial System | ENV: #{env} | #{custom_footer}"
  end

  defp build_footer(nil) do
    env = get_environment()
    "YSC Financial System | ENV: #{env}"
  end

  defp build_embed(opts) do
    embed = %{
      title: opts[:title],
      description: opts[:description]
    }

    embed =
      if color = opts[:color] do
        Map.put(embed, :color, get_color(color))
      else
        embed
      end

    embed =
      if fields = opts[:fields] do
        Map.put(embed, :fields, fields)
      else
        embed
      end

    embed = Map.put(embed, :footer, %{text: build_footer(opts[:footer])})

    embed =
      if timestamp = opts[:timestamp] do
        Map.put(embed, :timestamp, DateTime.to_iso8601(timestamp))
      else
        embed
      end

    embed =
      if url = opts[:url] do
        Map.put(embed, :url, url)
      else
        embed
      end

    embed =
      if thumbnail_url = opts[:thumbnail_url] do
        Map.put(embed, :thumbnail, %{url: thumbnail_url})
      else
        embed
      end

    embed =
      if image_url = opts[:image_url] do
        Map.put(embed, :image, %{url: image_url})
      else
        embed
      end

    # Remove nil values
    Map.reject(embed, fn {_k, v} -> is_nil(v) end)
  end

  defp get_color(color) when is_atom(color) do
    Map.get(@colors, color, @colors.info)
  end

  defp get_color(color) when is_integer(color), do: color

  defp send_webhook(payload) do
    url = webhook_url()
    body = Jason.encode!(payload)
    headers = [{"content-type", "application/json"}]

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Ysc.Finch) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        {:ok, :sent}

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        {:error, {:bad_status, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, error}
  end

  defp build_reconciliation_fields(report) do
    base_fields = [
      %{
        name: "Overall Status",
        value: format_status(report.overall_status),
        inline: true
      },
      %{
        name: "Duration",
        value: "#{report.duration_ms}ms",
        inline: true
      }
    ]

    payment_fields =
      if report.checks.payments do
        [
          %{
            name: "Payments",
            value: """
            Total: #{report.checks.payments.total_payments}
            Discrepancies: #{report.checks.payments.discrepancies_count}
            Match: #{format_boolean(report.checks.payments.totals.match)}
            """,
            inline: true
          }
        ]
      else
        []
      end

    refund_fields =
      if report.checks.refunds do
        [
          %{
            name: "Refunds",
            value: """
            Total: #{report.checks.refunds.total_refunds}
            Discrepancies: #{report.checks.refunds.discrepancies_count}
            Match: #{format_boolean(report.checks.refunds.totals.match)}
            """,
            inline: true
          }
        ]
      else
        []
      end

    balance_fields =
      if report.checks.ledger_balance do
        [
          %{
            name: "Ledger Balance",
            value: format_boolean(report.checks.ledger_balance.balanced),
            inline: true
          }
        ]
      else
        []
      end

    entity_fields =
      if report.checks.entity_totals do
        [
          %{
            name: "Entity Totals",
            value: """
            Memberships: #{format_boolean(report.checks.entity_totals.memberships.match)}
            Bookings: #{format_boolean(report.checks.entity_totals.bookings.match)}
            Events: #{format_boolean(report.checks.entity_totals.events.match)}
            """,
            inline: false
          }
        ]
      else
        []
      end

    base_fields ++
      payment_fields ++ refund_fields ++ balance_fields ++ entity_fields
  end

  defp format_status(:ok), do: "✅ PASS"
  defp format_status(:error), do: "❌ FAIL"
  defp format_status(_), do: "❓ UNKNOWN"

  defp format_boolean(true), do: "✅"
  defp format_boolean(false), do: "❌"
  defp format_boolean(_), do: "❓"
end
